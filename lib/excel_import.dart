import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'app_state.dart';

String _cellText(dynamic v) {
  if (v == null) return '';
  try {
    final inner = (v as dynamic).value;
    if (inner is String) return inner;
    if (inner is TextSpan) return inner.toPlainText();
    if (inner is double && inner == inner.truncateToDouble()) {
      return inner.toInt().toString();
    }
    if (inner != null) return inner.toString();
  } catch (_) {}
  return v.toString();
}

/// Layouts supported:
///  1) One sheet with header row "Team" | "Player" (blank Team cell = same team as above)
///  2) One sheet per team: sheet name = team name, players in column A
Map<String, List<String>> parseRoster(List<int> bytes) {
  final ex = Excel.decodeBytes(bytes);
  final out = <String, List<String>>{};

  void add(String team, String player) {
    team = team.trim();
    player = player.trim();
    if (team.isEmpty) return;
    final list = out.putIfAbsent(team, () => []);
    if (player.isNotEmpty && !list.contains(player)) list.add(player);
  }

  for (final entry in ex.tables.entries) {
    final rows = entry.value.rows
        .map((r) => r.map((c) => _cellText(c?.value)).toList())
        .toList();
    if (rows.isEmpty) continue;
    final header = rows.first.map((e) => e.trim().toLowerCase()).toList();
    final ti = header.indexOf('team');
    final pi = header.indexWhere(
        (h) => h == 'player' || h == 'players' || h == 'name' || h == 'player name');
    if (ti >= 0 && pi >= 0) {
      var lastTeam = '';
      for (final r in rows.skip(1)) {
        String cell(int i) => i < r.length ? r[i].trim() : '';
        var t = cell(ti);
        if (t.isEmpty) {
          t = lastTeam;
        } else {
          lastTeam = t;
        }
        add(t, cell(pi));
      }
    } else {
      final first = header.isNotEmpty ? header.first : '';
      final start = (first == 'player' || first == 'players' || first == 'name') ? 1 : 0;
      for (final r in rows.skip(start)) {
        if (r.isNotEmpty) add(entry.key, r.first);
      }
    }
  }
  return out;
}

Future<Map<String, List<String>>?> pickRosterFromExcel() async {
  final r = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
    withData: true,
  );
  if (r == null || r.files.isEmpty) return null;
  final bytes = r.files.single.bytes;
  if (bytes == null) throw Exception('Could not read the file');
  return parseRoster(bytes);
}

Future<void> importRosterFlow(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final r = await pickRosterFromExcel();
    if (r == null) return;
    if (r.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('No teams found. Use columns: Team | Player')));
      return;
    }
    AppState.I.mergeRoster(r);
    final players = r.values.fold<int>(0, (s, l) => s + l.length);
    messenger.showSnackBar(
        SnackBar(content: Text('Imported ${r.length} teams, $players players')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
  }
}
