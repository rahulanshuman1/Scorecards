import 'dart:convert';
import 'package:archive/archive.dart' as ar;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart' as x;
import 'app_state.dart';

// ---------------------------------------------------------------------------
// Own lightweight .xlsx reader (zip + xml): cells + pictures placed on cells.
// ---------------------------------------------------------------------------

class SheetImage {
  final int row, rowTo; // 0-based sheet rows (top-left / bottom-right anchor)
  final List<int> bytes;
  final String ext;
  SheetImage(this.row, this.rowTo, this.bytes, this.ext);
}

class SheetData {
  final String name;
  final List<List<String>> rows;
  final List<int> rowNums; // 0-based sheet row index of each entry in [rows]
  final List<SheetImage> images;
  SheetData(this.name, this.rows, this.rowNums, [this.images = const []]);
}

class PendingPhoto {
  final String team, player, ext;
  final List<int> bytes;
  PendingPhoto(this.team, this.player, this.bytes, this.ext);
}

class RosterResult {
  final Map<String, List<String>> teams;
  final List<PendingPhoto> photos;
  RosterResult(this.teams, this.photos);
}

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

String _resolve(String baseDir, String target) {
  if (target.startsWith('/')) return target.substring(1);
  final parts = <String>[...baseDir.split('/').where((e) => e.isNotEmpty)];
  for (final seg in target.split('/')) {
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (seg != '.' && seg.isNotEmpty) {
      parts.add(seg);
    }
  }
  return parts.join('/');
}

class _Grid {
  final List<List<String>> rows = [];
  final List<int> nums = [];
}

_Grid _readSheet(String xmlText, List<String> shared) {
  final doc = x.XmlDocument.parse(xmlText);
  final grid = _Grid();
  var lastRow = -1;
  for (final row in _els(doc, 'row')) {
    final rAttr = int.tryParse(row.getAttribute('r') ?? '');
    final rowIdx = rAttr != null ? rAttr - 1 : lastRow + 1;
    lastRow = rowIdx;
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
    grid.rows.add([for (var i = 0; i <= maxC; i++) cells[i] ?? '']);
    grid.nums.add(rowIdx);
  }
  return grid;
}

List<SheetData> readXlsx(List<int> bytes) {
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

  // pictures placed over cells of a sheet
  List<SheetImage> imagesFor(String sheetPath) {
    final out = <SheetImage>[];
    try {
      final slash = sheetPath.lastIndexOf('/');
      final dir = sheetPath.substring(0, slash);
      final file = sheetPath.substring(slash + 1);
      final rel = text('$dir/_rels/$file.rels');
      if (rel == null) return out;
      for (final r in _els(x.XmlDocument.parse(rel), 'Relationship')) {
        if (!(r.getAttribute('Type') ?? '').endsWith('/drawing')) continue;
        final dPath = _resolve(dir, r.getAttribute('Target') ?? '');
        final dXml = text(dPath);
        if (dXml == null) continue;
        final dSlash = dPath.lastIndexOf('/');
        final dDir = dPath.substring(0, dSlash);
        final dFile = dPath.substring(dSlash + 1);
        final targets = <String, String>{};
        final dRel = text('$dDir/_rels/$dFile.rels');
        if (dRel != null) {
          for (final rr in _els(x.XmlDocument.parse(dRel), 'Relationship')) {
            targets[rr.getAttribute('Id') ?? ''] = _resolve(dDir, rr.getAttribute('Target') ?? '');
          }
        }
        final doc = x.XmlDocument.parse(dXml);
        final anchors = doc.descendants.whereType<x.XmlElement>().where(
            (e) => e.name.local == 'twoCellAnchor' || e.name.local == 'oneCellAnchor');
        for (final anchor in anchors) {
          final fromEl = _kids(anchor, 'from');
          if (fromEl.isEmpty) continue;
          final rowEl = _kids(fromEl.first, 'row');
          if (rowEl.isEmpty) continue;
          final row = int.tryParse(rowEl.first.innerText.trim());
          if (row == null) continue;
          var rowTo = row;
          final toEl = _kids(anchor, 'to');
          if (toEl.isNotEmpty) {
            final rt = _kids(toEl.first, 'row');
            if (rt.isNotEmpty) rowTo = int.tryParse(rt.first.innerText.trim()) ?? row;
          }
          String? embed;
          for (final blip in _els(anchor, 'blip')) {
            for (final a in blip.attributes) {
              if (a.name.local == 'embed') embed = a.value;
            }
          }
          if (embed == null) continue;
          final mediaPath = targets[embed];
          if (mediaPath == null) continue;
          final f = find(mediaPath);
          if (f == null) continue;
          final dot = mediaPath.lastIndexOf('.');
          out.add(SheetImage(
            row,
            rowTo,
            List<int>.from((f.content as List).cast<int>()),
            dot >= 0 ? mediaPath.substring(dot).toLowerCase() : '.png',
          ));
        }
      }
    } catch (_) {}
    return out;
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

  final out = <SheetData>[];
  for (final s in sheets) {
    final t = text(s.value);
    if (t == null) continue;
    final g = _readSheet(t, shared);
    out.add(SheetData(s.key, g.rows, g.nums, imagesFor(s.value)));
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
/// Pictures placed over a player's row (any column) become that player's photo.
RosterResult rosterFromSheets(List<SheetData> sheets) {
  final out = <String, List<String>>{};
  final photos = <PendingPhoto>[];

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
    final rows = sh.rows.map((r) => r.map((e) => e.trim()).toList()).toList();
    final rowOf = <int, MapEntry<String, String>>{}; // sheet row -> (team, player)
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
      for (var ri = hi + 1; ri < rows.length; ri++) {
        final r = rows[ri];
        String cell(int i) => i < r.length ? r[i] : '';
        var t = cell(ti);
        if (t.isEmpty) {
          t = lastTeam;
        } else {
          lastTeam = t;
        }
        final player = cell(pi);
        add(t, player);
        if (t.isNotEmpty && player.isNotEmpty) {
          rowOf[sh.rowNums[ri]] = MapEntry(t, player);
        }
      }
    } else {
      var started = false;
      for (var ri = 0; ri < rows.length; ri++) {
        final r = rows[ri];
        if (r.isEmpty || r.first.isEmpty) continue;
        if (!started) {
          started = true;
          if (isPlayerH(r.first.toLowerCase())) continue;
        }
        add(sh.name, r.first);
        rowOf[sh.rowNums[ri]] = MapEntry(sh.name, r.first);
      }
    }
    for (final img in sh.images) {
      final hit = rowOf[img.row] ?? rowOf[img.rowTo];
      if (hit != null) photos.add(PendingPhoto(hit.key, hit.value, img.bytes, img.ext));
    }
  }
  return RosterResult(out, photos);
}

Future<RosterResult?> pickRosterFromExcel() async {
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
    return rosterFromSheets([
      SheetData('Teams', rows, [for (var i = 0; i < rows.length; i++) i]),
    ]);
  }
  return rosterFromSheets(readXlsx(bytes));
}

