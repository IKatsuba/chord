import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  final orange = Style(fg: RgbColor.hex('#ff5a1f'));
  final cream = Style(fg: RgbColor.hex('#f2ead9'));

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('at $size', () {
      testWidgets('CHORD. at large is seven rows of full blocks, its size '
          'as measure says', (t) async {
        await t.pumpWidget(
          Align(
            alignment: Alignment.topLeft,
            child: DisplayText('CHORD.', size: DisplaySize.large),
          ),
          size: size,
        );
        final m = DisplayText.measure('CHORD.', DisplaySize.large);
        expect(m, (width: 6 * 12 - 2, height: 7));
        expect(t.screen.lines[0], startsWith('  ██████    ██      ██'));
        expect(t.screen.lines[6].length, lessThanOrEqualTo(m.width));
        expect(t.screen.lines[7], '');
      });

      testWidgets('rich runs keep their own colour over the style', (t) async {
        await t.pumpWidget(
          Align(
            alignment: Alignment.topLeft,
            child: DisplayText.rich(
              TextSpan('APP', children: [TextSpan('.', style: orange)]),
              size: DisplaySize.large,
              style: cream,
            ),
          ),
          size: size,
        );
        // A: column 2 of row 0 is on; the stop's pixels are in rows 5–6.
        expect(t.screen.styleAt(2, 0), cream);
        final stop = 3 * 12 + 2; // the full stop's first on column
        expect(t.screen.charAt(stop, 6), '█');
        expect(t.screen.styleAt(stop, 6), orange);
      });

      testWidgets('it does not wrap: a narrow room clips it', (t) async {
        await t.pumpWidget(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 30,
              child: DisplayText('INSTALL.', size: DisplaySize.large),
            ),
          ),
          size: size,
        );
        expect(t.screen.lines.take(7).every((l) => l.length <= 30), isTrue);
        expect(t.screen.lines[7], '');
      });

      testWidgets('align centres the block in its room', (t) async {
        await t.pumpWidget(
          DisplayText('404', size: DisplaySize.huge, align: TextAlign.center),
          size: size,
        );
        final width = DisplayText.measure('404', DisplaySize.huge).width;
        final left = (size.width - width) ~/ 2;
        final first = t.screen.lines.indexWhere((l) => l.trim().isNotEmpty);
        final line = t.screen.lines[first];
        expect(
          line.length - line.trimLeft().length,
          greaterThanOrEqualTo(left),
        );
        expect(t.screen.lines.where((l) => l.trim().isNotEmpty), hasLength(14));
      });
    });
  }
}
