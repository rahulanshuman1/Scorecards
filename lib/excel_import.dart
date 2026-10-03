import 'dart:convert';
import 'package:archive/archive.dart' as ar;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart' as x;
import 'app_state.dart';

// ---------------------------------------------------------------------------
// Own lightweight .xlsx reader (zip + xml) - no dependency on the `excel`
// package, which crashes on some files with "Null check operator...".
// ---------------------------------------------------------------------------

typedef SheetRows = MapEntry<String, List<List<String>>>;

Iterable<x.XmlElement> _els(x.XmlNode n, String local) =>
    n.descendants.whereType<x.XmlElement>().where((e) => e.name.local == local);

Iterable<x.XmlElement> _kids(x.XmlNode n, String local) =>
    n.children.whereType<x.XmlElement>().where((e) => e.name.local == local);

int _colIndex(String ref) {
  var n = 0;
  for (final u in ref.codeUnits) {
    if (u >= 65 && u <= 90) {
      n = n * 26 + (u - 64);
    } else if (u >= 97 && u <= 122) {
      n = n * 26 + (u - 96);
    } else {
      break;
    }
  }
  return n > 0 ? n - 1 : 0;
}

List<List<String>> _readSheet(String xmlText, List<String> shared) {
  final doc = x.XmlDocument.parse(xmlText);
  final rows = <List<String>>[];
  for (final row in _els(doc, 'row')) {
    final cells = <int, String>{};
    var next = 0;
    for (final c in _kids(row, 'c')) {
      final ref = c.getAttribute('r');
      final col = ref != null ? _colIndex(ref) : next;
      next = col + 1;
      final type = c.getAttribute('t');
      var val = '';
      if (type == 'inlineStr') {
        val = _els(c, 't').map((e) => e.innerText).join();
      } else {
        final vs = _kids(c, 'v');
        final raw = vs.isEmpty ? '' : vs.first.innerText;
        if (type == 's') {
          final idx = int.tryParse(raw);
          val = (idx != null && idx >= 0 && idx < shared.length) ? shared[idx] : '';
        } else if (type == 'b') {
          val = raw == '1' ? 'TRUE' : 'FALSE';
        } else {
          val = raw;
          final d = double.tryParse(raw);
          if (d != null && d == d.truncateToDouble() && d.abs() < 1e15) {
            val = d.toInt().toString();
          }
        }
      }
      cells[col] = val;
    }
    if (cells.isEmpty) continue;
    final maxC = cells.keys.reduce((a, b) => a > b ? a : b);
    rows.add([for (var i = 0; i <= maxC; i++) cells[i] ?? '']);
  }
  return rows;
}

List<SheetRows> readXlsx(List<int> bytes) {
  final zip = ar.ZipDecoder().decodeBytes(bytes);

  ar.ArchiveFile? find(String name) {
    for (final f in zip.files) {
      if (f.isFile && f.name.toLowerCase() == name.toLowerCase()) return f;
    }
    return null;
  }

  String? text(String name) {
    final f = find(name);
    if (f == null) return null;
    return utf8.decode((f.content as List).cast<int>(), allowMalformed: true);
  }

  // shared strings
  final shared = <String>[];
  final ss = text('xl/sharedStrings.xml');
  if (ss != null) {
    final doc = x.XmlDocument.parse(ss);
    for (final si in _els(doc, 'si')) {
      final sb = StringBuffer();
      for (final t in _els(si, 't')) {
        final inPhonetic =
            t.ancestors.whereType<x.XmlElement>().any((e) => e.name.local == 'rPh');
        if (!inPhonetic) sb.write(t.innerText);
      }
      shared.add(sb.toString());
    }
  }

  // sheet names -> files
  final sheets = <MapEntry<String, String>>[];
  final wb = text('xl/workbook.xml');
  final rels = text('xl/_rels/workbook.xml.rels');
  if (wb != null && rels != null) {
    final target = <String, String>{};
    for (final r in _els(x.XmlDocument.parse(rels), 'Relationship')) {
      target[r.getAttribute('Id') ?? ''] = r.getAttribute('Target') ?? '';
    }
    for (final s in _els(x.XmlDocument.parse(wb), 'sheet')) {
      String? rid;
      for (final a in s.attributes) {
        if (a.name.local == 'id') rid = a.value;
      }
      final t = target[rid ?? ''];
      if (t != null && t.isNotEmpty) {
        sheets.add(MapEntry(
          s.getAttribute('name') ?? 'Sheet',
          t.startsWith('/') ? t.substring(1) : 'xl/$t',
        ));
      }
    }
  }
  if (sheets.isEmpty) {
    final re = RegExp(r'^xl/worksheets/sheet\d+\.xml$', caseSensitive: false);
    final names = zip.files.where((f) => f.isFile && re.hasMatch(f.name)).map((f) => f.name).toList()
      ..sort();
    for (var i = 0; i < names.length; i++) {
      sheets.add(MapEntry('Sheet ${i + 1}', names[i]));
    }
  }

  final out = <SheetRows>[];
  for (final s in sheets) {
    final t = text(s.value);
    if (t == null) continue;
    out.add(MapEntry(s.key, _readSheet(t, shared)));
  }
  return out;
}

