import 'dart:math' as math;

import 'face_controller.dart';
import 'face_state.dart';

/// Trung bình trượt N giá trị gần nhất.
class MovingAverage {
  MovingAverage(this.n);
  final int n;
  final _buf = <double>[];

  double add(double v) {
    _buf.add(v);
    if (_buf.length > n) _buf.removeAt(0);
    return value;
  }

  double get value => _buf.isEmpty ? 0 : _buf.reduce((a, b) => a + b) / _buf.length;

  void reset() => _buf.clear();
}

/// Biến tín hiệu thô từ ML Kit thành đầu vào ổn định cho game:
/// hiệu chỉnh mốc 0, làm mượt, vùng chết, phát hiện há miệng / nhắm mắt.
class InputHub {
  InputHub(this.face) {
    face.state.addListener(_onFace);
  }

  final FaceController face;

  // Cấu hình (do menu chỉnh)
  double range = 25; // độ nghiêng (°) để giỏ chạm mép
  double deadzone = 5; // vùng chết ±°
  bool invert = false;

  // Hiệu chỉnh
  double baselineRoll = 0;
  double mouthBaseline = 0.02;

  final _roll = MovingAverage(4);
  final _smile = MovingAverage(4);
  final _eye = MovingAverage(3);

  bool _calibrating = false;
  final _rollSamples = <double>[];
  final _mouthSamples = <double>[];

  bool hasFace = false;
  double smile = 0;
  double rollRaw = 0;
  double? mouthRatio;

  int _lastUpdateMs = -100000;
  final _clock = Stopwatch()..start();

  double eyesClosedFor = 0; // giây
  int _mouthFrames = 0;
  bool _mouthArmed = true;
  bool _mouthTrigger = false;

  /// Face ổn định = có mặt và dữ liệu còn mới.
  bool get faceOk => hasFace && _clock.elapsedMilliseconds - _lastUpdateMs < 700;

  double get smoothedRoll => _roll.value;

  /// Ngưỡng há miệng = mốc miệng khép + 0.07 (tính theo chiều cao mặt).
  double get mouthThreshold => mouthBaseline + 0.07;

  /// -1..1, đã lật gương theo hướng tự nhiên (nghiêng sang phải -> sang phải).
  double get move {
    var d = _roll.value - baselineRoll;
    if (invert) d = -d;
    if (d.abs() <= deadzone) return 0;
    final s = d.sign * (d.abs() - deadzone);
    return (s / math.max(1, range - deadzone)).clamp(-1.0, 1.0);
  }

  bool get isSmiling => smile > 0.6;

  bool get eyesClosed => eyesClosedFor >= 0.8;

  void _onFace() {
    final s = face.state.value;
    hasFace = s.hasFace;
    _lastUpdateMs = _clock.elapsedMilliseconds;
    if (!s.hasFace) {
      _mouthFrames = 0;
      return;
    }
    rollRaw = s.roll;
    _roll.add(s.roll);
    smile = _smile.add(s.smile);
    _eye.add(s.eyeOpen);
    mouthRatio = s.mouthRatio;

    if (_calibrating) {
      _rollSamples.add(s.roll);
      if (s.mouthRatio != null) _mouthSamples.add(s.mouthRatio!);
    }

    final m = s.mouthRatio;
    if (m != null) {
      if (m > mouthThreshold) {
        _mouthFrames++;
        if (_mouthFrames >= 2 && _mouthArmed) {
          _mouthTrigger = true;
          _mouthArmed = false;
        }
      } else if (m < mouthThreshold * 0.6) {
        _mouthFrames = 0;
        _mouthArmed = true;
      }
    }
  }

  /// Gọi mỗi tick của game để cộng dồn thời gian nhắm mắt.
  void update(double dt) {
    if (faceOk && _eye.value < 0.3) {
      eyesClosedFor += dt;
    } else {
      eyesClosedFor = 0;
    }
  }

  /// Đọc và xoá cờ há miệng (rising edge).
  bool consumeMouthTrigger() {
    final t = _mouthTrigger;
    _mouthTrigger = false;
    return t;
  }

  void beginCalibration() {
    _calibrating = true;
    _rollSamples.clear();
    _mouthSamples.clear();
  }

  void cancelCalibration() => _calibrating = false;

  /// Chốt mốc 0: lấy trung bình góc đầu và độ há miệng khi khép.
  bool finishCalibration() {
    _calibrating = false;
    if (_rollSamples.length < 3) return false;
    baselineRoll = _rollSamples.reduce((a, b) => a + b) / _rollSamples.length;
    if (_mouthSamples.isNotEmpty) {
      mouthBaseline =
          (_mouthSamples.reduce((a, b) => a + b) / _mouthSamples.length).clamp(0.0, 0.08);
    }
    _roll.reset();
    return true;
  }

  int get calibrationSamples => _rollSamples.length;

  void resetRuntime() {
    eyesClosedFor = 0;
    _mouthFrames = 0;
    _mouthArmed = true;
    _mouthTrigger = false;
  }

  void dispose() => face.state.removeListener(_onFace);
}

/// Giá trị hiển thị cho màn Face Lab.
extension FaceStateX on FaceState {
  double get mouthNormalized => ((mouthRatio ?? 0) / 0.2).clamp(0.0, 1.0);
}
