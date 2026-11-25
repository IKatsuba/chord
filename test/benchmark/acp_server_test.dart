import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/session/record.dart';
import 'package:test/test.dart';

import '../../benchmark/acp_server.dart' as bench;
import '../acp_client.dart';
import '../fixtures/fake_harness.dart';

void main() {
  group('tester U15 benchmark boundaries', () {
    test(
      'every header split and a long discarded tail preserve next requests',
      () {
        const header = '{"jsonrpc":"2.0","method":"session/prompt","id":42';
        for (var split = 0; split <= header.length; split++) {
          final heard = <(String, Object)>[];
          final input = bench.LeanInput(
            (method, id) => heard.add((method, id)),
          );
          input.add(utf8.encode(header.substring(0, split)));
          input.add(utf8.encode(header.substring(split)));
          for (var i = 0; i < 17; i++) {
            input.add(List.filled(bench.pipeRead, 120));
          }
          expect(heard, isEmpty);
          input.add(
            utf8.encode(
              '}\n{"jsonrpc":"2.0","method":"session/load","id":43}\n',
            ),
          );
          expect(heard, [
            ('session/prompt', 42),
            ('session/load', 43),
          ], reason: 'split $split');
          input.end();
        }
      },
    );

    test('multiple lines and a partial next header share one read', () async {
      final heard = <(String, Object)>[];
      final input = bench.LeanInput((method, id) => heard.add((method, id)));
      input.add(
        utf8.encode(
          '{"jsonrpc":"2.0","method":"initialize","id":1}\n{"jsonrpc":"2.0","method":"session/new","id":2}\n{"jsonrpc":',
        ),
      );
      input.add(utf8.encode('"2.0","method":"session/load","id":3}\n'));
      expect(heard, [
        ('initialize', 1),
        ('session/new', 2),
        ('session/load', 3),
      ]);
      input.end();
      input.end();
      await input.done;
    });

    test(
      'counting sink and its waiter agree on batched complete output',
      () async {
        final sink = bench.CountingSink(['"stopReason"', '"sessionId"']);
        var settled = false;
        final waiting = sink
            .until('"stopReason"', 2)
            .then((_) => settled = true);
        final first = utf8.encode('{"stopReason":"end_turn"}\n');
        final second = utf8.encode(
          '{"sessionId":"a"}\n{"stopReason":"cancelled"}\n',
        );
        sink.add(first);
        await Future<void>.delayed(Duration.zero);
        expect(settled, isFalse);
        sink.add(second);
        await waiting;
        expect(sink.counts, {'"stopReason"': 2, '"sessionId"': 1});
        expect(sink.lines, 3);
        expect(sink.bytes, first.length + second.length);
        await sink.until('"stopReason"', 2);
        await sink.flush();
        await sink.close();
      },
    );

    test(
      'ten thousand record chunks precede load answer in exact order',
      () async {
        final client = AcpClient();
        const id = '0b6f7c2e-1d3a-4c5b-9e8f-7a6b5c4d3e2f';
        final records = Directory(recordsDir(client.stateDir))
          ..createSync(recursive: true);
        final record = StringBuffer()
          ..write(
            encodeRecord({
              'type': 'session',
              'version': 1,
              'sessionId': id,
              'agent': 'fake',
              'cwd': client.cwd,
              'at': 1,
            }),
          );
        for (var turn = 0; turn < 100; turn++) {
          record.write(
            encodeRecord({
              'type': 'prompt',
              'turnId': 't$turn',
              'prompt': 'turn $turn',
              'images': 0,
              'at': turn + 2,
            }),
          );
          for (var index = turn * 100; index < (turn + 1) * 100; index++) {
            record.write(
              encodeRecord({
                'type': 'update',
                'turnId': 't$turn',
                'update': {
                  'sessionUpdate': 'agent_message_chunk',
                  'content': {'type': 'text', 'text': 'chunk $index'},
                },
              }),
            );
          }
          record.write(
            encodeRecord({
              'type': 'result',
              'turnId': 't$turn',
              'result': {'status': 'completed', 'stopReason': 'end_turn'},
            }),
          );
        }
        File('${records.path}/$id.jsonl').writeAsStringSync('$record');
        await client.initialize();
        final asked = client.ask('session/load', {
          'sessionId': id,
          'cwd': client.cwd,
          'mcpServers': <Object?>[],
        });
        expect((await client.answer(asked))['error'], isNull);
        final messages = client.lines.messages;
        final answer = messages.indexWhere(
          (m) => m['id'] == asked && !m.containsKey('method'),
        );
        final updates = [
          for (final m in messages.take(answer))
            if (m['method'] == 'session/update')
              (m['params'] as Map)['update'] as Map,
        ];
        expect(updates, hasLength(10100));
        expect(
          [
            for (final u in updates)
              if (u['sessionUpdate'] == 'agent_message_chunk')
                (u['content'] as Map)['text'],
          ],
          [for (var i = 0; i < 10000; i++) 'chunk $i'],
        );
        expect(
          messages
              .skip(answer + 1)
              .where(
                (m) =>
                    m['method'] == 'session/update' &&
                    ((m['params'] as Map)['update'] as Map)['sessionUpdate'] ==
                        'agent_message_chunk',
              ),
          isEmpty,
        );
        await client.request('session/close', {'sessionId': id});
        expect(client.host.sessions, isEmpty);
      },
      skip: fakeAgentSkip,
    );
  });
}
