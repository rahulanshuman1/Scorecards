import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'models.dart';
import 'xlsx_writer.dart';

XCell _h(String s) => XCell(s, bold: true);

List<XSheet> cricketSheets(CricketMatch m) {
  final sheets = <XSheet>[];
  String score(Innings i) => '${i.runs}/${i.wickets} (${i.overs} ov)';

  sheets.add(XSheet('Summary', [
    [_h('Match'), XCell('${m.teamA} vs ${m.teamB}')],
    [_h('Date'), XCell(m.date.toString().substring(0, 16))],
    [_h('Overs per innings'), XCell(m.overs)],
    [_h(m.teamA), XCell(score(m.innings[0]))],
    [_h(m.teamB), XCell(score(m.innings[1]))],
    [_h('Result'), XCell(m.finished ? m.result : 'In progress')],
  ]));

  for (var k = 0; k < 2; k++) {
    final i = m.innings[k];
    if (k == 1 && m.current == 0 && i.balls.isEmpty) continue;
    final team = k == 0 ? m.teamA : m.teamB;
    sheets.add(XSheet('Innings ${k + 1} - $team', [
      [_h('$team  ${i.runs}/${i.wickets}  (${i.overs} ov)')],
      [],
      [_h('Batter'), _h('How out'), _h('Runs'), _h('Balls'), _h('4s'), _h('6s'), _h('SR')],
      for (final b in i.batting)
        [
          XCell(b.name),
          XCell(b.how ?? 'not out'),
          XCell(b.runs),
          XCell(b.balls),
          XCell(b.fours),
          XCell(b.sixes),
          XCell(double.parse(b.sr.toStringAsFixed(1))),
        ],
      [XCell('Extras'), XCell(''), XCell(i.extras)],
      [_h('Total'), XCell(''), _h('${i.runs}'), XCell('${i.wickets} wkts, ${i.overs} ov')],
      [],
      [_h('Bowler'), _h('Overs'), _h('Runs'), _h('Wickets'), _h('Econ')],
      for (final b in i.bowling)
        [
          XCell(b.name),
          XCell(b.overs),
          XCell(b.runs),
          XCell(b.wkts),
          XCell(double.parse(b.econ.toStringAsFixed(2))),
        ],
    ]));
  }

  final bb = <List<XCell>>[
    [_h('Innings'), _h('Over'), _h('Ball'), _h('Bowler'), _h('Striker'), _h('Non-striker'),
     _h('Event'), _h('Runs'), _h('Score')],
  ];
  for (var k = 0; k < 2; k++) {
    var legal = 0, total = 0, wk = 0;
    for (final b in m.innings[k].balls) {
      total += b.total;
      if (b.wicket) wk++;
      final event = b.wicket
          ? 'Wicket (${b.wkType ?? 'out'}) ${b.out ?? ''}'.trim()
          : (b.extra != null ? b.label : '${b.runs}');
      bb.add([
        XCell(k + 1),
        XCell(legal ~/ 6 + 1),
        XCell(legal % 6 + 1),
        XCell(b.bowler ?? ''),
        XCell(b.batter ?? ''),
        XCell(b.nonStriker ?? ''),
        XCell(event),
        XCell(b.total),
        XCell('$total/$wk'),
      ]);
      if (b.legal) legal++;
    }
  }
  sheets.add(XSheet('Ball by ball', bb));
  return sheets;
}

List<XSheet> footballSheets(FootballMatch m) {
  const names = {
    'goal': 'Goal',
    'owngoal': 'Own goal',
    'yellow': 'Yellow card',
    'red': 'Red card',
    'sub': 'Substitution',
  };
  return [
    XSheet('Summary', [
      [_h('Match'), XCell('${m.teamA} vs ${m.teamB}')],
      [_h('Date'), XCell(m.date.toString().substring(0, 16))],
      [_h('Score'), XCell('${m.teamA} ${m.score(0)} - ${m.score(1)} ${m.teamB}')],
      [_h('Status'), XCell(m.finished ? 'Full time' : 'In progress')],
      [],
      [_h('Team'), _h('Goals'), _h('Yellow cards'), _h('Red cards'), _h('Substitutions')],
      [XCell(m.teamA), XCell(m.score(0)), XCell(m.count('yellow', 0)), XCell(m.count('red', 0)), XCell(m.count('sub', 0))],
      [XCell(m.teamB), XCell(m.score(1)), XCell(m.count('yellow', 1)), XCell(m.count('red', 1)), XCell(m.count('sub', 1))],
    ]),
    XSheet('Events', [
      [_h('Minute'), _h('Team'), _h('Event'), _h('Player')],
      for (final e in m.events)
        [
          XCell(e.minute),
          XCell(e.team == 0 ? m.teamA : m.teamB),
          XCell(names[e.type] ?? e.type),
          XCell(e.player),
        ],
    ]),
  ];
}

Future<void> exportMatch(BuildContext context, SportMatch m) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final sheets = m is CricketMatch ? cricketSheets(m) : footballSheets(m as FootballMatch);
    final bytes = Uint8List.fromList(buildXlsx(sheets));
    final base = '${m.teamA}_vs_${m.teamB}'.replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');
    var path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save scorecard',
      fileName: '$base.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      bytes: bytes,
    );
    if (path == null) return;
    if (!Platform.isAndroid && !Platform.isIOS) {
      if (!path.toLowerCase().endsWith('.xlsx')) path = '$path.xlsx';
      await File(path).writeAsBytes(bytes);
    }
    messenger.showSnackBar(const SnackBar(content: Text('Scorecard saved as Excel file')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}
