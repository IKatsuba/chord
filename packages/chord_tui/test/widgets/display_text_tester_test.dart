import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('CHD-638 tester: display text geometry', () {
    for (final size in DisplaySize.values) {
      testWidgets('empty $size reserves its measured rows', (t) async {
        await t.pumpWidget(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DisplayText('', size: size),
              Text('after'),
            ],
          ),
        );
        expect(
          t.screen.lines.indexOf('after'),
          DisplayText.measure('', size).height,
        );
      });
    }

    testWidgets(
      'zero one and narrow rooms recover without wrapping display rows',
      (t) async {
        await t.pumpWidget(
          DisplayText('I界🙂e\u0301\x1b[31m', size: DisplaySize.huge),
          size: Size.zero,
        );
        for (final size in [
          const Size(1, 1),
          const Size(2, 2),
          const Size(5, 3),
          const Size(80, 24),
          const Size(120, 40),
        ]) {
          await t.resize(size);
          expect(
            t.screen.lines.every((line) => cellWidth(line) <= size.width),
            isTrue,
          );
          expect(t.screen.lines.skip(14).every((line) => line.isEmpty), isTrue);
          expect(t.screen.text, isNot(contains('\x1b')));
        }
      },
    );

    testWidgets('unbounded row has no extra gap after its glyph block', (
      t,
    ) async {
      await t.pumpWidget(
        Row(
          children: [
            DisplayText('I', size: DisplaySize.large),
            Text('after'),
          ],
        ),
      );
      expect(t.screen.lines.first, '${'█' * 10}after');
    });

    for (final align in [TextAlign.left, TextAlign.center, TextAlign.right]) {
      testWidgets('$align places the whole block in a wider room', (t) async {
        await t.pumpWidget(
          DisplayText('I', size: DisplaySize.large, align: align),
        );
        final left = align == TextAlign.left
            ? 0
            : align == TextAlign.center
            ? 35
            : 70;
        expect(t.screen.lines.first, '${' ' * left}${'█' * 10}');
      });
    }

    testWidgets(
      'nested rich runs inherit attributes and keep their own colour',
      (t) async {
        final base = Style(fg: RgbColor.hex('#f2ead9'));
        final orange = Style(fg: RgbColor.hex('#ff5a1f'));
        await t.pumpWidget(
          DisplayText.rich(
            TextSpan(
              'I',
              style: Style.bold,
              children: [
                TextSpan('I', style: orange),
                const TextSpan('I', style: Style.underline),
              ],
            ),
            style: base,
          ),
        );
        expect(t.screen.styleAt(0, 0), base.merge(Style.bold));
        expect(t.screen.styleAt(12, 0), base.merge(Style.bold).merge(orange));
        expect(
          t.screen.styleAt(24, 0),
          base.merge(Style.bold).merge(Style.underline),
        );
      },
    );

    testWidgets(
      '1000 updates settle on the last text and removal drops the listener',
      (t) async {
        final text = ValueNotifier('W');
        addTearDown(text.dispose);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: text,
            builder: (_) => DisplayText(text.value),
          ),
        );
        for (var i = 0; i < 1000; i++) {
          text.value = 'I' * (i % 3 + 1);
        }
        await t.pump();
        expect(t.screen.lines.first, '█' * 10);
        await t.resize(const Size(120, 40));
        expect(t.screen.lines.first, '█' * 10);
        await t.pumpWidget(Text('removed'));
        text.value = 'AAAA';
        await t.pump();
        expect(t.screen.text, 'removed');
      },
    );
  });
}
