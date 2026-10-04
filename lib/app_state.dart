import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
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
  Map<String, String> photos = {}; // 'team\u0001player' -> file path

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    fontScale = p.getDouble('fs') ?? 1.0;
    bold = p.getBool('bold') ?? false;
    animations = p.getBool('anim') ?? true;
    accent = p.getInt('accent') ?? 0xFF0B6E4F;
    textColor = p.containsKey('tc') ? p.getInt('tc') : null;
    final mi = (p.getInt('mode') ?? 0).clamp(0, 2).toInt();
    mode = ThemeMode.values[mi];
    final ph = p.getString('photos_v1');
    if (ph != null) {
      try {
        photos = (jsonDecode(ph) as Map).map((k, v) => MapEntry(k as String, v as String));
      } catch (_) {}
    }
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
    _dropPhotos('$team\u0001');
    notifyListeners();
    _saveRoster();
  }

  void clearRoster() {
    roster = {};
    _dropPhotos('');
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
    if (name != old) {
      final prefix = '$old\u0001';
      final moved = <String, String>{};
      photos.removeWhere((k, v) {
        if (k.startsWith(prefix)) {
          moved['$name\u0001${k.substring(prefix.length)}'] = v;
          return true;
        }
        return false;
      });
      photos.addAll(moved);
      _savePhotos();
    }
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
    final oldKey = _pk(team, l[index]);
    l[index] = player;
    final path = photos.remove(oldKey);
    if (path != null) {
      photos[_pk(team, player)] = path;
      _savePhotos();
    }
    _rosterChanged();
  }

  void removePlayer(String team, int index) {
    final l = roster[team];
    if (l == null || index < 0 || index >= l.length) return;
    final gone = photos.remove(_pk(team, l[index]));
    if (gone != null) {
      _deleteFile(gone);
      _savePhotos();
    }
    l.removeAt(index);
    _rosterChanged();
  }

  // ---- player photos ----
  String _pk(String team, String player) => '$team\u0001$player';

  String? photoFor(String team, String player) {
    final p = photos[_pk(team, player)];
    if (p == null) return null;
    try {
      return File(p).existsSync() ? p : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _savePhotos() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('photos_v1', jsonEncode(photos));
  }

  void _deleteFile(String? path) {
    if (path == null) return;
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  void _dropPhotos(String prefix) {
    final keys = photos.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in keys) {
      _deleteFile(photos.remove(k));
    }
    _savePhotos();
  }

  Future<void> setPhoto(String team, String player, String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}${Platform.pathSeparator}player_photos');
    if (!await folder.exists()) await folder.create(recursive: true);
    var ext = '';
    final dot = sourcePath.lastIndexOf('.');
    if (dot >= 0 && sourcePath.length - dot <= 6) ext = sourcePath.substring(dot);
    final dest =
        '${folder.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}$ext';
    await File(sourcePath).copy(dest);
    _deleteFile(photos[_pk(team, player)]);
    photos[_pk(team, player)] = dest;
    notifyListeners();
    await _savePhotos();
  }

  void removePhoto(String team, String player) {
    _deleteFile(photos.remove(_pk(team, player)));
    notifyListeners();
    _savePhotos();
  }
}
