import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'markdown_controls_test.dart' show cell, primary, click;

void main() {
  group('tester: run controls preserve current action and capture ownership', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'every run cell activates the complete raw descriptor $size',
        (t) async {
          const raw = '\t界👩‍💻é\x1b[31mX\x1b[0m\n\nlast';
          final source = SelectionSource.markdown(
            id: 'raw',
            revision: 0,
            text: '```custom\n$raw\n```',
            runCodeBlockLanguages: {'custom'},
          );
          final runs = <MarkdownCodeBlock>[];
          await t.pumpWidget(
            Markdown.fromSelectionSource(source, onRunCodeBlock: runs.add),
            size: size,
          );
          final start = cell(t, '[run]');
          for (var x = 0; x < 5; x++) {
            await click(t, Offset(start.x + x, start.y));
          }
          expect(runs, hasLength(5));
          expect(
            runs.every((block) => identical(block, source.codeBlocks.single)),
            isTrue,
          );
          expect(runs.map((block) => block.text), everyElement(raw));
          await click(t, Offset(start.x - 1, start.y));
          await click(t, Offset(start.x + 5, start.y));
          expect(runs, hasLength(5));
        },
      );

      testWidgets(
        'callback replacement keeps geometry and uses latest callback $size',
        (t) async {
          final changed = ValueNotifier(false);
          addTearDown(changed.dispose);
          final source = SelectionSource.markdown(
            id: 'callback',
            revision: 0,
            text: '```custom\n\n```',
            runCodeBlockLanguages: {'custom'},
          );
          final calls = <String>[];
          await t.pumpWidget(
            ListenableBuilder(
              listenable: changed,
              builder: (_) => Markdown.fromSelectionSource(
                source,
                onRunCodeBlock: changed.value
                    ? (_) => calls.add('new')
                    : (_) => calls.add('old'),
              ),
            ),
            size: size,
          );
          final at = cell(t, '[run]');
          await t.mouse(primary(MouseEventKind.press, at));
          changed.value = true;
          await t.pump();
          await t.mouse(primary(MouseEventKind.release, at));
          expect(calls, ['new']);
          expect(source.codeBlocks.single.text, isEmpty);
        },
      );

      testWidgets(
        'run suppression cancels permanently while copy stays visible $size',
        (t) async {
          var runs = 0;
          final source = SelectionSource.markdown(
            id: 'narrow',
            revision: 0,
            text: '```custom\nx\n```',
            copyCodeBlocks: true,
            runCodeBlockLanguages: {'custom'},
          );
          await t.pumpWidget(
            Markdown.fromSelectionSource(
              source,
              onCopyCodeBlock: (_) {},
              onRunCodeBlock: (_) => runs++,
            ),
            size: size,
          );
          final at = cell(t, '[run]');
          await t.mouse(primary(MouseEventKind.press, at));
          await t.resize(const Size(24, 24));
          expect(t.screen, shows('[copy]'));
          expect(t.screen.text, isNot(contains('[run]')));
          await t.resize(size);
          await t.mouse(primary(MouseEventKind.release, at));
          expect(runs, 0);
          await click(t, cell(t, '[run]'));
          expect(runs, 1);
        },
      );

      testWidgets(
        'run callback can establish the next capture reentrantly $size',
        (t) async {
          final source = SelectionSource.markdown(
            id: 'reentrant',
            revision: 0,
            text: '```custom\nx\n```',
            runCodeBlockLanguages: {'custom'},
          );
          late Offset at;
          var runs = 0;
          await t.pumpWidget(
            Markdown.fromSelectionSource(
              source,
              onRunCodeBlock: (_) {
                runs++;
                if (runs == 1) {
                  t.host.handleMouse(primary(MouseEventKind.press, at));
                }
              },
            ),
            size: size,
          );
          at = cell(t, '[run]');
          await click(t, at);
          expect(runs, 1);
          await t.mouse(primary(MouseEventKind.release, at));
          expect(runs, 2);
        },
      );

      testWidgets(
        'a thousand revisions before a frame never release an old action $size',
        (t) async {
          final update = ValueNotifier(0);
          addTearDown(update.dispose);
          final runs = <MarkdownCodeBlock>[];
          await t.pumpWidget(
            ListenableBuilder(
              listenable: update,
              builder: (_) => Markdown.fromSelectionSource(
                SelectionSource.markdown(
                  id: 'updates',
                  revision: update.value,
                  text: '```custom\n${update.value}\n```',
                  runCodeBlockLanguages: {'custom'},
                ),
                onRunCodeBlock: runs.add,
              ),
            ),
            size: size,
          );
          final at = cell(t, '[run]');
          await t.mouse(primary(MouseEventKind.press, at));
          for (var i = 1; i <= 1000; i++) {
            update.value = i;
          }
          t.host.handleMouse(primary(MouseEventKind.release, at));
          expect(runs, isEmpty);
          await t.pump();
          await click(t, cell(t, '[run]'));
          expect(runs.single.text, '1000');
          expect(runs.single.revision, 1000);
        },
      );
    }
    testWidgets('unbounded row constraints keep a finite run target', (
      t,
    ) async {
      final runs = <MarkdownCodeBlock>[];
      await t.pumpWidget(
        Row(
          children: [
            Markdown(
              '```custom\nx\n```',
              runCodeBlockLanguages: {'custom'},
              onRunCodeBlock: runs.add,
            ),
          ],
        ),
      );
      await click(t, cell(t, '[run]'));
      expect(runs.single.text, 'x');
    });
    for (final size in [const Size(0, 0), const Size(1, 1)]) {
      testWidgets('zero and one cell expose no run target $size', (t) async {
        var runs = 0;
        await t.pumpWidget(
          Markdown(
            '```custom\n界👩‍💻é\n```',
            runCodeBlockLanguages: {'custom'},
            onRunCodeBlock: (_) => runs++,
          ),
          size: size,
        );
        await click(t, Offset.zero);
        expect(runs, 0);
      });
    }
  });
}
