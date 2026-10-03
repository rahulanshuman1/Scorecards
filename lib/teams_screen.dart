import 'package:flutter/material.dart';
import 'app_state.dart';
import 'excel_import.dart';
import 'settings_screen.dart';

class TeamsScreen extends StatelessWidget {
  const TeamsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final teams = AppState.I.roster;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Teams & Players'),
            actions: [
              ...displayActions(context),
              if (teams.isNotEmpty)
                IconButton(
                  tooltip: 'Delete all teams',
                  icon: const Icon(Icons.delete_sweep),
                  onPressed: () => AppState.I.clearRoster(),
                ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                FilledButton.icon(
                  onPressed: () => importRosterFlow(context),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import from Excel (.xlsx) or CSV'),
                ),
                const SizedBox(height: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Excel format: first row = headers "Team" and "Player". '
                      'One row per player. Leave the Team cell blank to repeat the team above.\n'
                      'Or: one sheet per team (sheet name = team name, players in column A).\n'
                      'Importing again updates teams with the same name.',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (teams.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No teams imported yet.')),
                  ),
                for (final e in teams.entries)
                  Card(
                    child: ExpansionTile(
                      title: Text('${e.key}  (${e.value.length} players)'),
                      children: [
                        for (int i = 0; i < e.value.length; i++)
                          ListTile(dense: true, leading: Text('${i + 1}'), title: Text(e.value[i])),
                        ListTile(
                          leading: const Icon(Icons.delete_outline),
                          title: const Text('Delete team'),
                          onTap: () => AppState.I.removeTeam(e.key),
                        ),
                      ],
                    ),
                  ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
