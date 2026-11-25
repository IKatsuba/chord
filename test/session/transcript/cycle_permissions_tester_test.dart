import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/transcript/reports.dart' show runningTurn;
import 'package:test/test.dart';

void main() {
  group('tester: cycle permission reducer boundaries', () {
    test(
      'several requests preserve cycle start through partial and final answers',
      () {
        var state = reduceTranscript(
          Transcript.empty,
          const CycleStartedAction('cycle', 10),
        );
        state = reduceTranscript(
          state,
          const PermissionRequestedAction(
            'cycle',
            PermissionWait('p1'),
            at: 20,
            between: true,
          ),
        );
        state = reduceTranscript(
          state,
          const PermissionRequestedAction(
            'cycle',
            PermissionWait('p2'),
            at: 30,
            between: true,
          ),
        );
        final waiting = state.turn as AwaitingPermission;
        expect(
          (waiting.since, waiting.cycleSince, waiting.cycle, waiting.between),
          (20, 10, true, true),
        );
        expect(waiting.permissions.map((p) => p.id), ['p1', 'p2']);
        expect(runningTurn(waiting), 'cycle');
        state = reduceTranscript(
          state,
          const PermissionSettledAction('cycle', 'p2', Withdrawn()),
        );
        final partial = state.turn as AwaitingPermission;
        expect(
          (partial.since, partial.cycleSince, partial.cycle),
          (20, 10, true),
        );
        expect(partial.permissions.single.id, 'p1');
        state = reduceTranscript(
          state,
          const PermissionSettledAction('cycle', 'p1', Withdrawn()),
        );
        final working = state.turn as Working;
        expect(
          (working.turnId, working.since, working.cycle),
          ('cycle', 10, true),
        );
      },
    );

    test(
      'ending a cycle leaves held requests but answering cannot revive it',
      () {
        var state = reduceTranscript(
          Transcript.empty,
          const CycleStartedAction('cycle', 10),
        );
        for (final id in ['p1', 'p2']) {
          state = reduceTranscript(
            state,
            PermissionRequestedAction(
              'cycle',
              PermissionWait(id),
              at: 20,
              between: true,
            ),
          );
        }
        state = reduceTranscript(
          state,
          const ResultAction('cycle', TurnAnswered('end_turn')),
        );
        final ended = state.turn as AwaitingPermission;
        expect(
          (ended.between, ended.cycle, ended.cycleSince),
          (true, false, null),
        );
        expect(runningTurn(ended), isNull);
        state = reduceTranscript(
          state,
          const PermissionSettledAction('cycle', 'p1', Withdrawn()),
        );
        expect(runningTurn(state.turn), isNull);
        state = reduceTranscript(
          state,
          const PermissionSettledAction('cycle', 'p2', Withdrawn()),
        );
        expect(state.turn, isA<Idle>());
      },
    );

    test(
      'duplicate and unknown request events leave cycle metadata intact',
      () {
        var state = reduceTranscript(
          Transcript.empty,
          const CycleStartedAction('cycle', 10),
        );
        const asked = PermissionRequestedAction(
          'cycle',
          PermissionWait('p1'),
          at: 20,
          between: true,
        );
        state = reduceTranscript(state, asked);
        expect(reduceTranscript(state, asked), same(state));
        expect(
          reduceTranscript(
            state,
            const PermissionSettledAction('cycle', 'unknown', Withdrawn()),
          ),
          same(state),
        );
        final held = state.turn as AwaitingPermission;
        expect((held.cycle, held.cycleSince), (true, 10));
        expect(() => held.permissions.clear(), throwsUnsupportedError);
      },
    );
  });
}
