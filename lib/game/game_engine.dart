import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum ItemKind { apple, orange, banana, grape, watermelon, bomb, chili, heart }

extension ItemKindX on ItemKind {
  String get emoji => const {
        ItemKind.apple: '🍎',
        ItemKind.orange: '🍊',
        ItemKind.banana: '🍌',
        ItemKind.grape: '🍇',
        ItemKind.watermelon: '🍉',
        ItemKind.bomb: '💣',
        ItemKind.chili: '🌶️',
        ItemKind.heart: '❤️',
      }[this]!;

  Color get juice => const {
        ItemKind.apple: Color(0xFFFF4D4D),
        ItemKind.orange: Color(0xFFFF9F1C),
        ItemKind.banana: Color(0xFFFFE066),
        ItemKind.grape: Color(0xFF9B5DE5),
        ItemKind.watermelon: Color(0xFFFF6B8B),
        ItemKind.bomb: Color(0xFFFFA94D),
        ItemKind.chili: Color(0xFFFF4D4D),
        ItemKind.heart: Color(0xFFFF7AA8),
      }[this]!;

  bool get isFruit => index <= ItemKind.watermelon.index;
  bool get isBad => this == ItemKind.bomb || this == ItemKind.chili;
  int get points => this == ItemKind.watermelon ? 20 : 10;
}

enum Phase { countdown, playing, paused, over }

enum PauseReason { none, noFace, eyesClosed }

/// Sự kiện để lớp ngoài phát âm thanh (engine không biết gì về âm thanh).
enum GameEvent {
  catchFruit, // n = combo hiện tại - 1 (cao độ tăng dần)
  catchBig,
  hitBomb,
  hitChili,
  heart,
  skill,
  combo, // n = combo
  levelUp, // n = level mới
  gameOver,
  newBest,
  tick, // n = số đang đếm
  go,
  pause,
  resume,
}

class Item {
  Item(this.kind, this.x, this.y, this.vy, this.spin) : phase = math.Random().nextDouble() * 6.28;
  final ItemKind kind;
  double x, y, vy, spin;
  double angle = 0;
  final double phase;
}

class Popup {
  Popup(this.text, this.x, this.y, this.color, {this.size = 22});
  final String text;
  final double x;
  double y;
  final Color color;
  final double size;
  double age = 0;
  static const life = 0.9;
}

enum ParticleShape { dot, emoji, confetti, star }

class Particle {
  Particle(
    this.x,
    this.y,
    this.vx,
    this.vy,
    this.color,
    this.size, {
    this.shape = ParticleShape.dot,
    this.emoji = '',
    this.life = 0.7,
    this.gravity = 600,
    this.spin = 0,
  });
  double x, y, vx, vy, size, spin;
  double age = 0;
  double rot = 0;
  final Color color;
  final ParticleShape shape;
  final String emoji;
  final double life;
  final double gravity;
}

class ScreenBanner {
  ScreenBanner(this.text, this.color);
  final String text;
  final Color color;
  double age = 0;
  static const life = 1.5;
}

/// Đầu vào mỗi tick, do màn hình game dựng từ [InputHub] hoặc cảm ứng.
class GameInput {
  const GameInput({
    required this.move,
    required this.faceControlled,
    required this.faceOk,
    required this.smiling,
    required this.eyesClosed,
    required this.skill,
  });
  final double move; // -1..1
  final bool faceControlled;
  final bool faceOk;
  final bool smiling;
  final bool eyesClosed;
  final bool skill;
}

/// Toàn bộ luật chơi, không phụ thuộc UI. Toạ độ tính bằng pixel của vùng vẽ.
class GameEngine extends ChangeNotifier {
  GameEngine({required this.best}) : _startBest = best;

  static const maxLives = 3;
  static const skillCooldown = 12.0;
  static const feverCombo = 10;
  static const maxParticles = 220;
  static const _hitFlashTime = 0.45;

  final _rnd = math.Random();
  int best;
  int _startBest;

  /// Lớp ngoài đăng ký để phát âm thanh.
  void Function(GameEvent event, int n)? onEvent;

  Size size = Size.zero;
  double topInset = 0;

