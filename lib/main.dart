import 'package:flutter/material.dart';
import 'models.dart';
import 'storage.dart';
import 'cricket_screen.dart';
import 'football_screen.dart';

void main() => runApp(const ScorecardApp());

class ScorecardApp extends StatelessWidget {
  const ScorecardApp({super.key});
  @override
  Widget build(BuildContext context) {
    ThemeData t(Brightness b) => ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF0B6E4F),
          brightness: b,
        );
    return MaterialApp(
      title: 'Scorecard',
      debugShowCheckedModeBanner: false,
      theme: t(Brightness.light),
      darkTheme: t(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<SportMatch> matches = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    Store.load().then((m) => setState(() {
          matches = m..sort((a, b) => b.date.compareTo(a.date));
          loading = false;
        }));
  }

  Future<void> _open(SportMatch m) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => m is CricketMatch
            ? CricketScreen(match: m, onChanged: _persist)
            : FootballScreen(match: m as FootballMatch, onChanged: _persist),
      ),
    );
    setState(() {});
  }

  void _persist() => Store.save(matches);

  Future<void> _newMatch(String sport) async {
    final a = TextEditingController(text: 'Team A');
    final b = TextEditingController(text: 'Team B');
    final ov = TextEditingController(text: '20');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(sport == 'cricket' ? 'New Cricket Match' : 'New Football Match'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: a, decoration: const InputDecoration(labelText: 'Team A')),
          TextField(controller: b, decoration: const InputDecoration(labelText: 'Team B')),
          if (sport == 'cricket')
            TextField(
              controller: ov,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Overs per innings'),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Start')),
        ],
      ),
    );
    if (ok != true) return;
    final na = a.text.trim().isEmpty ? 'Team A' : a.text.trim();
    final nb = b.text.trim().isEmpty ? 'Team B' : b.text.trim();
    final SportMatch m = sport == 'cricket'
        ? CricketMatch(
            id: SportMatch.newId(),
            teamA: na,
            teamB: nb,
            overs: (int.tryParse(ov.text) ?? 20).clamp(1, 100))
        : FootballMatch(id: SportMatch.newId(), teamA: na, teamB: nb);
    matches.insert(0, m);
    _persist();
    _open(m);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Scorecard'), centerTitle: false),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(child: _SportCard('Cricket', Icons.sports_cricket, cs.primaryContainer, () => _newMatch('cricket'))),
                const SizedBox(width: 12),
                Expanded(child: _SportCard('Football', Icons.sports_soccer, cs.tertiaryContainer, () => _newMatch('football'))),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(alignment: Alignment.centerLeft, child: Text('Match history', style: TextStyle(fontWeight: FontWeight.bold))),
            ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : matches.isEmpty
                      ? const Center(child: Text('No matches yet. Start one above.'))
                      : ListView.builder(
                          itemCount: matches.length,
                          itemBuilder: (_, i) {
                            final m = matches[i];
                            return Dismissible(
                              key: ValueKey(m.id),
                              background: Container(color: Colors.red),
                              onDismissed: (_) {
                                matches.removeAt(i);
                                _persist();
                                setState(() {});
                              },
                              child: ListTile(
                                leading: Icon(m.sport == 'cricket' ? Icons.sports_cricket : Icons.sports_soccer),
                                title: Text(m.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
                                subtitle: Text(m.date.toString().substring(0, 16)),
                                onTap: () => _open(m),
                              ),
                            );
                          },
                        ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _SportCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _SportCard(this.label, this.icon, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => Card(
        color: color,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(children: [
              Icon(icon, size: 44),
              const SizedBox(height: 8),
              Text('New $label', style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
      );
}
