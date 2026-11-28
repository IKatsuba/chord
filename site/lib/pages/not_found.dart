import 'package:chord_tui/chord_tui.dart';

import '../page.dart';

/// What a path no page has shows, in C: the giant `404` in green, `PAGE NOT
/// FOUND.`, the path, and a button home on Enter (Esc too, the shell's). It
/// does not go home by itself, so a mistyped link stays readable.
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
      measure: posterMeasure,
      bindings: [Binding('enter', 'home', home, id: _homeId)],
      sections: [
        Text(''),
        Text(''),
        LayoutBuilder(
          builder: (context, c) => DisplayText(
            '404',
            size:
                DisplayText.measure('404', DisplaySize.huge).width <= c.maxWidth
                ? DisplaySize.huge
                : DisplaySize.large,
            style: theme.accent,
          ),
        ),
        Text(''),
        Text('PAGE NOT FOUND.', style: theme.text.merge(Style.bold)),
        Text(path, softWrap: false),
        Text(''),
        Text(''),
        Row(
          children: [
            // The page holds the focus; Enter is the page's binding.
            FilledButton(
              action: _homeId,
              dense: true,
              canRequestFocus: false,
              child: Text('HOME'),
            ),
          ],
        ),
      ],
    );
  }
}
