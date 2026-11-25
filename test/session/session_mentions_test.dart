@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/files.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/prompt/mentions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../fixtures/fake_harness.dart';

List<Map<String, Object?>> sent(TrafficRecorder traffic, String method) => [
  for (final event in traffic.heard)
    if (event case ChordTraffic(
      :final message,
    ) when message['method'] == method)
      message,
];
Future<void> withLinks(
  Future<void> Function(Session, TrafficRecorder, Directory) body, {
  ResolveMentionLinks resolver = mentionLinks,
}) async {
  final dir = await Directory.systemTemp.createTemp('chord-links-session-');
  final traffic = TrafficRecorder(), pids = <int>[];
  Session? session;
  try {
    session = await openSession(
      agent: 'fake',
      command: fakeAgentCommand(),
      cwd: dir.path,
      open: fakeSessionOpener(pids.add),
      onTraffic: traffic.add,
      resolveMentions: resolver,
    );
    await body(session, traffic, dir);
  } finally {
    await session?.close();
    expect(
      pids.where(
        (pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0,
      ),
      isEmpty,
    );
    await dir.delete(recursive: true);
  }
}

acp.ContentBlock link(String name) => acp.ContentBlock.fromJson({
  'type': 'resource_link',
  'name': name,
  'uri': 'file:///project/$name',
});

void main() {
  group('owned session mention payloads', () {
    test(
      'fake ACP receives typed text then valid literal links once in order',
      () async {
        await withLinks((session, traffic, dir) async {
          await Directory(p.join(dir.path, 'src')).create();
          await File(p.join(dir.path, 'src/a.ts')).writeAsString('');
          await File(p.join(dir.path, 'my notes.md')).writeAsString('');
          await File(p.join(dir.path, '.gitignore')).writeAsString('*.log\n');
          await File(p.join(dir.path, 'out.log')).writeAsString('');
          const typed =
              'see @src/a.ts @"my notes.md" @src/a.ts @@"reader @hidden" @out.log @src @missing @../outside';
          final turn = session.prompt(typed, mentions: mentionsIn(typed));
          expect(await turn.result, isA<TurnAnswered>());
          final request =
              sent(traffic, 'session/prompt').single['params'] as Map;
          final blocks = (request['prompt'] as List).cast<Map>();
          expect(blocks.first, {'type': 'text', 'text': typed});
          expect(blocks.skip(1).map((x) => x['name']), [
            'src/a.ts',
            'my notes.md',
          ]);
          expect(blocks.skip(1).map((x) => x['uri']), [
            Uri.file(p.join(dir.path, 'src/a.ts')).toString(),
            Uri.file(p.join(dir.path, 'my notes.md')).toString(),
          ]);
          expect(traffic.said, contains('Received a link: src/a.ts'));
          expect(traffic.said, contains('Received a link: my notes.md'));
          await session
              .prompt(
                '@@parser @@"reader @hidden"',
                mentions: mentionsIn('@@parser @@"reader @hidden"'),
              )
              .result;
          final next = sent(traffic, 'session/prompt').last['params'] as Map;
          expect(next['prompt'], [
            {'type': 'text', 'text': '@@parser @@"reader @hidden"'},
          ]);
        });
      },
    );
    for (final cancelSession in [false, true]) {
      test(
        '${cancelSession ? 'session' : 'turn'} cancel before resolver ends sends nothing and rejects late links',
        () async {
          final pending = Completer<List<acp.ContentBlock>>();
          CancellationToken? token;
          await withLinks(
            (session, traffic, _) async {
              final paths = ['a.ts'];
              final turn = session.prompt('see @a.ts', mentions: paths);
              paths.add('late.ts');
              await (cancelSession ? session.cancel() : turn.cancel());
              expect((await turn.result as TurnAnswered).cancelled, isTrue);
              expect(token!.isCancelled, isTrue);
              expect(sent(traffic, 'session/prompt'), isEmpty);
              expect(sent(traffic, 'session/cancel'), isEmpty);
              pending.complete([link('a.ts')]);
              await Future<void>.delayed(Duration.zero);
              expect(sent(traffic, 'session/prompt'), isEmpty);
              await session.prompt('text').result;
              expect(sent(traffic, 'session/prompt'), hasLength(1));
            },
            resolver: (paths, cwd, {cancellationToken}) {
              expect(paths, ['a.ts']);
              expect(() => paths.add('bad'), throwsUnsupportedError);
              token = cancellationToken;
              return pending.future;
            },
          );
        },
      );
    }
    test(
      'resolver failure preserves prompt and close cancels pending resolution',
      () async {
        await withLinks(
          (session, traffic, _) async {
            expect(
              await session.prompt('text', mentions: ['a']).result,
              isA<TurnAnswered>(),
            );
            expect(
              (sent(traffic, 'session/prompt').single['params']
                  as Map)['prompt'],
              [
                {'type': 'text', 'text': 'text'},
              ],
            );
          },
          resolver: (paths, cwd, {cancellationToken}) =>
              Future.error(StateError('walk failed')),
        );
        final pending = Completer<List<acp.ContentBlock>>();
        CancellationToken? token;
        await withLinks(
          (session, traffic, _) async {
            final turn = session.prompt('text', mentions: ['a']);
            await session.close();
            expect((await turn.result as TurnAnswered).cancelled, isTrue);
            expect(token!.isCancelled, isTrue);
            pending.completeError(StateError('late resolver error'));
            await Future<void>.delayed(Duration.zero);
            expect(sent(traffic, 'session/prompt'), isEmpty);
          },
          resolver: (paths, cwd, {cancellationToken}) {
            token = cancellationToken;
            return pending.future;
          },
        );
      },
    );
    test(
      'conversation preserves typed transcript and distinct contextual payload with links',
      () async {
        await withLinks((session, traffic, dir) async {
          await File(p.join(dir.path, 'a.ts')).writeAsString('');
          final conversation = Conversation(
            ({required onTraffic, required cancellationToken}) async => session,
          );
          final connected = Completer<void>(), ended = Completer<void>();
          final typed = <String>[];
          conversation.listen((event) {
            if (event is Connected) connected.complete();
            if (event case Transcribed(action: PromptAction(:final text))) {
              typed.add(text);
            }
            if (event case Transcribed(action: ResultAction())) {
              ended.complete();
            }
          });
          conversation.start();
          await connected.future;
          const text = 'see @a.ts';
          const payload = '<context>@not-a-link</context>\n\nsee @a.ts';
          expect(conversation.send(text, payload, mentionsIn(text)), isTrue);
          await ended.future;
          expect(typed, [text]);
          final blocks =
              ((sent(traffic, 'session/prompt').single['params']
                          as Map)['prompt']
                      as List)
                  .cast<Map>();
          expect(blocks.first['text'], payload);
          expect(blocks.skip(1).map((x) => x['name']), ['a.ts']);
          await conversation.close();
        });
      },
    );
  }, skip: fakeAgentSkip);
}
