import 'package:chord/acp/connection.dart' show Tail;
import 'package:chord/session/start_failure.dart';
import 'package:chord/ui/app/start_failure.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester: failed-start stderr block boundaries', () {
    for (final size in const [Size(80, 24), Size(120, 40)]) {
      testWidgets(
        'original long indented stderr wraps at the tail column $size',
        (t) async {
          await t.pumpWidget(
            StartFailureBlock(
              agent: 'fake',
              failure: StartFailure(
                step: StartStep.initialize,
                stderr: Tail(['    ${'x' * 150}…', 'final diagnostic'], 3),
              ),
            ),
            size: size,
          );
          final lines = t.screen.lines;
          final first = lines.indexWhere((row) => row.contains('xxxxx'));
          final column = lines
              .firstWhere((row) => row.contains('final diagnostic'))
              .indexOf('final');
          expect(lines[first - 1].trim(), isEmpty);
          expect(lines[first].indexOf('x'), column);
          expect(lines[first + 1].indexOf('x'), column);
          expect(lines.any((row) => row.endsWith('…')), isTrue);
        },
      );

      testWidgets(
        'pin, cut, ANSI tail and way-on retain order and styles $size',
        (t) async {
          const failure = StartFailure(
            step: StartStep.newSession,
            code: -32602,
            pinned: 'fake-acp@1.2.3',
            stderr: Tail([
              '\x1b[31m界👩‍💻e\u0301\x1b[0m',
              'final diagnostic',
            ], 1),
          );
          await t.pumpWidget(
            const StartFailureBlock(agent: 'zeroclaw', failure: failure),
            size: size,
          );
          final lines = t.screen.lines;
          expect(lines.take(5), [
            '  ⎿  chord ran fake-acp@1.2.3, the version this chord pins.',
            '     The end of its stderr:',
            '       … +1 line',
            '       界👩‍💻e\u0301',
            '       final diagnostic',
          ]);
          expect(t.screen.styleAt(7, 3).fg, Colors.red);
          expect(lines[5], startsWith('     Set a default agent:'));
          final before = t.screen.buffer.lines;
          await t.resize(Size.zero);
          await t.resize(const Size(1, 1));
          await t.resize(size);
          expect(t.screen.buffer.lines, before);
        },
      );
    }

    testWidgets('empty facts and other error codes add no advice', (t) async {
      for (final code in [null, -32601, -32603]) {
        await t.pumpWidget(
          StartFailureBlock(
            agent: 'zeroclaw',
            failure: StartFailure(step: StartStep.newSession, code: code),
          ),
        );
        expect(t.screen.text, isEmpty);
      }
    });
  });
}
