// The conversation folds its subagents' updates on the original's fake
// agent, as tests/session/subagents_test.ts's subagentupdate case does, and
// its record keeps them with their subagent's id for a replay.
@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/subagents.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'session_fake.dart';

void main() {
  test("an agent that sends ACP's own subagent_update folds its subagent's "
      'work under it, and a replay of its record does too', () async {
    final dir = Directory.systemTemp.createTempSync('chord-subagents-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final events = <ConversationEvent>[];
    final conversation = Conversation(
      ({required onTraffic, required CancellationToken cancellationToken}) =>
          openSession(
            agent: 'fake',
            command: fakeAgentCommand(),
            cwd: dir.path,
            open: fakeOpenerWith(
              capabilities: acp.ClientCapabilities.fromJson({
                'subagents': <String, Object?>{},
              }),
            ),
            onTraffic: onTraffic,
            cancellationToken: cancellationToken,
          ),
    )..listen(events.add);
    addTearDown(conversation.close);
    conversation.start();
    Future<void> until(bool Function() holds) async {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (!holds()) {
        if (DateTime.now().isAfter(deadline)) fail('timed out');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    List<TranscriptAction> actions() => [
      for (final event in events)
        if (event case Transcribed(:final action)) action,
    ];
    await until(() => events.any((e) => e is Connected));
    conversation.send('subagentupdate');
    await until(() => actions().any((a) => a is ResultAction));
    final transcript = actions().fold(Transcript.empty, reduceTranscript);
    final [subagent] = subagentsIn(transcript.entries);
    expect(
      (subagent.title, subagent.state, subagent.startedAt != null),
      ('Summarise the README', SubagentState.ended, true),
    );
    expect(
      subagent.entries.whereType<ToolEntry>().single.call.title,
      'Read README.md',
    );
    expect(
      subagent.entries.whereType<AssistantEntry>().single.text.text,
      'chord is a terminal client for ACP agents.',
    );
    expect(
      transcript.entries.whereType<AssistantEntry>().single.text.text,
      'It says chord is a terminal client for ACP agents.',
    );

    // As the record writes and a replay reads it.
    final lines = historyEntries(actions());
    final replayed = recordActions(
      lines,
    ).actions.fold(Transcript.empty, reduceTranscript);
    expect(
      [for (final s in subagentsIn(replayed.entries)) (s.title, s.state)],
      [('Summarise the README', SubagentState.ended)],
    );
    expect(
      subagentsIn(replayed.entries).single.entries.whereType<ToolEntry>(),
      hasLength(1),
    );
  }, skip: fakeAgentSkip);
}
