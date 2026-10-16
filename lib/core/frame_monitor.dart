import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class RenderStats {
  const RenderStats({this.fps = 0, this.buildMs = 0, this.rasterMs = 0, this.jank = 0});
  final double fps;
  final double buildMs;
  final double rasterMs;

  /// Tỉ lệ khung hình mà build + raster vượt 25ms (giật thấy được).
  final double jank;
}

/// Đo FPS thật của giao diện game (khác FPS của ML Kit) từ FrameTiming của engine.
class FrameMonitor {
  FrameMonitor._();
  static final instance = FrameMonitor._();

  final stats = ValueNotifier<RenderStats>(const RenderStats());
  final _clock = Stopwatch();
  int _frames = 0, _janky = 0;
  int _buildUs = 0, _rasterUs = 0;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _clock.start();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _frames++;
      _buildUs += t.buildDuration.inMicroseconds;
      _rasterUs += t.rasterDuration.inMicroseconds;
      if (t.buildDuration.inMicroseconds + t.rasterDuration.inMicroseconds > 25000) _janky++;
    }
    final ms = _clock.elapsedMilliseconds;
    if (ms < 1000 || _frames == 0) return;
    stats.value = RenderStats(
      fps: _frames * 1000 / ms,
      buildMs: _buildUs / _frames / 1000,
      rasterMs: _rasterUs / _frames / 1000,
      jank: _janky / _frames,
    );
    if (kDebugMode || const bool.fromEnvironment('PERF_LOG')) {
      debugPrint('PERF ui=${stats.value.fps.toStringAsFixed(0)}fps '
          'build=${stats.value.buildMs.toStringAsFixed(1)}ms '
          'raster=${stats.value.rasterMs.toStringAsFixed(1)}ms');
    }
    _frames = _janky = _buildUs = _rasterUs = 0;
    _clock
      ..reset()
      ..start();
  }
}
