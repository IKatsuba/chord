import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/transcript/tools/tools.dart';
import 'package:chord_tui/chord_tui.dart' hide Terminal;
import 'package:test/test.dart';

acp.ToolCallContent _text(String value) => acp.ToolCallContent.fromJson({
  'type': 'content',
  'content': {'type': 'text', 'text': value},
});

void main() {
  group('tester U2 summary boundaries', () {
    test(
      'Read fold counts source lines before wrapping at both screen widths',
      () {
        final call = ToolCall(
          'a',
          kind: 'read',
          content: [_text('${'x' * 150}\n\nthird\nfourth\nfifth\n')],
        );
        for (final width in [75, 115]) {
          final view = summary(call, false, width: width);
          expect(view.hidden, 2);
          expect(view.lines, hasLength(4));
          expect(view.lines[2], '');
          expect(view.lines.last, 'third');
          expect(
            view.rows.map(TextLayout.lineWidth),
            everyElement(lessThanOrEqualTo(width)),
          );
          expect(summary(call, true, width: width).hidden, 0);
        }
      },
    );

    test(
      'failure notes across several terminals suppress only generic failure',
      () {
        final call = ToolCall(
          'a',
          status: 'failed',
          terminals: [
            const Terminal('empty'),
            const Terminal('success', exited: true, exitCode: 0),
            const Terminal('killed', output: 'tail', signal: 'SIGTERM'),
          ],
        );
        final view = summary(call, false, ended: true);
        expect(view.lines, isEmpty);
        expect(view.terminals, hasLength(2));
        expect(view.terminals.first.note!.text, '(No output)');
        expect(view.terminals.last.note!.text, 'Killed by SIGTERM');
        final withText = summary(
          ToolCall(
            'a',
            status: 'failed',
            terminals: call.terminals,
            content: [_text('reason\nnext')],
          ),
          false,
        );
        expect(withText.lines, ['Error: reason', 'next']);
      },
    );

    test('empty width and one cell do not change hidden source counts', () {
      final call = ToolCall(
        'a',
        kind: 'read',
        content: [_text('abc\nd\ne\nf')],
      );
      expect(summary(call, false, width: 0).hidden, 1);
      // Source folding precedes wrapLine's one-cell minimum.
      expect(summary(call, false, width: 0).lines, ['a', 'b', 'c', 'd', 'e']);
      final one = summary(call, false, width: 1);
      expect(one.lines, ['a', 'b', 'c', 'd', 'e']);
      expect(one.hidden, 1);
    });

    test('ANSI and complete graphemes survive wrapping at every edge', () {
      for (final width in [2, 3, 7, 75, 115]) {
        for (var edge = 0; edge <= width; edge++) {
          final text = '${'x' * edge}界👩‍💻e\u0301';
          final call = ToolCall('a', content: [_text('\x1b[31m$text\x1b[0m')]);
          final view = summary(call, false, width: width);
          expect(view.lines.join(), text);
          expect(
            view.rows.map(TextLayout.lineWidth),
            everyElement(lessThanOrEqualTo(width)),
          );
          expect(
            view.rows.expand((r) => r).every((g) => g.style.fg != null),
            isTrue,
          );
        }
      }
    });
  });
}