Future<void> importRosterFlow(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final r = await pickRosterFromExcel();
    if (r == null) return;
    if (r.teams.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('No teams found. First row must have columns: Team | Player')));
      return;
    }
    AppState.I.mergeRoster(r.teams);
    var photoCount = 0;
    for (final p in r.photos) {
      try {
        await AppState.I.setPhotoBytes(p.team, p.player, p.bytes, p.ext);
        photoCount++;
      } catch (_) {}
    }
    final players = r.teams.values.fold<int>(0, (s, l) => s + l.length);
    messenger.showSnackBar(SnackBar(
        content: Text('Imported ${r.teams.length} teams, $players players'
            '${photoCount > 0 ? ', $photoCount photos' : ''}')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(
        content: Text(
            'Could not read this file. Save it as .xlsx (not .xls) with columns Team | Player.  [$e]')));
  }
}

// ---------------------------------------------------------------------------
// Bulk photo import: pick many images; "Rahul Sharma.jpg" -> player "Rahul Sharma"
// ---------------------------------------------------------------------------

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[_\-\.]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

Future<void> importPhotosByName(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true);
    if (r == null || r.files.isEmpty) return;
    final index = <String, List<MapEntry<String, String>>>{};
    AppState.I.roster.forEach((team, players) {
      for (final p in players) {
        index.putIfAbsent(_norm(p), () => []).add(MapEntry(team, p));
      }
    });
    var matched = 0;
    final missed = <String>[];
    for (final f in r.files) {
      final path = f.path;
      if (path == null) continue;
      final dot = f.name.lastIndexOf('.');
      final base = dot > 0 ? f.name.substring(0, dot) : f.name;
      final hits = index[_norm(base)];
      if (hits == null || hits.isEmpty) {
        missed.add(f.name);
        continue;
      }
      for (final h in hits) {
        await AppState.I.setPhoto(h.key, h.value, path);
      }
      matched++;
    }
    final extra = missed.isEmpty
        ? ''
        : ' (no player named like: ${missed.take(3).join(', ')}${missed.length > 3 ? ', ...' : ''})';
    messenger.showSnackBar(
        SnackBar(content: Text('Photos matched: $matched of ${r.files.length}$extra')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Photo import failed: $e')));
  }
}
