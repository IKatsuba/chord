import 'package:chord_tui/chord_tui.dart';

import '../router.dart';
import '../site.dart' show siteKeys;
import 'example_frame.dart';

/// chord_tui: what it is, README's example running, and the way to the
/// gallery.
class ChordTuiPage extends StatelessWidget {
  /// The page with [readme] running, opening the gallery through [open].
  const ChordTuiPage(this.readme, this.open, {super.key});

  /// Builds README's example.
  final Widget Function() readme;

  /// Opens a route.
  final void Function(SiteRoute route) open;

  @override
  Widget build(BuildContext context) {
    void gallery() => open(const GalleryRoute());
    // No menu here: a menu would hold the focus, and README's example needs
    // its keys. Enter and a tap open the gallery from the page. The keys are
    // bound in the build, not the layout, so the site's help row, built
    // before the layout, has them from the first frame.
    return Actions(
      bindings: [
        Binding('enter', 'gallery', gallery, id: '${siteKeys}gallery'),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 100;
          final theme = Theme.of(context);
          return Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'The Flutter way, for the terminal: a Dart framework for '
                        'rich terminal interfaces.',
                      ),
                      if (wide)
                        Text(
                          'Widgets, state, layout in cells, rich text and keyboard '
                          'actions, with a headless tester. Written from scratch.',
                          style: Theme.of(context).dim,
                        ),
                      Text(''),
                      Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (_) => gallery(),
                        child: Text.rich(
                          TextSpan(
                            '',
                            children: [
                              TextSpan(
                                'enter ',
                                style: theme.text.merge(Style.bold),
                              ),
                              TextSpan('Gallery', style: theme.link),
                              TextSpan(
                                wide
                                    ? "    the framework's examples, running here"
                                    : '    examples, running here',
                                style: theme.dim,
                              ),
                            ],
                          ),
                          softWrap: false,
                        ),
                      ),
                      Text(''),
                    ],
                  ),
                ),
                Expanded(
                  child: ExampleFrame(
                    title: 'example/main.dart',
                    caption: "README's example: ctrl+o opens the fold",
                    home: () => open(const HomeRoute()),
                    child: (_) => readme(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
