import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'game_engine.dart';

/// Vẽ toàn bộ thế giới game bằng Canvas (nền, vật phẩm, giỏ, hiệu ứng).
class GamePainter extends CustomPainter {
  GamePainter(this.engine) : super(repaint: engine);

  final GameEngine engine;

  /// Tỉ lệ điểm ảnh của màn hình, để sprite vẽ sẵn luôn sắc nét.
  double dpr = 1;

  // Emoji và chữ được vẽ sẵn MỘT LẦN thành ảnh (sprite), mỗi khung chỉ còn dán ảnh lên.
  // Dàn chữ/emoji màu mỗi khung hình là phần tốn GPU nhất trước đây.
  final _sprites = <String, ui.Image>{};
  final _textSprites = <Object, ui.Image>{}; // theo từng Popup / ScreenBanner
  final _spritePaint = Paint()..filterQuality = FilterQuality.medium;

  // Bảng màu bầu trời: ngày → hoàng hôn → chiều tối → đêm. Level lên là trời đổi màu.
  static const _sky = [
    [Color(0xFF5BB8FF), Color(0xFFA8DEFF), Color(0xFFFFEFC2)],
    [Color(0xFF5A8FE0), Color(0xFFFFB38A), Color(0xFFFFE3A8)],
    [Color(0xFF2E2A6B), Color(0xFF9B4FA8), Color(0xFFFF9A8F)],
    [Color(0xFF0B1030), Color(0xFF1B2358), Color(0xFF3A3F7A)],
  ];
  static const _dark = [0.0, 0.2, 0.6, 1.0];

  late final List<Offset> _stars = () {
    final r = math.Random(11);
    return List.generate(46, (_) => Offset(r.nextDouble(), r.nextDouble() * 0.7));
  }();

