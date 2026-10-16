import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';

import 'face_state.dart';

/// Mở camera trước, đẩy từng khung hình vào ML Kit và phát ra [FaceState].
///
/// - Face Detection (mỗi khung hình): góc nghiêng đầu, cười, mở mắt -> điều khiển chính.
/// - Face Mesh (cách vài khung hình): 468 điểm để vẽ lưới + đo độ há miệng.
/// - Nếu Face Mesh lỗi, tự chuyển sang Face Detection + contours để đo miệng.
class FaceController extends ChangeNotifier {
  static const _meshMinGapMs = 140; // Face Mesh tối đa ~7 lần/giây
  static const _meshLoad = 2.5; // và không quá ~40% thời gian xử lý
  static const _lostTolerance = 3;
  static const _mouthStaleMs = 500;

  static const _deviceRotation = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  final state = ValueNotifier<FaceState>(FaceState.none);
  final mesh = ValueNotifier<MeshFrame?>(null);
  final stats = ValueNotifier<PerfStats>(const PerfStats());

  CameraController? camera;
  CameraDescription? description;
  String? error;
  bool initializing = false;

  /// Cộng thêm vào góc xoay ảnh gửi ML Kit (phòng khi thiết bị/emulator lệch hướng).
  int rotationOffset = 0;

