import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const DisplayTextExample());

/// Display type at each size, a word with a green stop at the size that
/// fits the window, and the glyph set; ctrl+q quits.
class DisplayTextExample extends StatelessWidget {
  /// The example.
  const DisplayTextExample({super.key});

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [Binding('ctrl+q', 'Quit', () => exitApp(context))],
    child: LayoutBuilder(
      builder: (context, constraints) {
        final accent = Style(fg: RgbColor.hex('#47e7a5'));
        final word =
            DisplayText.measure('CHORD.', DisplaySize.huge).width <=
                constraints.maxWidth
            ? DisplaySize.huge
            : DisplaySize.large;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DisplayText.rich(
              TextSpan('CHORD', children: [TextSpan('.', style: accent)]),
              size: word,
            ),
            Text(''),
            DisplayText('01 02 03', size: DisplaySize.numeral, style: accent),
            Text(''),
            DisplayText("ABCDEFGHIJKLMNOPQRSTUVWXYZ", size: DisplaySize.half),
            DisplayText(".,:!?-_/'+&# 0123456789", size: DisplaySize.half),
            const Spacer(),
            const KeyHelp(),
          ],
        );
      },
    ),
  );
}
