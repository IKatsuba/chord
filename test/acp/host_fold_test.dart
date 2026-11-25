// chord acp's host fold: each event folded before the host reads it, a
// clear starting it again, every event type either folded or listed as no
// action; and a child's state words read from what is folded.
import 'dart:io';

import 'package:chord/acp/host_fold.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/upstream.dart';
import 'package:test/test.dart';

FoldedSession _fold(Iterable<ConversationEvent> events) {
  FoldedSession? fold;
  for (final event in events) {
    fold = foldEvent(fold, event);
  }
  return fold ?? noFold;
}

const _prompt = Transcribed(PromptAction('t1', 'look', 0));
const _asked = Transcribed(
  PermissionRequestedAction('t1', PermissionWait('p1', toolCallId: 'c1')),
);

void main() {
  test('every event type is folded or listed as no action, never both', () {
    // Read from the source, as Dart cannot list a sealed class's subtypes:
    // a new event fails here until it is placed in one list.
    final source = File('lib/session/conversation.dart').readAsStringSync();
    final types = {
      for (final match in RegExp(
        r'final class (\w+) extends ConversationEvent',
      ).allMatches(source))
        match.group(1)!,
    };
    expect(types, isNotEmpty);
    expect(hostFolded.intersection(hostNotActions), isEmpty);
    expect({...hostFolded, ...hostNotActions}, types);
  });

  test('a session nothing was heard of is idle, its queue empty', () {
    expect(noFold.queue, isEmpty);
    expect(agentStateOf(noFold), {'state': 'idle'});
  });

  test('a transcript action folds in at once', () {
    expect(agentStateOf(_fold([_prompt])), {'state': 'running'});
    expect(agentStateOf(_fold([_prompt, _asked])), {
      'state': 'requires_action',
    });
  });

  test('a clear starts the fold again', () {
    expect(identical(_fold([_prompt, _asked, const Cleared()]), noFold), true);
  });

  test('an event that is no action leaves the fold as it was', () {
    final fold = _fold([_prompt]);
    for (final event in <ConversationEvent>[
      const Connected('s1', AgentState.empty),
      const Gone('The agent exited.'),
      const AgentClosed('a1'),
      const Closing(),
    ]) {
      expect(identical(foldEvent(fold, event), fold), true);
    }
  });

  test('a replayed past takes the transcript as the window draws it', () {
    final fold = _fold([
      _prompt,
      HistoryReplayed(const [
        PromptAction('r1', 'before', 0),
        ResultAction('r1', TurnAnswered('end_turn')),
      ], state: AgentState.empty),
    ]);
    expect(agentStateOf(fold, stopReason: 'end_turn'), {
      'state': 'idle',
      'stopReason': 'end_turn',
    });
  });

  test('an open plan ask wants the client before anything else', () {
    final fold = _fold([
      _prompt,
      const Transcribed(
        PlanRequestedAction(
          't1',
          PlanWait('plan-1', PlanAgent.cursor, toolCallId: 'c1'),
        ),
      ),
    ]);
    expect(agentStateOf(fold), {'state': 'requires_action'});
  });

  group('a child\'s update', () {
    const report = AgentReport(
      parent: 'm',
      upstreamId: 'm/a1',
      title: 'parser',
      state: {'state': 'idle'},
      runtime: 'codex',
      model: 'gpt',
    );

    test('goes on its parent with what chord knows of it', () {
      expect(agentUpdate({'subagents': <String, Object?>{}}, report), {
        'sessionId': 'm',
        'update': {
          'sessionUpdate': 'subagent_update',
          'sessionId': 'm/a1',
          'title': 'parser',
          'state': {'state': 'idle'},
          'capabilities': {'cancel': <String, Object?>{}},
          '_meta': {
            'chord/agent': {'runtime': 'codex', 'model': 'gpt'},
          },
        },
      });
    });

    test('closed, has nothing left to cancel', () {
      final update =
          agentUpdate({'subagents': true}, report.asClosed)!['update']
              as Map<String, Object?>;
      expect(update.containsKey('capabilities'), false);
      expect(update['_meta'], {
        'chord/agent': {'runtime': 'codex', 'model': 'gpt', 'closed': true},
      });
    });

    test('goes nowhere for a client that takes no subagents', () {
      expect(agentUpdate(const {}, report), isNull);
    });
  });

  test("a child session's updates reach only a client that takes "
      'subagents', () {
    final session = childSession('s2', 'm/a1');
    const chunk = {
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': 'hi'},
    };
    expect(mapUpdate(session, const {}, chunk).notification, isNull);
    expect(mapUpdate(session, const {'subagents': true}, chunk).notification, {
      'sessionId': 'm/a1',
      'update': chunk,
    });
  });
}
