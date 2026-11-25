import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

TextLayout _layout(String text, int width, {int? maxLines}) =>
    TextLayout.compute(
      TextSpan(text),
      maxWidth: width,
      softWrap: false,
      maxLines: maxLines,
      overflow: TextOverflow.middle,
    );
String _line(TextLayout layout) =>
    layout.lines.single.map((g) => g.text).join();

void main() {
  group('tester U4a middle overflow boundaries', () {
    test(
      'fitting lines at tiny widths remain intact including wide glyphs',
      () {
        for (final (text, width) in [
          ('', 0),
          ('a', 1),
          ('界', 2),
          ('👩‍💻', 2),
          ('e\u0301', 1),
          ('abc', 3),
        ]) {
          expect(_line(_layout(text, width)), text);
        }
        for (var width = 0; width <= 3; width++) {
          expect(_line(_layout('abcde', width)), '');
        }
      },
    );

    test(
      'wide glyphs block each contiguous end without moving spare cells',
      () {
        expect(_line(_layout('界abcdefx', 5)), '...x');
        expect(_line(_layout('xabcdef界', 5)), 'x...');
        expect(_line(_layout('界abcdef界', 5)), '...');
        expect(_line(_layout('👩‍💻abcdef👩‍💻', 5)), '...');
        expect(_line(_layout('e\u0301abcdefe\u0301', 5)), 'e\u0301...e\u0301');
        expect(_line(_layout('  abcdef  ', 7)), '  ...  ');
      },
    );

    test('all bounded widths keep full end clusters and a bounded result', () {
      for (final cluster in ['界', '👩‍💻', 'e\u0301']) {
        final text = '$cluster${'x' * 120}$cluster';
        for (var width = 0; width <= 125; width++) {
          final layout = _layout(text, width);
          expect(layout.width, lessThanOrEqualTo(width));
          for (final glyph in layout.lines.single) {
            expect([cluster, 'x', '.'], contains(glyph.text));
          }
          if (cellWidth(text) <= width) expect(_line(layout), text);
        }
      }
    });

    test('line limits never expose the final paragraph as the tail', () {
      final layout = _layout('ABCDEFGHIJK\nlast paragraph', 7, maxLines: 1);
      expect(_line(layout), 'AB...JK');
      expect(
        _line(_layout('short\nlonger paragraph', 7, maxLines: 1)),
        'short',
      );
      expect(_layout('long paragraph', 7, maxLines: 0).lines, isEmpty);
      expect(_line(_layout('ABCDEFGHIJK', unbounded)), 'ABCDEFGHIJK');
      final wrapped = TextLayout.compute(
        const TextSpan('one two three'),
        maxWidth: 5,
        overflow: TextOverflow.middle,
      );
      expect(wrapped.lines.map((r) => r.map((g) => g.text).join()), [
        'one',
        'two',
        'three',
      ]);
    });

    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('rich inherited marker styles and clipping at $size', (
        t,
      ) async {
        await t.pumpWidget(
          Row(
            children: [
              SizedBox(
                width: 9,
                child: DefaultTextStyle(
                  style: Style.italic,
                  softWrap: false,
                  overflow: TextOverflow.middle,
                  child: Text.rich(
                    TextSpan(
                      '',
                      children: [
                        TextSpan(
                          'ABCDEFGHIJKLM',
                          style: const Style(fg: IndexedColor(1)),
                        ),
                        TextSpan('NOPQRSTUVWXYZ', style: Style.bold),
                      ],
                    ),
                  ),
                ),
              ),
              Text('|'),
            ],
          ),
          size: size,
        );
        expect(t.screen.lines.first, 'ABC...XYZ|');
        expect(t.screen.styleAt(0, 0).fg, const IndexedColor(1));
        expect(t.screen.styleAt(8, 0).isBold, isTrue);
        for (var x = 3; x < 6; x++) {
          expect(t.screen.styleAt(x, 0), Style.italic);
        }
        for (var width = 0; width <= 3; width++) {
          await t.pumpWidget(
            Row(
              children: [
                SizedBox(
                  width: width,
                  child: Text.ansi(
                    '\x1b[31mabcdef',
                    softWrap: false,
                    overflow: TextOverflow.middle,
                  ),
                ),
                Text('|'),
              ],
            ),
            size: size,
          );
          expect(t.screen.lines.first, '${' ' * width}|');
          expect(t.screen.styleAt(width, 0).fg, isNull);
        }
      });
    }

    testWidgets('resize recomputes both ends on the same mounted text', (
      t,
    ) async {
      final text = 'A${'x' * 180}界👩‍💻e\u0301Z';
      await t.pumpWidget(
        Text(text, softWrap: false, overflow: TextOverflow.middle),
        size: const Size(120, 40),
      );
      final wide = t.screen.buffer.lines;
      expect(t.screen.lines.first, contains('...'));
      expect(t.screen.lines.first, endsWith('界👩‍💻e\u0301Z'));
      await t.resize(const Size(80, 24));
      expect(cellWidth(t.screen.lines.first), lessThanOrEqualTo(80));
      expect(t.screen.lines.first, endsWith('界👩‍💻e\u0301Z'));
      await t.resize(const Size(0, 0));
      expect(t.screen.text, isEmpty);
      await t.resize(const Size(1, 1));
      expect(t.screen.text, isEmpty);
      await t.resize(const Size(120, 40));
      expect(t.screen.buffer.lines, wide);
    });

    testWidgets('a thousand stream updates then removal cancel UI listening', (
      t,
    ) async {
      final value = ValueNotifier('start');
      final stream = StreamController<String>(sync: true);
      final subscription = stream.stream.listen((text) => value.value = text);
      addTearDown(() async {
        await subscription.cancel();
        await stream.close();
        value.dispose();
      });
      await t.pumpWidget(
        Align(
          alignment: Alignment.topLeft,
          child: ListenableBuilder(
            listenable: value,
            builder: (_) => SizedBox(
              width: 9,
              child: Text(
                value.value,
                softWrap: false,
                overflow: TextOverflow.middle,
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 1000; i++) {
        stream.add('ABCDEFGHIJ$i');
      }
      await t.pump();
      expect(t.screen.lines.first, 'ABC...999');
      await t.pumpWidget(Text('removed'));
      stream.add('still live');
      await t.pump();
      expect(t.screen.text, 'removed');
    });

    testWidgets('passive focus and unbound keys preserve middle overflow', (
      t,
    ) async {
      final first = FocusNode();
      final second = FocusNode();
      await t.pumpWidget(
        Column(
          children: [
            Focus(
              focusNode: first,
              child: SizedBox(
                width: 7,
                child: Text(
                  'ABCDEFGHIJK',
                  softWrap: false,
                  overflow: TextOverflow.middle,
                ),
              ),
            ),
            Focus(focusNode: second, child: Text('other')),
          ],
        ),
      );
      final before = t.screen.buffer.lines;
      for (final node in [first, second, first]) {
        node.requestFocus();
        for (final key in [
          'enter',
          'esc',
          'up',
          'down',
          'home',
          'end',
          'pageup',
          'pagedown',
          'ctrl+o',
        ]) {
          await t.press(key);
          expect(t.screen.buffer.lines, before);
        }
      }
      t.dispose();
      first.dispose();
      second.dispose();
    });
  });
}
