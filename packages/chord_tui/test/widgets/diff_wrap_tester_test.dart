import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/text/selection_layout.dart'
    show shapeSelectionSource;
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester U1 wrapAnsi boundaries and lifecycle', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('graphemes stay whole at each wrap edge at $size', (t) async {
        for (final cluster in ['界', '👩‍💻', 'e\u0301']) {
          for (var edge = 0; edge <= 4; edge++) {
            final width = 4 + edge + graphemeWidth(cluster);
            final text = '${'x' * edge}${cluster}z';
            final view = diffTexts('', text).view();
            await t.pumpWidget(
              Row(
                children: [
                  SizedBox(
                    width: width,
                    child: Diff.fromView(
                      view,
                      showTitle: false,
                      wrap: DiffWrap.wrapAnsi,
                    ),
                  ),
                  Text('|'),
                ],
              ),
              size: size,
            );
            expect(t.screen.charAt(4 + edge, 0), cluster);
            expect(t.screen.charAt(width, 0), '|');
            expect(t.screen.lines[1], '    z');
            final source = SelectionSource.diff(
              id: 'edge',
              revision: 0,
              view: view,
              wrap: DiffWrap.wrapAnsi,
            );
            expect(
              shapeSelectionSource(source, width: width).selectedText,
              text,
            );
          }
        }
      });
    }

    testWidgets('zero one unbounded and resized widths recover the same rows', (
      t,
    ) async {
      final text = '${'x' * 90}界👩‍💻e\u0301';
      final view = diffTexts('', text).view();
      final widget = Diff.fromView(
        view,
        showTitle: false,
        wrap: DiffWrap.wrapAnsi,
      );
      await t.pumpWidget(
        Row(children: [widget, Text('|')]),
        size: const Size(120, 40),
      );
      expect(t.screen.lines.first, '1 + $text|');
      await t.resize(const Size(0, 0));
      expect(t.screen.text, isEmpty);
      await t.resize(const Size(1, 1));
      await t.resize(const Size(120, 40));
      expect(t.screen.lines.first, '1 + $text|');
      await t.pumpWidget(widget, size: const Size(120, 40));
      final wide = t.screen.buffer.lines;
      await t.resize(const Size(80, 24));
      expect(t.screen.lines[1], '    ${'x' * 14}界👩‍💻e\u0301');
      await t.resize(const Size(120, 40));
      expect(t.screen.buffer.lines, wide);
    });

    testWidgets(
      'mode changes invalidate retained geometry after burst updates',
      (t) async {
        final phase = ValueNotifier(0);
        final view = diffTexts('', '    alpha beta gamma delta').view();
        Widget content(DiffWrap wrap) =>
            Diff.fromView(view, showTitle: false, wrap: wrap);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: phase,
            builder: (_) => content(
              phase.value.isEven ? DiffWrap.keepSpaces : DiffWrap.wrapAnsi,
            ),
          ),
          size: const Size(15, 24),
        );
        final before = t.screen.buffer.lines;
        for (var i = 1; i <= 1001; i++) {
          phase.value = i;
        }
        await t.pump();
        final wrapped = t.screen.buffer.lines;
        expect(wrapped, isNot(before));
        await t.pumpWidget(
          content(DiffWrap.wrapAnsi),
          size: const Size(15, 24),
        );
        expect(t.screen.buffer.lines, wrapped);
        await t.pumpWidget(Text('removed'));
        phase.value = 1002;
        await t.pump();
        expect(t.screen.text, 'removed');
        phase.dispose();
      },
    );

    testWidgets('focus and keys keep escaped source inert', (t) async {
      final first = FocusNode();
      final second = FocusNode();
      await t.pumpWidget(
        Column(
          children: [
            Focus(
              focusNode: first,
              child: const Diff(
                '',
                '\x1b[31mred\x1b[0m words words words',
                wrap: DiffWrap.wrapAnsi,
              ),
            ),
            Focus(focusNode: second, child: Text('other')),
          ],
        ),
        size: const Size(15, 24),
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
          'left',
          'right',
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

    test(
      'changing a source mode reshapes without changing copied whitespace',
      () {
        final view = diffTexts('', '      alpha    beta gamma   ').view();
        final before = SelectionSource.diff(
          id: 'source',
          revision: 0,
          view: view,
        );
        final after = SelectionSource.diff(
          id: 'source',
          revision: 1,
          view: view,
          previous: before,
          wrap: DiffWrap.wrapAnsi,
        );
        for (final width in [5, 7, 15, 80, 120]) {
          final shape = shapeSelectionSource(after, width: width);
          expect(
            shape.selectedText,
            '      alpha    beta gamma   ',
            reason: 'width $width',
          );
        }
        expect(
          shapeSelectionSource(after, width: 15).height,
          Diff.measure(view, 15, wrap: DiffWrap.wrapAnsi),
        );
        expect(
          [
            for (final row in shapeSelectionSource(after, width: 15).rows)
              [for (final cell in row.glyphs) (cell.x, cell.glyph.text)],
          ],
          isNot([
            for (final row in shapeSelectionSource(before, width: 15).rows)
              [for (final cell in row.glyphs) (cell.x, cell.glyph.text)],
          ]),
        );
      },
    );
  });
}
