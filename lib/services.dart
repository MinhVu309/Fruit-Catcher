import 'package:flutter/widgets.dart';

import 'core/audio_service.dart';
import 'core/face_controller.dart';
import 'core/input_hub.dart';
import 'data/app_settings.dart';
import 'data/score_store.dart';

/// Các đối tượng dùng chung toàn app.
class Services extends InheritedWidget {
  const Services({
    super.key,
    required this.face,
    required this.hub,
    required this.settings,
    required this.scores,
    required this.audio,
    required super.child,
  });

  final FaceController face;
  final InputHub hub;
  final AppSettings settings;
  final ScoreStore scores;
  final AudioService audio;

  static Services of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Services>()!;

  @override
  bool updateShouldNotify(Services old) => false;
}
