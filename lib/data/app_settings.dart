import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cài đặt người chơi, lưu trên máy.
class AppSettings extends ChangeNotifier {
  SharedPreferences? _p;

  String playerName = '';
  bool faceControl = true; // false = điều khiển bằng cảm ứng
  bool showMesh = true;
  bool showDebug = true;
  bool invertTilt = false;
  bool soundOn = true;
  bool musicOn = true;
  double tiltRange = 25; // °

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    playerName = _p!.getString('name') ?? '';
    faceControl = _p!.getBool('faceControl') ?? true;
    showMesh = _p!.getBool('showMesh') ?? true;
    showDebug = _p!.getBool('showDebug') ?? true;
    invertTilt = _p!.getBool('invertTilt') ?? false;
    soundOn = _p!.getBool('soundOn') ?? true;
    musicOn = _p!.getBool('musicOn') ?? true;
    tiltRange = _p!.getDouble('tiltRange') ?? 25;
    notifyListeners();
  }

  void update({
    String? playerName,
    bool? faceControl,
    bool? showMesh,
    bool? showDebug,
    bool? invertTilt,
    bool? soundOn,
    bool? musicOn,
    double? tiltRange,
  }) {
    this.playerName = playerName ?? this.playerName;
    this.faceControl = faceControl ?? this.faceControl;
    this.showMesh = showMesh ?? this.showMesh;
    this.showDebug = showDebug ?? this.showDebug;
    this.invertTilt = invertTilt ?? this.invertTilt;
    this.soundOn = soundOn ?? this.soundOn;
    this.musicOn = musicOn ?? this.musicOn;
    this.tiltRange = tiltRange ?? this.tiltRange;
    notifyListeners();
    final p = _p;
    if (p == null) return;
    p.setString('name', this.playerName);
    p.setBool('faceControl', this.faceControl);
    p.setBool('showMesh', this.showMesh);
    p.setBool('showDebug', this.showDebug);
    p.setBool('invertTilt', this.invertTilt);
    p.setBool('soundOn', this.soundOn);
    p.setBool('musicOn', this.musicOn);
    p.setDouble('tiltRange', this.tiltRange);
  }
}
