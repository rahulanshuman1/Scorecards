import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide display settings + imported teams/players roster.
class AppState extends ChangeNotifier {
  static final AppState I = AppState._();
  AppState._();

  double fontScale = 1.0;
  bool bold = false;
  bool animations = true;
  int accent = 0xFF0B6E4F;
  int? textColor; // null = automatic
  ThemeMode mode = ThemeMode.system;
  Map<String, List<String>> roster = {};

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    fontScale = p.getDouble('fs') ?? 1.0;
    bold = p.getBool('bold') ?? false;
    animations = p.getBool('anim') ?? true;
    accent = p.getInt('accent') ?? 0xFF0B6E4F;
    textColor = p.containsKey('tc') ? p.getInt('tc') : null;
    final mi = (p.getInt('mode') ?? 0).clamp(0, 2).toInt();
    mode = ThemeMode.values[mi];
    final r = p.getString('roster_v1');
    if (r != null) {
      try {
        roster = (jsonDecode(r) as Map)
            .map((k, v) => MapEntry(k as String, List<String>.from(v)));
      } catch (_) {}
    }
  }

  Future<void> _saveSettings() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('fs', fontScale);
    await p.setBool('bold', bold);
    await p.setBool('anim', animations);
    await p.setInt('accent', accent);
    if (textColor == null) {
      await p.remove('tc');
    } else {
      await p.setInt('tc', textColor!);
    }
    await p.setInt('mode', mode.index);
  }

  Future<void> _saveRoster() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('roster_v1', jsonEncode(roster));
  }

  void _changed() {
    notifyListeners();
    _saveSettings();
  }

  void setFontScale(double v) {
    fontScale = double.parse(v.clamp(0.8, 2.5).toStringAsFixed(2));
    _changed();
  }

  void setBold(bool v) {
    bold = v;
    _changed();
  }

  void setAnimations(bool v) {
    animations = v;
    _changed();
  }

  void setAccent(int c) {
    accent = c;
    _changed();
  }

  void setTextColor(int? c) {
    textColor = c;
    _changed();
  }

  void setMode(ThemeMode m) {
    mode = m;
    _changed();
  }

  void resetDisplay() {
    fontScale = 1.0;
    bold = false;
    animations = true;
    accent = 0xFF0B6E4F;
    textColor = null;
    mode = ThemeMode.system;
    _changed();
  }

  void mergeRoster(Map<String, List<String>> m) {
    roster = {...roster, ...m};
    notifyListeners();
    _saveRoster();
  }

  void removeTeam(String team) {
    roster.remove(team);
    notifyListeners();
    _saveRoster();
  }

  void clearRoster() {
    roster = {};
    notifyListeners();
    _saveRoster();
  }

  // ---- roster editing ----
  void _rosterChanged() {
    notifyListeners();
    _saveRoster();
  }

  void addTeam(String name) {
    name = name.trim();
    if (name.isEmpty || roster.containsKey(name)) return;
    roster = {...roster, name: <String>[]};
    _rosterChanged();
  }

  void renameTeam(String old, String name) {
    name = name.trim();
    if (name.isEmpty || !roster.containsKey(old)) return;
    if (name != old && roster.containsKey(name)) return;
    roster = {
      for (final e in roster.entries) (e.key == old ? name : e.key): e.value,
    };
    _rosterChanged();
  }

  void addPlayer(String team, String player) {
    player = player.trim();
    final l = roster[team];
    if (l == null || player.isEmpty || l.contains(player)) return;
    l.add(player);
    _rosterChanged();
  }

  void renamePlayer(String team, int index, String player) {
    player = player.trim();
    final l = roster[team];
    if (l == null || player.isEmpty || index < 0 || index >= l.length) return;
    l[index] = player;
    _rosterChanged();
  }

  void removePlayer(String team, int index) {
    final l = roster[team];
    if (l == null || index < 0 || index >= l.length) return;
    l.removeAt(index);
    _rosterChanged();
  }
}
