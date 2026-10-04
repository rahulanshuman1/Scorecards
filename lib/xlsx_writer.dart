import 'dart:convert';
import 'package:archive/archive.dart' as ar;

/// Minimal .xlsx writer (no extra dependency). Text cells use inline strings.
class XCell {
  final Object? value;
  final bool bold;
  const XCell(this.value, {this.bold = false});
}

class XSheet {
  final String name;
  final List<List<XCell>> rows;
  XSheet(this.name, this.rows);
}

const _ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _nsR = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _nsRel = 'http://schemas.openxmlformats.org/package/2006/relationships';
const _hdr = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

String _esc(String s) => s
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _col(int i) {
  var n = i + 1;
  var s = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

String _sheetXml(XSheet sh) {
  final widths = <int, int>{};
  for (final r in sh.rows) {
    for (var c = 0; c < r.length; c++) {
      final len = (r[c].value?.toString() ?? '').length;
      if (len > (widths[c] ?? 0)) widths[c] = len;
    }
  }
  final sb = StringBuffer('$_hdr<worksheet xmlns="$_ns">');
  if (widths.isNotEmpty) {
    sb.write('<cols>');
    final keys = widths.keys.toList()..sort();
    for (final c in keys) {
      final w = (widths[c]! + 3).clamp(8, 60);
      sb.write('<col min="${c + 1}" max="${c + 1}" width="$w" customWidth="1"/>');
    }
    sb.write('</cols>');
  }
  sb.write('<sheetData>');
  for (var ri = 0; ri < sh.rows.length; ri++) {
    final r = sh.rows[ri];
    sb.write('<row r="${ri + 1}">');
    for (var ci = 0; ci < r.length; ci++) {
      final cell = r[ci];
      final v = cell.value;
      if (v == null || (v is String && v.isEmpty)) continue;
      final ref = '${_col(ci)}${ri + 1}';
      final st = cell.bold ? ' s="1"' : '';
      if (v is num) {
        final n = (v is double && !v.isFinite) ? 0 : v;
        sb.write('<c r="$ref"$st><v>$n</v></c>');
      } else {
        sb.write('<c r="$ref"$st t="inlineStr"><is><t xml:space="preserve">${_esc(v.toString())}</t></is></c>');
      }
    }
    sb.write('</row>');
  }
  sb.write('</sheetData></worksheet>');
  return sb.toString();
}

String _safeName(String name, Set<String> used) {
  var n = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  if (n.isEmpty) n = 'Sheet';
  if (n.length > 31) n = n.substring(0, 31);
  var out = n;
  var k = 2;
  while (used.contains(out.toLowerCase())) {
    final suffix = ' ($k)';
    out = (n.length + suffix.length > 31 ? n.substring(0, 31 - suffix.length) : n) + suffix;
    k++;
  }
  used.add(out.toLowerCase());
  return out;
}

const _styles = '$_hdr<styleSheet xmlns="$_ns">'
    '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
    '<fills count="2"><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';

List<int> buildXlsx(List<XSheet> sheets) {
  final used = <String>{};
  final names = [for (final s in sheets) _safeName(s.name, used)];
  final a = ar.Archive();
  void add(String path, String content) {
    final b = utf8.encode(content);
    a.addFile(ar.ArchiveFile(path, b.length, b));
  }

  final ct = StringBuffer('$_hdr<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');
  for (var i = 0; i < sheets.length; i++) {
    ct.write('<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
  }
  ct.write('</Types>');
  add('[Content_Types].xml', ct.toString());

  add('_rels/.rels',
      '$_hdr<Relationships xmlns="$_nsRel"><Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
      'Target="xl/workbook.xml"/></Relationships>');

  final wb = StringBuffer('$_hdr<workbook xmlns="$_ns" xmlns:r="$_nsR"><sheets>');
  final rel = StringBuffer('$_hdr<Relationships xmlns="$_nsRel">');
  for (var i = 0; i < sheets.length; i++) {
    wb.write('<sheet name="${_esc(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>');
    rel.write('<Relationship Id="rId${i + 1}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
        'Target="worksheets/sheet${i + 1}.xml"/>');
    add('xl/worksheets/sheet${i + 1}.xml', _sheetXml(sheets[i]));
  }
  wb.write('</sheets></workbook>');
  rel.write('<Relationship Id="rId${sheets.length + 1}" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
      'Target="styles.xml"/></Relationships>');
  add('xl/workbook.xml', wb.toString());
  add('xl/_rels/workbook.xml.rels', rel.toString());
  add('xl/styles.xml', _styles);

  final List<int>? out = ar.ZipEncoder().encode(a);
  if (out == null) throw Exception('Could not create the Excel file');
  return out;
}
