import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';

/// Kết quả đã rút gọn của Face Detection (một khung hình).
class FaceState {
  final bool hasFace;

  /// headEulerAngleZ (độ): nghiêng đầu sang trái/phải.
  final double roll;

  /// smilingProbability (0..1).
  final double smile;

  /// Trung bình leftEyeOpenProbability và rightEyeOpenProbability (0..1).
  final double eyeOpen;

  /// Độ há miệng = khoảng cách môi trên-dưới / chiều cao khuôn mặt. Null nếu chưa đo được.
  final double? mouthRatio;

  const FaceState({
    required this.hasFace,
    this.roll = 0,
    this.smile = 0,
    this.eyeOpen = 1,
    this.mouthRatio,
  });

  static const none = FaceState(hasFace: false);
}

/// Dữ liệu Face Mesh (468 điểm) đã quy về toạ độ ảnh "dựng đứng".
class MeshFrame {
  final Size imageSize;
  final List<Offset> points;
  final Map<FaceMeshContourType, List<Offset>> contours;

  /// Chỉ số đỉnh của các tam giác (3 số mỗi tam giác) - cố định, chỉ cần lấy một lần.
  final Uint16List triangles;

  const MeshFrame({
    required this.imageSize,
    required this.points,
    required this.contours,
    required this.triangles,
  });
}

/// Số liệu hiệu năng để chứng minh "on-device, độ trễ thấp".
class PerfStats {
  final double fps;
  final int detectMs;
  final int meshMs;
  final bool meshOk;
  final bool contourFallback;
  final Size imageSize;
  final int rotation;

  const PerfStats({
    this.fps = 0,
    this.detectMs = 0,
    this.meshMs = 0,
    this.meshOk = true,
    this.contourFallback = false,
    this.imageSize = Size.zero,
    this.rotation = 0,
  });
}
