import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

enum Sfx {
  catchFruit,
  bonus,
  bomb,
  chili,
  heart,
  skill,
  combo,
  levelUp,
  gameOver,
  newBest,
  tick,
  go,
  pause,
  resume,
  click,
}

/// Âm thanh game: hiệu ứng (chơi qua nhóm player low-latency) + nhạc nền lặp.
/// Mọi file nằm trong assets nên chạy được khi tắt mạng.
class AudioService {
  AudioService() {
    // Hiệu ứng và nhạc cùng phát, không giành audio focus của nhau.
    AudioPlayer.global.setAudioContext(
      AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
    );
  }

  static const _poolSize = 3;
  static const _sfxVolume = 0.9;
  static const _musicVolume = 0.55;

  bool sfxOn = true;
  bool musicOn = true;

  final _pools = <String, List<AudioPlayer>>{};
  final _next = <String, int>{};
  AudioPlayer? _music;
  Future<void> _musicQueue = Future.value();
  bool _musicWanted = false;
  bool _suspended = false;
  double _rate = 1;

  static String _file(Sfx s, int n) => switch (s) {
        Sfx.catchFruit => 'catch_${n.clamp(0, 7)}',
        Sfx.bonus => 'bonus',
        Sfx.bomb => 'bomb',
        Sfx.chili => 'chili',
        Sfx.heart => 'heart',
        Sfx.skill => 'skill',
        Sfx.combo => 'combo',
        Sfx.levelUp => 'levelup',
        Sfx.gameOver => 'gameover',
        Sfx.newBest => 'newbest',
        Sfx.tick => 'tick',
        Sfx.go => 'go',
        Sfx.pause => 'pause',
        Sfx.resume => 'resume',
        Sfx.click => 'click',
      };

  /// [n] chỉ dùng cho [Sfx.catchFruit]: combo hiện tại -> cao độ tăng dần.
  Future<void> play(Sfx sfx, {int n = 0}) async {
    if (!sfxOn || _suspended) return;
    final name = _file(sfx, n);
    try {
      final pool = _pools.putIfAbsent(name, () {
        return List.generate(_poolSize, (_) => AudioPlayer()..setPlayerMode(PlayerMode.lowLatency));
      });
      final i = _next[name] = ((_next[name] ?? -1) + 1) % _poolSize;
      await pool[i].stop();
      await pool[i].play(AssetSource('audio/$name.wav'), volume: _sfxVolume);
    } catch (e) {
      debugPrint('Audio sfx error ($name): $e');
    }
  }

  /// Các thao tác nhạc chạy lần lượt, tránh play/pause/stop giẫm lên nhau.
  Future<void> _queue(Future<void> Function() op) {
    return _musicQueue = _musicQueue.then((_) => op()).catchError((Object e) {
      debugPrint('Audio music error: $e');
    });
  }

  Future<void> startMusic() {
    _musicWanted = true;
    if (!musicOn || _suspended) return Future.value();
    return _queue(() async {
      final p = _music ??= AudioPlayer();
      await p.setReleaseMode(ReleaseMode.loop);
      await p.setVolume(_musicVolume);
      await p.play(AssetSource('audio/music.wav'), volume: _musicVolume);
      if (_rate != 1) await p.setPlaybackRate(_rate);
    });
  }

  Future<void> pauseMusic() => _queue(() async => _music?.pause());

  Future<void> resumeMusic() {
    if (!musicOn || _suspended || !_musicWanted) return Future.value();
    if (_music == null || _music!.state == PlayerState.stopped) return startMusic();
    return _queue(() async => _music!.resume());
  }

  Future<void> stopMusic() {
    _musicWanted = false;
    return _queue(() async => _music?.stop());
  }

  /// Nhạc nhanh dần theo level (1.0 → 1.25).
  Future<void> setMusicRate(double rate) async {
    if ((rate - _rate).abs() < 0.01) return;
    _rate = rate;
    await _queue(() async => _music?.setPlaybackRate(rate));
  }

  void setMusicOn(bool v) {
    musicOn = v;
    if (!v) {
      pauseMusic();
    } else if (_musicWanted) {
      startMusic();
    }
  }

  /// App xuống nền thì tắt tiếng.
  void suspend(bool value) {
    _suspended = value;
    if (value) {
      pauseMusic();
    } else if (_musicWanted) {
      resumeMusic();
    }
  }

  Future<void> dispose() async {
    for (final pool in _pools.values) {
      for (final p in pool) {
        await p.dispose();
      }
    }
    await _music?.dispose();
  }
}
