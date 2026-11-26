import 'package:chord_tui/chord_tui.dart';

import '../article.dart';
import '../gallery.dart';
import '../live_plate.dart';
import '../site.dart' show narrowWidth, panelOnly;
import '../sources.g.dart';
import 'chord_tui.dart' show articleNames;
import 'framework_text.dart';

/// The width of an example page's key column.
const keyColumn = 18;

/// One gallery example on its page: its name, the lede, the example live
/// in a plate, its keys and its source.
class ExamplePage extends StatefulWidget {
  /// [entry], page [page] of [gallery]'s.
  const ExamplePage({
    super.key,
    required this.gallery,
    required this.entry,
    required this.openPage,
    required this.openUrl,
    required this.home,
  });

  /// The examples.
  final Gallery gallery;

  /// The example.
  final GalleryEntry entry;

  /// Opens chord_tui's page [page]: 0 the overview, then the examples.
  final void Function(int page) openPage;

  /// Opens a page outside the site.
  final void Function(String url) openUrl;

  /// Goes home.
  final void Function() home;

  @override
  State<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  final _live = LivePlateController();

  static const _sourceId = '${panelOnly}example:source';

  @override
  void dispose() {
    _live.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = widget.entry;
    final name = entry.name;
    final title = entry.title.toUpperCase();
    final page = widget.gallery.entries.indexOf(entry) + 1;
    final leave = entry.ownsEscape ? 'ctrl+q' : 'esc';
    return ArticlePage(
      pages: (names: articleNames(widget.gallery), open: widget.openPage),
      page: page,
      bindings: [
        Binding('tab', 'enter example', _live.enter, id: 'article:enter'),
        Binding(
          's',
          'source',
          () => widget.openUrl(exampleSourceUrl(name)),
          id: _sourceId,
        ),
      ],
      heading: [
        Text('02 / FRAMEWORK / GALLERY', style: theme.dim, softWrap: false),
        Text(''),
        Text(title, style: theme.text.merge(Style.bold), softWrap: false),
        Text('━' * title.length, style: theme.accent, softWrap: false),
        Text(''),
        Text(exampleLedes[name] ?? entry.description),
      ],
      sections: [
        (
          head: 'The example',
          children: [
            LayoutBuilder(
              builder: (context, c) => LivePlate(
                controller: _live,
                figure: 1,
                title: 'example/$name.dart',
                rows: c.maxWidth < narrowWidth - 4 ? 20 : 24,
                ownsEscape: entry.ownsEscape,
                home: widget.home,
                child: entry.build,
              ),
            ),
          ],
        ),
        (
          head: 'Keys',
          children: [
            _key(theme, 'tab', 'enter the example'),
            _key(theme, leave, 'leave it'),
            for (final row in exampleKeys[name] ?? const <KeyRow>[])
              _key(theme, row.keys.join(' '), row.words),
          ],
        ),
        (
          head: 'Source',
          children: [
            CodeBlock(
              label: 'example/$name.dart',
              source: exampleSources[name] ?? '',
            ),
            Text(''),
            Link(
              'example/$name.dart on GitHub',
              action: _sourceId,
              external: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _key(ThemeData theme, String keys, String words) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: keyColumn,
        child: Text(keys, style: theme.text.merge(Style.bold)),
      ),
      Expanded(child: Text(words, style: theme.dim)),
    ],
  );
}
