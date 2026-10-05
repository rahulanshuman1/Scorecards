import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'app_state.dart';
import 'excel_import.dart';
import 'settings_screen.dart';

Future<String?> _prompt(BuildContext context, String title, {String initial = ''}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      void submit(String v) {
        if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
      }

      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: submit,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => submit(c.text), child: const Text('Save')),
        ],
      );
    },
  );
}

Future<void> _pickPhoto(AppState s, String team, String player) async {
  final r = await FilePicker.platform.pickFiles(type: FileType.image);
  if (r == null || r.files.isEmpty) return;
  final p = r.files.single.path;
  if (p != null) await s.setPhoto(team, player, p);
}

Widget _avatar(String? path, int n) => CircleAvatar(
      radius: 20,
      backgroundImage: path != null ? FileImage(File(path)) : null,
      child: path == null ? Text('$n') : null,
    );

class TeamsScreen extends StatelessWidget {
  const TeamsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final s = AppState.I;
        final teams = s.roster;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Teams & Players'),
            actions: [
              ...displayActions(context),
              if (teams.isNotEmpty)
                IconButton(
                  tooltip: 'Delete all teams',
                  icon: const Icon(Icons.delete_sweep),
                  onPressed: () => s.clearRoster(),
                ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: () => importRosterFlow(context),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Import Excel / CSV'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => importPhotosByName(context),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Import photos (by file name)'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final n = await _prompt(context, 'New team name');
                      if (n != null) s.addTeam(n);
                    },
                    icon: const Icon(Icons.group_add),
                    label: const Text('Add team'),
                  ),
                ]),
                const SizedBox(height: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Excel format: first row = headers "Team" and "Player", one row per player. '
                      'Or one sheet per team (sheet name = team, players in column A).\n'
                      'Photos: place a picture over a player\'s row in the Excel file (Insert > Pictures > Place over cells) '
                      'and it is imported with the player. Or use "Import photos" and pick many images named like the player, e.g. "Rahul Sharma.jpg".\n'
                      'Tap a team to edit it. Tap a player\'s circle (or the camera icon) to set a photo, long-press the circle to remove it. '
                      'Photos appear on the 50 / 100 / 150 animation. Changes apply to matches you start next; '
                      'matches already created keep their old names.',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (teams.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No teams yet. Import a file or add a team.')),
                  ),
                for (final e in teams.entries)
                  Card(
                    child: ExpansionTile(
                      key: PageStorageKey('team_${e.key}'),
                      title: Text('${e.key}  (${e.value.length} players)'),
                      children: [
                        for (int i = 0; i < e.value.length; i++)
                          ListTile(
                            dense: true,
                            leading: InkWell(
                              onTap: () => _pickPhoto(s, e.key, e.value[i]),
                              onLongPress: () => s.removePhoto(e.key, e.value[i]),
                              customBorder: const CircleBorder(),
                              child: _avatar(s.photoFor(e.key, e.value[i]), i + 1),
                            ),
                            title: Text(e.value[i]),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                tooltip: 'Set photo',
                                icon: const Icon(Icons.add_a_photo),
                                onPressed: () => _pickPhoto(s, e.key, e.value[i]),
                              ),
                              IconButton(
                                tooltip: 'Edit name',
                                icon: const Icon(Icons.edit),
                                onPressed: () async {
                                  final n = await _prompt(context, 'Edit player', initial: e.value[i]);
                                  if (n != null) s.renamePlayer(e.key, i, n);
                                },
                              ),
                              IconButton(
                                tooltip: 'Remove player',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => s.removePlayer(e.key, i),
                              ),
                            ]),
                          ),
                        ListTile(
                          leading: const Icon(Icons.person_add),
                          title: const Text('Add player'),
                          onTap: () async {
                            final n = await _prompt(context, 'New player in ${e.key}');
                            if (n != null) s.addPlayer(e.key, n);
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.drive_file_rename_outline),
                          title: const Text('Rename team'),
                          onTap: () async {
                            final n = await _prompt(context, 'Rename team', initial: e.key);
                            if (n != null) s.renameTeam(e.key, n);
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.delete_outline),
                          title: const Text('Delete team'),
                          onTap: () => s.removeTeam(e.key),
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
