import 'package:chord_tui/chord_tui.dart';

import '../article.dart';
import '../gallery.dart';
import '../giant.dart';
import '../live_plate.dart';
import '../site.dart' show narrowWidth, panelOnly;
import '../sources.g.dart';
import 'framework_text.dart';

/// The pages chord_tui's index lists, in caps: Overview, then [gallery]'s.
List<String> articleNames(Gallery gallery) => [
  'OVERVIEW',
  for (final e in gallery.entries) e.title.toUpperCase(),
];

/// chord_tui's overview: what it is, README's example live, testing, and
/// where next.
class ChordTuiPage extends StatefulWidget {
  /// The overview, with [gallery]'s README example live.
  const ChordTuiPage({
    super.key,
    required this.gallery,
    required this.openPage,
    required this.openGallery,
    required this.openUrl,
    required this.home,
  });

  /// Opens the gallery.
  final void Function() openGallery;

  /// The examples, README's among them.
  final Gallery gallery;

  /// Opens chord_tui's page [page]: 0 this one, then the examples.
  final void Function(int page) openPage;

  /// Opens a page outside the site.
  final void Function(String url) openUrl;

  /// Goes home.
  final void Function() home;

  @override
  State<ChordTuiPage> createState() => _ChordTuiPageState();
}

class _ChordTuiPageState extends State<ChordTuiPage> {
  final _live = LivePlateController();

  @override
  void dispose() {
    _live.dispose();
    super.dispose();
  }

  static const _docsId = '${panelOnly}overview:docs';
  static const _sourceId = '${panelOnly}overview:source';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bold = theme.text.merge(Style.bold);
    return ArticlePage(
      pages: (names: articleNames(widget.gallery), open: widget.openPage),
      page: 0,
      bindings: [
        Binding('tab', 'enter example', _live.enter, id: 'article:enter'),
        Binding('d', 'API docs', () => widget.openUrl(apiDocsUrl), id: _docsId),
        Binding(
          's',
          'source',
          () => widget.openUrl(frameworkSourceUrl),
          id: _sourceId,
        ),
      ],
      heading: [
        const GiantWord('TUI'),
        Text(''),
        Text(overviewLede, style: bold),
      ],
      sections: [
        (
          head: 'What it is',
          children: [
            for (final (i, p) in overviewWhat.indexed) ...[
              if (i > 0) Text(''),
              Text(p),
            ],
          ],
        ),
        (
          head: 'The example',
          children: [
            Text(overviewExample),
            Text(''),
            LivePlate(
              controller: _live,
              figure: 1,
              title: "README's example",
              rows: 8,
              home: widget.home,
              child: (_) => widget.gallery.readme(),
            ),
            Text(''),
            CodeBlock(
              label: 'example/main.dart',
              source: exampleSources['main']!,
            ),
          ],
        ),
        (
          head: 'Testing',
          children: [
            Text(overviewTesting),
            Text(''),
            const CodeBlock(
              label: 'test/dialog_test.dart',
              source: testingSource,
            ),
          ],
        ),
        (
          head: 'Where next',
          children: [
            LayoutBuilder(builder: (context, c) => _cards(theme, c.maxWidth)),
          ],
        ),
      ],
    );
  }

  /// The four ways on, two to a row (one on the phone), 4 apart.
  Widget _cards(ThemeData theme, int width) {
    final bold = theme.text.merge(Style.bold);
    final key = theme.accent.merge(Style.bold);
    // A tap does what the card's key does.
    Widget card(
      String title,
      String key_,
      String text, {
      Widget? body,
      void Function()? onTap,
    }) => Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: onTap == null
          ? null
          : (event) {
              if (event.button == MouseButton.primary) onTap();
            },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              title,
              style: bold,
              children: [if (key_.isNotEmpty) TextSpan('  $key_', style: key)],
            ),
            softWrap: false,
          ),
          LayoutBuilder(
            builder: (context, c) =>
                Text('─' * c.maxWidth, style: theme.border, softWrap: false),
          ),
          ?body,
          Text(text, style: theme.dim),
        ],
      ),
    );
    final cards = [
      card(
        'GALLERY →',
        '3',
        'Nine examples, running here.',
        onTap: widget.openGallery,
      ),
      card(
        'INSTALL',
        '',
        'Add it to a Dart package.',
        body: CopyHint(
          text: pubAddCommand,
          label: Text(pubAddCommand, style: theme.accent, softWrap: false),
        ),
      ),
      card(
        'API DOCS ↗',
        'd',
        "The framework's documentation on pub.dev.",
        onTap: () => widget.openUrl(apiDocsUrl),
      ),
      card(
        'SOURCE ↗',
        's',
        'packages/chord_tui on GitHub.',
        onTap: () => widget.openUrl(frameworkSourceUrl),
      ),
    ];
    final perRow = width < narrowWidth - 4 ? 1 : 2;
    const gap = 4;
    final cell = (width - gap * (perRow - 1)) ~/ perRow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var r = 0; r * perRow < cards.length; r++) ...[
          if (r > 0) ...[Text(''), Text('')],
          Row(
            spacing: gap,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var j = 0; j < perRow && r * perRow + j < cards.length; j++)
                SizedBox(width: cell, child: cards[r * perRow + j]),
            ],
          ),
        ],
      ],
    );
  }
}
