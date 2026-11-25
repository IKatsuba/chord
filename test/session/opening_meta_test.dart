import 'dart:io';

import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart' show MemoryAgentProcess;
import 'package:chord/session/session.dart';
import 'package:chord/session/sessions.dart';
import 'package:test/test.dart';
import 'package:fake_async/fake_async.dart';

import '../acp_rig.dart';

const _claude = '@agentclientprotocol/claude-agent-acp';
const _off = {
  'claudeCode': {
    'options': {'promptSuggestions': false},
  },
};

/// An in-memory agent named [name] that offers load or resume, and fork,
/// and answers every request it is sent.
final class _Agent {
  _Agent(this.name, {this.load = true}) {
    process = MemoryAgentProcess(
      onSignal: (_) {
        process.exit();
        process.closeStdout();
        process.closeStderr();
      },
    );
  }

  final String name;
  final bool load;
  late final MemoryAgentProcess process;

  /// The params of the request that opened the session.
  Map<String, Object?>? opened;

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
        onTraffic: (traffic) {
          onTraffic(traffic);
          if (traffic case ChordTraffic(:final message)) _react(message);
        },
        onPermission: onPermission,
        relay: relay,
        cancellationToken: cancellationToken,
        stop: const StopBounds(
          exit: Duration.zero,
          term: Duration(milliseconds: 10),
          kill: Duration(milliseconds: 100),
        ),
      );

  void _react(Map<String, Object?> request) {
    if (!request.containsKey('id') || process.exited) return;
    final method = request['method'] as String?;
    final Object result = switch (method) {
      'initialize' => {
        'protocolVersion': 1,
        'agentInfo': {'name': name, 'version': '1'},
        'agentCapabilities': {
          'loadSession': load,
          'sessionCapabilities': {
            if (!load) 'resume': <String, Object?>{},
            'fork': <String, Object?>{},
          },
        },
      },
      'session/new' || 'session/fork' => {'sessionId': 'opened'},
      'session/prompt' => {'stopReason': 'end_turn'},
      _ => <String, Object?>{},
    };
    if (method != null && method.startsWith('session/') && opened == null) {
      opened = {
        'method': method,
        ...request['params']! as Map<String, Object?>,
      };
    }
    process.send({'jsonrpc': '2.0', 'id': request['id'], 'result': result});
  }
}

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('chord-opening-meta-');
  });
  tearDown(() => dir.delete(recursive: true));

  Future<Map<String, Object?>> opening(
    String name, {
    bool load = true,
    bool resume = false,
    bool fork = false,
  }) async {
    final agent = _Agent(name, load: load);
    final session = await openSession(
      agent: 'memory',
      command: 'memory',
      cwd: dir.path,
      open: agent.open,
      resume: resume ? Resume(sessionId: 'earlier', cwd: dir.path) : null,
      fork: fork ? 'earlier' : null,
    );
    await session.close();
    return agent.opened!;
  }

  group('tester: CTUI-87 opening identity boundaries', () {
    for (final name in [
      '',
      'claude',
      '$_claude ',
      ' $_claude',
      '@agentclientprotocol/CLAUDE-agent-acp',
      '$_claude-fork',
    ]) {
      test('adapter lookalike "$name" receives no private options', () async {
        for (final (load, resume, fork) in [
          (true, false, false),
          (true, true, false),
          (false, true, false),
          (true, false, true),
        ]) {
          expect(
            (await opening(
              name,
              load: load,
              resume: resume,
              fork: fork,
            )).containsKey('_meta'),
            isFalse,
          );
        }
      });
    }

    for (final (method, load) in [
      ('session/new', true),
      ('session/load', true),
      ('session/resume', false),
    ]) {
      test('hosted $method derives metadata per initialized upstream', () {
        fakeAsync((async) {
          final rig = Rig(async)
            ..initOf = (index) => {
              'protocolVersion': 1,
              'agentInfo': {
                'name': index == 0 ? _claude : 'codex-acp',
                'version': '1',
              },
              'agentCapabilities': {
                'loadSession': load,
                if (!load)
                  'sessionCapabilities': {'resume': <String, Object?>{}},
              },
            };
          rig.initialize();
          for (var index = 0; index < 2; index++) {
            final id = rig.request(method, {
              'cwd': '/w',
              'mcpServers': <Object?>[],
              if (method != 'session/new') 'sessionId': 'past-$index',
            });
            expect(rig.answer(id)!['error'], isNull);
            final upstream = rig.agents[index].stdin.messages.singleWhere(
              (message) => message['method'] == method,
            );
            final params = upstream['params'] as Map;
            if (index == 0) {
              expect(params['_meta'], _off);
            } else {
              expect(params.containsKey('_meta'), isFalse);
            }
          }
          rig.eof();
          expect(rig.agents.every((agent) => agent.exited), isTrue);
        });
      });
    }
  });

  for (final (how, load, resume, fork, method) in [
    ('new', true, false, false, 'session/new'),
    ('loaded', true, true, false, 'session/load'),
    ('resumed', false, true, false, 'session/resume'),
    ('forked', true, false, true, 'session/fork'),
  ]) {
    test("Claude's adapter is asked for no prompt suggestions on a $how "
        'session; any other agent is sent no _meta', () async {
      final claude = await opening(
        _claude,
        load: load,
        resume: resume,
        fork: fork,
      );
      expect(claude['method'], method);
      expect(claude['_meta'], _off);

      final other = await opening(
        'codex-acp',
        load: load,
        resume: resume,
        fork: fork,
      );
      expect(other['method'], method);
      expect(other.containsKey('_meta'), isFalse);
    });
  }
}
