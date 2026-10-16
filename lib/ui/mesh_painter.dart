import 'package:flutter/material.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';

import '../core/face_state.dart';

/// Vẽ lưới 468 điểm + các đường viền (mắt, môi, lông mày, oval mặt) lên ảnh camera.
class MeshPainter extends CustomPainter {
  MeshPainter(this.frame, {required this.mirror, this.showTriangles = true});

  final MeshFrame? frame;
  final bool mirror;
  final bool showTriangles;

  static const contourColors = <FaceMeshContourType, Color>{
    FaceMeshContourType.faceOval: Color(0xFFFFFFFF),
    FaceMeshContourType.leftEyebrowTop: Color(0xFFFFD43B),
    FaceMeshContourType.leftEyebrowBottom: Color(0xFFFFD43B),
    FaceMeshContourType.rightEyebrowTop: Color(0xFFFFD43B),
    FaceMeshContourType.rightEyebrowBottom: Color(0xFFFFD43B),
    FaceMeshContourType.leftEye: Color(0xFF3DDBD9),
    FaceMeshContourType.rightEye: Color(0xFF3DDBD9),
    FaceMeshContourType.upperLipTop: Color(0xFFFF5D8F),
    FaceMeshContourType.upperLipBottom: Color(0xFFFF5D8F),
    FaceMeshContourType.lowerLipTop: Color(0xFFFF5D8F),
    FaceMeshContourType.lowerLipBottom: Color(0xFFFF5D8F),
    FaceMeshContourType.noseBridge: Color(0xFFA78BFA),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame;
    if (f == null || f.imageSize.isEmpty) return;
    final sx = size.width / f.imageSize.width;
    final sy = size.height / f.imageSize.height;
    Offset map(Offset p) => Offset((mirror ? f.imageSize.width - p.dx : p.dx) * sx, p.dy * sy);

    if (showTriangles) {
      final path = Path();
      final t = f.triangles;
      final pts = f.points;
      for (var i = 0; i + 2 < t.length; i += 3) {
        final a = map(pts[t[i]]), b = map(pts[t[i + 1]]), c = map(pts[t[i + 2]]);
        path
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(c.dx, c.dy)
          ..close();
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = Colors.white.withValues(alpha: 0.38),
      );
    }

    for (final entry in f.contours.entries) {
      final pts = entry.value;
      if (pts.length < 2) continue;
      final path = Path()..moveTo(map(pts.first).dx, map(pts.first).dy);
      for (final p in pts.skip(1)) {
        final m = map(p);
        path.lineTo(m.dx, m.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..color = contourColors[entry.key] ?? Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant MeshPainter old) => old.frame != frame || old.mirror != mirror;
}
