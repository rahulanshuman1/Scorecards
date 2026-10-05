import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'app_state.dart';
import 'break_screen.dart';
import 'events_anim.dart';
import 'export_xlsx.dart';
import 'milestone_anim.dart';
import 'models.dart';
import 'settings_screen.dart';

class CricketScreen extends StatefulWidget {
  final CricketMatch match;
  final VoidCallback onChanged;
  const CricketScreen({super.key, required this.match, required this.onChanged});
  @override
  State<CricketScreen> createState() => _CricketScreenState();
}

class _CricketScreenState extends State<CricketScreen> {
  CricketMatch get m => widget.match;
  bool _asking = false;
  final _fx = GlobalKey<EventOverlayState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensure());
  }

  void _do(VoidCallback f) {
    setState(f);
    widget.onChanged();
  }

  void _act(VoidCallback f) {
    _do(f);
    _ensure();
  }

  /// Add a ball and play the matching animation (Six, Four, No Ball, Wide, Out).
  void _score(Ball b) {
    final before = m.now.balls.length;
    _do(() => m.addBall(b));
    if (m.now.balls.length <= before) {
      _ensure();
      return;
    }
    final k = <EventKind>[];
    if (b.wicket) {
      k.add(EventKind.out);
    } else {
      if (b.extra == 'nb') k.add(EventKind.noBall);
      if (b.extra == 'wd') k.add(EventKind.wide);
      if (b.extra == null || b.extra == 'nb') {
        if (b.runs == 6) k.add(EventKind.six);
        if (b.runs == 4) k.add(EventKind.four);
      }
    }
    // Batter reached 50 / 100 / 150 / 200 ...
    MilestoneInfo? milestone;
    if (!b.wicket && b.batterRuns > 0 && b.batter != null) {
      BatStat? st;
      for (final x in m.now.batting) {
        if (x.name == b.batter) st = x;
      }
      if (st != null) {
        final after = st.runs;
        final before = after - b.batterRuns;
        if (after >= 50 && after ~/ 50 > before ~/ 50) {
          milestone = MilestoneInfo(
            name: st.name,
            team: m.battingTeam,
            runs: after,
            balls: st.balls,
            fours: st.fours,
            sixes: st.sixes,
            strikeRate: st.sr,
            milestone: (after ~/ 50) * 50,
            photoPath: AppState.I.photoFor(m.battingTeam, st.name),
          );
        }
      }
    }
    // Show the animation first; ask for the new batter / bowler only afterwards.
    final fx = _fx.currentState;
    if (fx == null) {
      _ensure();
    } else {
      fx.show(k, milestone: milestone, onDone: _ensure);
    }
  }

  // ---- player selection ----

  Future<String?> _askName(String title, List<String> options,
      {List<String> returning = const []}) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        void submit(String v) {
          if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
        }

        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: c,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Player name'),
              onSubmitted: submit,
            ),
            if (options.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(spacing: 6, children: [
                  for (final o in options)
                    ActionChip(label: Text(o), onPressed: () => Navigator.pop(ctx, o)),
                ]),
              ),
            if (returning.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Retired hurt – can return:'),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, children: [
                    for (final o in returning)
                      ActionChip(
                        avatar: const Icon(Icons.replay, size: 18),
                        label: Text(o),
                        onPressed: () => Navigator.pop(ctx, o),
                      ),
                  ]),
                ]),
              ),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
            FilledButton(onPressed: () => submit(c.text), child: const Text('OK')),
          ],
        );
      },
    );
  }

  List<String> _batOptions(Innings i) {
    final used = i.batting.map((b) => b.name).toSet();
    return m.battingPlayers.where((p) => !used.contains(p)).toList();
  }

  Future<void> _timeout() async {
    if (m.finished) return;
    final i = m.now;
    final limit = AppState.I.timeoutsPerInnings;
    if (limit > 0 && i.timeouts.length >= limit) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Timeout limit reached'),
          content: Text('All $limit strategic timeouts for this innings have been used. Start another one anyway?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start anyway')),
          ],
        ),
      );
      if (go != true) return;
    }
    if (!mounted) return;
    final by = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Strategic timeout – called by'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, '${m.battingTeam} (batting)'),
            child: Text('${m.battingTeam}  (batting team)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, '${m.bowlingTeam} (bowling)'),
            child: Text('${m.bowlingTeam}  (bowling team)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'Mandatory broadcast timeout'),
            child: const Text('Mandatory / broadcast timeout'),
          ),
        ],
      ),
    );
    if (by == null || !mounted) return;
    final secs = AppState.I.timeoutSeconds;
    _do(() => i.timeouts.add(TimeoutRec(i.legalBalls, by, secs)));
    await showBreak(
      context,
      match: m,
      kind: BreakKind.timeout,
      seconds: secs,
      calledBy: by,
      timeoutNo: i.timeouts.length,
      timeoutTotal: limit,
    );
    if (mounted) _ensure();
  }

  Future<void> _inningsBreak() async {
    await showBreak(
      context,
      match: m,
      kind: BreakKind.innings,
      seconds: AppState.I.breakMinutes * 60,
    );
    if (mounted) _ensure();
  }

  Future<void> _endInnings() async {
    if (m.finished) return;
    if (m.current == 0) {
      _do(m.endInnings);
      await _inningsBreak();
    } else {
      _act(m.endInnings);
    }
  }

  List<String> _returning(Innings i) =>
      i.batting.where((b) => b.how == 'retired hurt').map((b) => b.name).toList();

  Future<void> _retire() async {
    final i = m.now;
    if (m.finished || i.striker == null || i.nonStriker == null) return;
    final strikerOut = await showDialog<bool>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Retired hurt – who?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('${i.striker} (striker)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('${i.nonStriker} (non-striker)'),
          ),
        ],
      ),
    );
    if (strikerOut == null) return;
    final who = strikerOut ? i.striker! : i.nonStriker!;
    final name = await _askName('Replace $who with', _batOptions(i), returning: _returning(i));
    if (name == null) return;
    if (name == i.striker || name == i.nonStriker) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('That batter is already at the crease')));
      }
      return;
    }
    _do(() => i.retire(strikerOut, name));
  }

  List<String> _bowlOptions(Innings i) =>
      m.bowlingPlayers.isNotEmpty ? m.bowlingPlayers : i.bowlerNames;

  Future<void> _ensure() async {
    if (_asking) return;
    _asking = true;
    try {
      while (mounted && !m.finished && !m.inningsOver && m.now.needsPlayers) {
        final i = m.now;
        if (i.striker == null) {
          final n = await _askName(i.balls.isEmpty ? 'Opening batter (striker)' : 'New batter', _batOptions(i),
              returning: _returning(i));
          if (n == null) break;
          _do(() => i.striker = n);
        } else if (i.nonStriker == null) {
          final n = await _askName(i.balls.isEmpty ? 'Opening batter (non-striker)' : 'New batter', _batOptions(i),
              returning: _returning(i));
          if (n == null) break;
          _do(() => i.nonStriker = n);
        } else {
          final n = await _askName('Bowler – ${m.bowlingTeam}', _bowlOptions(i));
          if (n == null) break;
          _do(() => i.bowler = n);
        }
      }
    } finally {
      _asking = false;
    }
  }

  // ---- scoring actions ----

  Future<void> _extra(String type) async {
    final title = {
      'wd': 'Wide – extra runs run',
      'nb': 'No ball – runs off the bat',
      'b': 'Byes',
      'lb': 'Leg byes',
    }[type]!;
    final options = (type == 'wd' || type == 'nb') ? [0, 1, 2, 3, 4, 6] : [1, 2, 3, 4];
    final r = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
            for (final o in options)
              FilledButton.tonal(onPressed: () => Navigator.pop(ctx, o), child: Text('$o')),
          ]),
        ],
      ),
    );
    if (r != null) _score(Ball(extra: type, runs: r));
  }

  Future<void> _wicket() async {
    final i = m.now;
    final types = ['Bowled', 'Caught', 'LBW', 'Stumped', 'Hit wicket', 'Run out (striker)', 'Run out (non-striker)'];
    final t = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('How out?'),
        children: [
          for (final x in types)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, x), child: Text(x)),
        ],
      ),
    );
    if (t == null) return;
    final runOut = t.startsWith('Run out');
    _score(Ball(
      wicket: true,
      wkType: runOut ? 'run out' : t.toLowerCase(),
      out: t == 'Run out (non-striker)' ? i.nonStriker : null,
    ));
  }

  // ---- export ----

  Future<void> _pdf() async {
    final doc = pw.Document();
    final font = pw.Font.courier();
    doc.addPage(pw.MultiPage(
      build: (_) => [pw.Text(m.scorecardText, style: pw.TextStyle(font: font, fontSize: 9))],
    ));
    final bytes = await doc.save();
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: '${m.teamA}_vs_${m.teamB}');
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: m.scorecardText));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Scorecard copied')));
    }
  }

  // ---- UI ----

  Widget _btn(String label, VoidCallback onTap, {Color? color}) {
    final enabled = !(m.finished || m.inningsOver || m.now.needsPlayers);
    return Padding(
      padding: const EdgeInsets.all(4),
      child: FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size(72, 52),
          backgroundColor: color,
        ),
        onPressed: enabled ? onTap : null,
        child: Text(label, style: const TextStyle(fontSize: 17)),
      ),
    );
  }

  Widget _face(String? name) {
    if (name == null) return const SizedBox.shrink();
    final p = AppState.I.photoFor(m.battingTeam, name);
    return CircleAvatar(
      radius: 16,
      backgroundImage: p != null ? FileImage(File(p)) : null,
      child: p == null ? Text(name.substring(0, 1).toUpperCase()) : null,
    );
  }

  void _previewMilestone() {
    if (!AppState.I.animations) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Animations are switched off in Display settings')));
      return;
    }
    final i = m.now;
    final name = i.striker ??
        (m.battingPlayers.isNotEmpty ? m.battingPlayers.first : 'Sample Player');
    BatStat? st;
    for (final x in i.batting) {
      if (x.name == name) st = x;
    }
    _fx.currentState?.show([],
        milestone: MilestoneInfo(
          name: name,
          team: m.battingTeam,
          runs: 50,
          balls: st != null && st.balls > 0 ? st.balls : 32,
          fours: st?.fours ?? 5,
          sixes: st?.sixes ?? 2,
          strikeRate: st != null && st.balls > 0 ? st.sr : 156.3,
          milestone: 50,
          photoPath: AppState.I.photoFor(m.battingTeam, name),
        ));
  }

  Widget _crease(Innings i) {
    BatStat? find(String? n) {
      for (final b in i.batting) {
        if (b.name == n) return b;
      }
      return null;
    }

    String bat(String? n, String mark) {
      if (n == null) return '-';
      final s = find(n);
      return '$n$mark  ${s?.runs ?? 0} (${s?.balls ?? 0})';
    }

    String bowl() {
      if (i.bowler == null) return '-';
      for (final b in i.bowling) {
        if (b.name == i.bowler) return '${b.name}  ${b.overs}-${b.runs}-${b.wkts}';
      }
      return '${i.bowler}  0.0-0-0';
    }

    return Column(children: [
      Row(children: [
        Expanded(
          child: Row(children: [
            _face(i.striker),
            const SizedBox(width: 6),
            Expanded(child: Text(bat(i.striker, ' *'))),
          ]),
        ),
        Expanded(
          child: Row(children: [
            _face(i.nonStriker),
            const SizedBox(width: 6),
            Expanded(child: Text(bat(i.nonStriker, ''))),
          ]),
        ),
      ]),
      const SizedBox(height: 4),
      Align(alignment: Alignment.centerLeft, child: Text('Bowling: ${bowl()}')),
    ]);
  }

  Widget _inningsCard(int k) {
    final i = m.innings[k];
    final team = k == 0 ? m.teamA : m.teamB;
    return Card(
      child: ExpansionTile(
        key: PageStorageKey('inn$k'),
        initiallyExpanded: k == m.current,
        title: Text('$team  ${i.runs}/${i.wickets}  (${i.overs} ov)'),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 16,
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 44,
              columns: const [
                DataColumn(label: Text('Batter')),
                DataColumn(label: Text('R'), numeric: true),
                DataColumn(label: Text('B'), numeric: true),
                DataColumn(label: Text('4s'), numeric: true),
                DataColumn(label: Text('6s'), numeric: true),
                DataColumn(label: Text('SR'), numeric: true),
              ],
              rows: [
                for (final b in i.batting)
                  DataRow(cells: [
                    DataCell(Text('${b.name}${b.out ? '' : '*'}${b.how != null ? '  (${b.how})' : ''}')),
                    DataCell(Text('${b.runs}')),
                    DataCell(Text('${b.balls}')),
                    DataCell(Text('${b.fours}')),
                    DataCell(Text('${b.sixes}')),
                    DataCell(Text(b.sr.toStringAsFixed(1))),
                  ]),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(alignment: Alignment.centerLeft, child: Text('Extras: ${i.extras}')),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 16,
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 44,
              columns: const [
                DataColumn(label: Text('Bowler')),
                DataColumn(label: Text('O'), numeric: true),
                DataColumn(label: Text('R'), numeric: true),
                DataColumn(label: Text('W'), numeric: true),
                DataColumn(label: Text('Econ'), numeric: true),
              ],
              rows: [
                for (final b in i.bowling)
                  DataRow(cells: [
                    DataCell(Text(b.name)),
                    DataCell(Text(b.overs)),
                    DataCell(Text('${b.runs}')),
                    DataCell(Text('${b.wkts}')),
                    DataCell(Text(b.econ.toStringAsFixed(2))),
                  ]),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i = m.now;
    final canScore = !(m.finished || m.inningsOver);
    return Scaffold(
      appBar: AppBar(
        title: Text('${m.teamA} vs ${m.teamB}'),
        actions: [
          ...displayActions(context),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'timeout') {
                _timeout();
              } else if (v == 'break') {
                _inningsBreak();
              } else if (v == 'preview') {
                _previewMilestone();
              } else if (v == 'xlsx') {
                exportMatch(context, m);
              } else if (v == 'pdf') {
                _pdf();
              } else {
                _copy();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'timeout', child: Text('Strategic timeout')),
              PopupMenuItem(
                value: 'break',
                enabled: m.current == 1,
                child: const Text('Innings break'),
              ),
              const PopupMenuItem(value: 'preview', child: Text('Preview 50 animation')),
              PopupMenuItem(value: 'xlsx', child: Text('Export Excel (.xlsx)')),
              PopupMenuItem(value: 'pdf', child: Text('Export PDF / Print')),
              PopupMenuItem(value: 'copy', child: Text('Copy scorecard text')),
            ],
          ),
        ],
      ),
      body: EventOverlay(
        key: _fx,
        child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  Text('${m.battingTeam} batting • Innings ${m.current + 1}'),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('${i.runs}/${i.wickets}',
                        style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold)),
                  ),
                  Text('Overs ${i.overs} / ${m.overs}   •   RR ${i.runRate.toStringAsFixed(2)}'),
                  if (m.current == 1 && !m.finished) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Need ${m.target - i.runs} from ${m.overs * 6 - i.legalBalls} balls',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (m.finished) ...[
                    const SizedBox(height: 8),
                    Text(m.result, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                  if (canScore) ...[const Divider(height: 24), _crease(i)],
                ]),
              ),
            ),
            if (canScore && i.needsPlayers)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.tonalIcon(
                  onPressed: _ensure,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Select batters / bowler'),
                ),
              ),
            if (m.current == 0 && m.inningsOver && !m.finished)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.icon(
                  onPressed: _endInnings,
                  icon: const Icon(Icons.free_breakfast),
                  label: const Text('Innings complete – start innings break'),
                ),
              ),
            const SizedBox(height: 8),
            const Text('This over'),
            Wrap(spacing: 6, children: [for (final b in i.currentOver) Chip(label: Text(b.label))]),
            const SizedBox(height: 8),
            Wrap(alignment: WrapAlignment.center, children: [
              for (final r in [0, 1, 2, 3, 4, 6])
                _btn('$r', () => _score(Ball(runs: r))),
              _btn('Wd', () => _extra('wd'), color: Colors.orange),
              _btn('Nb', () => _extra('nb'), color: Colors.orange),
              _btn('Bye', () => _extra('b'), color: Colors.orange),
              _btn('LB', () => _extra('lb'), color: Colors.orange),
              _btn('W', _wicket, color: Colors.red),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _act(m.undo),
                  icon: const Icon(Icons.undo),
                  label: const Text('Undo'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: m.finished ? null : () => _endInnings(),
                  icon: const Icon(Icons.flag),
                  label: Text(m.current == 0 ? 'End innings' : 'End match'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: canScore ? _timeout : null,
                icon: const Icon(Icons.timer),
                label: Text('Strategic timeout (${i.timeouts.length}/${AppState.I.timeoutsPerInnings})'),
              ),
              OutlinedButton.icon(
                onPressed: (canScore && i.striker != null && i.nonStriker != null) ? _retire : null,
                icon: const Icon(Icons.healing),
                label: const Text('Retired hurt – replace batter'),
              ),
            ]),
            const SizedBox(height: 16),
            for (int k = 0; k <= m.current; k++) _inningsCard(k),
          ]),
        ),
      )),
    );
  }
}
