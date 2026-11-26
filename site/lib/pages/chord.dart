import 'package:chord_tui/chord_tui.dart';

import '../menu.dart';
import '../router.dart';
import '../screens.dart';

/// chord: what it is, and the menu of its recorded screens.
class ChordPage extends StatelessWidget {
  /// The page, listing [recordings] and opening one through [open].
  const ChordPage(this.recordings, this.open, {super.key});

  /// The recorded screens, by name.
  final List<String> recordings;

  /// Opens a route.
  final void Function(SiteRoute route) open;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2, top: 1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('One terminal for every coding agent.'),
        Text(
          'Claude Code, Codex, Gemini CLI and more, side by side in one '
          'keyboard-driven window.',
          style: Theme.of(context).dim,
        ),
        Text(''),
        if (recordings.isEmpty)
          Text('No screens were recorded.', style: Theme.of(context).dim)
        else
          SiteMenu([
            for (final name in orderedScreens(recordings))
              SiteMenuItem(
                name,
                () => open(RecordingRoute(name)),
                description: screenCaptions[name] ?? '',
              ),
          ]),
      ],
    ),
  );
}
