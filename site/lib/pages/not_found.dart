import 'package:chord_tui/chord_tui.dart';

import '../chord_art.dart';
import '../page.dart';

/// What a path no page has shows: chord's art, "404 · page not found", the
/// path, and a button home on Enter (Esc too, the shell's). It does not go
/// home by itself, so a mistyped link stays readable.
class NotFoundPage extends StatelessWidget {
  /// Nothing at [path]; [home] goes home.
  const NotFoundPage(this.path, this.home, {super.key});

  /// The path that was asked for.
  final String path;

  /// Goes home.
  final void Function() home;

  static const _homeId = 'not-found:home';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SitePage(
      bindings: [Binding('enter', 'home', home, id: _homeId)],
      sections: [
        Text(''),
        // The art by the room the measure leaves it.
        LayoutBuilder(
          builder: (context, c) =>
              Center(child: ChordArt(artFormFor(c.maxWidth))),
        ),
        Text(''),
        Center(
          child: Text(
            '404 · page not found',
            style: theme.text.merge(Style.bold),
          ),
        ),
        Center(child: Text(path, softWrap: false)),
        Text(''),
        Center(
          // The page holds the focus; Enter is the page's binding.
          child: FilledButton(
            action: _homeId,
            canRequestFocus: false,
            child: Text('Home'),
          ),
        ),
      ],
    );
  }
}
