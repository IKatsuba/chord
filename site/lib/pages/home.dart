import 'package:chord_tui/chord_tui.dart';

import '../menu.dart';
import '../router.dart';

/// The home page: what the site is, and the menu of its parts.
class HomePage extends StatelessWidget {
  /// Home, opening a part through [open].
  const HomePage(this.open, {super.key});

  /// Opens a route.
  final void Function(SiteRoute route) open;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 100;
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.only(left: 2, top: 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // One child whatever the width, so the menu after it keeps its
            // place, and its selection, across a resize.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: wide
                  ? [
                      Text(
                        'A terminal window for coding agents, and the '
                        'Flutter-shaped Dart framework it is built on.',
                      ),
                      Text(
                        'This page is that framework, compiled to WebAssembly.',
                      ),
                    ]
                  : [
                      Text(
                        'A terminal window for coding agents, and the '
                        'framework it is built on.',
                      ),
                    ],
            ),
            Text(''),
            SiteMenu([
              SiteMenuItem(
                'chord',
                () => open(const ChordRoute()),
                description: wide
                    ? 'the app: sessions, agents, teams, permissions, plans'
                    : 'the app',
              ),
              SiteMenuItem(
                'chord_tui',
                () => open(const ChordTuiRoute()),
                description: wide
                    ? 'the framework: widgets, layout, text, keys, the tester'
                    : 'the framework',
              ),
              SiteMenuItem(
                'Gallery',
                () => open(const GalleryRoute()),
                description: wide
                    ? "the framework's examples, running here"
                    : 'examples, running here',
              ),
              SiteMenuItem(
                'Install',
                () => open(const InstallRoute()),
                description: wide
                    ? 'Homebrew, npm, from source'
                    : 'Homebrew, npm, source',
              ),
            ]),
            if (wide) ...[
              Text(''),
              Box(
                title: 'Try it',
                titleStyle: theme.dim,
                padding: const EdgeInsets.symmetric(horizontal: 1),
                width: constraints.maxWidth - 4,
                child: Text(
                  'Every action has a key. Press ? for all of them, Esc to go '
                  'up a level.',
                  style: theme.text,
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}
