import 'package:flutter/material.dart';
import 'app_state.dart';
import 'models.dart';
import 'storage.dart';
import 'cricket_screen.dart';
import 'football_screen.dart';
import 'settings_screen.dart';
import 'teams_screen.dart';
import 'excel_import.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.I.load();
  runApp(const ScorecardApp());
}

ThemeData _theme(Brightness b, AppState s) {
  final base = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: Color(s.accent),
    brightness: b,
  );
  final c = s.textColor == null ? null : Color(s.textColor!);
  final tt = base.textTheme.apply(
    bodyColor: c,
    displayColor: c,
    fontWeightDelta: s.bold ? 3 : 0,
  );
  return base.copyWith(textTheme: tt);
}

class ScorecardApp extends StatelessWidget {
  const ScorecardApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final s = AppState.I;
        return MaterialApp(
          title: 'Scorecard',
          debugShowCheckedModeBanner: false,
          theme: _theme(Brightness.light, s),
          darkTheme: _theme(Brightness.dark, s),
          themeMode: s.mode,
          builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(s.fontScale)),
            child: child!,
          ),
          home: const HomeScreen(),
        );
      },
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

  Widget _teamField(TextEditingController c, String label) {
    final teams = AppState.I.roster.keys.toList();
    if (teams.isEmpty) {
      return TextField(controller: c, decoration: InputDecoration(labelText: label));
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DropdownMenu<String>(
        controller: c,
        label: Text(label),
        width: 280,
        enableFilter: true,
        requestFocusOnTap: true,
        dropdownMenuEntries: [for (final t in teams) DropdownMenuEntry(value: t, label: t)],
      ),
    );
  }

  Future<void> _newMatch(String sport) async {
    final teams = AppState.I.roster.keys.toList();
    final a = TextEditingController(text: teams.isNotEmpty ? teams[0] : 'Team A');
    final b = TextEditingController(text: teams.length > 1 ? teams[1] : 'Team B');
    final ov = TextEditingController(text: '20');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(sport == 'cricket' ? 'New Cricket Match' : 'New Football Match'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _teamField(a, 'Team A'),
            _teamField(b, 'Team B'),
            if (sport == 'cricket')
              TextField(
                controller: ov,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Overs per innings'),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Start')),
        ],
      ),
    );
    if (ok != true) return;
    final na = a.text.trim().isEmpty ? 'Team A' : a.text.trim();
    final nb = b.text.trim().isEmpty ? 'Team B' : b.text.trim();
    final pa = List<String>.from(AppState.I.roster[na] ?? const []);
    final pb = List<String>.from(AppState.I.roster[nb] ?? const []);
    final SportMatch m = sport == 'cricket'
        ? CricketMatch(
            id: SportMatch.newId(),
            teamA: na,
            teamB: nb,
            playersA: pa,
            playersB: pb,
            overs: (int.tryParse(ov.text) ?? 20).clamp(1, 100))
        : FootballMatch(
            id: SportMatch.newId(), teamA: na, teamB: nb, playersA: pa, playersB: pb);
    matches.insert(0, m);
    _persist();
    _open(m);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scorecard'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Teams & players',
            icon: const Icon(Icons.groups),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const TeamsScreen())),
          ),
          ...displayActions(context),
        ],
      ),
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
            ListenableBuilder(
              listenable: AppState.I,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton.tonalIcon(
                  onPressed: () => importRosterFlow(context),
                  icon: const Icon(Icons.upload_file),
                  label: Text(AppState.I.roster.isEmpty
                      ? 'Import teams & players (Excel)'
                      : 'Import Excel  •  ${AppState.I.roster.length} teams loaded'),
                ),
              ),
            ),
            const SizedBox(height: 12),
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
                                title: Text(m.summary, maxLines: 3, overflow: TextOverflow.ellipsis),
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
