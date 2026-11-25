// The working line while a form or link waits, as the original's status.ts
// says it: Esc answers the box rather than interrupting the turn, and the
// wait counts from when it was asked.
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/status/status.dart';
import 'package:test/test.dart';

void main() {
  test('a form waits in a turn and between turns', () {
    final inTurn = workingLine(
      const Working('t', 1000),
      13000,
      input: (at: 4000),
    )!;
    expect((inTurn.label, inTurn.detail), ('Waiting for your input…', '9s'));
    final unstamped = workingLine(
      const Working('t', 1000),
      13000,
      input: (at: null),
    )!;
    expect(unstamped.detail, '12s');
    final idle = workingLine(const Idle(), 13000, input: (at: 10000))!;
    expect((idle.label, idle.detail), ('Waiting for your input…', '3s'));
  });

  test('a permission or a cancel still says itself over a form', () {
    expect(
      workingLine(
        const AwaitingPermission('t', 0, []),
        5000,
        input: (at: 1),
      )!.label,
      'Waiting for permission…',
    );
    expect(
      workingLine(const Cancelling('t', 0, 1), 5000, input: (at: 1))!.label,
      'Interrupting…',
    );
    expect(workingLine(const Idle(), 5000), isNull);
  });
}
