import 'dart:async';
import 'package:flutter/material.dart';
import 'events_anim.dart';
import 'models.dart';
import 'settings_screen.dart';

class FootballScreen extends StatefulWidget {
  final FootballMatch match;
  final VoidCallback onChanged;
  const FootballScreen({super.key, required this.match, required this.onChanged});
  @override
  State<FootballScreen> createState() => _FootballScreenState();
}

class _FootballScreenState extends State<FootballScreen> {
  FootballMatch get m => widget.match;
  Timer? _timer;
  final _fx = GlobalKey<EventOverlayState>();
  bool running = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (m.finished) return;
    if (running) {
      _timer?.cancel();
    } else {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => m.seconds++);
        if (m.seconds % 15 == 0) widget.onChanged();
      });
    }
    setState(() => running = !running);
    widget.onChanged();
  }

  void _nextPeriod() {
    _timer?.cancel();
    running = false;
    setState(() {
      if (m.period < 4) {
        m.period++;
        m.seconds = const [0, 0, 45, 90, 105][m.period] * 60;
      } else {
        m.finished = true;
      }
    });
    widget.onChanged();
  }

  void _finish() {
    _timer?.cancel();
    running = false;
    setState(() => m.finished = true);
    widget.onChanged();
  }

  Future<void> _addEvent(String type, int team) async {
    final c = TextEditingController();
    final label = {'goal': 'Goal', 'owngoal': 'Own goal', 'yellow': 'Yellow card', 'red': 'Red card', 'sub': 'Substitution'}[type]!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$label – ${team == 0 ? m.teamA : m.teamB}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: c,
              autofocus: true,
              decoration: InputDecoration(labelText: type == 'sub' ? 'Player in / out' : 'Player name / number'),
            ),
            if ((team == 0 ? m.playersA : m.playersB).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Builder(
                  builder: (ctx) => Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final p in (team == 0 ? m.playersA : m.playersB))
                      ActionChip(
                        label: Text(p),
                        onPressed: () {
                          if (type == 'sub') {
                            c.text = c.text.isEmpty ? p : '${c.text} / $p';
                          } else {
                            c.text = p;
                            Navigator.pop(ctx, true);
                          }
                        },
                      ),
                  ]),
                ),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => m.events.add(FootballEvent(type, team, c.text.trim(), m.minute)));
    widget.onChanged();
    if (type == 'goal' || type == 'owngoal') _fx.currentState?.show([EventKind.goal]);
    if (type == 'yellow') _fx.currentState?.show([EventKind.yellow]);
    if (type == 'red') _fx.currentState?.show([EventKind.red]);
  }

  String _icon(String t) =>
      const {'goal': '⚽', 'owngoal': '⚽ (OG)', 'yellow': '🟨', 'red': '🟥', 'sub': '🔁'}[t]!;

  Widget _teamPanel(int team) {
    final name = team == 0 ? m.teamA : m.teamB;
    return Expanded(
      child: Column(children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text('🟨 ${m.count('yellow', team)}  🟥 ${m.count('red', team)}'),
        const SizedBox(height: 6),
        Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
          for (final t in ['goal', 'owngoal', 'yellow', 'red', 'sub'])
            ActionChip(
              label: Text(_icon(t)),
              onPressed: m.finished ? null : () => _addEvent(t, team),
            ),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mm = (m.seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (m.seconds % 60).toString().padLeft(2, '0');
    return Scaffold(
      appBar: AppBar(
        title: Text('${m.teamA} vs ${m.teamB}'),
        actions: displayActions(context),
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
                  Text(m.finished ? 'Full time' : m.periodLabel),
                  Text('$mm:$ss', style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    Flexible(child: Text(m.teamA, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18))),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('${m.score(0)} - ${m.score(1)}',
                          style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
                    ),
                    Flexible(child: Text(m.teamB, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18))),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: m.finished ? null : _toggle,
                  icon: Icon(running ? Icons.pause : Icons.play_arrow),
                  label: Text(running ? 'Pause' : 'Start / Resume'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: m.finished ? null : _nextPeriod,
                  child: Text(m.period < 4 ? 'Next period' : 'End match'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: m.finished ? null : _finish, child: const Text('Full time')),
            ]),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [_teamPanel(0), _teamPanel(1)]),
            const Divider(height: 32),
            const Text('Timeline', style: TextStyle(fontWeight: FontWeight.bold)),
            for (int i = m.events.length - 1; i >= 0; i--)
              ListTile(
                dense: true,
                leading: Text("${m.events[i].minute}'"),
                title: Text('${_icon(m.events[i].type)} ${m.events[i].player}'),
                subtitle: Text(m.events[i].team == 0 ? m.teamA : m.teamB),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    setState(() => m.events.removeAt(i));
                    widget.onChanged();
                  },
                ),
              ),
          ]),
        ),
      )),
    );
  }
}
