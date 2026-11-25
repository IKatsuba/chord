// chord acp's agents extension in memory: `_chord/agents/send` and
// `_chord/agents/close` with the original's errors, `session/cancel` on a
// child and on a task, `/new` as a prompt and chord's command list, and
// `agents: 1` advertised now that all of them work.
import 'dart:io' show ProcessSignal;

import 'package:chord/acp/process.dart';
import 'package:chord/server/server.dart';
import 'package:chord/server/tools.dart';
import 'package:chord/session/leaving.dart' show LeaveSignal;
import 'package:chord/session/new_args.dart';
import 'package:chord/session/upstream_commands.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'acp_rig.dart';
import 'session/new_args_test.dart' show newArgsCases;

/// chord's server as the host uses it, keeping who was let in.
final class _Server implements ChordServer {
  final admitted = <String, Caller>{};
  var _tokens = 0;

  /// Heard as a child is let in, before its launch: what `/new` does while
  /// its work is still under way.
  void Function()? onChild;

  @override
  String get url => 'http://127.0.0.1:9/mcp';

  @override
  Admitted admit(Caller caller) {
    if (caller.role == Role.child) onChild?.call();
    final token = 'token-${++_tokens}';
    admitted[token] = caller;
    return (
      token: token,
      server: {
        'type': 'http',
        'name': 'chord',
        'url': url,
        'headers': <Object?>[],
      },
    );
  }

  @override
  void revoke(String token) {}

  @override
  Future<void> close() async {}

  /// The callers of main sessions, in the order they were let in.
  List<Caller> get mains => [
    for (final caller in admitted.values)
      if (caller.role == Role.person) caller,
  ];
}

const _send = '_chord/agents/send';
const _close = '_chord/agents/close';

Map<String, Object?> _text(String text) => {'type': 'text', 'text': text};

const _teamCommand = {
  'name': 'team',
  'description': 'Show and run teams of agents',
  'input': {
    'hint': 'list | run <name> <job> | show <name> | stop <run> | new <words>',
  },
};

const _newCommand = {
  'name': 'new',
  'description': 'Open a new agent beside main',
  'input': {'hint': '[agent] [--name <name>]'},
};

/// The agent's messages of [method], in order.
List<Map<String, Object?>> _asked(MemoryAgentProcess agent, String method) => [
  for (final message in agent.stdin.messages)
    if (message['method'] == method) message,
];

/// Answers the agent's last prompt with [stop].
void _endTurn(Rig rig, MemoryAgentProcess agent, [String stop = 'end_turn']) {
  agent.send({
    'jsonrpc': '2.0',
    'id': _asked(agent, 'session/prompt').last['id'],
    'result': {'stopReason': stop},
  });
  rig.settle();
}

void _update(
  Rig rig,
  MemoryAgentProcess agent,
  String sessionId,
  Map<String, Object?> update,
) {
  agent.send({
    'jsonrpc': '2.0',
    'method': 'session/update',
    'params': {'sessionId': sessionId, 'update': update},
  });
  rig.settle();
}

/// Every `subagent_update` chord sent of [child] under [parent].
List<Map<String, Object?>> _reports(Rig rig, String parent, String child) => [
  for (final params in rig.notified('session/update'))
    if (params['sessionId'] == parent)
      if (params['update'] case final Map<String, Object?> update
          when update['sessionUpdate'] == 'subagent_update' &&
              update['sessionId'] == child)
        update,
];

/// The command lists chord sent under [sessionId], in order.
List<List<Object?>> _lists(Rig rig, String sessionId) => [
  for (final params in rig.notified('session/update'))
    if (params['sessionId'] == sessionId)
      if (params['update'] case final Map<String, Object?> update
          when update['sessionUpdate'] == 'available_commands_update')
        update['availableCommands'] as List<Object?>,
];

/// The error of request [id]'s answer.
Map<String, Object?>? _error(Rig rig, int id) =>
    rig.answer(id)?['error'] as Map<String, Object?>?;