  Phase phase = Phase.countdown;
  PauseReason pauseReason = PauseReason.none;
  double countdown = 3;
  int _tickShown = 0;

  int score = 0;
  int lives = maxLives;
  int combo = 0;
  int bestCombo = 0;
  int caught = 0;
  double skill = 0; // 0..1
  bool multiplier = false;
  int _lastLevel = 1;

  double basketX = 0;
  double basketVx = 0;
  double time = 0;
  double _spawnTimer = 0.6;

  final items = <Item>[];
  final popups = <Popup>[];
  final particles = <Particle>[];
  ScreenBanner? banner;

  double hitFlash = 0; // đỏ khi mất mạng
  double skillFlash = 0; // trắng khi dùng skill
  double shake = 0;
  double squash = 0; // giỏ nảy khi hứng
  double scoreBump = 0; // chữ điểm nảy
  String? mood; // emoji trên mặt giỏ
  double moodTime = 0;
  double skyPos = 0; // vị trí liên tục trong bảng màu bầu trời (đổi theo level)
  double _confettiLeft = 0;
  double _sparkTimer = 0;

  int get level => 1 + score ~/ 150;
  bool get fever => combo >= feverCombo;
  double get tilt => (basketVx / 1800).clamp(-0.28, 0.28);
  double get itemSize => size.width * 0.105;
  double get basketWidth => size.width * 0.26;
  double get basketTop => size.height * 0.80;
  bool get skillReady => skill >= 1;
  bool get isNewBest => score > best;
  bool get brokeRecord => score > _startBest;

  double get _fallSpeed => size.height * 0.30 * (1 + 0.11 * (level - 1)).clamp(1.0, 2.4);
  double get _spawnInterval => math.max(0.38, 0.95 - 0.06 * (level - 1));

  void _emit(GameEvent e, [int n = 0]) => onEvent?.call(e, n);

  void resize(Size s, double inset) {
    if (s == size && inset == topInset) return;
    final first = size == Size.zero;
    size = s;
    topInset = inset;
    if (first) basketX = s.width / 2;
  }

  void start() {
    phase = Phase.countdown;
    countdown = 3;
    _tickShown = 0;
    pauseReason = PauseReason.none;
    score = 0;
    lives = maxLives;
    combo = 0;
    bestCombo = 0;
    caught = 0;
    skill = 0.35;
    multiplier = false;
    _lastLevel = 1;
    _startBest = best;
    _spawnTimer = 0.6;
    items.clear();
    popups.clear();
    particles.clear();
    banner = null;
    hitFlash = skillFlash = shake = squash = scoreBump = moodTime = 0;
    mood = null;
    skyPos = 0;
    _confettiLeft = 0;
    if (size != Size.zero) basketX = size.width / 2;
    notifyListeners();
  }

  void update(double dt, GameInput input) {
    if (size == Size.zero) return;
    time += dt;
    _updateEffects(dt);
    if (phase == Phase.over) {
      notifyListeners();
      return;
    }

    // Tạm dừng: mất mặt (chế độ khuôn mặt) hoặc nhắm mắt lâu.
    var reason = PauseReason.none;
    if (input.faceControlled && !input.faceOk) {
      reason = PauseReason.noFace;
    } else if (input.eyesClosed) {
      reason = PauseReason.eyesClosed;
    }
    if (reason != PauseReason.none) {
      if (phase != Phase.paused) _emit(GameEvent.pause);
      pauseReason = reason;
      phase = Phase.paused;
      notifyListeners();
      return;
    }
    if (phase == Phase.paused) {
      pauseReason = PauseReason.none;
      phase = Phase.countdown;
      countdown = 2;
      _tickShown = 0;
      _emit(GameEvent.resume);
    }

    _moveBasket(dt, input.move);
    multiplier = input.smiling;

    if (phase == Phase.countdown) {
      countdown -= dt;
      final c = countdown.ceil();
      if (countdown <= 0) {
        phase = Phase.playing;
        _emit(GameEvent.go);
      } else if (c != _tickShown && c >= 1 && c <= 3) {
        _tickShown = c;
        _emit(GameEvent.tick, c);
      }
      notifyListeners();
      return;
    }

    skill = math.min(1, skill + dt / skillCooldown);
    if (input.skill && skillReady) _useSkill();

    _spawnTimer -= dt;
    if (_spawnTimer <= 0) {
      _spawn();
      _spawnTimer = _spawnInterval * (0.75 + _rnd.nextDouble() * 0.5);
    }

    _updateItems(dt);
    notifyListeners();
  }

