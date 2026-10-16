import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../core/face_controller.dart';
import '../core/face_state.dart';
import '../core/frame_monitor.dart';
import 'mesh_painter.dart';
import 'palette.dart';

/// Ảnh camera (lấp đầy khung) + lưới Face Mesh tuỳ chọn. Camera trước tự lật gương.
class FaceView extends StatelessWidget {
  const FaceView({super.key, required this.face, this.showMesh = true, this.showTriangles = true});

  final FaceController face;
  final bool showMesh;
  final bool showTriangles;

  @override
  Widget build(BuildContext context) {
    final c = face.camera;
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(color: Colors.black, child: Center(child: CircularProgressIndicator()));
    }
    final ps = c.value.previewSize!;
    // previewSize luôn ở dạng ngang; ở chế độ dọc thì đảo lại.
    final w = ps.height, h = ps.width;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(c),
              if (showMesh)
                ValueListenableBuilder<MeshFrame?>(
                  valueListenable: face.mesh,
                  builder: (_, m, _) => CustomPaint(
                    painter: MeshPainter(m, mirror: face.isFront, showTriangles: showTriangles),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dòng chữ nhỏ FPS / độ trễ - bằng chứng "on-device, độ trễ thấp".
class PerfPill extends StatelessWidget {
  const PerfPill({super.key, required this.face});
  final FaceController face;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([face.stats, FrameMonitor.instance.stats]),
      builder: (_, _) {
        final s = face.stats.value;
        final ui = FrameMonitor.instance.stats.value;
        final mesh = s.meshOk ? 'Mesh ${s.meshMs}ms' : 'Mesh→contours';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Pal.green.withValues(alpha: 0.7)),
          ),
          child: Text(
            '🎮 ${ui.fps.toStringAsFixed(0)} FPS · 🧠 ML ${s.fps.toStringAsFixed(0)} FPS · Detect ${s.detectMs}ms · $mesh',
            style: const TextStyle(
              color: Pal.green,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        );
      },
    );
  }
}
