import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScoreEntry {
  final String name;
  final int score;
  final DateTime date;
  const ScoreEntry(this.name, this.score, this.date);

  Map<String, dynamic> toJson() => {'n': name, 's': score, 'd': date.millisecondsSinceEpoch};

  factory ScoreEntry.fromJson(Map<String, dynamic> j) => ScoreEntry(
        j['n'] as String,
        j['s'] as int,
        DateTime.fromMillisecondsSinceEpoch(j['d'] as int),
      );
}

/// Bảng điểm cao (top 5) lưu trên máy.
class ScoreStore extends ChangeNotifier {
  static const _key = 'scores_v1';
  List<ScoreEntry> top = [];
  SharedPreferences? _prefs;

  int get best => top.isEmpty ? 0 : top.first.score;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    try {
      final raw = _prefs!.getString(_key);
      if (raw != null) {
        top = (jsonDecode(raw) as List)
            .map((e) => ScoreEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      top = [];
    }
    notifyListeners();
  }

  /// Trả về true nếu là kỷ lục mới.
  Future<bool> add(String name, int score) async {
    if (score <= 0) return false;
    final isBest = score > best;
    top = [...top, ScoreEntry(name.isEmpty ? 'Ẩn danh' : name, score, DateTime.now())]
      ..sort((a, b) => b.score.compareTo(a.score));
    if (top.length > 5) top = top.sublist(0, 5);
    notifyListeners();
    try {
      await _prefs?.setString(_key, jsonEncode(top.map((e) => e.toJson()).toList()));
    } catch (_) {}
    return isBest;
  }
}
