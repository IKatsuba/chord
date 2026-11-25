// dimcode's notice under `chord -p`: once, at the start or as a
// config_option_update moves its permission option, in the handed order
// (the original's src/session/oneshot.ts:179-199).

import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart' show MemoryAgentProcess;
import 'package:chord/notices.dart';
import 'package:chord/session/oneshot.dart';
import 'package:chord/session/session.dart' show SessionOpener;
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

Map<String, Object?> _permission(String current) => {
  'id': 'permission',
  'name': 'Permission',
  'type': 'select',
  'currentValue': current,
  'options': [
    for (final v in ['read-only', 'workspace-write', 'full-access'])
      {'value': v, 'name': v},
  ],
};

/// An agent in memory whose session starts with dimcode's permission option
/// at [start] (none when null) and which, during the turn, says "before",
/// moves the option through [moves], then says "after".
final class NoticeAgent {
  NoticeAgent({this.start, this.moves = const []}) {
    process = MemoryAgentProcess(
      onSignal: (signal) {
        if (process.exited) return;
        process.exit(const Exit(143, 'SIGTERM'));
        process.closeStdout();
        process.closeStderr();
      },
    );
  }

  final String? start;
  final List<String> moves;
  late final MemoryAgentProcess process;
  final _answered = <Object?>{};

  /// Opens the agent above, wherever chord asks.
  SessionOpener get open =>
      ({
        required command,
        env,
        required cwd,
        required onTraffic,
        required onPermission,
        relay,
        cancellationToken,
      }) => connectAgent(
        process,
        onTraffic: onTraffic,
        onPermission: onPermission,
        relay: relay,
        cancellationToken: cancellationToken,
      );

  void _send(Map<String, Object?> message) =>
      process.send({'jsonrpc': '2.0', ...message});

  void _update(Map<String, Object?> update) => _send({
    'method': 'session/update',
    'params': {'sessionId': 's1', 'update': update},
  });

  void _say(String text) => _update({
    'sessionUpdate': 'agent_message_chunk',
    'content': {'type': 'text', 'text': text},
  });

  /// Answers what chord asked since the last step.
  void step() {
    for (final message in [...process.stdin.messages]) {
      final id = message['id'];
      if (id == null || message['method'] == null || !_answered.add(id)) {
        continue;
      }
      switch (message['method']) {
        case 'initialize':
          _send({
            'id': id,
            'result': {'protocolVersion': 1},
          });
        case 'session/new':
          _send({
            'id': id,
            'result': {
              'sessionId': 's1',
              'configOptions': [if (start case final at?) _permission(at)],
            },
          });
        case 'session/prompt':
          _say('before');
          for (final at in moves) {
            _update({
              'sessionUpdate': 'config_option_update',
              'configOptions': [_permission(at)],
            });
            _say('moved $at');
          }
          _say('after');
          _send({
            'id': id,
            'result': {'stopReason': 'end_turn'},
          });
        default:
          _send({'id': id, 'result': <String, Object?>{}});
      }
    }
  }

  /// Drives [run] to its end under fake time, stepping the agent.
  void drive(FakeAsync async, Future<void> run) {
    var done = false;
    run.then((_) => done = true);
    for (var i = 0; i < 300 && !done; i++) {
      async.flushMicrotasks();
      step();
      async.elapse(const Duration(milliseconds: 100));
    }
    expect(done, isTrue);
    expect(process.exited, isTrue);
  }
}

/// What a one-shot turn of [agent], run as [name], handed on, in order.
List<String> _heard(NoticeAgent agent, {String name = 'dimcode'}) {
  final heard = <String>[];
  fakeAsync((async) {
    agent.drive(
      async,
      runOneshot(
        agent: name,
        command: 'memory',
        cwd: '/w',
        prompt: 'hello',
        open: agent.open,
        onRefused: (_) {},
        onUpdate: (update) {
          if (update.toJson()['content'] case {'text': final String text}) {
            heard.add(text);
          }
        },
        onNotice: (paragraphs) {
          expect(paragraphs, dimcodeWords.paragraphs);
          heard.add('notice');
        },
      ),
    );
  });
  return heard;
}

void main() {
  test('a session at full-access from the start hears it first, once', () {
    expect(
      _heard(NoticeAgent(start: 'full-access', moves: ['workspace-write'])),
      ['notice', 'before', 'moved workspace-write', 'after'],
    );
  });

  test('an update out of read-only says it there, in the reply\'s order', () {
    expect(
      _heard(NoticeAgent(start: 'read-only', moves: ['workspace-write'])),
      ['before', 'notice', 'moved workspace-write', 'after'],
    );
  });

  test('back to read-only and out again still says it only once', () {
    expect(
      _heard(
        NoticeAgent(start: 'full-access', moves: ['read-only', 'full-access']),
      ),
      ['notice', 'before', 'moved read-only', 'moved full-access', 'after'],
    );
  });

  test('read-only throughout, no such option, or another agent: nothing', () {
    for (final (agent, name) in [
      (NoticeAgent(start: 'read-only', moves: ['read-only']), 'dimcode'),
      (NoticeAgent(), 'dimcode'),
      (NoticeAgent(start: 'full-access'), 'codex'),
    ]) {
      expect(_heard(agent, name: name), isNot(contains('notice')));
    }
  });
}
