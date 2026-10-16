import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/audio_service.dart';
import '../services.dart';
import 'calibration_screen.dart';
import 'game_screen.dart';
import 'lab_screen.dart';
import 'palette.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  late final TextEditingController _name;
  bool _init = false;
  late Services _s;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    _s = Services.of(context);
    _name = TextEditingController(text: _s.settings.playerName);
  }

  @override
  void dispose() {
    _bob.dispose();
    _name.dispose();
    super.dispose();
  }

  void _play() {
    _s.audio.play(Sfx.click);
    FocusScope.of(context).unfocus();
    _s.settings.update(playerName: _name.text.trim());
    final faceMode = _s.settings.faceControl;
    if (faceMode && !_s.face.ready) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => faceMode ? const CalibrationScreen() : const GameScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Pal.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([_s.face, _s.settings, _s.scores]),
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              _title(),
              const SizedBox(height: 18),
              _cameraStatus(),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                style: const TextStyle(color: Pal.text),
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Tên người chơi (để lên bảng xếp hạng)',
                  labelStyle: const TextStyle(color: Pal.muted),
                  prefixIcon: const Icon(Icons.person_rounded, color: Pal.muted),
                  filled: true,
                  fillColor: Pal.card,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 14),
              _bigButton('▶  CHƠI NGAY', Pal.amber, Colors.black, _play),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _smallButton(Icons.face_retouching_natural_rounded, 'Face Lab', () {
                      if (!_s.face.ready) return;
                      _s.audio.play(Sfx.click);
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LabScreen()));
                    }),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _smallButton(Icons.help_outline_rounded, 'Cách chơi', _howTo)),
                ],
              ),
              const SizedBox(height: 18),
              _leaderboard(),
              const SizedBox(height: 18),
              _settingsCard(),
              const SizedBox(height: 18),
              const Center(
                child: Text(
                  '✈ ML Kit chạy on-device: không cần mạng, không gửi ảnh đi đâu',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Pal.muted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _title() {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _bob,
          builder: (_, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 4; i++)
                Transform.translate(
                  offset: Offset(0, -8 * math.sin((_bob.value * 2 * math.pi) - i * 0.9).abs()),
                  child: Text(['🧺', '🍎', '🍊', '🍌'][i], style: const TextStyle(fontSize: 40)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text('Fruit Catcher',
            style: TextStyle(color: Pal.text, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        const SizedBox(height: 2),
        const Text('Hứng trái cây bằng khuôn mặt của bạn',
            style: TextStyle(color: Pal.amber, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: const [
            _Tag('ML Kit Face Detection'),
            _Tag('ML Kit Face Mesh'),
            _Tag('On-device'),
          ],
        ),
      ],
    );
  }

  Widget _cameraStatus() {
    final f = _s.face;
    final Color c;
    final String t;
    if (f.error != null) {
      c = Pal.pink;
      t = f.error!;
    } else if (f.ready) {
      c = Pal.green;
      t = 'Camera sẵn sàng';
    } else {
      c = Pal.amber;
      t = 'Đang khởi động camera…';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(f.error != null ? Icons.error_outline_rounded : Icons.videocam_rounded, color: c),
          const SizedBox(width: 10),
          Expanded(child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w700))),
          if (f.error != null) TextButton(onPressed: f.init, child: const Text('Thử lại')),
        ],
      ),
    );
  }

  Widget _bigButton(String t, Color bg, Color fg, VoidCallback onTap) => SizedBox(
        height: 60,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          child: Text(t, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ),
      );

  Widget _smallButton(IconData i, String t, VoidCallback onTap) => SizedBox(
        height: 50,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(i, color: Pal.teal),
          label: Text(t, style: const TextStyle(color: Pal.text, fontWeight: FontWeight.w800)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Pal.card2, width: 1.5),
            backgroundColor: Pal.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );

  Widget _leaderboard() {
    final top = _s.scores.top;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Pal.card, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🏆 Bảng xếp hạng', style: TextStyle(color: Pal.text, fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (top.isEmpty)
            const Text('Chưa có ai. Hãy là người đầu tiên!', style: TextStyle(color: Pal.muted))
          else
            for (var i = 0; i < top.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 30,
                      child: Text(['🥇', '🥈', '🥉', '4', '5'][i], style: const TextStyle(fontSize: 18, color: Pal.muted)),
                    ),
                    Expanded(
                      child: Text(top[i].name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Pal.text, fontWeight: FontWeight.w700)),
                    ),
                    Text('${top[i].score}',
                        style: const TextStyle(color: Pal.amber, fontWeight: FontWeight.w900, fontSize: 16)),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _settingsCard() {
    final st = _s.settings;
    Widget sw(String t, String sub, bool v, ValueChanged<bool> on) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: v,
          onChanged: on,
          activeThumbColor: Pal.amber,
          title: Text(t, style: const TextStyle(color: Pal.text, fontWeight: FontWeight.w700)),
          subtitle: Text(sub, style: const TextStyle(color: Pal.muted, fontSize: 12)),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(color: Pal.card, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          sw('Âm thanh hiệu ứng', 'Tiếng hứng trái, bom, combo…', st.soundOn, (v) {
            st.update(soundOn: v);
            if (v) _s.audio.play(Sfx.combo);
          }),
          sw('Nhạc nền', 'Nhạc vui nhộn khi chơi, nhanh dần theo level', st.musicOn, (v) => st.update(musicOn: v)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _soundTest,
              icon: const Icon(Icons.volume_up_rounded, color: Pal.teal),
              label: const Text('Thử âm thanh', style: TextStyle(color: Pal.teal, fontWeight: FontWeight.w800)),
            ),
          ),
          sw('Điều khiển bằng khuôn mặt', 'Tắt = kéo ngón tay (dự phòng)', st.faceControl, (v) => st.update(faceControl: v)),
          sw('Hiện lưới Face Mesh', 'Lưới 468 điểm trong ô camera', st.showMesh, (v) => st.update(showMesh: v)),
          sw('Hiện FPS / độ trễ', 'Chứng minh on-device, độ trễ thấp', st.showDebug, (v) => st.update(showDebug: v)),
          sw('Đảo chiều nghiêng', 'Nếu giỏ đi ngược hướng đầu', st.invertTilt, (v) => st.update(invertTilt: v)),
          Row(
            children: [
              const Text('Độ nhạy', style: TextStyle(color: Pal.text, fontWeight: FontWeight.w700)),
              Expanded(
                child: Slider(
                  value: 50 - st.tiltRange, // kéo phải = nhạy hơn (cần nghiêng ít hơn)
                  min: 10,
                  max: 35,
                  activeColor: Pal.amber,
                  onChanged: (v) => st.update(tiltRange: 50 - v),
                ),
              ),
              Text('${st.tiltRange.round()}°', style: const TextStyle(color: Pal.muted)),
            ],
          ),
        ],
      ),
    );
  }

  /// Phát thử vài tiếng liên tiếp để kiểm tra loa (hiệu ứng, nhạc nền).
  Future<void> _soundTest() async {
    final a = _s.audio;
    if (!_s.settings.soundOn) {
      _s.settings.update(soundOn: true);
    }
    for (var i = 0; i < 5; i++) {
      a.play(Sfx.catchFruit, n: i);
      await Future<void>.delayed(const Duration(milliseconds: 130));
    }
    a.play(Sfx.combo);
    if (_s.settings.musicOn) {
      await a.startMusic();
      await Future<void>.delayed(const Duration(seconds: 3));
      await a.stopMusic();
    }
  }

  void _howTo() {
    _s.audio.play(Sfx.click);
    const rows = [
      ('↔️', 'Nghiêng đầu trái/phải', 'Giỏ chạy theo'),
      ('😮', 'Há miệng', 'Skill: ăn hết trái, nổ hết bom (hồi 12s)'),
      ('😁', 'Cười', 'Điểm x2 khi đang cười'),
      ('😴', 'Nhắm mắt > 0.8s', 'Tạm dừng'),
      ('🙈', 'Mất mặt', 'Tự tạm dừng, thấy mặt lại thì đếm ngược'),
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Pal.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Cách chơi', style: TextStyle(color: Pal.text, fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Text(r.$1, style: const TextStyle(fontSize: 26)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.$2, style: const TextStyle(color: Pal.text, fontWeight: FontWeight.w800)),
                            Text(r.$3, style: const TextStyle(color: Pal.muted, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              const Text('🍎🍊🍌🍇 +10  ·  🍉 +20  ·  ❤️ +1 mạng  ·  💣🌶️ mất 1 mạng',
                  style: TextStyle(color: Pal.amber, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Pal.card2,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: const TextStyle(color: Pal.teal, fontSize: 11, fontWeight: FontWeight.w800)),
      );
}
