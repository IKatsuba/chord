import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  final dark = ThemeData.dark();
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('a given titleStyle reaches the title cells at $size', (
      t,
    ) async {
      final style = Style(fg: RgbColor.hex('#8d919c'));
      await t.pumpWidget(
        Align(
          alignment: Alignment.topLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Box(title: 'Try it', titleStyle: style, width: 20),
              DecoratedBox(
                border: Border.rounded,
                title: 'frame',
                titleStyle: style,
                child: SizedBox(width: 18),
              ),
            ],
          ),
        ),
        size: size,
      );
      expect(t.screen.lines[0], startsWith('┌ Try it ─'));
      for (var x = 1; x <= 8; x++) {
        expect(t.screen.styleAt(x, 0), style, reason: 'column $x');
      }
      expect(t.screen.styleAt(9, 0), dark.border, reason: 'the line after');
      expect(t.screen.lines[2], startsWith('╭ frame ─'));
      expect(t.screen.styleAt(2, 2), style);
    });

    testWidgets('a null titleStyle keeps the bold border style at $size', (
      t,
    ) async {
      await t.pumpWidget(
        Align(
          alignment: Alignment.topLeft,
          child: Box(title: 'Try it', width: 20),
        ),
        size: size,
      );
      expect(t.screen.styleAt(2, 0), dark.border.merge(Style.bold));
    });
  }
}
