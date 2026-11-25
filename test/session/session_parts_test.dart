// A prompt's images, embedded resources and links on the original's fake
// agent, which tells back each it received.
@Tags(['fake_agent'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:chord/acp/traffic.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/session.dart';
import 'package:test/test.dart';

import 'session_fake.dart';

const _png = (mimeType: 'image/png', data: 'AAAA');
const _resource = {
  'type': 'resource',
  'resource': {'uri': 'file:///notes.md', 'text': 'held words'},
};
const _link = {'type': 'resource_link', 'name': 'a.ts', 'uri': 'file:///a.ts'};

void main() {
  final skip = fakeAgentSkip;

  test('the agent\'s prompt capabilities, as its initialize says', () async {
    await withSession((session, _) async {
      expect(session.takesImages(), isTrue);
      expect(session.takesEmbeddedContext(), isFalse);
    });
    await withSession((session, _) async {
      expect(session.takesImages(), isFalse);
      expect(session.takesEmbeddedContext(), isTrue);
    }, flags: ['--no-images', '--embedded-context']);
  }, skip: skip);

  test('text, then images, resources, then links, each as given; the '
      'record keeps a resource\'s uri and type only', () async {
    await withSession((session, traffic) async {
      SubmittedContent? submitted;
      final turn = session.prompt(
        'look',
        parts: const PromptParts(
          images: [_png],
          resources: [_resource],
          links: [_link],
        ),
        turnId: 't1',
        onSubmitted: (content) => submitted = content,
      );
      await turn.result;
      final sent = traffic.heard
          .whereType<ChordTraffic>()
          .map((traffic) => traffic.message)
          .lastWhere((message) => message['method'] == 'session/prompt');
      expect((sent['params'] as Map)['prompt'], [
        {'type': 'text', 'text': 'look'},
        {'type': 'image', 'mimeType': 'image/png', 'data': 'AAAA'},
        _resource,
        _link,
      ]);
      final heard = [
        for (final update in traffic.updates)
          if (update case {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'text': final String text},
          })
            text,
      ].join();
      expect(heard, contains('Received an image: image/png, 3 bytes'));
      final resource = RegExp(r'Received a resource: (.*)').firstMatch(heard);
      expect(jsonDecode(resource![1]!), _resource);
      expect(heard, contains('Received a link: a.ts, file:///a.ts'));
      expect(submitted!.images, 1);
      expect(submitted!.resources, [
        {'uri': 'file:///notes.md'},
      ]);
      expect(submitted!.links, [_link]);
    }, flags: ['--embedded-context']);
  }, skip: skip);

  group('tester U5 wire payload boundaries', () {
    for (final steer in [false, true]) {
      test(
        '${steer ? 'steer' : 'prompt'} orders whole resources before resolved and supplied links',
        () async {
          await withSession(
            (session, traffic) async {
              await File('${session.cwd}/mention.md').writeAsString('mention');
              const resources = [
                {
                  'type': 'resource',
                  'resource': {
                    'uri': 'memory://text',
                    'mimeType': 'text/plain',
                    'text': '界👩‍💻e\u0301\n\u001b[31m',
                  },
                  '_meta': {'retained': true},
                },
                {
                  'type': 'resource',
                  'resource': {
                    'uri': 'memory://blob',
                    'mimeType': 'application/octet-stream',
                    'blob': 'AAEC',
                  },
                },
              ];
              const supplied = {
                'type': 'resource_link',
                'name': 'supplied',
                'uri': 'memory://link',
                '_meta': {'keep': true},
              };
              const parts = PromptParts(
                images: [_png],
                resources: resources,
                links: [supplied],
              );
              final submitted = <SubmittedContent>[];
              Turn? running;
              if (steer) {
                running = session.prompt('running');
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
                expect(
                  await session.steer(
                    'payload @mention.md',
                    mentions: ['mention.md'],
                    parts: parts,
                    turnId: 'payload',
                    onSubmitted: submitted.add,
                  ),
                  SteerOutcome.injected,
                );
                expect(await running.result, isA<TurnAnswered>());
              } else {
                expect(
                  await session
                      .prompt(
                        'payload @mention.md',
                        mentions: ['mention.md'],
                        parts: parts,
                        turnId: 'payload',
                        onSubmitted: submitted.add,
                      )
                      .result,
                  isA<TurnAnswered>(),
                );
              }
              final method = steer ? '_session/steering' : 'session/prompt';
              final message = traffic.heard
                  .whereType<ChordTraffic>()
                  .map((t) => t.message)
                  .lastWhere((m) => m['method'] == method);
              final blocks = ((message['params'] as Map)['prompt'] as List)
                  .cast<Map>();
              expect(blocks.map((b) => b['type']), [
                'text',
                'image',
                'resource',
                'resource',
                'resource_link',
                'resource_link',
              ]);
              expect(blocks.take(2), [
                {'type': 'text', 'text': 'payload @mention.md'},
                {'type': 'image', 'mimeType': 'image/png', 'data': 'AAAA'},
              ]);
              expect(blocks.skip(2).take(2), resources);
              expect(blocks[4]['name'], 'mention.md');
              expect(blocks.last, supplied);
              expect(submitted.single.turnId, 'payload');
              expect(submitted.single.images, 1);
              expect(submitted.single.resources, [
                {'uri': 'memory://text', 'mimeType': 'text/plain'},
                {
                  'uri': 'memory://blob',
                  'mimeType': 'application/octet-stream',
                },
              ]);
              expect(submitted.single.links.map((l) => l['name']), [
                'mention.md',
                'supplied',
              ]);
            },
            scenario: steer ? 'texttillsteered' : null,
            flags: [
              '--embedded-context',
              if (steer) ...['--steering', 'claude'],
            ],
          );
        },
        skip: skip,
      );
    }
  });
}
