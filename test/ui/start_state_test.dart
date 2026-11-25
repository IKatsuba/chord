import 'package:chord/ui/start_state.dart';
import 'package:test/test.dart';

const starting = StartState(phase: StartPhase.starting);

void main() {
  group('reduceStart', () {
    test('idle starts once asked', () {
      expect(
        reduceStart(StartState.idle, const StartRequested()).phase,
        StartPhase.starting,
      );
    });

    test(
      'a session opened connects, keeping what the agent said of itself',
      () {
        final state = reduceStart(
          starting,
          const SessionOpened('s1', agentName: 'fake', agentVersion: '1.0'),
        );
        expect(state.phase, StartPhase.connected);
        expect(state.sessionId, 's1');
        expect(state.agentName, 'fake');
        expect(state.agentVersion, '1.0');
        expect(state.reason, isNull);
      },
    );

    test('an empty identity stays absent', () {
      final state = reduceStart(
        starting,
        const SessionOpened('s1', agentName: '', agentVersion: ''),
      );
      expect(state.agentName, isNull);
      expect(state.agentVersion, isNull);
    });

    test('a session without an id does not connect', () {
      expect(reduceStart(starting, const SessionOpened('')), same(starting));
    });

    test('a failed start keeps its reason and its stderr', () {
      final state = reduceStart(
        starting,
        const StartFailed('The agent exited.', lines: ['a', 'b'], cut: 3),
      );
      expect(state.phase, StartPhase.failed);
      expect(state.reason, 'The agent exited.');
      expect(state.stderrLines, ['a', 'b']);
      expect(state.stderrCut, 3);
      expect(() => state.stderrLines.add('c'), throwsUnsupportedError);
    });

    test('an exit after connecting is gone, keeping the session', () {
      final connected = reduceStart(
        starting,
        const SessionOpened('s1', agentName: 'fake'),
      );
      final state = reduceStart(
        connected,
        const AgentExited('The agent exited.', lines: ['bye']),
      );
      expect(state.phase, StartPhase.gone);
      expect(state.sessionId, 's1');
      expect(state.agentName, 'fake');
      expect(state.reason, 'The agent exited.');
      expect(state.stderrLines, ['bye']);
    });

    test('nothing late or twice moves a phase', () {
      final failed = reduceStart(starting, const StartFailed('no'));
      final gone = reduceStart(
        reduceStart(starting, const SessionOpened('s1')),
        const AgentExited('The agent exited.'),
      );
      for (final (state, event) in [
        (StartState.idle, const SessionOpened('s1')),
        (StartState.idle, const AgentExited('x')),
        (starting, const StartRequested()),
        (starting, const AgentExited('x')),
        (failed, const SessionOpened('s1')),
        (failed, const StartRequested()),
        (failed, const AgentExited('x')),
        (gone, const SessionOpened('s2')),
        (gone, const StartFailed('x')),
        (gone, const AgentExited('y')),
      ]) {
        expect(reduceStart(state, event), same(state), reason: '$event');
      }
    });
  });

  group('the rows', () {
    test('the status per phase, named by the CLI name', () {
      expect(statusLine(StartState.idle, 'fake'), isNull);
      expect(statusLine(starting, 'fake'), 'Starting fake…');
      expect(
        statusLine(reduceStart(starting, const SessionOpened('s')), 'fake'),
        'Connected',
      );
      expect(
        statusLine(
          reduceStart(starting, const StartFailed('The agent exited.')),
          'fake',
        ),
        'fake did not start: The agent exited.',
      );
      expect(
        statusLine(
          reduceStart(
            reduceStart(starting, const SessionOpened('s')),
            const AgentExited('The agent exited.'),
          ),
          'fake',
        ),
        'The agent exited.',
      );
    });

    test('the end of stderr, as the original shows it', () {
      expect(detailLines(starting), isEmpty);
      expect(
        detailLines(const StartState(stderrLines: ['a', 'b'], stderrCut: 4)),
        ['The end of its stderr:', '  … +4 lines', '  a', '  b'],
      );
      expect(detailLines(const StartState(stderrLines: ['a'], stderrCut: 1)), [
        'The end of its stderr:',
        '  … +1 line',
        '  a',
      ]);
      expect(detailLines(const StartState(stderrLines: ['a'])), [
        'The end of its stderr:',
        '  a',
      ]);
    });

    test('control characters never reach the terminal', () {
      expect(printable('a\x1b[31mb\x07c\nd\x7f\x9be'), 'a�[31mb�c�d��e');
      expect(printable('plain · text…'), 'plain · text…');
    });
  });
}
