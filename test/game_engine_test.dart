import 'dart:ui';

import 'package:demo_gr9/game/game_engine.dart';
import 'package:flutter_test/flutter_test.dart';

GameInput input({
  double move = 0,
  bool faceControlled = true,
  bool faceOk = true,
  bool smiling = false,
  bool eyesClosed = false,
  bool skill = false,
}) =>
    GameInput(
      move: move,
      faceControlled: faceControlled,
      faceOk: faceOk,
      smiling: smiling,
      eyesClosed: eyesClosed,
      skill: skill,
    );

GameEngine playing() {
  final e = GameEngine(best: 0)
    ..resize(const Size(400, 800), 100)
    ..start();
  // Qua đếm ngược.
  for (var i = 0; i < 200 && e.phase != Phase.playing; i++) {
    e.update(0.02, input());
  }
  e.items.clear();
  return e;
}

/// Thả một vật ngay trên miệng giỏ rồi chạy engine đến khi nó chạm.
void drop(GameEngine e, ItemKind kind, {GameInput? inp}) {
  e.items.add(Item(kind, e.basketX, e.basketTop - 5, 300, 0));
  for (var i = 0; i < 5; i++) {
    e.update(0.016, inp ?? input());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('đếm ngược 3s rồi mới chơi', () {
    final e = GameEngine(best: 0)
      ..resize(const Size(400, 800), 100)
      ..start();
    expect(e.phase, Phase.countdown);
    e.update(1, input());
    expect(e.phase, Phase.countdown);
    e.update(2.5, input());
    expect(e.phase, Phase.playing);
  });

  test('hứng trái cây được cộng điểm, cười thì x2', () {
    final e = playing();
    drop(e, ItemKind.apple);
    expect(e.score, 10);
    drop(e, ItemKind.watermelon, inp: input(smiling: true));
    expect(e.score, 10 + 40);
    expect(e.lives, 3);
  });

  test('hứng bom hoặc ớt thì mất mạng, hết 3 mạng thì game over', () {
    final e = playing();
    drop(e, ItemKind.bomb);
    expect(e.lives, 2);
    drop(e, ItemKind.chili);
    drop(e, ItemKind.bomb);
    expect(e.lives, 0);
    expect(e.phase, Phase.over);
  });

  test('trái rơi trượt không mất mạng nhưng reset combo', () {
    final e = playing();
    drop(e, ItemKind.apple);
    expect(e.combo, 1);
    e.items.add(Item(ItemKind.apple, 20, e.size.height - 1, 900, 0));
    e.basketX = 380;
    e.update(0.1, input(move: 1));
    expect(e.combo, 0);
    expect(e.lives, 3);
  });

  test('skill há miệng: ăn hết trái, nổ bom không mất mạng, rồi hồi chiêu', () {
    final e = playing();
    e.skill = 1;
    e.items
      ..add(Item(ItemKind.apple, 50, 300, 0, 0))
      ..add(Item(ItemKind.grape, 150, 300, 0, 0))
      ..add(Item(ItemKind.bomb, 250, 300, 0, 0));
    e.update(0.016, input(skill: true));
    expect(e.items, isEmpty);
    expect(e.score, 20);
    expect(e.lives, 3);
    expect(e.skillReady, isFalse);
  });

  test('skill chưa sạc đầy thì không dùng được', () {
    final e = playing();
    e.skill = 0.3;
    e.items.add(Item(ItemKind.apple, 50, 300, 0, 0));
    e.update(0.016, input(skill: true));
    expect(e.items, isNotEmpty);
  });

  test('mất mặt thì tạm dừng, thấy lại thì đếm ngược rồi chơi tiếp', () {
    final e = playing();
    final y0 = e.items.isEmpty ? 0 : e.items.first.y;
    e.update(0.016, input(faceOk: false));
    expect(e.phase, Phase.paused);
    expect(e.pauseReason, PauseReason.noFace);
    e.update(0.016, input());
    expect(e.phase, Phase.countdown);
    e.update(2.1, input());
    expect(e.phase, Phase.playing);
    expect(y0, 0);
  });

  test('nhắm mắt lâu thì tạm dừng', () {
    final e = playing();
    e.update(0.016, input(eyesClosed: true));
    expect(e.phase, Phase.paused);
    expect(e.pauseReason, PauseReason.eyesClosed);
  });

  test('chế độ cảm ứng không bị tạm dừng khi không có mặt', () {
    final e = playing();
    e.update(0.016, input(faceControlled: false, faceOk: false));
    expect(e.phase, Phase.playing);
  });

  test('giỏ chạy theo move và không ra khỏi màn hình', () {
    final e = playing();
    for (var i = 0; i < 120; i++) {
      e.update(0.016, input(move: 1));
    }
    expect(e.basketX, closeTo(400 - e.basketWidth / 2, 1));
    for (var i = 0; i < 120; i++) {
      e.update(0.016, input(move: -1));
    }
    expect(e.basketX, closeTo(e.basketWidth / 2, 1));
  });

  test('độ khó tăng theo điểm', () {
    final e = playing();
    expect(e.level, 1);
    e.score = 450;
    expect(e.level, 4);
  });

  group('sự kiện âm thanh và hiệu ứng', () {
    test('đếm ngược phát tick 3,2,1 rồi go', () {
      final events = <(GameEvent, int)>[];
      final e = GameEngine(best: 0)
        ..resize(const Size(400, 800), 100)
        ..onEvent = ((ev, n) => events.add((ev, n)))
        ..start();
      for (var i = 0; i < 200 && e.phase != Phase.playing; i++) {
        e.update(0.02, input());
      }
      expect(events.where((x) => x.$1 == GameEvent.tick).map((x) => x.$2), [3, 2, 1]);
      expect(events.last.$1, GameEvent.go);
    });

    test('hứng liên tiếp: cao độ tăng theo combo, mốc 5 có banner + sự kiện combo', () {
      final events = <(GameEvent, int)>[];
      final e = playing()..onEvent = (ev, n) => events.add((ev, n));
      for (var i = 0; i < 5; i++) {
        drop(e, ItemKind.apple);
      }
      expect(events.where((x) => x.$1 == GameEvent.catchFruit).map((x) => x.$2), [0, 1, 2, 3, 4]);
      expect(events.where((x) => x.$1 == GameEvent.combo).map((x) => x.$2), [5]);
      expect(e.banner, isNotNull);
      expect(e.fever, isFalse);
      for (var i = 0; i < 5; i++) {
        drop(e, ItemKind.apple);
      }
      expect(e.fever, isTrue);
    });

    test('đủ điểm thì lên level, có banner và sự kiện levelUp', () {
      final events = <(GameEvent, int)>[];
      final e = playing()..onEvent = (ev, n) => events.add((ev, n));
      e.score = 145;
      drop(e, ItemKind.apple);
      expect(e.level, 2);
      expect(events.any((x) => x.$1 == GameEvent.levelUp && x.$2 == 2), isTrue);
      expect(e.banner?.text, contains('LEVEL 2'));
    });

    test('trúng bom/ớt phát đúng loại âm, đổi mặt giỏ sang 😵', () {
      final events = <GameEvent>[];
      final e = playing()..onEvent = (ev, n) => events.add(ev);
      drop(e, ItemKind.bomb);
      drop(e, ItemKind.chili);
      expect(events, [GameEvent.hitBomb, GameEvent.hitChili]);
      expect(e.mood, '😵');
    });

    test('hết mạng: gameOver, còn nếu phá kỷ lục thì newBest', () {
      final a = <GameEvent>[];
      final e1 = GameEngine(best: 100)
        ..resize(const Size(400, 800), 100)
        ..onEvent = ((ev, n) => a.add(ev))
        ..start();
      for (var i = 0; i < 200 && e1.phase != Phase.playing; i++) {
        e1.update(0.02, input());
      }
      e1.lives = 1;
      drop(e1, ItemKind.bomb);
      expect(a.last, GameEvent.gameOver);

      final b = <GameEvent>[];
      final e2 = playing()..onEvent = (ev, n) => b.add(ev);
      drop(e2, ItemKind.apple);
      e2.lives = 1;
      drop(e2, ItemKind.bomb);
      expect(b.last, GameEvent.newBest);
    });

    test('skill không phát tiếng hứng cho từng trái, chỉ một tiếng skill', () {
      final events = <GameEvent>[];
      final e = playing()..onEvent = (ev, n) => events.add(ev);
      e.skill = 1;
      e.items
        ..add(Item(ItemKind.apple, 50, 300, 0, 0))
        ..add(Item(ItemKind.grape, 150, 300, 0, 0));
      e.update(0.016, input(skill: true));
      expect(events.where((x) => x == GameEvent.skill).length, 1);
      expect(events.where((x) => x == GameEvent.catchFruit).length, 0);
    });

    test('pause/resume phát sự kiện đúng một lần mỗi lần chuyển trạng thái', () {
      final events = <GameEvent>[];
      final e = playing()..onEvent = (ev, n) => events.add(ev);
      e.update(0.016, input(faceOk: false));
      e.update(0.016, input(faceOk: false));
      e.update(0.016, input());
      expect(events.where((x) => x == GameEvent.pause || x == GameEvent.resume), [GameEvent.pause, GameEvent.resume]);
      expect(events.contains(GameEvent.tick), isTrue); // đếm ngược sau khi tiếp tục
    });
  });
}
