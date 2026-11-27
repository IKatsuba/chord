import 'package:chord_tui/chord_tui.dart';

/// The lines and size [word] (with its full stop) is drawn at in [width]
/// columns: whole at huge where it fits, else at large, whole or split into
/// halves with the first the longer (`GALL` / `ERY.`), and where neither
/// fits at large, the same at half. The margins stay; the word shrinks.
({DisplaySize size, List<String> lines}) giantLayout(String word, int width) {
  final full = '$word.';
  final half = (full.length + 1) ~/ 2;
  final split = [full.substring(0, half), full.substring(half)];
  bool fits(List<String> lines, DisplaySize size) =>
      lines.every((l) => DisplayText.measure(l, size).width <= width);
  final candidates = [
    (size: DisplaySize.huge, lines: [full]),
    (size: DisplaySize.large, lines: [full]),
    (size: DisplaySize.large, lines: split),
    (size: DisplaySize.half, lines: [full]),
  ];
  for (final c in candidates) {
    if (fits(c.lines, c.size)) return c;
  }
  return (size: DisplaySize.half, lines: split);
}

/// A poster page's giant word, in cream with a green full stop, at the
/// size its room allows.
class GiantWord extends StatelessWidget {
  /// [word], without its stop.
  const GiantWord(this.word, {super.key});

  /// The word, in caps.
  final String word;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final layout = giantLayout(word, constraints.maxWidth);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, line) in layout.lines.indexed) ...[
            if (i > 0) Text(''),
            DisplayText.rich(
              TextSpan(
                '',
                children: [
                  TextSpan(
                    line.endsWith('.')
                        ? line.substring(0, line.length - 1)
                        : line,
                    style: theme.text,
                  ),
                  if (line.endsWith('.')) TextSpan('.', style: theme.accent),
                ],
              ),
              size: layout.size,
            ),
          ],
        ],
      );
    },
  );
}

/// A poster page's kicker over its giant word: `03 / THE GALLERY`, in
/// green bold caps.
class Kicker extends StatelessWidget {
  /// The kicker for section [number] (1–4), titled [title].
  const Kicker(this.number, this.title, {super.key});

  /// The section's number.
  final int number;

  /// The title after the slash, in caps.
  final String title;

  @override
  Widget build(BuildContext context) => Text(
    '0$number / $title',
    style: Theme.of(context).accent.merge(Style.bold),
    softWrap: false,
  );
}
