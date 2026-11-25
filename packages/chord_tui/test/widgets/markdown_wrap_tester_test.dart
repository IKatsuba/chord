import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../example/markdown_wrap.dart' show wrappingSample;

void main() {
  group('tester: Markdown wrap boundaries and lifecycle', () {
    testWidgets('all orphan pairs carry together across styled spans', (
      t,
    ) async {
      for (final preposition in ['with', 'in', 'on', 'of', 'to', 'for']) {
        for (final article in ['a', 'an', 'the']) {
          final tail = '$preposition $article';
          await t.pumpWidget(
            Markdown(
              '| Holds |\n|---|\n| alpha **$preposition** *$article* beta |',
            ),
            size: Size(6 + 'alpha $tail'.length, 24),
          );
          expect(t.screen.lines[3].split('│')[1].trim(), 'alpha');
          expect(t.screen.lines[4].split('│')[1].trim(), '$tail beta');
          expect(t.screen.styleAt(2, 4).isBold, isTrue);
          expect(t.screen.styleAt(3 + preposition.length, 4).isItalic, isTrue);
        }
      }
    });

    testWidgets('punctuation wraps keep wide and combining graphemes whole', (
      t,
    ) async {
      for (final cluster in ['界', '👩‍💻', 'e\u0301']) {
        final width = 7 + cellWidth(cluster);
        await t.pumpWidget(
          Markdown('prefix **$cluster/abcdefgh**'),
          size: Size(width + 1, 24),
        );
        expect(t.screen.lines.take(2), ['prefix $cluster/', 'abcdefgh']);
        expect(t.screen.styleAt(7, 0).isBold, isTrue);
        await t.resize(Size(width, 24));
        final fresh = WidgetTester();
        try {
          await fresh.pumpWidget(
            Markdown('prefix **$cluster/abcdefgh**'),
            size: Size(width, 24),
          );
          expect(t.screen.buffer.lines, fresh.screen.buffer.lines);
        } finally {
          fresh.dispose();
        }
      }
    });

    testWidgets(
      'streamed Unicode link and table survive zero and repeated resize',
      (t) async {
        const source =
            '$wrappingSample\n\n'
            'prefix [界👩‍💻e\u0301](https://example.test/a-b/c) final\n\n'
            '| Holds |\n|---|\n| alpha **with the** 界👩‍💻e\u0301 |';
        final text = ValueNotifier('');
        await t.pumpWidget(
          ListenableBuilder(
            listenable: text,
            builder: (context) => Markdown(text.value, growing: true),
          ),
          size: const Size(120, 40),
        );
        for (var i = 0; i < 1000; i++) {
          text.value = source.substring(0, source.length * i ~/ 999);
        }
        await t.pump();
        for (final size in [
          const Size(0, 0),
          const Size(1, 1),
          const Size(80, 24),
          const Size(120, 40),
          const Size(16, 40),
          const Size(80, 24),
        ]) {
          await t.resize(size);
          final fresh = WidgetTester();
          try {
            await fresh.pumpWidget(const Markdown(source), size: size);
            expect(t.screen.buffer.lines, fresh.screen.buffer.lines);
          } finally {
            fresh.dispose();
          }
        }
        await t.pumpWidget(const SizedBox());
        text.value = 'late source after removal';
        await t.pump();
        expect(t.screen.text, isEmpty);
        text.dispose();
      },
    );
  });
}