  late final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.15,
    ),
  );
  FaceDetector? _contourDetector;
  FaceMeshDetector? _meshDetector;

  bool _meshBroken = false;
  int _meshErrors = 0;
  Uint16List? _triangles;

  int _users = 0;
  bool _streaming = false;
  bool _suspended = false;
  bool _syncing = false;
  bool _busy = false;
  bool _disposed = false;

  int _frame = 0;
  int _lost = 0;
  int _detectMs = 0;
  int _meshMs = 0;
  int _fpsFrames = 0;
  final _fpsClock = Stopwatch()..start();
  double _fps = 0;
  Size _imageSize = Size.zero;
  int _lastRotation = 0;

  final _meshClock = Stopwatch()..start();
  int _meshAtMs = -100000;

  double? _mouth;
  final _mouthClock = Stopwatch()..start();
  int _mouthAtMs = -100000;

  bool get ready => camera?.value.isInitialized ?? false;
  bool get isFront => description?.lensDirection == CameraLensDirection.front;

  Future<void> init() async {
    if (initializing || ready) return;
    initializing = true;
    error = null;
    notifyListeners();
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('none', 'Không tìm thấy camera');
      description = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final c = CameraController(
        description!,
        ResolutionPreset.medium,
        fps: 30,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await c.initialize();
      try {
        await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {}
      camera = c;
      _meshDetector ??= FaceMeshDetector(option: FaceMeshDetectorOptions.faceMesh);
    } on CameraException catch (e) {
      error = e.code == 'CameraAccessDenied'
          ? 'Chưa cấp quyền camera. Hãy cấp quyền rồi thử lại.'
          : 'Lỗi camera: ${e.description ?? e.code}';
    } catch (e) {
      error = 'Lỗi camera: $e';
    } finally {
      initializing = false;
      if (!_disposed) notifyListeners();
    }
    unawaited(_sync());
  }

  /// Màn hình cần dữ liệu khuôn mặt thì gọi [acquire], xong thì [release].
  void acquire() {
    _users++;
    unawaited(_sync());
  }

  void release() {
    _users = math.max(0, _users - 1);
    unawaited(_sync());
  }

  void suspend(bool value) {
    _suspended = value;
    unawaited(_sync());
  }

  Future<void> _sync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      while (!_disposed) {
        final c = camera;
        if (c == null || !c.value.isInitialized) return;
        final want = _users > 0 && !_suspended;
        if (want == _streaming) return;
        try {
          if (want) {
            _resetTracking();
            await c.startImageStream(_onFrame);
          } else {
            await c.stopImageStream();
          }
          _streaming = want;
        } catch (e) {
          debugPrint('FaceController stream error: $e');
          _streaming = want;
          return;
        }
      }
    } finally {
      _syncing = false;
    }
  }

  void _resetTracking() {
    _lost = 0;
    _busy = false;
    state.value = FaceState.none;
    mesh.value = null;
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _disposed) return;
    _busy = true;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      _frame++;

      final sw = Stopwatch()..start();
      final faces = await _detector.processImage(input);
      _detectMs = _ema(_detectMs, sw.elapsedMilliseconds);

      if (faces.isEmpty) {
        _lost++;
        if (_lost >= _lostTolerance) {
          state.value = FaceState.none;
          mesh.value = null;
        }
      } else {
        _lost = 0;
        final face = faces.reduce((a, b) => _area(a) >= _area(b) ? a : b);

        if (!_meshBroken) {
          if (_meshDue()) await _runMesh(input);
        } else if (_frame % 2 == 0) {
          await _runContourFallback(input);
        }

        final eyes = <double>[
          if (face.leftEyeOpenProbability != null) face.leftEyeOpenProbability!,
          if (face.rightEyeOpenProbability != null) face.rightEyeOpenProbability!,
        ];
        final mouthFresh = _mouthClock.elapsedMilliseconds - _mouthAtMs < _mouthStaleMs;
        state.value = FaceState(
          hasFace: true,
          roll: face.headEulerAngleZ ?? 0,
          smile: face.smilingProbability ?? 0,
          eyeOpen: eyes.isEmpty ? 1 : eyes.reduce((a, b) => a + b) / eyes.length,
          mouthRatio: mouthFresh ? _mouth : null,
        );
      }
      _tickStats();
    } catch (e, st) {
      debugPrint('FaceController frame error: $e\n$st');
    } finally {
      _busy = false;
    }
  }

  /// Face Mesh nặng hơn Detection nhiều: tự giãn tần suất theo thời gian xử lý thực tế
  /// để điều khiển (Detection) luôn mượt, kể cả khi máy yếu hoặc đang bận.
  bool _meshDue() {
    final gap = math.max(_meshMinGapMs, (_meshMs * _meshLoad).round());
    return _meshClock.elapsedMilliseconds - _meshAtMs >= gap;
  }

  Future<void> _runMesh(InputImage input) async {
    _meshAtMs = _meshClock.elapsedMilliseconds;
    try {
      final sw = Stopwatch()..start();
      final meshes = await _meshDetector!.processImage(input);
      _meshMs = _ema(_meshMs, sw.elapsedMilliseconds);
      _meshErrors = 0;
      if (meshes.isEmpty) {
        mesh.value = null;
        return;
      }
      final m = meshes.first;
      final pts = List<Offset>.filled(468, Offset.zero);
      for (final p in m.points) {
        if (p.index >= 0 && p.index < pts.length) pts[p.index] = Offset(p.x, p.y);
      }
      final contours = <FaceMeshContourType, List<Offset>>{
        for (final e in m.contours.entries)
          e.key: [for (final p in e.value ?? <FaceMeshPoint>[]) Offset(p.x, p.y)],
      };
      _triangles ??= Uint16List.fromList([
        for (final t in m.triangles)
          for (final p in t.points) p.index,
      ]);
      mesh.value = MeshFrame(
        imageSize: _imageSize,
        points: pts,
        contours: contours,
        triangles: _triangles!,
      );
      _setMouth(
        contours[FaceMeshContourType.upperLipBottom],
        contours[FaceMeshContourType.lowerLipTop],
        contours[FaceMeshContourType.faceOval],
      );
    } catch (e) {
      debugPrint('FaceMesh error: $e');
      if (++_meshErrors >= 3) {
        _meshBroken = true;
        mesh.value = null;
      }
    }
  }

  Future<void> _runContourFallback(InputImage input) async {
    try {
      _contourDetector ??= FaceDetector(
        options: FaceDetectorOptions(
          enableContours: true,
          performanceMode: FaceDetectorMode.fast,
          minFaceSize: 0.15,
        ),
      );
      final faces = await _contourDetector!.processImage(input);
      if (faces.isEmpty) return;
      List<Offset>? pts(FaceContourType t) => faces.first.contours[t]?.points
          .map((p) => Offset(p.x.toDouble(), p.y.toDouble()))
          .toList();
      _setMouth(
        pts(FaceContourType.upperLipBottom),
        pts(FaceContourType.lowerLipTop),
        pts(FaceContourType.face),
      );
    } catch (e) {
      debugPrint('Contour fallback error: $e');
    }
  }

  void _setMouth(List<Offset>? upper, List<Offset>? lower, List<Offset>? oval) {
    if (upper == null || lower == null || oval == null) return;
    if (upper.isEmpty || lower.isEmpty || oval.isEmpty) return;
    final u = _centroid(upper);
    final l = _centroid(lower);
    var top = double.infinity, bottom = -double.infinity;
    for (final p in oval) {
      top = math.min(top, p.dy);
      bottom = math.max(bottom, p.dy);
    }
    final height = bottom - top;
    if (height <= 1) return;
    _mouth = (l - u).distance / height;
    _mouthAtMs = _mouthClock.elapsedMilliseconds;
  }

  Offset _centroid(List<Offset> pts) {
    var x = 0.0, y = 0.0;
    for (final p in pts) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(x / pts.length, y / pts.length);
  }

  double _area(Face f) => f.boundingBox.width * f.boundingBox.height;

  int _ema(int old, int value) => old == 0 ? value : (old * 0.7 + value * 0.3).round();

  void _tickStats() {
    _fpsFrames++;
    final ms = _fpsClock.elapsedMilliseconds;
    if (ms < 500) return;
    _fps = _fpsFrames * 1000 / ms;
    _fpsFrames = 0;
    _fpsClock
      ..reset()
      ..start();
    stats.value = PerfStats(
      fps: _fps,
      detectMs: _detectMs,
      meshMs: _meshMs,
      meshOk: !_meshBroken,
      contourFallback: _meshBroken,
      imageSize: _imageSize,
      rotation: _lastRotation,
    );
  }

  InputImage? _toInputImage(CameraImage image) {
    final cam = description;
    final c = camera;
    if (cam == null || c == null) return null;

    final device = _deviceRotation[c.value.deviceOrientation] ?? 0;
    var degrees = cam.lensDirection == CameraLensDirection.front
        ? (cam.sensorOrientation + device) % 360
        : (cam.sensorOrientation - device + 360) % 360;
    degrees = (degrees + rotationOffset) % 360;
    final rotation = InputImageRotationValue.fromRawValue(degrees);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format != InputImageFormat.nv21 || image.planes.length != 1) return null;

    final sideways = degrees == 90 || degrees == 270;
    _imageSize = sideways
        ? Size(image.height.toDouble(), image.width.toDouble())
        : Size(image.width.toDouble(), image.height.toDouble());
    _lastRotation = degrees;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format!,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _detector.close();
    _contourDetector?.close();
    _meshDetector?.close();
    camera?.dispose();
    state.dispose();
    mesh.dispose();
    stats.dispose();
    super.dispose();
  }
}
