import 'package:chord_tui/chord_tui.dart';

import '../gallery.dart';
import '../giant.dart';
import '../grid.dart';
import '../page.dart';
import '../palette.dart';
import '../router.dart';
import '../site.dart' show narrowWidth;

/// The gallery, in C: `03 / THE GALLERY`, the giant word and the lede, then
/// the examples as numbered cells, three to a row from 120 columns, two
/// from 60, one on a phone. The arrows move the selection, Enter runs it, a
/// digit or a tap runs that cell.
class GalleryPage extends StatefulWidget {
  /// [gallery]'s cells, running an example through [open].
  const GalleryPage(this.gallery, this.open, {super.key});

  /// The examples.
  final Gallery gallery;

  /// Opens a route.
  final void Function(SiteRoute route) open;

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

/// Columns between cells.
const cellGap = 6;

class _GalleryPageState extends State<GalleryPage> {
  final _scroll = ScrollController();
  var _selected = 0;
  var _columns = 3;

  // The list items before the first row of cells: the header's.
  static const _headerItems = 7;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

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
    // Even a step that stays put brings its cell back into sight.
    _reveal();
  }

  // Each row of cells is an item, then its gap: keep the selected row whole
  // in sight.
  void _reveal() {
    if (!mounted) return;
    revealItem(_scroll, _headerItems + 2 * (_selected ~/ _columns));
  }

  // The columns the last layout had: a change moves the selected cell's
  // row, which is brought back into sight once the new layout is done.
  var _laidColumns = 0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // One cell below 60 columns, two below 120, three from there.
      _columns = constraints.maxWidth < narrowWidth
          ? 1
          : constraints.maxWidth < 120
          ? 2
          : 3;
      if (_columns != _laidColumns) {
        if (_laidColumns != 0) context.owner.afterLayout(_reveal);
        _laidColumns = _columns;
      }
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
        measure: posterMeasure,
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
          Text(''),
          const Kicker(3, 'THE GALLERY'),
          Text(''),
          const GiantWord('GALLERY'),
          Text(''),
          const Paragraph(
            "Nine of chord_tui's examples, compiled to WebAssembly with this "
            'page. Pick one with the arrows or its number; Enter runs it, Esc '
            'comes back.',
          ),
          Text(''),
          for (final row in rows) ...[
            LayoutBuilder(
              builder: (context, c) {
                // Leftover columns go one each to the first cells, so a row
                // ends at the margin.
                final room = c.maxWidth - cellGap * (_columns - 1);
                return Row(
                  spacing: cellGap,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (j, i) in row.indexed)
                      _Cell(
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
            const SizedBox(height: 2),
          ],
        ],
      );
    },
  );
}

/// One example's cell: an orange numeral, the caps name over a rule, the
/// still preview on raised, and what it shows.
class _Cell extends StatelessWidget {
  const _Cell({
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
    final orange = theme.accent.merge(Style.bold);
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (event.button == MouseButton.primary) onTap();
      },
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DisplayText(
              number.toString().padLeft(2, '0'),
              size: DisplaySize.numeral,
              style: theme.accent,
            ),
            Text(''),
            Row(
              children: [
                Text(
                  entry.title.toUpperCase(),
                  // Selected: ink on orange.
                  style: selected
                      ? theme.accent.merge(
                          const Style(bold: true, inverse: true),
                        )
                      : theme.text.merge(Style.bold),
                  softWrap: false,
                ),
                const Spacer(),
                if (selected) Text('⏎ RUN', style: orange, softWrap: false),
              ],
            ),
            Text(
              '─' * width,
              style: selected ? theme.accent : theme.border,
              softWrap: false,
            ),
            Box(
              background: raised,
              width: width,
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
