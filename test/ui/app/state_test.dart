// The original's tests/ui/app/state_test.ts, the M1 slice: the start, the
// agent's state, the transcript, the queue and the scroll rule. Left for
// later: dialogs, pickers, the prompt box, selection, scroll positions and
// every other window feature.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/start_state.dart';
import 'package:test/test.dart';

AppState _fold(List<ConversationEvent> events, [AppState? from]) =>
    events.fold(from ?? AppState.starting, reduceApp);

Transcribed _say(String turnId, String text) => Transcribed(
  UpdateAction(
    turnId,
    acp.SessionUpdate.fromJson({
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': text},
    }),
  ),
);

List<String> _queue(AppState state) => [
  for (final q in state.queue)
    '${q.turnId} ${q.text}${q.afterAnswer ? ' after answer' : ''}',
];

void main() {
  test('the start moves to connected with the session, and the agent state '
      'is the one it opened with', () {
    const agent = AgentState(models: {'currentModelId': 'm'});
    final state = _fold([const Connected('s1', agent)]);

    expect(state.start.phase, StartPhase.connected);
    expect(state.start.sessionId, 's1');
    expect(identical(state.agent, agent), isTrue);
  });

  test('a start that fails says why; a gone agent keeps its session and '
      'its stderr', () {
    expect(
      _fold([const ConnectFailed('no such agent')]).start.reason,
      'no such agent',
    );

    final gone = _fold([
      const Connected('s1', AgentState.empty),
      const Gone('The agent exited.', stderrLines: ['oom'], stderrCut: 2),
    ]).start;

    expect(gone.phase, StartPhase.gone);
    expect(gone.sessionId, 's1');
    expect(
      [gone.reason, gone.stderrLines, gone.stderrCut],
      [
        'The agent exited.',
        ['oom'],
        2,
      ],
    );
  });

  test("the agent's state is replaced by the one the conversation tells", () {
    const moved = AgentState(modes: {'currentModeId': 'plan'});
    final state = _fold([
      const Connected('s1', AgentState.empty),
      const AgentStateChanged(moved),
    ]);

    expect(identical(state.agent, moved), isTrue);
  });

  test('every transcript action goes through the reducer', () {
    final state = _fold([
      Transcribed(const PromptAction('turn-1', 'hello', 100)),
      _say('turn-1', 'Hi.'),
      const Transcribed(ResultAction('turn-1', TurnAnswered('end_turn'))),
    ]);

    expect(state.transcript.entries.map((e) => e.runtimeType), [
      UserEntry,
      AssistantEntry,
    ]);
    expect(state.transcript.turn, isA<Idle>());
  });

  group('the queue', () {
    test('a queued prompt is added in order, told again in place, and gone '
        'once its turn starts', () {
      final state = _fold([
        const Queued('turn-2', 'two'),
        const Queued('turn-3', 'three'),
        const Queued('turn-2', 'two', afterAnswer: true),
      ]);

      expect(_queue(state), ['turn-2 two after answer', 'turn-3 three']);
      expect(
        _queue(
          _fold([Transcribed(const PromptAction('turn-2', 'two', 1))], state),
        ),
        ['turn-3 three'],
      );
    });

    test('taken back, the prompts leave the queue; one not there changes '
        'nothing', () {
      final state = _fold([
        const Queued('turn-2', 'two'),
        const Queued('turn-3', 'three'),
      ]);
      final withdrawn = reduceApp(
        state,
        const QueueWithdrawn([QueuedPrompt('turn-2', 'two')]),
      );

      expect(_queue(withdrawn), ['turn-3 three']);
      expect(
        identical(
          reduceApp(state, const QueueWithdrawn([QueuedPrompt('x', 'x')])),
          state,
        ),
        isTrue,
      );
    });
  });

  group('identity', () {
    test('an event that changes nothing leaves the identical state', () {
      final state = _fold([const Connected('s1', AgentState.empty)]);

      for (final event in <ConversationEvent>[
        Transcribed(
          UpdateAction(
            'turn-1',
            acp.SessionUpdate.fromJson({'sessionUpdate': 'something_new'}),
          ),
        ),
        const ConnectFailed('late'),
        AgentStateChanged(state.agent),
        const QueueWithdrawn([]),
      ]) {
        expect(
          identical(reduceApp(state, event), state),
          isTrue,
          reason: '$event',
        );
      }
      // Gone before the session connected moves nothing.
      expect(
        identical(
          reduceApp(AppState.starting, const Gone('early')),
          AppState.starting,
        ),
        isTrue,
      );
    });
  });

  group('the scroll rule', () {
    test('a prompt brings the view to the bottom', () {
      const event = Transcribed(PromptAction('turn-1', 'hello', 1));
      final after = reduceApp(AppState.starting, event);

      expect(
        scrollEffectOf(AppState.starting, after, event),
        ScrollEffect.bottom,
      );
    });

    test('anything else added to the entries is news; a change that adds '
        'none is nothing', () {
      final before = _fold([Transcribed(const PromptAction('turn-1', 'p', 1))]);
      final chunk = _say('turn-1', 'Hi.');
      final plan = Transcribed(
        UpdateAction(
          'turn-1',
          acp.SessionUpdate.fromJson({
            'sessionUpdate': 'plan',
            'entries': <Object?>[],
          }),
        ),
      );

      expect(
        scrollEffectOf(before, reduceApp(before, chunk), chunk),
        ScrollEffect.news,
      );
      expect(
        scrollEffectOf(before, reduceApp(before, plan), plan),
        ScrollEffect.none,
      );
      expect(
        scrollEffectOf(
          before,
          reduceApp(before, const Queued('turn-2', 'q')),
          const Queued('turn-2', 'q'),
        ),
        ScrollEffect.none,
      );
    });
  });

  group('tester: app queue snapshots', () {
    test(
      'withdrawing a middle prompt keeps order, snapshots and transcript identity',
      () {
        final before = _fold([
          const Transcribed(PromptAction('running', 'p', 0)),
          const Queued('a', '界'),
          const Queued('b', 'e\u0301'),
          const Queued('c', '👩‍💻\x1b[31m'),
        ]);
        const event = QueueWithdrawn([QueuedPrompt('b', 'e\u0301')]);
        final after = reduceApp(before, event);
        expect(_queue(after), ['a 界', 'c 👩‍💻\x1b[31m']);
        expect(before.queue, hasLength(3));
        expect(identical(after.queue.first, before.queue.first), isTrue);
        expect(identical(after.queue.last, before.queue.last), isTrue);
        expect(identical(after.transcript, before.transcript), isTrue);
        expect(scrollEffectOf(before, after, event), ScrollEffect.none);
        expect(() => after.queue.clear(), throwsUnsupportedError);
      },
    );
  });
}
