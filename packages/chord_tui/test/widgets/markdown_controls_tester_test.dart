import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'markdown_controls_test.dart' show cell, primary;

void main() {
  group('tester: code controls at empty, reentrant and narrow boundaries', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'closed empty code invokes its current descriptor without selecting furniture $size',
        (t) async {
          final c = SelectionController();
          final source = SelectionSource.markdown(
            id: 'empty',
            revision: 0,
            text: '```ts\n```',
            copyCodeBlocks: true,
          );
          final copies = <MarkdownCodeBlock>[];
          var finalized = 0;
          await t.pumpWidget(
            SelectionArea(
              controller: c,
              selectionStyle: Style.inverse,
              onSelectionFinalized: (_) => finalized++,
              child: Markdown.fromSelectionSource(
                source,
                onCopyCodeBlock: copies.add,
              ),
            ),
            size: size,
          );
          final at = cell(t, '[copy]');
          await t.mouse(primary(MouseEventKind.press, at));
          await t.mouse(primary(MouseEventKind.release, at));
          expect(copies.single.id, source.codeBlocks.single.id);
          expect(copies.single.text, isEmpty);
          expect(copies.single.complete, isTrue);
          expect(finalized, 0);
          expect(c.snapshot()!.hasText, isFalse);
          t.dispose();
          c.dispose();
        },
      );

      testWidgets(
        'copy callback can start a new button capture before old up returns $size',
        (t) async {
          final source = SelectionSource.markdown(
            id: 'code',
            revision: 0,
            text: '```\n\tfirst\n\nlast\n```',
            copyCodeBlocks: true,
          );
          late Offset at;
          final copies = <String>[];
          await t.pumpWidget(
            Markdown.fromSelectionSource(
              source,
              onCopyCodeBlock: (block) {
                copies.add(block.text);
                if (copies.length == 1) {
                  t.host.handleMouse(primary(MouseEventKind.press, at));
                }
              },
            ),
            size: size,
          );
          at = cell(t, '[copy]');
          await t.mouse(primary(MouseEventKind.press, at));
          await t.mouse(primary(MouseEventKind.release, at));
          expect(copies, ['\tfirst\n\nlast']);
          await t.mouse(primary(MouseEventKind.release, at));
          expect(copies, ['\tfirst\n\nlast', '\tfirst\n\nlast']);
        },
      );

      testWidgets(
        'temporary narrow suppression permanently invalidates old press $size',
        (t) async {
          var copies = 0;
          final source = SelectionSource.markdown(
            id: 'code',
            revision: 0,
            text: '```ts\nx\n```',
            copyCodeBlocks: true,
          );
          await t.pumpWidget(
            Markdown.fromSelectionSource(
              source,
              onCopyCodeBlock: (_) => copies++,
            ),
            size: size,
          );
          final at = cell(t, '[copy]');
          await t.mouse(primary(MouseEventKind.press, at));
          await t.resize(const Size(14, 24));
          expect(t.screen.text, isNot(contains('[copy]')));
          await t.resize(size);
          await t.mouse(primary(MouseEventKind.release, at));
          expect(copies, 0);
          await t.mouse(primary(MouseEventKind.press, at));
          await t.mouse(primary(MouseEventKind.release, at));
          expect(copies, 1);
        },
      );
    }
  });
}
