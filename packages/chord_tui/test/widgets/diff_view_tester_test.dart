import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester U2a selected rendering', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('zero and one cell clip a selected view at $size', (t) async {
        final view = diffTexts('界', '👩‍💻e\u0301').view(maxRows: 1);
        for (final width in [0, 1, 2, 3, 4, 5]) {
          await t.pumpWidget(
            Row(
              children: [
                SizedBox(width: width, child: Diff.fromView(view)),
                Text('|'),
              ],
            ),
            size: size,
          );
          expect(t.screen.charAt(width, 0), '|');
          for (var y = 0; y < size.height; y++) {
            for (var x = width + 1; x < size.width; x++) {
              expect(t.screen.charAt(x, y), ' ');
              expect(t.screen.styleAt(x, y).bg, isNull);
            }
          }
        }
      });

      testWidgets('Unicode stays whole at every selected wrap edge at $size', (
        t,
      ) async {
        for (final cluster in ['界', '👩‍💻', 'e\u0301']) {
          for (var edge = 0; edge <= 4; edge++) {
            final width = 4 + edge + graphemeWidth(cluster);
            final view = diffTexts(
              '',
              '${'x' * edge}${cluster}z',
            ).view(maxRows: 1);
            await t.pumpWidget(
              Row(
                children: [SizedBox(width: width, child: Diff.fromView(view))],
              ),
              size: size,
            );
            expect(t.screen.charAt(4 + edge, 0), cluster);
            expect(t.screen.lines[1], '    z');
            expect(view.hidden, 0);
          }
        }
      });

      testWidgets('title override selects language while hidden at $size', (
        t,
      ) async {
        final view = parseUnifiedDiff(
          '--- a/a.unknown\n+++ b/a.unknown\n'
          '@@ -1 +1 @@\n-old\n+return 1;\n',
        ).view();
        await t.pumpWidget(
          Diff.fromView(view, title: 'override.dart', showTitle: false),
          size: size,
        );
        expect(t.screen.lines.take(3), ['1 - old', '1 + return 1;', '']);
        final theme = ThemeData.dark();
        expect(
          t.screen.styleAt(4, 1),
          theme.diff.tint!.text
              .merge(theme.code!.tint.keyword)
              .copyWith(bg: theme.diff.tint!.added.bg),
        );
      });
    }

    testWidgets('unbounded layout and resize retain source row selection', (
      t,
    ) async {
      final view = diffTexts('', '${'x' * 90}界👩‍💻e\u0301').view(maxRows: 1);
      await t.pumpWidget(
        Row(children: [Diff.fromView(view), Text('|')]),
        size: const Size(120, 40),
      );
      expect(t.screen.lines.first, '1 + ${'x' * 90}界👩‍💻e\u0301|');
      await t.resize(const Size(0, 0));
      expect(t.screen.text, isEmpty);
      await t.resize(const Size(1, 1));
      await t.resize(const Size(120, 40));
      expect(t.screen.lines.first, '1 + ${'x' * 90}界👩‍💻e\u0301|');
      await t.pumpWidget(Diff.fromView(view), size: const Size(120, 40));
      final before = t.screen.buffer.lines;
      await t.resize(const Size(80, 24));
      expect(t.screen.lines[1], '    ${'x' * 14}界👩‍💻e\u0301');
      expect(view.rows, hasLength(1));
      await t.resize(const Size(120, 40));
      expect(t.screen.buffer.lines, before);
    });

    testWidgets('a thousand updates switch retained views and constructors', (
      t,
    ) async {
      final phase = ValueNotifier(0);
      final model = diffTexts('old', 'new');
      await t.pumpWidget(
        ListenableBuilder(
          listenable: phase,
          builder: (_) => phase.value == 1001
              ? const Diff('before', 'after')
              : Diff.fromView(model.view(maxRows: phase.value % 3)),
        ),
      );
      expect(t.screen.text, isEmpty);
      for (var i = 1; i <= 1000; i++) {
        phase.value = i;
      }
      await t.pump();
      expect(t.screen.text, '1 - old');
      phase.value = 1001;
      await t.pump();
      expect(t.screen.lines.take(2), ['1 - before', '1 + after']);
      phase.value = 2;
      await t.pump();
      expect(t.screen.lines.take(2), ['1 - old', '1 + new']);
      await t.pumpWidget(Text('removed'));
      phase.value = 0;
      await t.pump();
      expect(t.screen.text, 'removed');
      phase.dispose();
    });

    testWidgets('focus and unbound keys leave the passive view unchanged', (
      t,
    ) async {
      final first = FocusNode();
      final second = FocusNode();
      final view = diffTexts('old', '\x1b[31mnew\x1b[0m').view();
      await t.pumpWidget(
        Column(
          children: [
            Focus(focusNode: first, child: Diff.fromView(view)),
            Focus(focusNode: second, child: Text('other')),
          ],
        ),
      );
      final before = t.screen.buffer.lines;
      expect(t.screen.text, isNot(contains('\x1b')));
      for (final node in [first, second, first]) {
        node.requestFocus();
        for (final key in [
          'ctrl+o',
          'enter',
          'esc',
          'pageup',
          'pagedown',
          'home',
          'end',
          'up',
          'down',
          'tab',
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
