import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/audio_service.dart';
import 'core/face_controller.dart';
import 'core/frame_monitor.dart';
import 'core/input_hub.dart';
import 'data/app_settings.dart';
import 'data/score_store.dart';
import 'services.dart';
import 'ui/menu_screen.dart';
import 'ui/palette.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FrameMonitor.instance.start();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const FruitCatcherApp());
}

class FruitCatcherApp extends StatefulWidget {
  const FruitCatcherApp({super.key});

  @override
  State<FruitCatcherApp> createState() => _FruitCatcherAppState();
}

class _FruitCatcherAppState extends State<FruitCatcherApp> with WidgetsBindingObserver {
  final _face = FaceController();
  final _settings = AppSettings();
  final _scores = ScoreStore();
  final _audio = AudioService();
  late final InputHub _hub = InputHub(_face);
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  Future<void> _boot() async {
    await Future.wait([_settings.load(), _scores.load()]);
    _hub
      ..invert = _settings.invertTilt
      ..range = _settings.tiltRange;
    _syncAudio();
    _settings.addListener(_syncAudio);
    if (mounted) setState(() => _loaded = true);
    await _face.init();
  }

  void _syncAudio() {
    _audio.sfxOn = _settings.soundOn;
    if (_audio.musicOn != _settings.musicOn) _audio.setMusicOn(_settings.musicOn);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final away = state != AppLifecycleState.resumed;
    _face.suspend(away);
    _audio.suspend(away);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings.removeListener(_syncAudio);
    _hub.dispose();
    _face.dispose();
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Services(
      face: _face,
      hub: _hub,
      settings: _settings,
      scores: _scores,
      audio: _audio,
      child: MaterialApp(
        title: 'Fruit Catcher',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: Pal.amber,
          scaffoldBackgroundColor: Pal.bg,
          useMaterial3: true,
        ),
        home: _loaded
            ? const MenuScreen()
            : const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    );
  }
}
