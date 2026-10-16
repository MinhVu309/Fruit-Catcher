import 'dart:async';

import 'package:flutter/material.dart';

import '../services.dart';
import 'face_view.dart';
import 'game_screen.dart';
import 'palette.dart';

/// 2 giây đầu: nhìn thẳng để lấy góc đầu làm mốc 0 (và độ khép miệng làm mốc).
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  static const _duration = 2.0;
  late Services _s;
  Timer? _timer;
  double _progress = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final s = _s = Services.of(context);
    s.face.acquire();
    s.hub.invert = s.settings.invertTilt;
    s.hub.range = s.settings.tiltRange;
    _begin(s);
  }

  void _begin(Services s) {
    _timer?.cancel();
    s.hub.beginCalibration();
    _progress = 0;
    var last = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final now = DateTime.now();
      final dt = now.difference(last).inMicroseconds / 1e6;
      last = now;
      if (!s.hub.faceOk) {
        // Mất mặt thì làm lại từ đầu để mốc chính xác.
        s.hub.beginCalibration();
        setState(() => _progress = 0);
        return;
      }
      setState(() => _progress += dt / _duration);
      if (_progress >= 1) {
        _timer?.cancel();
        if (s.hub.finishCalibration() && mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const GameScreen()),
          );
        } else {
          _begin(s);
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _s.hub.cancelCalibration();
    _s.face.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final ok = s.hub.faceOk;
    return Scaffold(
      backgroundColor: Pal.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          FaceView(face: s.face, showMesh: s.settings.showMesh, showTriangles: false),
          Container(color: Colors.black.withValues(alpha: 0.35)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 120,
                          height: 120,
                          child: CircularProgressIndicator(
                            value: ok ? _progress.clamp(0, 1) : null,
                            strokeWidth: 8,
                            color: ok ? Pal.green : Pal.pink,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                        Text(ok ? '😐' : '🙈', style: const TextStyle(fontSize: 48)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: [
                        Text(
                          ok ? 'Nhìn thẳng, giữ đầu thẳng…' : 'Hãy nhìn vào camera',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Đang hiệu chỉnh mốc 0 cho góc đầu và miệng khép',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Pal.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