List<List<String>> parseCsv(String text) {
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  final rows = <List<String>>[];
  var row = <String>[];
  final sb = StringBuffer();
  var inQ = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQ) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          sb.write('"');
          i++;
        } else {
          inQ = false;
        }
      } else {
        sb.write(ch);
      }
    } else if (ch == '"') {
      inQ = true;
    } else if (ch == ',' || ch == ';' || ch == '\t') {
      row.add(sb.toString());
      sb.clear();
    } else if (ch == '\n') {
      row.add(sb.toString());
      sb.clear();
      rows.add(row);
      row = <String>[];
    } else if (ch != '\r') {
      sb.write(ch);
    }
  }
  if (sb.isNotEmpty || row.isNotEmpty) {
    row.add(sb.toString());
    rows.add(row);
  }
  return rows;
}

/// Layouts supported:
///  1) Header row "Team" | "Player" (blank Team cell = same team as above)
///  2) One sheet per team: sheet name = team name, players in column A
Map<String, List<String>> rosterFromSheets(List<SheetRows> sheets) {
  final out = <String, List<String>>{};

  void add(String team, String player) {
    team = team.trim();
    player = player.trim();
    if (team.isEmpty) return;
    final list = out.putIfAbsent(team, () => []);
    if (player.isNotEmpty && !list.contains(player)) list.add(player);
  }

  bool isTeamH(String e) => e == 'team' || e == 'teams' || e == 'team name';
  bool isPlayerH(String e) =>
      e == 'player' || e == 'players' || e == 'player name' || e == 'name';

  for (final sh in sheets) {
    final rows = sh.value.map((r) => r.map((e) => e.trim()).toList()).toList();
    var hi = -1, ti = -1, pi = -1;
    for (var i = 0; i < rows.length && i < 10; i++) {
      final h = rows[i].map((e) => e.toLowerCase()).toList();
      final t = h.indexWhere(isTeamH);
      final p = h.indexWhere(isPlayerH);
      if (t >= 0 && p >= 0) {
        hi = i;
        ti = t;
        pi = p;
        break;
      }
    }
    if (hi >= 0) {
      var lastTeam = '';
      for (final r in rows.skip(hi + 1)) {
        String cell(int i) => i < r.length ? r[i] : '';
        var t = cell(ti);
        if (t.isEmpty) {
          t = lastTeam;
        } else {
          lastTeam = t;
        }
        add(t, cell(pi));
      }
    } else {
      final col = rows.where((r) => r.isNotEmpty && r.first.isNotEmpty).toList();
      if (col.isEmpty) continue;
      final first = col.first.first.toLowerCase();
      final start = isPlayerH(first) ? 1 : 0;
      for (final r in col.skip(start)) {
        add(sh.key, r.first);
      }
    }
  }
  return out;
}

Future<Map<String, List<String>>?> pickRosterFromExcel() async {
  final r = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'csv'],
    withData: true,
  );
  if (r == null || r.files.isEmpty) return null;
  final f = r.files.single;
  final bytes = f.bytes;
  if (bytes == null) throw Exception('Could not read the file');
  final ext = (f.extension ?? '').toLowerCase();
  if (ext == 'csv') {
    final rows = parseCsv(utf8.decode(bytes, allowMalformed: true));
    return rosterFromSheets([MapEntry('Teams', rows)]);
  }
  return rosterFromSheets(readXlsx(bytes));
}

Future<void> importRosterFlow(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final r = await pickRosterFromExcel();
    if (r == null) return;
    if (r.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('No teams found. First row must have columns: Team | Player')));
      return;
    }
    AppState.I.mergeRoster(r);
    final players = r.values.fold<int>(0, (s, l) => s + l.length);
    messenger.showSnackBar(
        SnackBar(content: Text('Imported ${r.length} teams, $players players')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(
        content: Text(
            'Could not read this file. Save it as .xlsx (not .xls) with columns Team | Player.  [$e]')));
  }
}