  void _moveBasket(double dt, double norm) {
    final half = basketWidth / 2;
    final target = size.width / 2 + norm * (size.width / 2 - half);
    final old = basketX;
    basketX += (target - basketX) * (1 - math.exp(-dt * 14));
    basketX = basketX.clamp(half, size.width - half);
    if (dt > 0) {
      final v = (basketX - old) / dt;
      basketVx += (v - basketVx) * (1 - math.exp(-dt * 12));
    }
  }

  void _spawn() {
    final r = itemSize / 2;
    final badChance = math.min(0.36, 0.16 + 0.02 * level);
    ItemKind kind;
    final roll = _rnd.nextDouble();
    if (lives < maxLives && roll < 0.03) {
      kind = ItemKind.heart;
    } else if (roll < badChance) {
      kind = _rnd.nextBool() ? ItemKind.bomb : ItemKind.chili;
    } else if (_rnd.nextDouble() < 0.12) {
      kind = ItemKind.watermelon;
    } else {
      kind = const [ItemKind.apple, ItemKind.orange, ItemKind.banana, ItemKind.grape][_rnd.nextInt(4)];
    }
    items.add(Item(
      kind,
      r + _rnd.nextDouble() * (size.width - 2 * r),
      topInset - r,
      _fallSpeed * (0.9 + _rnd.nextDouble() * 0.3),
      (_rnd.nextDouble() - 0.5) * 3,
    ));
  }

  void _updateItems(double dt) {
    final r = itemSize / 2;
    final half = basketWidth / 2;
    for (final it in items.toList()) {
      it.y += it.vy * dt;
      it.angle += it.spin * dt;

      // Bom bốc tia lửa ở ngòi.
      if (it.kind == ItemKind.bomb && _rnd.nextDouble() < dt * 22) {
        particles.add(Particle(
          it.x + r * 0.45,
          it.y - r * 0.75,
          (_rnd.nextDouble() - 0.5) * 80,
          -60 - _rnd.nextDouble() * 80,
          const Color(0xFFFFB703),
          2.5 + _rnd.nextDouble() * 2,
          life: 0.3,
          gravity: 100,
        ));
      }

      final inBasketY = it.y + r * 0.6 >= basketTop && it.y - r < basketTop + itemSize * 0.5;
      if (inBasketY && (it.x - basketX).abs() < half + r * 0.2) {
        items.remove(it);
        _onCatch(it);
      } else if (it.y - r > size.height) {
        items.remove(it);
        if (it.kind.isFruit) combo = 0;
      }
    }
  }

  void _setMood(String m, [double t = 0.7]) {
    mood = m;
    moodTime = t;
  }

  void _onCatch(Item it) {
    final pos = Offset(it.x, basketTop);
    if (it.kind.isBad) {
      lives--;
      combo = 0;
      hitFlash = _hitFlashTime;
      shake = 0.35;
      squash = 1;
      _setMood('😵', 1.0);
      _burst(pos, it.kind.juice, 18);
      _emojiBurst(pos, it.kind == ItemKind.bomb ? '💥' : '🔥', 5);
      popups.add(Popup('-1 ❤️', it.x, pos.dy - 20, const Color(0xFFFF4D4D), size: 26));
      HapticFeedback.heavyImpact();
      _emit(it.kind == ItemKind.bomb ? GameEvent.hitBomb : GameEvent.hitChili);
      if (lives <= 0) {
        lives = 0;
        _gameOver();
      }
    } else if (it.kind == ItemKind.heart) {
      lives = math.min(maxLives, lives + 1);
      squash = 0.7;
      _setMood('🥰');
      _burst(pos, it.kind.juice, 12);
      _emojiBurst(pos, '❤️', 6);
      popups.add(Popup('+1 ❤️', it.x, pos.dy - 20, const Color(0xFFFF7AA8), size: 26));
      HapticFeedback.mediumImpact();
      _emit(GameEvent.heart);
    } else {
      _scoreFruit(it.kind, pos);
      HapticFeedback.lightImpact();
    }
  }

