import 'package:flutter/material.dart';
import 'app_state.dart';

/// Quick text-size (A-/A+) and display-settings buttons for any AppBar.
List<Widget> displayActions(BuildContext context) => [
      IconButton(
        tooltip: 'Smaller text',
        icon: const Icon(Icons.text_decrease),
        onPressed: () => AppState.I.setFontScale(AppState.I.fontScale - 0.1),
      ),
      IconButton(
        tooltip: 'Bigger text',
        icon: const Icon(Icons.text_increase),
        onPressed: () => AppState.I.setFontScale(AppState.I.fontScale + 0.1),
      ),
      IconButton(
        tooltip: 'Display settings',
        icon: const Icon(Icons.palette),
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
      ),
    ];

const _accents = [
  0xFF0B6E4F, 0xFF1565C0, 0xFFC62828, 0xFFEF6C00,
  0xFF6A1B9A, 0xFF00838F, 0xFFAD1457, 0xFF212121,
];
const _textColors = [
  0xFFFFFFFF, 0xFFFFEB3B, 0xFF00E5FF, 0xFF69F0AE,
  0xFFFF9100, 0xFF000000, 0xFF0D47A1, 0xFFB71C1C,
];

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Widget _swatch(int color, bool selected, VoidCallback onTap) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Color(color),
            shape: BoxShape.circle,
            border: Border.all(color: selected ? Colors.amber : Colors.grey, width: selected ? 4 : 1),
          ),
          child: selected
              ? Icon(Icons.check, color: Color(color).computeLuminance() > 0.5 ? Colors.black : Colors.white)
              : null,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final s = AppState.I;
        return Scaffold(
          appBar: AppBar(title: const Text('Display settings (TV)')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(children: [
                      const Text('Preview'),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('INDIA 185/4',
                            style: Theme.of(context).textTheme.displaySmall),
                      ),
                      const Text('Overs 17.2 / 20  •  RR 10.67'),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Text size: ${(s.fontScale * 100).round()}%'),
                Slider(
                  value: s.fontScale,
                  min: 0.8,
                  max: 2.5,
                  divisions: 17,
                  label: '${(s.fontScale * 100).round()}%',
                  onChanged: s.setFontScale,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bold text'),
                  value: s.bold,
                  onChanged: s.setBold,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show Six / Four / Out animations'),
                  value: s.animations,
                  onChanged: s.setAnimations,
                ),
                const SizedBox(height: 8),
                const Text('Background'),
                const SizedBox(height: 6),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('System')),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ],
                  selected: {s.mode},
                  onSelectionChanged: (v) => s.setMode(v.first),
                ),
                const SizedBox(height: 16),
                const Text('Accent / theme color'),
                const SizedBox(height: 6),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final c in _accents) _swatch(c, s.accent == c, () => s.setAccent(c)),
                ]),
                const SizedBox(height: 16),
                const Text('Text color (pick one that contrasts with the background)'),
                const SizedBox(height: 6),
                Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  ChoiceChip(
                    label: const Text('Auto'),
                    selected: s.textColor == null,
                    onSelected: (_) => s.setTextColor(null),
                  ),
                  for (final c in _textColors)
                    _swatch(c, s.textColor == c, () => s.setTextColor(c)),
                ]),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: s.resetDisplay,
                  icon: const Icon(Icons.restore),
                  label: const Text('Reset to defaults'),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
