// The conversation over a real session on an agent in memory, its bytes
// exact: what no scenario of the fake agent plays.
import 'dart:convert';

import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart' show MemoryAgentProcess;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'transcript/fold.dart';

String _line(Map<String, Object?> message) => '${jsonEncode(message)}\n';

String _chunk(String text) => _line({
  'jsonrpc': '2.0',
  'method': 'session/update',
  'params': {
    'sessionId': 's1',
    'update': {
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': text},
    },
  },
});

/// A conversation on an agent in memory, connected, under [async]; [play]
/// gets the process, the id of the prompt `p` it sent, the conversation
/// and the window's state as it stands.
AppState _played(
  FakeAsync async,
  void Function(
    MemoryAgentProcess process,
    Object? promptId,
    Conversation conversation,
    AppState Function() state,
  )
  play,
) {
  late final MemoryAgentProcess process;
  process = MemoryAgentProcess(
    onSignal: (signal) {
      process.exit(const Exit(143, 'SIGTERM'));
      process.closeStdout();
      process.closeStderr();
    },
  );
  List<Map<String, Object?>> written() => process.stdin.messages;
  Object? idOf(String method) =>
      written().lastWhere((m) => m['method'] == method)['id'];
  void answer(Object? id, Map<String, Object?> result) =>
      process.send({'jsonrpc': '2.0', 'id': id, 'result': result});

  var state = AppState.starting;
  final conversation = Conversation(
    ({required onTraffic, required cancellationToken}) => openSession(
      agent: 'memory',
      command: 'memory',
      cwd: '/w',
      open:
          ({
            required command,
            env,
            required cwd,
            required onTraffic,
            required onPermission,
            relay,
            cancellationToken,
          }) {
            // As openAgent's spawn does, stderr reaches the tap.
            process.onStderr = (text) => onTraffic(Traffic.stderr(text));
            return connectAgent(
              process,
              onTraffic: onTraffic,
              onPermission: onPermission,
              relay: relay,
            );
          },
      onTraffic: onTraffic,
    ),
  )..listen((event) => state = reduceApp(state, event));

  conversation.start();
  async.flushMicrotasks();
  answer(idOf('initialize'), {'protocolVersion': 1});
  async.flushMicrotasks();
  answer(idOf('session/new'), {'sessionId': 's1'});
  async.flushMicrotasks();
  conversation.send('p');
  async.flushMicrotasks();
  play(process, idOf('session/prompt'), conversation, () => state);
  async.elapse(const Duration(seconds: 2));

  final played = state;

  conversation.close();
  async.elapse(const Duration(seconds: 5));
  return played;
}

void main() {
  // ACP has the client send session/cancel and then answer what the agent
  // asked as cancelled; an agent that hears the answer first may go on and
  // end its turn as though nothing were interrupted.
  // The running turn's id, as the window knows it.
  String running(AppState state) => switch (state.transcript.turn) {
    model.Working(:final turnId) ||
    model.AwaitingPermission(:final turnId) => turnId,
    final other => throw StateError('no running turn: $other'),
  };
  for (final (kind, asked, answer) in [
    (
      'permission',
      <String, Object?>{
        'method': 'session/request_permission',
        'params': {
          'sessionId': 's1',
          'toolCall': {'toolCallId': 'write-3', 'title': 'Write notes.txt'},
          'options': [
            {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
          ],
        },
      },
      <String, Object?>{
        'outcome': {'outcome': 'cancelled'},
      },
    ),
    (
      'form',
      <String, Object?>{
        'method': 'elicitation/create',
        'params': {
          'sessionId': 's1',
          'mode': 'form',
          'message': 'Set up the deploy target',
          'requestedSchema': {
            'type': 'object',
            'properties': <String, Object?>{},
          },
        },
      },
      <String, Object?>{'action': 'cancel'},
    ),
  ]) {
    for (final (how, stop) in <(String, void Function(Conversation, String))>[
      ('an interrupt', (conversation, _) => conversation.interrupt()),
      (
        'taking the running prompt back',
        (conversation, turnId) => conversation.cancelPrompt(turnId),
      ),
    ]) {
      test('$how with a $kind waiting sends session/cancel before '
          'it answers the $kind cancelled', () {
        fakeAsync((async) {
          late List<Map<String, Object?>> after;
          _played(async, (process, _, conversation, state) {
            process.send({'jsonrpc': '2.0', 'id': 9, ...asked});
            async.flushMicrotasks();
            final from = process.stdin.messages.length;
            stop(conversation, running(state()));
            async.flushMicrotasks();
            after = process.stdin.messages.sublist(from);
          });
          expect(
            [
              for (final m in after)
                if (m['method'] == 'session/cancel')
                  'session/cancel'
                else if (m['id'] == 9)
                  m['result'],
            ],
            ['session/cancel', answer],
          );
        });
      });
    }
  }

  test('one read holding update, answer, update gives the transcript three '
      'reads give', () {
    String answerLine(Object? id) => _line({
      'jsonrpc': '2.0',
      'id': id,
      'result': {'stopReason': 'end_turn'},
    });
    late Map<String, Object?> one;
    late Map<String, Object?> three;

    fakeAsync((async) {
      one = described(
        _played(async, (process, id, _, _) {
          process.writeStdout(
            utf8.encode(_chunk('Hello') + answerLine(id) + _chunk(', world')),
          );
        }).transcript,
      );
    });
    fakeAsync((async) {
      three = described(
        _played(async, (process, id, _, _) {
          process.writeStdout(utf8.encode(_chunk('Hello')));
          async.flushMicrotasks();
          process.writeStdout(utf8.encode(answerLine(id)));
          async.flushMicrotasks();
          process.writeStdout(utf8.encode(_chunk(', world')));
        }).transcript,
      );
    });

    expect(one, three);
    expect(one['turn'], {'status': 'idle'});
    expect((one['entries'] as List).last, {
      'turnId': 'turn-1',
      'kind': 'assistant',
      'text': 'Hello, world',
    });
  });

  test("the window learns of an idle exit with the agent's stderr", () {
    fakeAsync((async) {
      final state = _played(async, (process, id, _, _) {
        process.send({
          'jsonrpc': '2.0',
          'id': id,
          'result': {'stopReason': 'end_turn'},
        });
        async.flushMicrotasks();
        process.writeStderr('first\nlast words\n');
        process.closeStderr();
        process.closeStdout();
        process.exit(const Exit(1));
      });

      expect(state.start.stderrLines, ['first', 'last words']);
      expect(state.start.reason, 'The agent exited.');
    });
  });
}