  void _gameOver() {
    phase = Phase.over;
    if (score > best) best = score;
    if (brokeRecord) {
      _confettiLeft = 3.5;
      _emit(GameEvent.newBest);
    } else {
      _emit(GameEvent.gameOver);
    }
  }

  /// [silent]: dùng khi skill ăn nhiều trái cùng lúc, tránh dồn âm thanh.
  void _scoreFruit(ItemKind kind, Offset pos, {bool silent = false}) {
    combo++;
    caught++;
    if (combo > bestCombo) bestCombo = combo;
    final comboBonus = math.min(25, (combo ~/ 5) * 5);
    var pts = kind.points + comboBonus;
    if (multiplier) pts *= 2;
    score += pts;
    if (score > best) best = score;

    scoreBump = 1;
    squash = 1;
    _setMood(multiplier ? '😁' : '😋');
    _burst(pos, kind.juice, 12);
    _emojiBurst(pos, kind.emoji, 4);
    popups.add(Popup(
      multiplier ? '+$pts 😁x2' : '+$pts',
      pos.dx,
      pos.dy - 20,
      multiplier ? const Color(0xFFFFD43B) : const Color(0xFFFFFFFF),
      size: kind == ItemKind.watermelon ? 28 : 22,
    ));
    if (!silent) {
      _emit(kind == ItemKind.watermelon ? GameEvent.catchBig : GameEvent.catchFruit, combo - 1);
    }

    if (combo >= 5 && combo % 5 == 0) {
      _banner('COMBO x$combo 🔥', const Color(0xFFFFB703));
      _confetti(18);
      _emit(GameEvent.combo, combo);
    }
    if (level > _lastLevel) {
      _lastLevel = level;
      _banner('LEVEL $level! 🚀', const Color(0xFF3DDBD9));
      _confetti(60);
      _emit(GameEvent.levelUp, level);
    }
  }

  /// Há miệng: ăn hết trái trên màn hình, nổ hết vật xấu (không mất mạng).
  void _useSkill() {
    skill = 0;
    skillFlash = 0.6;
    shake = 0.2;
    _setMood('🤩', 1.0);
    _banner('NOM NOM! 😋', const Color(0xFFFF5D8F));
    _stars(Offset(basketX, basketTop), 22);
    _emit(GameEvent.skill);
    for (final it in items.toList()) {
      final pos = Offset(it.x, it.y);
      if (it.kind.isBad) {
        _burst(pos, const Color(0xFFFFA94D), 14);
        _emojiBurst(pos, '💥', 2);
      } else if (it.kind == ItemKind.heart) {
        lives = math.min(maxLives, lives + 1);
        _burst(pos, it.kind.juice, 10);
      } else {
        _scoreFruit(it.kind, pos, silent: true);
      }
    }
    items.clear();
    HapticFeedback.vibrate();
  }

  void _banner(String text, Color c) => banner = ScreenBanner(text, c);

  void _burst(Offset p, Color c, int n) {
    for (var i = 0; i < n; i++) {
      final a = _rnd.nextDouble() * math.pi * 2;
      final v = 80 + _rnd.nextDouble() * 220;
      particles.add(Particle(p.dx, p.dy, math.cos(a) * v, math.sin(a) * v - 120, c, 3 + _rnd.nextDouble() * 4));
    }
  }

