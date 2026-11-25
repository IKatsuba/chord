import 'dart:async';
import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart' as mcp;
import 'package:test/test.dart';

import '../options.dart' as options;
import '../rpc.dart';
import '../sessions.dart';
import '../turn.dart';
import 'chord_tools.dart';

final class _CapturedUpdates {
  _CapturedUpdates() {
    connection = Connection.serve(
      input.stream,
      (bytes) {
        final message = jsonDecode(utf8.decode(bytes)) as Map;
        updates.add(((message['params'] as Map)['update'] as Map));
      },
      () async {},
      requests: {},
      notifications: {},
    );
  }

  final input = StreamController<List<int>>();
  final updates = <Map>[];
  late final Connection connection;

  Future<void> close() async {
    await input.close();
    await connection.closed;
  }
}

final class _Mcp extends mcp.McpClient {
  _Mcp(this.answer)
    : super(const mcp.Implementation(name: 'tester', version: '0.0.0'));

  final Future<mcp.CallToolResult> answer;
  final called = Completer<void>();
  mcp.CallToolRequest? lastRequest;
  mcp.RequestOptions? lastOptions;

  @override
  Future<mcp.CallToolResult> callTool(
    mcp.CallToolRequest params, {
    mcp.RequestOptions? options,
  }) {
    lastRequest = params;
    lastOptions = options;
    called.complete();
    return answer;
  }
}

void main() {
  group('tester: CTUI-147 structured MCP rejection wording', () {
    for (final code in [-32601, -32602, -32000]) {
      test(
        'error $code keeps its code and message without appending data',
        () async {
          await expectLater(
            asOriginal<void>(() async {
              throw mcp.McpError(code, 'Fixture refusal', {
                'detail': 'not in the message',
              });
            }),
            throwsA(
              isA<McpFailure>()
                  .having(
                    (error) => error.message,
                    'message',
                    'MCP error $code: Fixture refusal',
                  )
                  .having(
                    (error) => error.toString(),
                    'text',
                    'MCP error $code: Fixture refusal',
                  ),
            ),
          );
        },
      );
    }

    test('a successful result keeps its identity', () async {
      final result = Object();
      expect(await asOriginal(() async => result), same(result));
    });

    test('a non-MCP failure keeps its original identity', () async {
      final error = StateError('transport failed');
      await expectLater(
        asOriginal<void>(() async => throw error),
        throwsA(same(error)),
      );
    });

    test('a rejected tool call leaves only the pending announcement', () async {
      options.args = ['--step-ms', '0'];
      final captured = _CapturedUpdates();
      addTearDown(captured.close);
      final reply = Completer<mcp.CallToolResult>();
      final client = _Mcp(reply.future);
      addTearDown(client.close);
      final turn = Turn(
        captured.connection.client,
        'tester-refused',
        Aborter().signal,
      );
      final result = callChord(turn, client, 'missing_tool', {});
      final failed = expectLater(
        result,
        throwsA(
          isA<McpFailure>().having(
            (error) => error.message,
            'message',
            'MCP error -32601: Tool not found',
          ),
        ),
      );
      await client.called.future;
      reply.completeError(
        mcp.McpError(-32601, 'Tool not found', {'detail': 'internal'}),
      );
      await failed;
      expect(captured.updates, hasLength(1));
      expect(captured.updates.single['status'], 'pending');
    });
  });

  group('tester: CTUI-147 MCP call results and cancellation options', () {
    setUp(() => options.args = ['--step-ms', '0']);
    for (final shape in ['claude', 'codex']) {
      for (final failed in [false, true]) {
        test(
          '$shape ${failed ? 'failure' : 'success'} retains text and call identity',
          () async {
            final captured = _CapturedUpdates();
            addTearDown(captured.close);
            final client = _Mcp(
              Future.value(
                mcp.CallToolResult(
                  content: const [
                    mcp.TextContent(text: 'first'),
                    mcp.ImageContent(data: 'AA==', mimeType: 'image/png'),
                    mcp.TextContent(text: 'second'),
                  ],
                  isError: failed,
                ),
              ),
            );
            addTearDown(client.close);
            final turn = Turn(
              captured.connection.client,
              'tester-mcp',
              Aborter().signal,
            );
            expect(
              await callChord(turn, client, 'get_budgets', {
                'n': 1,
              }, shape: shape),
              failed ? null : 'firstsecond',
            );
            expect(client.lastRequest!.name, 'get_budgets');
            expect(client.lastRequest!.arguments, {'n': 1});
            expect(captured.updates, hasLength(2));
            final pending = captured.updates.first;
            final completed = captured.updates.last;
            expect(pending['status'], 'pending');
            expect(
              pending['title'],
              shape == 'claude'
                  ? 'mcp__chord__get_budgets'
                  : 'mcp.chord.get_budgets',
            );
            expect(completed['toolCallId'], pending['toolCallId']);
            expect(completed['status'], failed ? 'failed' : 'completed');
            expect(((completed['content'] as List).single as Map)['content'], {
              'type': 'text',
              'text': 'firstsecond',
            });
          },
        );
      }
    }

    for (final timeout in <int?>[null, 123]) {
      test(
        'timeout $timeout forwards cancellation only when explicit',
        () async {
          final captured = _CapturedUpdates();
          addTearDown(captured.close);
          final answer = Completer<mcp.CallToolResult>();
          final client = _Mcp(answer.future);
          addTearDown(client.close);
          final abort = Aborter();
          final turn = Turn(
            captured.connection.client,
            'tester-cancel',
            abort.signal,
          );
          final result = callChord(
            turn,
            client,
            'monitor',
            {},
            timeout: timeout,
          );
          final reason = StateError('tester stopped');
          final failed = expectLater(result, throwsA(same(reason)));
          await client.called.future;
          expect(
            client.lastOptions!.timeout,
            Duration(milliseconds: timeout ?? 60000),
          );
          abort.abort(reason);
          if (timeout == null) {
            expect(client.lastOptions!.signal, isNull);
          } else {
            expect(client.lastOptions!.signal!.aborted, isTrue);
            expect(client.lastOptions!.signal!.reason, same(reason));
          }
          answer.complete(const mcp.CallToolResult(content: []));
          await failed;
          expect(captured.updates, hasLength(1));
        },
      );
    }

    test(
      'lookalike names and non-HTTP entries supply no chord client',
      () async {
        const sessionId = 'tester-no-server';
        mcpServers[sessionId] = [
          {'name': 'chord-1-extra', 'type': 'http', 'url': 'http://invalid'},
          {'name': 'not-chord', 'type': 'http', 'url': 'http://invalid'},
          {
            'name': 'chord',
            'command': 'never-start-this',
            'args': [],
            'env': [],
          },
        ];
        addTearDown(() => mcpServers.remove(sessionId));
        final captured = _CapturedUpdates();
        addTearDown(captured.close);
        expect(
          await chordClient(
            Turn(captured.connection.client, sessionId, Aborter().signal),
          ),
          isNull,
        );
      },
    );
  });
}
