import 'package:chord_tui/chord_tui.dart';

import '../gallery.dart';
import '../grid.dart';
import '../page.dart';
import '../palette.dart';
import '../router.dart';
import '../site.dart' show narrowWidth;

/// The gallery: a header, then the examples as cards, three to a row from
/// 120 columns, two from 60, one on a phone. The arrows move the selection, Enter runs it, a digit or a
/// tap runs that card.
class GalleryPage extends StatefulWidget {
  /// [gallery]'s cards, running an example through [open].
  const GalleryPage(this.gallery, this.open, {super.key});

  /// The examples.
  final Gallery gallery;

  /// Opens a route.
  final void Function(SiteRoute route) open;

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  final _scroll = ScrollController();
  var _selected = 0;
  var _columns = 3;

  // The list items before the first row of cards: the header's rows.
  static const _headerItems = 7;

  List<GalleryEntry> get _entries => widget.gallery.entries;

  void _run(int i) => widget.open(ExampleRoute(_entries[i].name));

  void _move(GridStep step) {
    final to = gridMove(
      _selected,
      count: _entries.length,
      columns: _columns,
      step: step,
    );
    if (to != _selected) setState(() => _selected = to);
    // Even a step that stays put brings its card back into sight.
    _reveal(fromAbove: step != GridStep.up);
  }

  // Each row of cards is an item, then a blank one: keep the selected row in
  // sight, from the row before it when coming down onto it.
  void _reveal({bool fromAbove = true}) {
    if (!mounted) return;
    final item = _headerItems + 2 * (_selected ~/ _columns);
    if (item < _scroll.firstVisible || item >= _scroll.lastVisible) {
      _scroll.jumpToAnchor(ListAnchor(fromAbove ? item - 1 : item, 0));
    }
  }

  // The columns the last layout had: a change moves the selected card's
  // row, which is brought back into sight once the new layout is done.
  var _laidColumns = 0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // One card below 60 columns, two below 120, three from there.
      _columns = constraints.maxWidth < narrowWidth
          ? 1
          : constraints.maxWidth < 120
          ? 2
          : 3;
      if (_columns != _laidColumns) {
        if (_laidColumns != 0) context.owner.afterLayout(_reveal);
        _laidColumns = _columns;
      }
      final theme = Theme.of(context);
      final entries = _entries;
      final rows = [
        for (var r = 0; r * _columns < entries.length; r++)
          [
            for (
              var i = r * _columns;
              i < (r + 1) * _columns && i < entries.length;
              i++
            )
              i,
          ],
      ];
      return SitePage(
        measure: wideMeasure,
        controller: _scroll,
        bindings: [
          for (final (key, step) in const [
            ('left', GridStep.left),
            ('right', GridStep.right),
            ('up', GridStep.up),
            ('down', GridStep.down),
          ])
            Binding(key, 'move', () => _move(step), id: 'gallery:move'),
          Binding(
            'enter',
            'run',
            () => _run(_selected),
            enabled: entries.isNotEmpty,
          ),
          for (var n = 1; n <= entries.length && n <= 9; n++)
            Binding('$n', 'open', () => _run(n - 1), id: 'gallery:open'),
        ],
        sections: [
          Text.rich(
            TextSpan(
              '',
              children: [
                TextSpan('Home', style: theme.dim),
                TextSpan(' › ', style: theme.dim),
                TextSpan('Gallery', style: theme.text),
              ],
            ),
            softWrap: false,
          ),
          Text(''),
          Text('GALLERY', style: theme.accent.merge(Style.bold)),
          Text(
            'The framework, running in your browser.',
            style: theme.text.merge(Style.bold),
          ),
          Text(''),
          Text(
            "Nine of chord_tui's examples, compiled to WebAssembly with this "
            'page. Pick one with the arrows or its number; Enter runs it, Esc '
            'comes back.',
            style: theme.dim,
          ),
          Text(''),
          for (final row in rows) ...[
            LayoutBuilder(
              builder: (context, c) {
                // The columns left over go one each to the first cards, so a
                // row ends at the measure's right edge, as the text does.
                final room = c.maxWidth - 2 * (_columns - 1);
                return Row(
                  spacing: 2,
                  children: [
                    for (final (j, i) in row.indexed)
                      _Card(
                        number: i + 1,
                        entry: entries[i],
                        selected: i == _selected,
                        width: room ~/ _columns + (j < room % _columns ? 1 : 0),
                        onTap: () => _run(i),
                      ),
                  ],
                );
              },
            ),
            Text(''),
          ],
        ],
      );
    },
  );
}

/// One example's card: number and name, a still preview, what it shows.
class _Card extends StatelessWidget {
  const _Card({
    required this.number,
    required this.entry,
    required this.selected,
    required this.width,
    required this.onTap,
  });

  final int number;
  final GalleryEntry entry;
  final bool selected;
  final int width;
  final void Function() onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raised =
        (theme.extension<SitePalette>() ?? const SitePalette()).raised;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (event.button == MouseButton.primary) onTap();
      },
      child: Box(
        border: Border.rounded.withStyle(
          selected ? theme.accent : theme.border,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('$number  ', style: theme.dim, softWrap: false),
                Text(
                  entry.title,
                  style: (selected ? theme.accent : theme.text).merge(
                    Style.bold,
                  ),
                  softWrap: false,
                ),
                const Spacer(),
                if (selected) Text('⏎ run', style: theme.accent),
              ],
            ),
            Text(''),
            Box(
              background: raised,
              // The card's whole inner width, so a row's strips line up.
              width: width - 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var r = 0; r < 4; r++)
                    _previewRow(
                      theme,
                      r < entry.preview.length ? entry.preview[r] : '',
                    ),
                ],
              ),
            ),
            Text(''),
            SizedBox(
              height: 2,
              child: Text(entry.blurb, style: theme.dim, maxLines: 2),
            ),
          ],
        ),
      ),
    );
  }

  /// One preview row, a column in from the raised edge: a `█` is a cursor
  /// cell, and a diff's `-` and `+` lines take the diff colours.
  Widget _previewRow(ThemeData theme, String row) {
    final diff = row.length > 4 && entry.name == 'diff'
        ? switch (row[4]) {
            '-' => theme.diff.removed,
            '+' => theme.diff.added,
            _ => null,
          }
        : null;
    final base = diff ?? theme.text;
    return Text.rich(
      TextSpan(
        ' ',
        children: [
          for (final (i, part) in row.split('█').indexed) ...[
            if (i > 0) TextSpan(' ', style: theme.cursor),
            TextSpan(part, style: base),
          ],
        ],
      ),
      softWrap: false,
    );
  }
}
