import 'package:chord_site/pages/example_frame.dart';
import 'package:chord_site/palette.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// The column and row where [text] starts on the screen.
(int, int) find(WidgetTester t, String text) {
  for (final (y, line) in t.screen.lines.indexed) {
    final x = line.indexOf(text);
    if (x >= 0) return (x, y);
  }
  throw StateError('"$text" is not on the screen:\n${t.screen.text}');
}

void main() {
  final theme = siteTheme();
  for (final size in const [Size(120, 40), Size(80, 24), Size(54, 56)]) {
    testWidgets('an example frame\'s title is muted at $size', (t) async {
      await t.pumpWidget(
        Theme(
          data: theme,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: ExampleFrame(
              title: 'example/demo.dart',
              caption: 'caption',
              home: () {},
              child: (_) => Text('an example as wide as its frame'),
            ),
          ),
        ),
        size: size,
      );
      final (x, y) = find(t, 'example/demo.dart');
      expect(t.screen.styleAt(x, y), theme.dim);
    });
  }
}