  /// Những bản sao nhỏ của emoji bắn tung ra.
  void _emojiBurst(Offset p, String emoji, int n) {
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + (_rnd.nextDouble() - 0.5) * 2.2;
      final v = 160 + _rnd.nextDouble() * 220;
      particles.add(Particle(
        p.dx,
        p.dy,
        math.cos(a) * v,
        math.sin(a) * v,
        const Color(0xFFFFFFFF),
        itemSize * 0.34,
        shape: ParticleShape.emoji,
        emoji: emoji,
        life: 0.85,
        spin: (_rnd.nextDouble() - 0.5) * 12,
      ));
    }
  }

  void _stars(Offset p, int n) {
    for (var i = 0; i < n; i++) {
      final a = _rnd.nextDouble() * math.pi * 2;
      final v = 120 + _rnd.nextDouble() * 360;
      particles.add(Particle(
        p.dx,
        p.dy,
        math.cos(a) * v,
        math.sin(a) * v - 80,
        const Color(0xFFFFFFFF),
        itemSize * 0.3,
        shape: ParticleShape.star,
        emoji: '✨',
        life: 0.9,
        gravity: 250,
        spin: (_rnd.nextDouble() - 0.5) * 8,
      ));
    }
  }

  static const _confettiColors = [
    Color(0xFFFF5D8F),
    Color(0xFFFFC23C),
    Color(0xFF3DDBD9),
    Color(0xFF6CE08A),
    Color(0xFFA78BFA),
    Color(0xFFFF8A3D),
  ];

  /// Pháo giấy bắn lên từ hai bên giỏ.
  void _confetti(int n) {
    for (var i = 0; i < n; i++) {
      final side = i.isEven ? -1 : 1;
      particles.add(Particle(
        basketX + side * basketWidth * 0.3,
        basketTop,
        side * (60 + _rnd.nextDouble() * 220),
        -(380 + _rnd.nextDouble() * 520),
        _confettiColors[_rnd.nextInt(_confettiColors.length)],
        6 + _rnd.nextDouble() * 5,
        shape: ParticleShape.confetti,
        life: 1.6,
        gravity: 520,
        spin: (_rnd.nextDouble() - 0.5) * 14,
      ));
    }
  }

  void _updateEffects(double dt) {
    for (final p in particles.toList()) {
      p.age += dt;
      p.vy += p.gravity * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.rot += p.spin * dt;
      if (p.age > p.life) particles.remove(p);
    }
    for (final p in popups.toList()) {
      p.age += dt;
      p.y -= 60 * dt;
      if (p.age > Popup.life) popups.remove(p);
    }
    final b = banner;
    if (b != null) {
      b.age += dt;
      if (b.age > ScreenBanner.life) banner = null;
    }

    // Pháo giấy rơi từ trên xuống khi phá kỷ lục.
    if (_confettiLeft > 0) {
      _confettiLeft -= dt;
      if (_rnd.nextDouble() < dt * 60) {
        particles.add(Particle(
          _rnd.nextDouble() * size.width,
          -10,
          (_rnd.nextDouble() - 0.5) * 120,
          80 + _rnd.nextDouble() * 160,
          _confettiColors[_rnd.nextInt(_confettiColors.length)],
          6 + _rnd.nextDouble() * 5,
          shape: ParticleShape.confetti,
          life: 3,
          gravity: 90,
          spin: (_rnd.nextDouble() - 0.5) * 12,
        ));
      }
    }

    // Fever: giỏ rải sao lấp lánh.
    if (fever && phase == Phase.playing) {
      _sparkTimer -= dt;
      if (_sparkTimer <= 0) {
        _sparkTimer = 0.07;
        particles.add(Particle(
          basketX + (_rnd.nextDouble() - 0.5) * basketWidth,
          basketTop + 4,
          (_rnd.nextDouble() - 0.5) * 60,
          -80 - _rnd.nextDouble() * 120,
          const Color(0xFFFFE066),
          3 + _rnd.nextDouble() * 3,
          life: 0.5,
          gravity: 80,
        ));
      }
    }

    // Giới hạn số hạt để máy yếu không bị tụt khung hình (bỏ hạt cũ nhất).
    if (particles.length > maxParticles) particles.removeRange(0, particles.length - maxParticles);

    hitFlash = math.max(0, hitFlash - dt);
    skillFlash = math.max(0, skillFlash - dt);
    shake = math.max(0, shake - dt);
    squash = math.max(0, squash - dt * 5);
    scoreBump = math.max(0, scoreBump - dt * 5);
    moodTime = math.max(0, moodTime - dt);
    if (moodTime == 0) mood = null;
    skyPos += ((level - 1) - skyPos) * (1 - math.exp(-dt * 0.9));
  }
}
