import 'dart:async';
import 'dart:io';

import 'package:chord/acp_agent.dart';
import 'package:chord/mcp.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/place.dart';
import 'package:chord/session/sessions.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'acp_rig.dart';

const _chunk = {
  'sessionUpdate': 'agent_message_chunk',
  'content': {'type': 'text', 'text': 'early'},
};

void main() {
  test('initialize answers what the design says and starts no agent; the '
      'first capabilities stay', () {
    fakeAsync((async) {
      final rig = Rig(async);
      expect(rig.initialize({'plan': <String, Object?>{}}), {
        'protocolVersion': 1,
        'agentInfo': {'name': 'chord', 'version': '9.9.9'},
        'authMethods': <Object?>[],
        'agentCapabilities': {
          'auth': {'status': <String, Object?>{}},
          'loadSession': true,
          'promptCapabilities': {
            'image': true,
            'audio': false,
            'embeddedContext': true,
          },
          'mcpCapabilities': {'http': true, 'sse': true},
          'sessionCapabilities': {
            'list': <String, Object?>{},
            'resume': <String, Object?>{},
            'close': <String, Object?>{},
            'title': <String, Object?>{},
          },
        },
        '_meta': {
          'chord/acp': {
            'version': 1,
            'extensions': {
              'session/state': 1,
              'session/steer': 1,
              'agents': 1,
              'monitors': 1,
            },
            'agent': {'name': 'memory'},
          },
        },
      });
      rig.initialize({'subagents': <String, Object?>{}});
      expect(rig.agents, isEmpty);
      expect(rig.host.capabilities?.containsKey('plan'), isTrue);
      expect(rig.host.capabilities?.containsKey('subagents'), isFalse);
      rig.eof();
    });
  });

  test('session/new answers once the agent is up, with its configuration and '
      'what the agent takes', () {
    fakeAsync((async) {
      final rig = Rig(async)
        ..init = {
          'protocolVersion': 1,
          'agentCapabilities': {
            'promptCapabilities': {'image': true},
          },
        }
        ..newAnswer = {
          'modes': {
            'currentModeId': 'ask',
            'availableModes': [
              {'id': 'ask', 'name': 'Ask'},
            ],
          },
        };
      rig.initialize();
      final id = rig.request('session/new', {'cwd': '/w', 'mcpServers': []});
      expect(rig.answer(id), {
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'sessionId': 's1',
          'configOptions': [
            {
              'type': 'select',
              'id': 'mode',
              'name': 'Mode',
              'category': 'mode',
              'currentValue': 'ask',
              'options': [
                {'value': 'ask', 'name': 'Ask'},
              ],
            },
          ],
          '_meta': {
            'chord/acp': {'image': true, 'embeddedContext': false},
          },
        },
      });
      rig.eof();
    });
  });

  test('what a session says before the client has its id waits for the '
      'answer\'s line', () {
    fakeAsync((async) {
      final rig = Rig(async)..answerNew = false;
      rig.initialize();
      rig.lines.hold = true;
      final id = rig.request('session/new', {'cwd': '/w', 'mcpServers': []});
      final agent = rig.agents.single;
      final asked = agent.stdin.messages.lastWhere(
        (m) => m['method'] == 'session/new',
      );
      agent
        ..send({
          'jsonrpc': '2.0',
          'method': 'session/update',
          'params': {'sessionId': 's1', 'update': _chunk},
        })
        ..send({
          'jsonrpc': '2.0',
          'id': asked['id'],
          'result': {'sessionId': 's1'},
        });
      rig.settle();
      // Its answer is written, its flush still held: nothing more yet.
      expect(
        rig.lines.messages.map((m) => m['id'] ?? m['method']),
        isNot(contains('session/update')),
      );
      rig.lines.release();
      rig.settle();
      final order = [
        for (final m in rig.lines.messages)
          if (m['id'] == id) 'answer' else if (m['method'] != null) m['method'],
      ];
      expect(
        order.indexOf('answer'),
        lessThan(order.indexOf('session/update')),
      );
      // chord's commands follow, for an agent that sent none.
      expect(rig.notified('session/update').first, {
        'sessionId': 's1',
        'update': _chunk,
      });
      rig.eof();
    });
  });

  test('an agent that answers a second session with a live id is aliased', () {
    fakeAsync((async) {
      final rig = Rig(async)..sessionId = (_) => 'same';
      rig.initialize();
      expect(rig.newSession(), 'same');
      expect(rig.newSession(), 'same~2');
      expect(rig.newSession(), 'same~3');
      expect(rig.host.sessions.keys, ['same', 'same~2', 'same~3']);
      rig.eof();
    });
  });

  test('two servers of one name go as the later, in the earlier'
      's place', () {
    fakeAsync((async) {
      final rig = Rig(async);
      rig.initialize();
      Map<String, Object?> stdio(String name, String command) => {
        'name': name,
        'command': command,
        'args': <Object?>[],
        'env': <Object?>[],
      };
      rig.newSession(
        mcpServers: [
          stdio('docs', 'a'),
          stdio('files', 'f'),
          stdio('docs', 'b'),
        ],
      );
      final asked = rig.agents.single.stdin.messages.lastWhere(
        (m) => m['method'] == 'session/new',
      );
      expect((asked['params'] as Map)['mcpServers'], [
        stdio('docs', 'b'),
        stdio('files', 'f'),
      ]);
      rig.eof();
    });
  });

  test("the directory's servers go first, a client's of the same name in "
      'its place', () {
    fakeAsync((async) {
      Map<String, Object?> stdio(String name, String command) => {
        'name': name,
        'command': command,
        'args': <Object?>[],
        'env': <Object?>[],
      };
      final rig = Rig(
        async,
        place: (cwd) async => (
          cwd: cwd,
          start: SessionStart(
            command: 'memory',
            mcpServers: [
              DefinedServer(stdio('docs', 'file'), '/w/.mcp.json'),
              DefinedServer(stdio('team', 'ours'), '/w/.mcp.json'),
            ],
          ),
        ),
      );
      rig.initialize();
      rig.newSession(
        mcpServers: [stdio('client', 'c'), stdio('docs', 'client')],
      );
      final asked = rig.agents.single.stdin.messages.lastWhere(
        (m) => m['method'] == 'session/new',
      );
      expect((asked['params'] as Map)['mcpServers'], [
        stdio('docs', 'client'),
        stdio('team', 'ours'),
        stdio('client', 'c'),
      ]);
      rig.eof();
    });
  });

  test('an MCP server over acp is refused before anything starts', () {
    fakeAsync((async) {
      final rig = Rig(async);
      rig.initialize();
      final id = rig.request('session/new', {
        'cwd': '/w',
        'mcpServers': [
          {'type': 'acp', 'name': 'peer', 'serverId': 'p'},
        ],
      });
      expect(rig.answer(id)!['error'], {
        'code': -32602,
        'message':
            'Invalid params: MCP server peer has an acp transport, which '
            'chord does not take from a client.',
      });
      expect(rig.agents, isEmpty);
      rig.eof();
    });
  });

  test('a command refused in the session\'s directory is -32603 with the '
      'refusal, and nothing starts', () {
    fakeAsync((async) {
      final rig = Rig(
        async,
        place: (cwd) async => (
          cwd: cwd,
          start: const SessionStart(refused: 'memory not started: refused'),
        ),
      );
      rig.initialize();
      final id = rig.request('session/new', {'cwd': '/w', 'mcpServers': []});
      expect(rig.answer(id)!['error'], {
        'code': -32603,
        'message': 'memory not started: refused',
      });
      expect(rig.agents, isEmpty);
      rig.eof();
    });
  });

  test('an agent that fails to start is -32603 with what to do, and chord '
      'goes on serving', () {
    fakeAsync((async) {
      final rig = Rig(async)..answerNew = false;
      rig.initialize();
      final id = rig.request('session/new', {'cwd': '/w', 'mcpServers': []});
      final agent = rig.agents.single;
      final asked = agent.stdin.messages.lastWhere(
        (m) => m['method'] == 'session/new',
      );
      agent.send({
        'jsonrpc': '2.0',
        'id': asked['id'],
        'error': {'code': -32603, 'message': 'no model'},
      });
      rig.settle();
      async.elapse(const Duration(seconds: 2));
      rig.settle();
      final error = rig.answer(id)!['error'] as Map;
      expect(error['code'], -32603);
      expect(error['message'], contains('no model'));
      expect((error['data'] as Map)['lines'], isA<List<Object?>>());
      expect(rig.host.sessions, isEmpty);
      rig.answerNew = true;
      expect(rig.newSession(), 's1');
      rig.eof();
    });
  });

  test('an agent that needs a sign-in is -32000, with its ways in', () {
    fakeAsync((async) {
      final rig = Rig(async)
        ..answerNew = false
        ..init = {
          'protocolVersion': 1,
          'authMethods': [
            {'id': 'login', 'name': 'Log in'},
          ],
        };
      rig.initialize();
      final id = rig.request('session/new', {'cwd': '/w', 'mcpServers': []});
      final agent = rig.agents.single;
      final asked = agent.stdin.messages.lastWhere(
        (m) => m['method'] == 'session/new',
      );
      agent.send({
        'jsonrpc': '2.0',
        'id': asked['id'],
        'error': {'code': -32000, 'message': 'Authentication required'},
      });
      rig.settle();
      async.elapse(const Duration(seconds: 2));
      rig.settle();
      final error = rig.answer(id)!['error'] as Map;
      expect(error['code'], -32000);
      expect(
        ((error['data'] as Map)['lines'] as List).join('\n'),
        contains('Log in'),
      );
      rig.eof();
    });
  });

  test('a cancel while the agent starts closes it and answers -32800', () {
    fakeAsync((async) {
      final rig = Rig(async)..answerNew = false;
      rig.initialize();
      final id = rig.request('session/new', {'cwd': '/w', 'mcpServers': []});
      rig.send({
        'jsonrpc': '2.0',
        'method': r'$/cancel_request',
        'params': {'requestId': id},
      });
      async.elapse(const Duration(seconds: 2));
      rig.settle();
      expect(rig.answer(id)!['error'], {
        'code': -32800,
        'message': 'Request cancelled',
        'data': {'requestId': id},
      });
      expect(rig.agents.single.signals, isNotEmpty);
      rig.eof();
    });
  });

  test('a signal while the place is read admits nothing and starts no '
      'agent', () {
    fakeAsync((async) {
      final reading = Completer<AcpPlace>();
      final rig = Rig(async, place: (cwd) => reading.future);
      rig.initialize();
      final id = rig.request('session/new', {'cwd': '/w', 'mcpServers': []});
      rig.host.leave(const LeaveSignal(ProcessSignal.sigterm));
      reading.complete((cwd: '/w', start: const SessionStart(command: 'x')));
      rig.settle();
      // Whether its answer reaches the client before the way out closes the
      // connection, it is the refusal, and no agent started.
      if (rig.answer(id) case final answer?) {
        expect(answer['error'], {
          'code': -32603,
          'message': 'chord is closing',
        });
      }
      expect(rig.agents, isEmpty);
      async.elapse(const Duration(seconds: 20));
      expect(rig.exits, [const LeaveExit.signal(ProcessSignal.sigterm)]);
    });
  });

  test('a way out begun as the place is read leaves no agent it does not '
      'own', () {
    fakeAsync((async) {
      final reading = Completer<AcpPlace>();
      late Rig rig;
      // Heard before chord's own continuation: the way out begins in a
      // microtask between the place's last check and the start.
      reading.future.then(
        (_) => scheduleMicrotask(
          () => rig.host.leave(const LeaveSignal(ProcessSignal.sigterm)),
        ),
      );
      rig = Rig(async, place: (cwd) => reading.future);
      rig.initialize();
      rig.request('session/new', {'cwd': '/w', 'mcpServers': []});
      reading.complete((cwd: '/w', start: const SessionStart(command: 'x')));
      rig.settle();
      async.elapse(const Duration(seconds: 20));
      rig.settle();
      // Admitted before it began, an agent is the way out's to stop; begun
      // first, none starts. Either way the request is refused.
      for (final agent in rig.agents) {
        expect(agent.stdin.closed || agent.signals.isNotEmpty, isTrue);
      }
      expect(rig.answer(2)!['error'], {
        'code': -32603,
        'message': 'chord is closing',
      });
      expect(rig.exits, [const LeaveExit.signal(ProcessSignal.sigterm)]);
    });
  });

  test('a session opening when a signal comes is refused -32603, and its '
      'agent closed', () {
    fakeAsync((async) {
      final rig = Rig(async)..answerNew = false;
      rig.initialize();
      final id = rig.request('session/new', {'cwd': '/w', 'mcpServers': []});
      rig.host.leave(const LeaveSignal(ProcessSignal.sigint));
      rig.settle();
      expect(rig.answer(id)!['error'], {
        'code': -32603,
        'message': 'chord is closing',
      });
      async.elapse(const Duration(seconds: 20));
      rig.settle();
      expect(rig.agents.single.signals, isNotEmpty);
      expect(rig.exits, [const LeaveExit.signal(ProcessSignal.sigint)]);
      expect(rig.groups.kills, 1);
    });
  });

  test('session/close stops the agent, keeps nothing open, and an unknown '
      'id is -32002', () {
    fakeAsync((async) {
      final rig = Rig(async);
      rig.initialize();
      final sessionId = rig.newSession();
      final id = rig.request('session/close', {'sessionId': sessionId});
      async.elapse(const Duration(seconds: 2));
      rig.settle();
      expect(rig.answer(id)!['result'], <String, Object?>{});
      expect(rig.host.sessions, isEmpty);
      expect(rig.agents.single.stdin.closed, isTrue);
      final again = rig.request('session/close', {'sessionId': sessionId});
      expect(rig.answer(again)!['error'], {
        'code': -32002,
        'message': 'Resource not found',
        'data': {'sessionId': sessionId},
      });
      rig.eof();
    });
  });

  // CTUI-114: a session's close begun in one error zone (here the whole
  // host's, as an event heard in chord's begins one) and failing must not
  // hold the way out, run from another, to its deadline.
  test('a session close begun in another error zone, failing as the way '
      'out waits for it, does not hold it to the deadline', () {
    fakeAsync((async) {
      late Rig rig;
      runZonedGuarded(() => rig = Rig(async), (_, _) {});
      rig.exitOnSignal = false;
      rig.initialize();
      final sessionId = rig.newSession();
      rig.request('session/close', {'sessionId': sessionId});
      async.elapse(const Duration(milliseconds: 50));
      rig.host.leave(const LeaveEof()).ignore();
      async.elapse(const Duration(seconds: 20));
      rig.settle();
      expect(rig.exits, [const LeaveExit.code(1)]);
      expect(rig.said, isNot(contains(startsWith('chord: not settled'))));
    });
  });

  test('session/list gives the startup agent\'s records, one page', () {
    fakeAsync((async) {
      final rig = Rig(
        async,
        records: () async => [
          SessionRecord(
            path: '/state/a.jsonl',
            sessionId: 'a',
            agent: 'memory',
            cwd: '/w',
            prompt: 'Fix the parser',
            lastUsedAt: 0,
          ),
          SessionRecord(
            path: '/state/b.jsonl',
            sessionId: 'b',
            agent: 'other',
            cwd: '/w',
            prompt: 'Not ours',
            lastUsedAt: 0,
          ),
        ],
      );
      rig.initialize();
      final id = rig.request('session/list', {});
      expect(rig.answer(id)!['result'], {
        'sessions': [
          {
            'sessionId': 'a',
            'cwd': '/w',
            'title': 'Fix the parser',
            'updatedAt': '1970-01-01T00:00:00.000Z',
          },
        ],
      });
      rig.eof();
    });
  });

  test('chord acp declares its set toward the agent, notices as the client '
      'did', () {
    fakeAsync((async) {
      final rig = Rig(async);
      rig.initialize({
        'session': {'notices': <String, Object?>{}},
      });
      rig.newSession();
      expect(rig.declared.single?.toJson(), {
        'elicitation': {
          'form': <String, Object?>{},
          'url': <String, Object?>{},
        },
        'plan': <String, Object?>{},
        'session': {
          'compaction': <String, Object?>{},
          'notices': <String, Object?>{},
        },
        'subagents': <String, Object?>{},
        '_meta': {'terminal_output_delta': true},
      });
      rig.eof();
    });
  });

  test('EOF with nothing open exits 0; an agent left is closed first', () {
    fakeAsync((async) {
      final rig = Rig(async);
      rig.initialize();
      rig.newSession();
      rig.eof();
      expect(rig.agents.single.stdin.closed, isTrue);
      expect(rig.exits, [const LeaveExit.code(0)]);
      expect(rig.lines.closed, isTrue);
    });
  });

  test('a line over 32 MiB is broken: exit 1, said on stderr', () {
    fakeAsync((async) {
      final rig = Rig(async);
      rig.input.add(List.filled(32 * 1024 * 1024 + 1, 0x20));
      rig.settle();
      async.elapse(const Duration(seconds: 20));
      expect(rig.exits, [const LeaveExit.code(1)]);
      expect(
        rig.said,
        contains(
          'chord: the connection closed: Incoming ACP data exceeds the '
          'configured 33554432 byte limit',
        ),
      );
    });
  });

  test('the by-hand note is for a terminal alone', () {
    expect(byHandNote(stdinIsTerminal: false), isEmpty);
    expect(byHandNote(stdinIsTerminal: true), [
      'chord: acp serves ACP on stdin and stdout, for a client that starts it.',
      'chord: nothing to press here. Ctrl-D or Ctrl-C leaves; `chord` opens a '
          'window.',
    ]);
  });
  group('tester U10 host admission boundaries', () {
    for (final signal in [false, true]) {
      test(
        '${signal ? 'signal' : 'EOF'} during a held place read admits nothing',
        () {
          fakeAsync((async) {
            final held = Completer<AcpPlace>();
            final rig = Rig(async, place: (_) => held.future);
            rig.initialize();
            final id = rig.request('session/new', {
              'cwd': '/held',
              'mcpServers': [],
            });
            expect(rig.agents, isEmpty);
            if (signal) {
              rig.host.leave(const LeaveSignal(ProcessSignal.sigterm));
              rig.settle();
              async.elapse(const Duration(seconds: 20));
            } else {
              rig.eof();
            }
            expect(rig.host.leaving, isTrue);
            held.complete((
              cwd: '/held',
              start: const SessionStart(command: 'memory'),
            ));
            rig.settle();
            expect(rig.agents, isEmpty);
            expect(rig.host.sessions, isEmpty);
            expect(rig.exits, [
              signal
                  ? const LeaveExit.signal(ProcessSignal.sigterm)
                  : const LeaveExit.code(0),
            ]);
            if (signal) {
              expect(rig.answer(id), {
                'jsonrpc': '2.0',
                'id': id,
                'error': {'code': -32603, 'message': 'chord is closing'},
              });
            } else {
              expect(rig.answer(id), isNull);
            }
          });
        },
      );
    }

    test('a crash rejects every held open by id before any place settles', () {
      fakeAsync((async) {
        final held = Completer<AcpPlace>();
        final rig = Rig(async, place: (_) => held.future);
        rig.initialize();
        for (final id in <Object?>[null, 7, '7']) {
          rig.send({
            'jsonrpc': '2.0',
            'id': id,
            'method': 'session/new',
            'params': {'cwd': '/held', 'mcpServers': []},
          });
        }
        rig.host.leave(const LeaveCrash());
        rig.settle();
        for (final id in <Object?>[null, 7, '7']) {
          expect(rig.answer(id), {
            'jsonrpc': '2.0',
            'id': id,
            'error': {'code': -32603, 'message': 'chord is closing'},
          });
        }
        expect(rig.agents, isEmpty);
        expect(rig.lines.closed, isTrue);
        final count = rig.lines.messages.length;
        held.complete((
          cwd: '/held',
          start: const SessionStart(command: 'memory'),
        ));
        rig.settle();
        expect(rig.agents, isEmpty);
        expect(rig.lines.messages, hasLength(count));
        expect(rig.exits, [const LeaveExit.code(1)]);
        expect(async.nonPeriodicTimerCount, 0);
      });
    });

    test('a cancelled directory read does not hold another session open', () {
      fakeAsync((async) {
        final held = Completer<AcpPlace>();
        final rig = Rig(
          async,
          place: (cwd) => cwd == '/held' ? held.future : anyPlace(cwd),
        );
        rig.initialize();
        final cancelled = rig.request('session/new', {
          'cwd': '/held',
          'mcpServers': [],
        });
        rig.send({
          'jsonrpc': '2.0',
          'method': r'$/cancel_request',
          'params': {'requestId': cancelled},
        });
        final live = rig.newSession(cwd: '/ready');
        expect(rig.agents, hasLength(1));
        held.complete((
          cwd: '/held',
          start: const SessionStart(command: 'memory'),
        ));
        rig.settle();
        expect((rig.answer(cancelled)!['error'] as Map)['code'], -32800);
        expect(rig.agents, hasLength(1));
        expect(rig.host.sessions.keys, [live]);
        rig.eof();
        expect(rig.agents.single.stdin.closed, isTrue);
        expect(async.nonPeriodicTimerCount, 0);
      });
    });

    test(
      'closing one aliased session leaves the others open and names reusable',
      () {
        fakeAsync((async) {
          final rig = Rig(async)..sessionId = (_) => 'same/id';
          rig.initialize();
          final first = rig.newSession();
          final second = rig.newSession();
          final close = rig.request('session/close', {'sessionId': first});
          async.elapse(const Duration(seconds: 1));
          rig.settle();
          expect(rig.answer(close)!['result'], <String, Object?>{});
          expect(rig.host.sessions.keys, [second]);
          expect(rig.agents[1].stdin.closed, isFalse);
          final third = rig.newSession();
          expect(third, first);
          expect(rig.host.sessions.keys, [second, third]);
          rig.eof();
          expect(rig.agents.every((a) => a.stdin.closed), isTrue);
          expect(rig.groups.kills, 1);
          expect(async.nonPeriodicTimerCount, 0);
        });
      },
    );
  });
}
