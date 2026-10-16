import 'package:flutter/material.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';

import '../core/face_state.dart';
import '../core/input_hub.dart';
import '../services.dart';
import 'face_view.dart';
import 'mesh_painter.dart';
import 'palette.dart';

/// Màn "Face Lab": phục vụ phần thuyết trình - lưới mặt, landmark và mọi thông số ML Kit.
class LabScreen extends StatefulWidget {
  const LabScreen({super.key});

  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> {
  late Services _s;
  bool _init = false;
  bool _triangles = true;
  bool _mesh = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    _s = Services.of(context);
    _s.face.acquire();
  }

  @override
  void dispose() {
    _s.face.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          FaceView(face: _s.face, showMesh: _mesh, showTriangles: _triangles),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      ),
                      const Text('Face Lab',
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                      const Spacer(),
                      _toggle('Lưới', _mesh, (v) => setState(() => _mesh = v)),
                      const SizedBox(width: 6),
                      _toggle('Tam giác', _triangles, (v) => setState(() => _triangles = v)),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                PerfPill(face: _s.face),
                const Spacer(),
                _legend(),
                const SizedBox(height: 8),
                _readouts(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label, style: TextStyle(color: value ? Colors.black : Colors.white, fontWeight: FontWeight.w700)),
      selected: value,
      onSelected: onChanged,
      selectedColor: Pal.teal,
      backgroundColor: Colors.black54,
      checkmarkColor: Colors.black,
      side: BorderSide.none,
    );
  }

  Widget _legend() {
    Widget dot(String t, Color c) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(t, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        );
    final c = MeshPainter.contourColors;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        children: [
          dot('Oval mặt', c[FaceMeshContourType.faceOval]!),
          dot('Lông mày', c[FaceMeshContourType.leftEyebrowTop]!),
          dot('Mắt', c[FaceMeshContourType.leftEye]!),
          dot('Môi', c[FaceMeshContourType.upperLipTop]!),
          dot('Sống mũi', c[FaceMeshContourType.noseBridge]!),
          const Text('468 điểm 3D', style: TextStyle(color: Pal.muted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _readouts() {
    return ValueListenableBuilder<FaceState>(
      valueListenable: _s.face.state,
      builder: (_, st, _) {
        final roll = st.roll;
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Pal.card.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(18)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!st.hasFace)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text('Không thấy khuôn mặt - hãy nhìn vào camera',
                      style: TextStyle(color: Pal.pink, fontWeight: FontWeight.w800)),
                ),
              _bar('Nghiêng đầu (headEulerAngleZ)', '${roll.toStringAsFixed(1)}°', (roll / 45).clamp(-1.0, 1.0), Pal.amber, centered: true),
              _bar('Cười (smilingProbability)', '${(st.smile * 100).round()}%', st.smile, Pal.pink),
              _bar('Mở mắt (left/rightEyeOpenProbability)', '${(st.eyeOpen * 100).round()}%', st.eyeOpen, Pal.teal),
              _bar('Há miệng (Face Mesh: môi trên-dưới / cao mặt)',
                  st.mouthRatio == null ? '--' : st.mouthRatio!.toStringAsFixed(3), st.mouthNormalized, Pal.green),
              const SizedBox(height: 6),
              ValueListenableBuilder<PerfStats>(
                valueListenable: _s.face.stats,
                builder: (_, p, _) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Ảnh ML Kit: ${p.imageSize.width.toInt()}×${p.imageSize.height.toInt()} · xoay ${p.rotation}°',
                        style: const TextStyle(color: Pal.muted, fontSize: 11)),
                    GestureDetector(
                      onTap: () => setState(() => _s.face.rotationOffset = (_s.face.rotationOffset + 90) % 360),
                      child: Text('↻ Xoay ảnh +90° (${_s.face.rotationOffset}°)',
                          style: const TextStyle(color: Pal.teal, fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bar(String label, String value, double v, Color color, {bool centered = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(label, style: const TextStyle(color: Pal.muted, fontSize: 11, fontWeight: FontWeight.w600))),
              Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 8,
            child: LayoutBuilder(builder: (_, box) {
              final w = box.maxWidth;
              final left = centered ? (v >= 0 ? w / 2 : w / 2 + v * w / 2) : 0.0;
              final width = centered ? v.abs() * w / 2 : v.clamp(0.0, 1.0) * w;
              return Stack(children: [
                Container(decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(4))),
                Positioned(
                  left: left,
                  width: width,
                  top: 0,
                  bottom: 0,
                  child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
                ),
                if (centered) Positioned(left: w / 2 - 1, width: 2, top: 0, bottom: 0, child: Container(color: Colors.white54)),
              ]);
            }),
          ),
        ],
      ),
    );
  }
}
