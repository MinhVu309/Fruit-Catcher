import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/audio_service.dart';
import '../core/face_state.dart';
import '../game/game_engine.dart';
import '../game/game_painter.dart';
import '../services.dart';
import 'face_view.dart';
import 'palette.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  late Services _s;
  late GameEngine _engine;
  late final Ticker _ticker;
  late final GamePainter _painter;

  Duration _last = Duration.zero;
  double _touchNorm = 0;
  bool _ready = false;
  bool _saved = false;
  bool _newBest = false;
  Phase _lastPhase = Phase.countdown;
  int _lastLevel = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;
    _s = Services.of(context);
    _s.face.acquire();
    _s.hub.invert = _s.settings.invertTilt;
    _s.hub.range = _s.settings.tiltRange;
    _s.hub.resetRuntime();
    _engine = GameEngine(best: _s.scores.best)
      ..onEvent = _onEvent
      ..start();
    _s.audio.startMusic();
    _painter = GamePainter(_engine);
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    final faceMode = _s.settings.faceControl;
    _s.hub.update(dt);
    _engine.update(
      dt,
      GameInput(
        move: faceMode ? _s.hub.move : _touchNorm,
        faceControlled: faceMode,
        faceOk: _s.hub.faceOk,
        smiling: faceMode && _s.hub.isSmiling,
        eyesClosed: faceMode && _s.hub.eyesClosed,
        skill: faceMode && _s.hub.consumeMouthTrigger(),
      ),
    );
    _syncMusic();
    if (_engine.phase == Phase.over && !_saved) {
      _saved = true;
      _s.scores.add(_s.settings.playerName, _engine.score).then((b) {
        if (mounted) setState(() => _newBest = b);
      });
      setState(() {});
    }
  }

  void _onEvent(GameEvent e, int n) {
    final a = _s.audio;
    switch (e) {
      case GameEvent.catchFruit:
        a.play(Sfx.catchFruit, n: n);
      case GameEvent.catchBig:
        a.play(Sfx.catchFruit, n: n);
        a.play(Sfx.bonus);
      case GameEvent.hitBomb:
        a.play(Sfx.bomb);
      case GameEvent.hitChili:
        a.play(Sfx.chili);
      case GameEvent.heart:
        a.play(Sfx.heart);
      case GameEvent.skill:
        a.play(Sfx.skill);
      case GameEvent.combo:
        a.play(Sfx.combo);
      case GameEvent.levelUp:
        a.play(Sfx.levelUp);
      case GameEvent.gameOver:
        a.play(Sfx.gameOver);
      case GameEvent.newBest:
        a.play(Sfx.newBest);
      case GameEvent.tick:
        a.play(Sfx.tick);
      case GameEvent.go:
        a.play(Sfx.go);
      case GameEvent.pause:
        a.play(Sfx.pause);
      case GameEvent.resume:
        a.play(Sfx.resume);
    }
  }

  /// Nhạc nền theo trạng thái game, nhanh dần theo level.
  void _syncMusic() {
    final ph = _engine.phase;
    if (ph != _lastPhase) {
      if (ph == Phase.paused) {
        _s.audio.pauseMusic();
      } else if (ph == Phase.over) {
        _s.audio.stopMusic();
      } else if (_lastPhase == Phase.paused) {
        _s.audio.resumeMusic();
      }
      _lastPhase = ph;
    }
    if (_engine.level != _lastLevel) {
      _lastLevel = _engine.level;
      _s.audio.setMusicRate((1 + 0.03 * (_lastLevel - 1)).clamp(1.0, 1.25));
    }
  }

  void _restart() {
    _s.audio.play(Sfx.click);
    _s.audio.setMusicRate(1);
    _s.audio.startMusic();
    _lastPhase = Phase.countdown;
    _lastLevel = 1;
    setState(() {
      _saved = false;
      _newBest = false;
      _engine.best = _s.scores.best;
      _engine.start();
      _s.hub.resetRuntime();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _s.audio.stopMusic();
    _s.audio.setMusicRate(1);
    _painter.dispose();
    _engine.dispose();
    _s.face.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    _painter.dpr = mq.devicePixelRatio;
    final headerH = mq.padding.top + 132;
    final faceMode = _s.settings.faceControl;
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, box) {
          _engine.resize(Size(box.maxWidth, box.maxHeight), headerH);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: faceMode
                ? null
                : (d) {
                    final x = d.localPosition.dx / box.maxWidth;
                    _touchNorm = ((x - 0.5) * 2).clamp(-1.0, 1.0);
                  },
            onPanStart: faceMode
                ? null
                : (d) => _touchNorm = ((d.localPosition.dx / box.maxWidth - 0.5) * 2).clamp(-1.0, 1.0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(child: CustomPaint(painter: _painter, size: Size.infinite)),
                _header(headerH, mq.padding.top),
                if (_s.settings.showDebug && faceMode) _debugBar(mq.padding.bottom),
                if (!faceMode) _touchHint(mq.padding.bottom),
                _overlay(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header(double h, double topPad) {
    final faceMode = _s.settings.faceControl;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: h,
      child: Container(
        padding: EdgeInsets.fromLTRB(12, topPad + 8, 12, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.72), Colors.black.withValues(alpha: 0.38)],
          ),
        ),
        child: Row(
          children: [
            if (faceMode)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 82,
                  height: 116,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white54, width: 1.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: RepaintBoundary(
                    child: FaceView(face: _s.face, showMesh: _s.settings.showMesh, showTriangles: false),
                  ),
                ),
              ),
            if (faceMode) const SizedBox(width: 12),
            Expanded(child: ListenableBuilder(listenable: _engine, builder: (_, _) => _stats())),
          ],
        ),
      ),
    );
  }

  Widget _stats() {
    final e = _engine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Transform.scale(
              scale: 1 + 0.35 * Curves.easeOut.transform(e.scoreBump),
              alignment: Alignment.bottomLeft,
              child: Text(
                '${e.score}',
                style: TextStyle(
                  color: e.scoreBump > 0 ? Pal.amber : Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('🏆 ${e.best}', style: const TextStyle(color: Pal.amber, fontWeight: FontWeight.w800)),
            ),
            const Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () {
                _s.audio.play(Sfx.click);
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (var i = 0; i < GameEngine.maxLives; i++)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Text(i < e.lives ? '❤️' : '🖤', style: const TextStyle(fontSize: 22)),
              ),
            const SizedBox(width: 8),
            _chip('Lv ${e.level}', Pal.teal),
            if (e.combo >= 3) ...[
              const SizedBox(width: 6),
              _chip(e.fever ? '🔥 FEVER x${e.combo}' : '🔥 x${e.combo}', Pal.amber),
            ],
            if (e.multiplier) ...[const SizedBox(width: 6), _chip('😁 x2', Pal.pink)],
          ],
        ),
        const SizedBox(height: 8),
        if (_s.settings.faceControl) _skillBar(),
      ],
    );
  }

  Widget _skillBar() {
    final e = _engine;
    final ready = e.skillReady;
    return Row(
      children: [
        Text(ready ? '😮' : '😐', style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: e.skill,
              minHeight: 10,
              backgroundColor: Colors.white24,
              color: ready ? Pal.amber : Pal.teal,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          ready ? 'HÁ MIỆNG!' : 'Skill',
          style: TextStyle(
            color: ready ? Pal.amber : Colors.white70,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c),
        ),
        child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 12)),
      );

  Widget _debugBar(double bottomPad) {
    return Positioned(
      left: 10,
      right: 10,
      bottom: bottomPad + 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<FaceState>(
            valueListenable: _s.face.state,
            builder: (_, st, _) {
              final h = _s.hub;
              final m = st.mouthRatio;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Z ${st.roll.toStringAsFixed(1)}° (mốc ${h.baselineRoll.toStringAsFixed(1)}°)  '
                  '😁 ${(st.smile * 100).round()}%  '
                  '👁 ${(st.eyeOpen * 100).round()}%  '
                  '👄 ${m == null ? '--' : m.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          PerfPill(face: _s.face),
        ],
      ),
    );
  }

  Widget _touchHint(double bottomPad) => Positioned(
        left: 0,
        right: 0,
        bottom: bottomPad + 10,
        child: const Center(
          child: Text('Kéo ngón tay trái/phải để di chuyển giỏ',
              style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _overlay() {
    return ListenableBuilder(
      listenable: _engine,
      builder: (_, _) {
        final e = _engine;
        switch (e.phase) {
          case Phase.playing:
            return const SizedBox.shrink();
          case Phase.countdown:
            final frac = e.countdown - e.countdown.floor();
            return IgnorePointer(
              child: Center(
                child: Opacity(
                  opacity: (0.35 + frac).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.8 + 0.9 * frac,
                    child: Text(
                      e.countdown.ceil().clamp(1, 3).toString(),
                      style: TextStyle(
                        fontSize: 140,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 12)],
                      ),
                    ),
                  ),
                ),
              ),
            );
          case Phase.paused:
            final noFace = e.pauseReason == PauseReason.noFace;
            return _panel(
              emoji: noFace ? '🙈' : '😴',
              title: noFace ? 'Hãy nhìn vào camera' : 'Tạm dừng',
              subtitle: noFace ? 'Game sẽ tiếp tục khi thấy mặt bạn' : 'Mở mắt ra để chơi tiếp',
            );
          case Phase.over:
            return _gameOver();
        }
      },
    );
  }

  Widget _panel({required String emoji, required String title, required String subtitle, List<Widget> actions = const []}) {
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 84)),
          const SizedBox(height: 8),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Pal.muted, fontSize: 15)),
          if (actions.isNotEmpty) const SizedBox(height: 24),
          ...actions,
        ],
      ),
    );
  }

  Widget _gameOver() {
    final e = _engine;
    return _panel(
      emoji: _newBest ? '🏆' : '💥',
      title: _newBest ? 'KỶ LỤC MỚI!' : 'Hết mạng!',
      subtitle: 'Điểm: ${e.score}   ·   Kỷ lục: ${e.best}\nBắt được ${e.caught} trái · Combo cao nhất x${e.bestCombo}',
      actions: [
        FilledButton.icon(
          onPressed: _restart,
          style: FilledButton.styleFrom(backgroundColor: Pal.amber, foregroundColor: Colors.black, minimumSize: const Size(220, 52)),
          icon: const Icon(Icons.replay_rounded),
          label: const Text('Chơi lại', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () {
            _s.audio.play(Sfx.click);
            Navigator.of(context).pop();
          },
          child: const Text('Về menu', style: TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}
