@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/acp/connection.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'session_fake.dart';

List<Map<String, Object?>> _sent(TrafficRecorder traffic, String method) => [
  for (final event in traffic.heard)
    if (event case ChordTraffic(
      :final message,
    ) when message['method'] == method)
      message,
];

void main() {
  test(
    'fake takes held text and a literal link into the existing turn',
    () async {
      await withSession(
        (session, traffic) async {
          await File('${session.cwd}/notes.txt').writeAsString('saved context');
          expect(session.steers(), isTrue);
          expect(session.cutsCallsOnSteer(), isTrue);
          final turn = session.prompt('first');
          await traffic.next(
            (event) => switch (event) {
              AgentTraffic(
                message: {
                  'method': 'session/update',
                  'params': {
                    'update': {'sessionUpdate': 'agent_message_chunk'},
                  },
                },
              ) =>
                true,
              _ => false,
            },
          );
          final submitted = <SubmittedContent>[];
          expect(
            await session.steer(
              'held shell output\nsee @notes.txt',
              mentions: ['notes.txt'],
              turnId: 'queued-1',
              onSubmitted: submitted.add,
            ),
            SteerOutcome.injected,
          );
          expect(await turn.result, isA<TurnAnswered>());
          expect(_sent(traffic, 'session/prompt'), hasLength(1));
          final params =
              _sent(traffic, '_session/steering').single['params'] as Map;
          expect(params['_meta'], {
            'steering': {'idleBehavior': 'promptRequired'},
          });
          final blocks = (params['prompt'] as List).cast<Map>();
          expect(blocks.first, {
            'type': 'text',
            'text': 'held shell output\nsee @notes.txt',
          });
          expect(blocks.last['name'], 'notes.txt');
          expect(submitted.single.turnId, 'queued-1');
          expect(
            submitted.single.links.single['uri'],
            Uri.file('${session.cwd}/notes.txt').toString(),
          );
        },
        scenario: 'texttillsteered',
        flags: ['--steering', 'claude'],
      );
    },
    skip: fakeAgentSkip,
  );

  for (final adapter in ['claude', 'codex24', 'opencode', 'codex']) {
    test(
      'idle $adapter preserves its original outcome without client prompt',
      () async {
        await withSession((session, traffic) async {
          expect(session.steers(), isTrue);
          expect(session.cutsCallsOnSteer(), adapter == 'claude');
          expect(
            await session.steer('text'),
            adapter == 'codex'
                ? SteerOutcome.startedNewTurn
                : SteerOutcome.refused,
          );
          expect(_sent(traffic, 'session/prompt'), isEmpty);
          if (adapter == 'codex') await session.cancel();
        }, flags: ['--steering', adapter]);
      },
      skip: fakeAgentSkip,
    );
  }
  test('explicit fake refusal stays refused', () async {
    await withSession((session, traffic) async {
      expect(await session.steer('text'), SteerOutcome.refused);
      expect(_sent(traffic, 'session/prompt'), isEmpty);
    }, flags: ['--steering', 'claude', '--steer-refuse']);
  }, skip: fakeAgentSkip);
}
