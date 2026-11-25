import 'package:chord/ui/app/startup_choice.dart';
import 'package:test/test.dart';

void main() {
  test('first startup result includes cancellation and never changes', () {
    for (final first in <String?>['claude', null]) {
      final selection = StartupSelection();
      expect(selection.settled, isFalse);
      expect(selection.settle(first), isTrue);
      expect(selection.settled, isTrue);
      expect(selection.settle('codex'), isFalse);
      expect(selection.settle(null), isFalse);
      expect(selection.selected, first);
    }
  });
  test('only unnamed interactive new launches ask for an agent', () {
    expect(chooseAgentAtStart(stdinTTY: true, stdoutTTY: true), isTrue);
    expect(
      chooseAgentAtStart(named: 'fake', stdinTTY: true, stdoutTTY: true),
      isFalse,
    );
    expect(
      chooseAgentAtStart(
        agentCommand: 'fixture',
        stdinTTY: true,
        stdoutTTY: true,
      ),
      isFalse,
    );
    expect(
      chooseAgentAtStart(print: '', stdinTTY: true, stdoutTTY: true),
      isFalse,
    );
    expect(
      chooseAgentAtStart(continuing: true, stdinTTY: true, stdoutTTY: true),
      isFalse,
    );
    expect(
      chooseAgentAtStart(resume: true, stdinTTY: true, stdoutTTY: true),
      isFalse,
    );
    expect(
      chooseAgentAtStart(resume: 'recorded', stdinTTY: true, stdoutTTY: true),
      isFalse,
    );
    expect(chooseAgentAtStart(stdinTTY: false, stdoutTTY: true), isFalse);
    expect(chooseAgentAtStart(stdinTTY: true, stdoutTTY: false), isFalse);
  });
}
