import 'package:demo_gr9/core/face_controller.dart';
import 'package:demo_gr9/core/face_state.dart';
import 'package:demo_gr9/core/input_hub.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FaceController face;
  late InputHub hub;

  void feed(double roll, {double smile = 0, double eye = 1, double? mouth}) {
    face.state.value = FaceState(
      hasFace: true,
      roll: roll,
      smile: smile,
      eyeOpen: eye,
      mouthRatio: mouth,
    );
  }

  setUp(() {
    face = FaceController();
    hub = InputHub(face);
  });

  tearDown(() {
    hub.dispose();
  });

  test('vùng chết ±5° giữ giỏ đứng yên', () {
    for (var i = 0; i < 6; i++) {
      feed(4);
    }
    expect(hub.move, 0);
  });

  test('nghiêng đủ lớn thì chạm mép, đúng chiều', () {
    for (var i = 0; i < 6; i++) {
      feed(30);
    }
    expect(hub.move, 1);
    for (var i = 0; i < 6; i++) {
      feed(-30);
    }
    expect(hub.move, -1);
  });

  test('đảo chiều', () {
    hub.invert = true;
    for (var i = 0; i < 6; i++) {
      feed(30);
    }
    expect(hub.move, -1);
  });

  test('hiệu chỉnh lấy góc đầu hiện tại làm mốc 0', () {
    hub.beginCalibration();
    for (var i = 0; i < 10; i++) {
      feed(12, mouth: 0.02);
    }
    expect(hub.finishCalibration(), isTrue);
    expect(hub.baselineRoll, closeTo(12, 1e-9));
    for (var i = 0; i < 6; i++) {
      feed(12);
    }
    expect(hub.move, 0);
    for (var i = 0; i < 6; i++) {
      feed(12 + 15);
    }
    expect(hub.move, greaterThan(0.3));
  });

  test('làm mượt: một khung hình nhiễu không làm giỏ nhảy', () {
    for (var i = 0; i < 4; i++) {
      feed(0);
    }
    feed(40);
    expect(hub.move.abs(), lessThan(0.6));
  });

  test('há miệng kích hoạt đúng một lần cho đến khi khép lại', () {
    for (var i = 0; i < 3; i++) {
      feed(0, mouth: 0.02);
    }
    expect(hub.consumeMouthTrigger(), isFalse);
    for (var i = 0; i < 5; i++) {
      feed(0, mouth: 0.2);
    }
    expect(hub.consumeMouthTrigger(), isTrue);
    for (var i = 0; i < 5; i++) {
      feed(0, mouth: 0.2);
    }
    expect(hub.consumeMouthTrigger(), isFalse);
    feed(0, mouth: 0.0);
    for (var i = 0; i < 3; i++) {
      feed(0, mouth: 0.2);
    }
    expect(hub.consumeMouthTrigger(), isTrue);
  });

  test('nhắm mắt cộng dồn thời gian, mở mắt thì reset', () {
    for (var i = 0; i < 4; i++) {
      feed(0, eye: 0.05);
    }
    hub.update(0.5);
    expect(hub.eyesClosed, isFalse);
    hub.update(0.4);
    expect(hub.eyesClosed, isTrue);
    for (var i = 0; i < 4; i++) {
      feed(0, eye: 1);
    }
    hub.update(0.1);
    expect(hub.eyesClosed, isFalse);
  });

  test('cười > 60% thì tính là đang cười', () {
    for (var i = 0; i < 5; i++) {
      feed(0, smile: 0.9);
    }
    expect(hub.isSmiling, isTrue);
  });
}