  ui.Image _render(double w, double h, void Function(Canvas c) draw) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)..scale(dpr);
    draw(c);
    final pic = rec.endRecording();
    final img = pic.toImageSync(math.max(1, (w * dpr).ceil()), math.max(1, (h * dpr).ceil()));
    pic.dispose();
    return img;
  }

  ui.Image _emoji(String s, double fontSize) {
    return _sprites.putIfAbsent('$s@${fontSize.round()}', () {
      final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontSize: fontSize, height: 1)),
        textDirection: TextDirection.ltr,
      )..layout();
      final pad = fontSize * 0.1;
      return _render(tp.width + 2 * pad, tp.height + 2 * pad, (c) => tp.paint(c, Offset(pad, pad)));
    });
  }

  /// Chữ đậm có viền tối, vẽ sẵn thành ảnh.
  ui.Image _outlinedText(String text, double fontSize, Color fill, {double stroke = 0.2, double spacing = 0}) {
    TextPainter tp(Paint? fg, Color? color) => TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              letterSpacing: spacing,
              foreground: fg,
              color: fg == null ? color : null,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
    final outline = tp(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = fontSize * stroke
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF1B1F3B),
      null,
    );
    final body = tp(null, fill);
    final pad = fontSize * stroke;
    return _render(outline.width + 2 * pad, outline.height + 2 * pad, (c) {
      outline.paint(c, Offset(pad, pad));
      body.paint(c, Offset(pad, pad));
    });
  }

  /// Dán sprite canh giữa tại gốc toạ độ hiện tại, có độ mờ.
  void _sprite(Canvas canvas, ui.Image img, [double opacity = 1]) {
    final w = img.width / dpr, h = img.height / dpr;
    _spritePaint.color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0));
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      _spritePaint,
    );
  }

  /// Bỏ ảnh của popup/banner đã biến mất.
  void _pruneTextSprites() {
    final alive = <Object>{...engine.popups, ?engine.banner};
    _textSprites.removeWhere((k, img) {
      if (alive.contains(k)) return false;
      img.dispose();
      return true;
    });
  }

  void dispose() {
    for (final img in _sprites.values) {
      img.dispose();
    }
    for (final img in _textSprites.values) {
      img.dispose();
    }
    _sprites.clear();
    _textSprites.clear();
  }

  /// Nội suy màu / số theo vị trí liên tục trong bảng màu (vòng tròn qua 4 pha).
  (int, int, double) _phase() {
    final p = engine.skyPos < 0 ? 0.0 : engine.skyPos;
    final i = p.floor();
    return (i % _sky.length, (i + 1) % _sky.length, p - i);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final e = engine;
    canvas.save();
    if (e.shake > 0) {
      final k = e.shake * 28;
      canvas.translate(math.sin(e.time * 90) * k, math.cos(e.time * 70) * k * 0.6);
    }
    _background(canvas, size);
    if (e.fever) _feverGlow(canvas, size);
    _items(canvas, size);
    _basket(canvas, size);
    _particles(canvas);
    _popups(canvas);
    canvas.restore();

    _banner(canvas, size);

    if (e.hitFlash > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.transparent,
              const Color(0xFFFF2D2D).withValues(alpha: 0.55 * (e.hitFlash / 0.45)),
            ],
            stops: const [0.45, 1],
          ).createShader(Offset.zero & size),
      );
    }
    if (e.skillFlash > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: 0.55 * (e.skillFlash / 0.6)),
      );
      final ring = (1 - e.skillFlash / 0.6);
      canvas.drawCircle(
        Offset(e.basketX, e.basketTop),
        size.width * (0.2 + ring * 1.2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10 * (1 - ring)
          ..color = const Color(0xFFFFE066).withValues(alpha: 1 - ring),
      );
    }
  }

  void _background(Canvas canvas, Size size) {
    final e = engine;
    final rect = Offset.zero & size;
    final (a, b, t) = _phase();
    final top = Color.lerp(_sky[a][0], _sky[b][0], t)!;
    final mid = Color.lerp(_sky[a][1], _sky[b][1], t)!;
    final bot = Color.lerp(_sky[a][2], _sky[b][2], t)!;
    final dark = _dark[a] + (_dark[b] - _dark[a]) * t;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, mid, bot],
        ).createShader(rect),
    );

    // Sao nhấp nháy khi trời tối.
    if (dark > 0.45) {
      final alpha = ((dark - 0.45) / 0.55).clamp(0.0, 1.0);
      final p = Paint();
      for (var i = 0; i < _stars.length; i++) {
        final tw = 0.5 + 0.5 * math.sin(e.time * 2 + i * 1.7);
        p.color = Colors.white.withValues(alpha: alpha * (0.35 + 0.65 * tw));
        canvas.drawCircle(
          Offset(_stars[i].dx * size.width, e.topInset + _stars[i].dy * (size.height - e.topInset)),
          0.8 + (i % 3) * 0.5,
          p,
        );
      }
    }

    // Mặt trời → mặt trăng
    final sunColor = Color.lerp(const Color(0xFFFFE27A), const Color(0xFFF4F1FF), dark)!;
    final sc = Offset(size.width * 0.84, e.topInset + size.width * 0.16 + dark * 10);
    canvas.drawCircle(sc, size.width * 0.09 * 1.35, Paint()..color = Colors.white.withValues(alpha: 0.22 * (1 - dark)));
    canvas.drawCircle(sc, size.width * 0.09, Paint()..color = sunColor);
    if (dark > 0.6) {
      final cr = Paint()..color = const Color(0xFFD9D4F0).withValues(alpha: (dark - 0.6) / 0.4);
      canvas.drawCircle(sc + const Offset(-10, -6), 7, cr);
      canvas.drawCircle(sc + const Offset(12, 10), 5, cr);
    }

    // Mây trôi (mờ dần vào ban đêm)
    final cloud = Paint()..color = Colors.white.withValues(alpha: 0.75 * (1 - 0.7 * dark));
    for (var i = 0; i < 3; i++) {
      final x = ((e.time * (12 + i * 5) + i * size.width * 0.45) % (size.width + 200)) - 100;
      final y = e.topInset + size.height * (0.10 + i * 0.13);
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: 110, height: 32), cloud);
      canvas.drawOval(Rect.fromCenter(center: Offset(x + 26, y - 14), width: 70, height: 36), cloud);
    }

    // Đồi + đất (xanh đậm dần về đêm)
    final hillColor = Color.lerp(const Color(0xFF6CCB5F), const Color(0xFF2E7D55), dark)!;
    final groundColor = Color.lerp(const Color(0xFF4DA843), const Color(0xFF1F5E3F), dark)!;
    final hill = Path()
      ..moveTo(0, size.height * 0.90)
      ..quadraticBezierTo(size.width * 0.3, size.height * 0.84, size.width * 0.6, size.height * 0.90)
      ..quadraticBezierTo(size.width * 0.85, size.height * 0.94, size.width, size.height * 0.88)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(hill, Paint()..color = hillColor);
    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.955, size.width, size.height * 0.045), Paint()..color = groundColor);
  }

  void _feverGlow(Canvas canvas, Size size) {
    final e = engine;
    final pulse = 0.65 + 0.35 * math.sin(e.time * 8);
    final c = Offset(e.basketX, e.basketTop + e.basketWidth * 0.2);
    canvas.drawCircle(
      c,
      e.basketWidth * 1.15,
      Paint()
        ..shader = RadialGradient(colors: [
          const Color(0xFFFFE066).withValues(alpha: 0.55 * pulse),
          const Color(0xFFFFE066).withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: c, radius: e.basketWidth * 1.15)),
    );
  }

  void _items(Canvas canvas, Size size) {
    final fs = engine.itemSize;
    for (final it in engine.items) {
      final img = _emoji(it.kind.emoji, fs);
      canvas.save();
      // Trái cây đung đưa nhẹ khi rơi.
      canvas.translate(it.x + math.sin(engine.time * 3 + it.phase) * 5, it.y);
      canvas.rotate(it.angle);
      if (it.kind.isBad) {
        canvas.drawCircle(
          Offset.zero,
          fs * 0.72,
          Paint()..color = const Color(0xFFFF3B3B).withValues(alpha: 0.18 + 0.1 * math.sin(engine.time * 10)),
        );
      }
      _sprite(canvas, img);
      canvas.restore();
    }
  }

  void _basket(Canvas canvas, Size size) {
    final e = engine;
    final w = e.basketWidth;
    final h = w * 0.52;
    final top = e.basketTop;
    final x = e.basketX;

    // Bóp méo "squash & stretch" khi hứng, nghiêng theo hướng chạy.
    final s = Curves.easeOut.transform(e.squash.clamp(0.0, 1.0));
    canvas.save();
    canvas.translate(x, top + h);
    canvas.rotate(e.tilt);
    canvas.scale(1 + 0.16 * s, 1 - 0.22 * s);
    canvas.translate(-x, -(top + h));

    final body = Path()
      ..moveTo(x - w / 2, top)
      ..lineTo(x + w / 2, top)
      ..lineTo(x + w * 0.38, top + h)
      ..quadraticBezierTo(x, top + h * 1.12, x - w * 0.38, top + h)
      ..close();
    final bodyRect = Rect.fromLTWH(x - w / 2, top, w, h);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, top + h * 1.05), width: w * 0.9, height: h * 0.25),
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: e.fever
              ? const [Color(0xFFFFE08A), Color(0xFFE0A030)]
              : const [Color(0xFFE0A15C), Color(0xFFB9742F)],
        ).createShader(bodyRect),
    );
    final weave = Paint()
      ..color = const Color(0xFF8A5521).withValues(alpha: 0.55)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.save();
    canvas.clipPath(body);
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(Offset(x - w / 2, top + h * i / 4), Offset(x + w / 2, top + h * i / 4), weave);
    }
    for (var i = -4; i <= 4; i++) {
      canvas.drawLine(Offset(x + i * w / 9, top), Offset(x + i * w / 11, top + h), weave);
    }
    canvas.restore();
    // Viền giỏ
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, top), width: w * 1.06, height: h * 0.2),
        Radius.circular(h * 0.1),
      ),
      Paint()..color = const Color(0xFFF1C27D),
    );

    // Mặt cảm xúc: 😋 hứng trái, 😵 trúng bom, 🤩 skill, 😁 khi đang cười.
    final face = e.mood ?? (e.multiplier ? '😁' : null);
    if (face != null) {
      final pop = e.mood != null ? 1 + 0.25 * math.sin((e.moodTime * 8).clamp(0, math.pi)) : 1.0;
      canvas.save();
      canvas.translate(x, top + h * 0.55);
      canvas.scale(pop);
      _sprite(canvas, _emoji(face, w * 0.34));
      canvas.restore();
    }
    canvas.restore();
  }

  void _particles(Canvas canvas) {
    final fs = engine.itemSize;
    for (final p in engine.particles) {
      final t = (1 - p.age / p.life).clamp(0.0, 1.0);
      switch (p.shape) {
        case ParticleShape.dot:
          canvas.drawCircle(Offset(p.x, p.y), p.size * t, Paint()..color = p.color.withValues(alpha: t));
        case ParticleShape.confetti:
          canvas.save();
          canvas.translate(p.x, p.y);
          canvas.rotate(p.rot);
          // Xoay quanh trục dọc cho cảm giác giấy lật.
          canvas.scale(1, math.cos(p.age * 9 + p.spin).abs().clamp(0.15, 1.0));
          canvas.drawRect(
            Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.55),
            Paint()..color = p.color.withValues(alpha: math.min(1.0, t * 2)),
          );
          canvas.restore();
        case ParticleShape.emoji:
        case ParticleShape.star:
          canvas.save();
          canvas.translate(p.x, p.y);
          canvas.rotate(p.rot);
          canvas.scale(0.6 + 0.4 * t);
          _sprite(canvas, _emoji(p.emoji, p.shape == ParticleShape.star ? fs * 0.3 : fs * 0.34), t < 0.4 ? t / 0.4 : 1);
          canvas.restore();
      }
    }
  }

  void _popups(Canvas canvas) {
    _pruneTextSprites();
    for (final p in engine.popups) {
      final t = (1 - p.age / Popup.life).clamp(0.0, 1.0);
      // Nảy to rồi co lại ở 0.2s đầu.
      final pop = 1 + 0.7 * math.max(0.0, 1 - p.age / 0.2);
      final img = _textSprites.putIfAbsent(p, () => _outlinedText(p.text, p.size, p.color, stroke: 0.22));
      canvas.save();
      canvas.translate(p.x, p.y + img.height / dpr / 2);
      canvas.scale(pop);
      _sprite(canvas, img, t);
      canvas.restore();
    }
  }

  /// Banner chữ to giữa màn hình: LEVEL UP, COMBO, NOM NOM…
  void _banner(Canvas canvas, Size size) {
    final b = engine.banner;
    if (b == null) return;
    final inT = Curves.easeOutBack.transform((b.age / 0.3).clamp(0.0, 1.0));
    final out = b.age > ScreenBanner.life - 0.35 ? (ScreenBanner.life - b.age) / 0.35 : 1.0;
    final img = _textSprites.putIfAbsent(
      b,
      () => _outlinedText(b.text, size.width * 0.115, b.color, stroke: 0.16, spacing: 1),
    );
    canvas.save();
    canvas.translate(size.width / 2, engine.topInset + size.height * 0.17);
    canvas.rotate(-0.05 + 0.03 * math.sin(engine.time * 9));
    canvas.scale(inT);
    _sprite(canvas, img, out);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GamePainter old) => false; // repaint do engine thông báo
}
