import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const DisplayTextExample());

/// Display type at each size, a word with an orange stop at the size that
/// fits the window, and the glyph set; ctrl+q quits.
class DisplayTextExample extends StatelessWidget {
  /// The example.
  const DisplayTextExample({super.key});

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [Binding('ctrl+q', 'Quit', () => exitApp(context))],
    child: LayoutBuilder(
      builder: (context, constraints) {
        final orange = Style(fg: RgbColor.hex('#ff5a1f'));
        final word =
            DisplayText.measure('CHORD.', DisplaySize.huge).width <=
                constraints.maxWidth
            ? DisplaySize.huge
            : DisplaySize.large;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DisplayText.rich(
              TextSpan('CHORD', children: [TextSpan('.', style: orange)]),
              size: word,
            ),
            Text(''),
            DisplayText('01 02 03', size: DisplaySize.numeral, style: orange),
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