void main() {
  late Rig rig;
  late _Server server;

  void up(FakeAsync async) {
    server = _Server();
    rig = Rig(async, server: server);
    // Agents that take chord's server over HTTP, as the real ones do.
    rig.init = {
      'protocolVersion': 1,
      'agentCapabilities': {
        'mcpCapabilities': {'http': true},
      },
    };
    rig.initialize({'subagents': <String, Object?>{}});
  }

  /// Main [caller] opens a child named [name] with [prompt] as its first
  /// turn; chord's id for it.
  String open(Caller caller, String name, {String prompt = 'go'}) {
    late final OpenAnswer answer;
    caller.window
        .open(
          caller.key,
          SpawnArgs(agent: 'memory', prompt: prompt, name: name),
          caller,
        )
        .then((answered) => answer = answered);
    rig.settle();
    return (answer as Started).id;
  }

  /// [caller] starts a task; its id.
  String spawn(Caller caller, String name) {
    late final SpawnAnswer answer;
    caller.window
        .spawn(caller, SpawnArgs(agent: 'memory', prompt: 'look', name: name))
        .then((answered) => answer = answered);
    rig.settle();
    return (answer as Started).id;
  }

  int send(String sessionId, List<Map<String, Object?>> prompt) =>
      rig.request(_send, {'sessionId': sessionId, 'prompt': prompt});

  int close(String sessionId) => rig.request(_close, {'sessionId': sessionId});

  /// Prompts [sessionId] with [blocks]; the request's id.
  int prompt(String sessionId, List<Map<String, Object?>> blocks) =>
      rig.request('session/prompt', {'sessionId': sessionId, 'prompt': blocks});

  /// The chunk a command said under [sessionId], last.
  Map<String, Object?> said(String sessionId) =>
      rig
              .notified('session/update')
              .lastWhere(
                (p) =>
                    p['sessionId'] == sessionId &&
                    ((p['update'] as Map)['_meta'] as Map?)?['chord/command'] !=
                        null,
              )['update']
          as Map<String, Object?>;

  test('initialize advertises agents and monitors at 1', () {
    fakeAsync((async) {
      up(async);
      final answered = rig.answer(1)!['result'] as Map;
      final meta = (answered['_meta'] as Map)['chord/acp'] as Map;
      expect(meta['extensions'], {
        'session/state': 1,
        'session/steer': 1,
        'agents': 1,
        'monitors': 1,
      });
      rig.eof();
    });
  });

  group('_chord/agents/send', () {
    test('an idle child is sent to, a busy one queued; the prompt reaches '
        'its agent, and no -32601 is left', () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        final id = open(server.mains.single, 'parser');
        final child = rig.agents[1];
        _endTurn(rig, child);

        final first = send('$main/$id', [_text('long')]);
        expect(rig.answer(first)?['result'], {'delivery': 'sent'});
        expect(
          (_asked(child, 'session/prompt').last['params'] as Map)['prompt'],
          [_text('long')],
        );
        final second = send('$main/$id', [_text('text')]);
        expect(rig.answer(second)?['result'], {'delivery': 'queued'});
        rig.eof();
      });
    });

    test('a block it does not take is invalid params, nothing sent', () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        final id = open(server.mains.single, 'parser');
        final child = rig.agents[1];
        _endTurn(rig, child);
        final prompts = _asked(child, 'session/prompt').length;
        final asked = send('$main/$id', [
          _text('look'),
          {'type': 'audio', 'data': '', 'mimeType': 'audio/wav'},
        ]);
        expect(_error(rig, asked), {
          'code': -32602,
          'message': 'Invalid params: A prompt cannot carry a audio block.',
        });
        expect(_asked(child, 'session/prompt'), hasLength(prompts));
        rig.eof();
      });
    });

    test('main, a typo, nobody or a task is no child: -32002 for send and '
        'close', () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        for (final id in [main, '$main/nobody', 'nobody']) {
          expect(_error(rig, send(id, [_text('text')])), {
            'code': -32002,
            'message': 'Resource not found',
            'data': {'sessionId': id},
          });
          expect(_error(rig, close(id))?['code'], -32002);
        }
        rig.request('session/prompt', {
          'sessionId': main,
          'prompt': [_text('split it')],
        });
        final task = spawn(server.mains.single, 'scan');
        expect(_error(rig, send('$main/$task', [_text('x')]))?['code'], -32002);
        rig.eof();
      });
    });

    test('a child still starting is -32603, nothing held', () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        rig.answerNew = false;
        final caller = server.mains.single;
        late final OpenAnswer opened;
        caller.window
            .open(
              caller.key,
              const SpawnArgs(agent: 'memory', prompt: '', name: 'parser'),
              caller,
            )
            .then((answer) => opened = answer);
        rig.settle();
        // Its first event makes its route; none came yet while it starts.
        final route = '$main/${(opened as Started).id}';
        final asked = send(route, [_text('text')]);
        expect(_error(rig, asked), {
          'code': -32603,
          'message':
              'parser is starting; send once its subagent_update says idle',
        });
        expect(_asked(rig.agents[1], 'session/prompt'), isEmpty);
        rig.eof();
      });
    });

    test('a child being cleared is -32603, nothing held', () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        final caller = server.mains.single;
        final id = open(caller, 'parser');
        _endTurn(rig, rig.agents[1]);
        // The fresh session is not answered: the clear goes on.
        rig.answerNew = false;
        caller.window.clear(caller, 'parser').ignore();
        rig.settle();
        expect(_error(rig, send('$main/$id', [_text('text')])), {
          'code': -32603,
          'message':
              'parser is being cleared; send once its subagent_update says '
              'idle',
        });
        expect(_asked(rig.agents.last, 'session/prompt'), isEmpty);
        rig.eof();
      });
    });

    test('a child whose start failed is -32002, and still closes', () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        rig.answerNew = false;
        final caller = server.mains.single;
        late final OpenAnswer opened;
        caller.window
            .open(
              caller.key,
              const SpawnArgs(agent: 'memory', prompt: 'go', name: 'parser'),
              caller,
            )
            .then((answer) => opened = answer);
        rig.settle();
        final child = rig.agents[1];
        child.send({
          'jsonrpc': '2.0',
          'id': _asked(child, 'session/new').last['id'],
          'error': {'code': -32603, 'message': 'no room'},
        });
        // Its failure is said once its agent's process has gone.
        async.elapse(const Duration(seconds: 5));
        rig.settle();
        final route = '$main/${(opened as Started).id}';
        expect(
          (_reports(rig, main, route).last['_meta'] as Map)['chord/agent'],
          containsPair('failed', 'it refused session/new: no room'),
        );
        expect(_error(rig, send(route, [_text('text')]))?['code'], -32002);
        expect(rig.answer(close(route))?['result'], {
          'closed': ['parser'],
        });
        rig.eof();
      });
    });
  });

  group('_chord/agents/close', () {
    test('a long-lived child closes as the person closes it, said last; '
        'again it is -32002', () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        final id = open(server.mains.single, 'parser');
        final route = '$main/$id';
        expect(rig.answer(close(route))?['result'], {
          'closed': ['parser'],
        });
        rig.settle();
        expect(
          (_reports(rig, main, route).last['_meta'] as Map)['chord/agent'],
          containsPair('closed', true),
        );
        // Main hears that the person closed it.
        final words =
            (_asked(rig.agents[0], 'session/prompt').single['params']
                    as Map)['prompt']
                .toString();
        expect(words, contains('The person closed parser'));
        expect(_error(rig, close(route))?['code'], -32002);
        expect(_error(rig, send(route, [_text('x')]))?['code'], -32002);
        rig.eof();
      });
    });

    test('a running task is stopped and named; ended, it is said ended', () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        prompt(main, [_text('split it')]);
        final id = spawn(server.mains.single, 'scan');
        final route = '$main/$id';
        expect(rig.answer(close(route))?['result'], {
          'closed': ['scan'],
        });
        final task = rig.agents[1];
        expect(_asked(task, 'session/cancel'), isNotEmpty);
        _endTurn(rig, task, 'cancelled');
        async.elapse(const Duration(seconds: 1));
        rig.settle();
        final last = _reports(rig, main, route).last;
        expect(last['state'], {'state': 'idle', 'stopReason': 'cancelled'});
        // A stop with no key, as the original's cancel with none.
        expect((last['_meta'] as Map).containsKey('chord/stopped'), isFalse);
        expect(rig.answer(close(route))?['result'], {
          'closed': <Object?>[],
          'ended': ['scan'],
        });
        rig.eof();
      });
    });
  });

  group('session/cancel', () {
    test("on a long-lived child stops its turn and it stays open", () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        final id = open(server.mains.single, 'parser');
        final child = rig.agents[1];
        rig.send({
          'jsonrpc': '2.0',
          'method': 'session/cancel',
          'params': {'sessionId': '$main/$id'},
        });
        expect(_asked(child, 'session/cancel').map((m) => m['params']), [
          {'sessionId': 's2'},
        ]);
        // Main's turn goes on; nothing of main was cancelled.
        expect(_asked(rig.agents[0], 'session/cancel'), isEmpty);
        _endTurn(rig, child, 'cancelled');
        expect(rig.answer(send('$main/$id', [_text('more')]))?['result'], {
          'delivery': 'sent',
        });
        rig.eof();
      });
    });

    test("on a task ends it as the person's x, and the task says chord can "
        'cancel it', () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        prompt(main, [_text('split it')]);
        final id = spawn(server.mains.single, 'scan');
        final route = '$main/$id';
        expect(_reports(rig, main, route).first['capabilities'], {
          'cancel': <String, Object?>{},
        });
        rig.send({
          'jsonrpc': '2.0',
          'method': 'session/cancel',
          'params': {'sessionId': route},
        });
        final task = rig.agents[1];
        expect(_asked(task, 'session/cancel'), isNotEmpty);
        expect(_asked(rig.agents[0], 'session/cancel'), isEmpty);
        _endTurn(rig, task, 'cancelled');
        async.elapse(const Duration(seconds: 1));
        rig.settle();
        final last = _reports(rig, main, route).last;
        expect(last['state'], {'state': 'idle', 'stopReason': 'cancelled'});
        expect((last['_meta'] as Map)['chord/stopped'], 'x');
        rig.eof();
      });
    });
  });

  group("chord's command list", () {
    test('goes to an agent that sends none, once its answer is written', () {
      fakeAsync((async) {
        up(async);
        rig.lines.hold = true;
        final id = rig.request('session/new', {'cwd': '/w', 'mcpServers': []});
        // Its answer is written, its flush held: no list yet.
        expect(rig.notified('session/update'), isEmpty);
        rig.lines.release();
        rig.settle();
        final main = (rig.answer(id)!['result'] as Map)['sessionId'] as String;
        expect(_lists(rig, main), [
          [_teamCommand, _newCommand],
        ]);
        final answered = rig.lines.messages.indexWhere((m) => m['id'] == id);
        final listed = rig.lines.messages.indexWhere(
          (m) =>
              ((m['params'] as Map?)?['update'] as Map?)?['sessionUpdate'] ==
              'available_commands_update',
        );
        expect(listed, greaterThan(answered));
        rig.eof();
      });
    });

    test(
      "join the agent's own, team and new first and a name both have chord's",
      () {
        fakeAsync((async) {
          up(async);
          final main = rig.newSession();
          _update(rig, rig.agents[0], 's1', {
            'sessionUpdate': 'available_commands_update',
            'availableCommands': [
              {'name': 'greet', 'description': 'Say hello'},
              {'name': 'new', 'description': "the agent's"},
            ],
          });
          expect(_lists(rig, main), [
            [_teamCommand, _newCommand],
            [
              _teamCommand,
              _newCommand,
              {'name': 'greet', 'description': 'Say hello'},
            ],
          ]);
          rig.eof();
        });
      },
    );

    test("an agent whose list came ahead of its answer gets no list of "
        "chord's alone", () {
      fakeAsync((async) {
        up(async);
        rig.answerNew = false;
        final id = rig.request('session/new', {'cwd': '/w', 'mcpServers': []});
        final agent = rig.agents.single;
        agent
          ..send({
            'jsonrpc': '2.0',
            'method': 'session/update',
            'params': {
              'sessionId': 's1',
              'update': {
                'sessionUpdate': 'available_commands_update',
                'availableCommands': [
                  {'name': 'greet', 'description': 'Say hello'},
                ],
              },
            },
          })
          ..send({
            'jsonrpc': '2.0',
            'id': _asked(agent, 'session/new').last['id'],
            'result': {'sessionId': 's1'},
          });
        rig.settle();
        final main = (rig.answer(id)!['result'] as Map)['sessionId'] as String;
        expect(_lists(rig, main), [
          [
            _teamCommand,
            _newCommand,
            {'name': 'greet', 'description': 'Say hello'},
          ],
        ]);
        rig.eof();
      });
    });

    test("a child's list is its own", () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        final id = open(server.mains.single, 'parser');
        final list = [
          {'name': 'greet', 'description': 'Say hello'},
        ];
        _update(rig, rig.agents[1], 's2', {
          'sessionUpdate': 'available_commands_update',
          'availableCommands': list,
        });
        expect(_lists(rig, '$main/$id'), [list]);
        // Main's is chord's alone, its agent having sent none.
        expect(_lists(rig, main), [
          [_teamCommand, _newCommand],
        ]);
        rig.eof();
      });
    });
  });

  group('/new', () {
    test('a way out while its work is under way answers it cancelled once, '
        'and nothing of the work goes after', () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        var heard = 0;
        // The child is let in from inside newTyped, after its prompt is
        // held as a command and before its answer: the signal comes there.
        server.onChild = () {
          heard++;
          rig.host.leave(const LeaveSignal(ProcessSignal.sigterm));
        };
        final asked = prompt(main, [_text('/new --name scout')]);
        async.elapse(const Duration(seconds: 20));
        rig.settle();
        expect(heard, 1);
        final answers = [
          for (final message in rig.lines.messages)
            if (!message.containsKey('method') && message['id'] == asked)
              message,
        ];
        expect(answers, [
          {
            'jsonrpc': '2.0',
            'id': asked,
            'result': {'stopReason': 'cancelled'},
          },
        ]);
        expect(
          rig
              .notified('session/update')
              .where(
                (p) =>
                    ((p['update'] as Map)['_meta'] as Map?)?['chord/command'] !=
                    null,
              ),
          isEmpty,
        );
        expect(rig.exits, hasLength(1));
      });
    });

    test("opens an idle child on main's runtime, said in a chunk; main "
        'hears of it ahead of its next prompt', () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        final asked = prompt(main, [_text('/new --name scout')]);
        expect(rig.answer(asked)?['result'], {'stopReason': 'end_turn'});
        expect(said(main), {
          'sessionUpdate': 'agent_message_chunk',
          'content': _text(openedText('scout', 'memory')),
          '_meta': {
            'chord/command': {'name': 'new', 'failed': false},
          },
        });
        // Its agent started, with no prompt; main's agent was not prompted.
        expect(rig.agents, hasLength(2));
        expect(_asked(rig.agents[1], 'session/prompt'), isEmpty);
        expect(_asked(rig.agents[0], 'session/prompt'), isEmpty);
        final report = rig
            .notified('session/update')
            .where((p) => p['sessionId'] == main)
            .map((p) => p['update'] as Map)
            .lastWhere((u) => u['sessionUpdate'] == 'subagent_update');
        expect(report['title'], 'scout');
        expect(report['state'], {'state': 'idle'});

        prompt(main, [_text('next')]);
        expect(
          (_asked(rig.agents[0], 'session/prompt').single['params']
                  as Map)['prompt']
              .toString(),
          contains(
            'The person opened @scout (memory) with /new; it has no prompt '
            'yet.',
          ),
        );
        rig.eof();
      });
    });

    group('refused in a chunk, not an error, nothing opened', () {
      final refusals = [
        for (final (typed, read) in newArgsCases)
          if (read case NewProblem(:final problem)) ('/new $typed', problem),
        ('/new nope', 'No agent named nope; chord knows memory'),
        ('/new --name main', 'The name main is taken in this window'),
      ];
      for (final (typed, words) in refusals) {
        test(typed, () {
          fakeAsync((async) {
            up(async);
            final main = rig.newSession();
            final asked = prompt(main, [_text(typed)]);
            expect(rig.answer(asked)?['result'], {'stopReason': 'end_turn'});
            expect(said(main), {
              'sessionUpdate': 'agent_message_chunk',
              'content': _text(words),
              '_meta': {
                'chord/command': {'name': 'new', 'failed': true},
              },
            });
            expect(rig.agents, hasLength(1));
            expect(_asked(rig.agents[0], 'session/prompt'), isEmpty);
            rig.eof();
          });
        });
      }
    });

    test('beside another block is refused, and nothing runs', () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        final asked = prompt(main, [
          _text('/new'),
          {'type': 'image', 'data': 'AAAA', 'mimeType': 'image/png'},
        ]);
        expect(rig.answer(asked)?['result'], {'stopReason': 'end_turn'});
        expect(said(main)['content'], _text(notAloneRefusal('new')));
        expect(rig.agents, hasLength(1));
        expect(_asked(rig.agents[0], 'session/prompt'), isEmpty);
        rig.eof();
      });
    });
  });

  group('CTUI-35 tester: ACP agents session isolation', () {
    test(
      'same-named new children in two sessions receive sends and cancellation only on their routes',
      () {
        fakeAsync((async) {
          up(async);
          final a = rig.newSession(), b = rig.newSession();
          for (final main in [a, b]) {
            expect(
              rig.answer(
                prompt(main, [_text('/new --name 界🙂e\u0301')]),
              )?['result'],
              {'stopReason': 'end_turn'},
            );
          }
          String route(String main) =>
              rig
                      .notified('session/update')
                      .where((p) => p['sessionId'] == main)
                      .map((p) => p['update'] as Map)
                      .lastWhere(
                        (u) => u['sessionUpdate'] == 'subagent_update',
                      )['sessionId']
                  as String;
          final routeA = route(a), routeB = route(b);
          expect(routeA, isNot(routeB));
          final childA = rig.agents[2], childB = rig.agents[3];
          for (final target in [routeA, routeB]) {
            expect(
              rig.answer(
                send(target, [_text('界🙂e\u0301 $target')]),
              )?['result'],
              {'delivery': 'sent'},
            );
          }
          expect(
            (_asked(childA, 'session/prompt').single['params']
                as Map)['prompt'],
            [_text('界🙂e\u0301 $routeA')],
          );
          expect(
            (_asked(childB, 'session/prompt').single['params']
                as Map)['prompt'],
            [_text('界🙂e\u0301 $routeB')],
          );
          expect(_asked(rig.agents[0], 'session/prompt'), isEmpty);
          expect(_asked(rig.agents[1], 'session/prompt'), isEmpty);
          expect(rig.answer(close(routeA))?['result'], {
            'closed': ['界🙂e\u0301'],
          });
          expect(_error(rig, send(routeA, [_text('late')]))?['code'], -32002);
          expect(_asked(childB, 'session/cancel'), isEmpty);
          rig.send({
            'jsonrpc': '2.0',
            'method': 'session/cancel',
            'params': {'sessionId': routeB},
          });
          expect(_asked(childB, 'session/cancel').map((m) => m['params']), [
            {'sessionId': 's4'},
          ]);
          _endTurn(rig, childB, 'cancelled');
          expect(rig.answer(send(routeB, [_text('still open')]))?['result'], {
            'delivery': 'sent',
          });
          rig.eof();
        });
      },
    );

    test(
      'cancelling one child withdraws its ask without settling a sibling same-id ask',
      () {
        fakeAsync((async) {
          up(async);
          final main = rig.newSession(), caller = server.mains.single;
          final a = open(caller, 'parser'), b = open(caller, 'docs');
          final childA = rig.agents[1], childB = rig.agents[2];
          void ask(MemoryAgentProcess child, String session) => child.send({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'session/request_permission',
            'params': {
              'sessionId': session,
              'toolCall': {'toolCallId': 'write', 'title': 'Write'},
              'options': [
                {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
                {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_once'},
              ],
            },
          });
          ask(childA, 's2');
          ask(childB, 's3');
          rig.settle();
          final asks = rig.lines.messages
              .where((m) => m['method'] == 'session/request_permission')
              .toList();
          final askA = asks.singleWhere(
            (m) => (m['params'] as Map)['sessionId'] == '$main/$a',
          );
          final askB = asks.singleWhere(
            (m) => (m['params'] as Map)['sessionId'] == '$main/$b',
          );
          expect(askA['id'], isNot(askB['id']));
          rig.send({
            'jsonrpc': '2.0',
            'method': 'session/cancel',
            'params': {'sessionId': '$main/$a'},
          });
          _endTurn(rig, childA, 'cancelled');
          rig.send({
            'jsonrpc': '2.0',
            'id': askA['id'],
            'result': {
              'outcome': {'outcome': 'selected', 'optionId': 'allow'},
            },
          });
          expect(
            childB.stdin.messages.where(
              (m) => m['id'] == 1 && !m.containsKey('method'),
            ),
            isEmpty,
          );
          expect(_reports(rig, main, '$main/$b').last['state'], {
            'state': 'requires_action',
          });
          rig.send({
            'jsonrpc': '2.0',
            'id': askB['id'],
            'result': {
              'outcome': {'outcome': 'selected', 'optionId': 'deny'},
            },
          });
          expect(
            childB.stdin.messages.singleWhere(
              (m) => m['id'] == 1 && !m.containsKey('method'),
            )['result'],
            {
              'outcome': {'outcome': 'selected', 'optionId': 'deny'},
            },
          );
          expect(_asked(rig.agents[0], 'session/cancel'), isEmpty);
          _endTurn(rig, childB);
          rig.eof();
        });
      },
    );
  });
}
