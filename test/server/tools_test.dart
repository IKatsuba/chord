// The original's tests/server/tools_test.ts for this task's tools, against
// a fake window, and the role matrix, schemas and serving that its
// server_test.ts reaches over the wire.
import 'dart:convert';
import 'dart:io';

import 'package:chord/server/runtimes.dart';
import 'package:chord/server/tools.dart';
import 'package:chord/session/budgets.dart';
import 'package:chord/session/monitors.dart';
import 'package:chord/session/team_selection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/teams.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../fixtures/fake.dart' show portPackageDir;

import 'fake_window.dart';

Caller person(FakeWindow window, {int key = 0}) =>
    Caller(role: Role.person, key: key, window: window);
Caller child(FakeWindow window) =>
    Caller(role: Role.child, key: 0, agent: '7f3a9c2e', window: window);
Caller task(FakeWindow window) =>
    Caller(role: Role.child, key: 0, task: 't1', window: window);

ToolSpec toolOf(Caller caller, String name) =>
    toolsOf(caller).firstWhere((tool) => tool.name == name);

const agentWords = 'The runtime, as list_agents names it';
const modelWords =
    "A model the runtime offers, by its id; the runtime's own if left out";
const effortWords =
    'An effort the runtime offers for that model, by its id, as list_agents '
    "lists them (`efforts`); the runtime's own if left out. One it does not "
    'take starts it on its own, and the answer says so';

Map<String, Object?> schema(
  Map<String, String> properties,
  List<String> required,
) => {
  r'$schema': 'http://json-schema.org/draft-07/schema#',
  'type': 'object',
  'properties': {
    for (final MapEntry(:key, :value) in properties.entries)
      key: {'type': 'string', 'description': value},
  },
  'required': required,
};

void main() {
  _testerForkEffects();
  _forkTests();
  _teamTests();
  _budgetsTests();
  _monitorTests();
  testerToolContractTests();
  group('list_agents', () {
    test('names every runtime, with the models and modes read and how to '
        'read the rest, starting none', () async {
      final window = FakeWindow();
      expect(await agentsAnswer(window), {
        'agents': [
          {
            'name': 'fake',
            'models': [
              {'id': 'fake-large', 'name': 'Fake Large'},
            ],
            'current': 'fake-large',
            'modes': [
              {'id': 'default', 'name': 'Default'},
              {'id': 'plan', 'name': 'Plan'},
            ],
            'currentMode': 'default',
          },
          {
            'name': 'broken',
            'note':
                'models and modes could not be read: Unknown agent '
                '"broken".',
          },
          {
            'name': 'claude',
            'note':
                'models and modes not read yet; list_agents with agent '
                '"claude" reads them',
          },
        ],
      });
      expect(window.probed, isEmpty);
    });

    test('with an agent reads that one, starting it if need be', () async {
      final window = FakeWindow();
      final answer = await agentsAnswer(window, agent: 'claude');
      expect((answer['agents'] as List).single, containsPair('name', 'claude'));
      expect(
        (answer['agents'] as List).single,
        containsPair('current', 'fake-large'),
      );
      expect(window.probed, ['claude']);
    });

    test(
      'with a runtime chord does not know says so and starts nothing',
      () async {
        final window = FakeWindow();
        expect(await agentsAnswer(window, agent: 'codx'), {
          'agents': [
            {
              'name': 'codx',
              'note':
                  'chord knows no runtime named codx; list_agents without '
                  'an agent names every one',
            },
          ],
        });
        expect(window.probed, isEmpty);
      },
    );

    test("a model's efforts and the one it is on, and a runtime's own "
        'efforts', () async {
      final window = _OfferWindow(
        const Offer(
          models: [
            (
              id: 'm',
              name: 'M',
              efforts: [(id: 'low', name: 'Low')],
              effort: 'low',
            ),
          ],
          current: 'm',
          efforts: [(id: 'high', name: 'High')],
          currentEffort: 'high',
        ),
      );
      expect(await agentsAnswer(window, agent: 'fake'), {
        'agents': [
          {
            'name': 'fake',
            'models': [
              {
                'id': 'm',
                'name': 'M',
                'efforts': [
                  {'id': 'low', 'name': 'Low'},
                ],
                'effort': 'low',
              },
            ],
            'current': 'm',
            'efforts': [
              {'id': 'high', 'name': 'High'},
            ],
            'currentEffort': 'high',
          },
        ],
      });
    });

    test('a failed read says why', () async {
      for (final why in [
        'it did not open a session within 60 s',
        'it offers no models or modes',
      ]) {
        final window = _OfferWindow(OfferError(why));
        expect(await agentsAnswer(window, agent: 'fake'), {
          'agents': [
            {
              'name': 'fake',
              'note': 'models and modes could not be read: $why',
            },
          ],
        });
      }
    });
  });

  group('list_sessions', () {
    test("gives the window's session, the caller's marked", () {
      final window = FakeWindow();
      expect(sessionsAnswer(person(window)), {
        'sessions': [
          {'id': 'one', 'runtime': 'fake', 'model': 'fake-large', 'you': true},
        ],
      });
      expect(sessionsAnswer(person(window, key: 5)), {
        'sessions': [
          {'id': 'one', 'runtime': 'fake', 'model': 'fake-large'},
        ],
      });
    });

    test("gives each session's long-lived agents with it, and a child is "
        'never `you`; unknown ids and models are null', () {
      final window = FakeWindow(
        sessions: [
          (
            key: 0,
            runtime: 'claude',
            id: null,
            model: null,
            children: [
              (id: '7f3a9c2e', name: 'parser', runtime: 'codex', model: null),
            ],
          ),
        ],
      );
      final parser = [
        {'id': '7f3a9c2e', 'name': 'parser', 'runtime': 'codex', 'model': null},
      ];
      expect(sessionsAnswer(person(window)), {
        'sessions': [
          {
            'id': null,
            'runtime': 'claude',
            'model': null,
            'you': true,
            'agents': parser,
          },
        ],
      });
      expect(sessionsAnswer(child(window)), {
        'sessions': [
          {'id': null, 'runtime': 'claude', 'model': null, 'agents': parser},
        ],
      });
    });
  });

  group('the role matrix', () {
    test('main has fifteen tools, a long-lived child eight, a lead ten, '
        'a member eight, a task one', () {
      final window = FakeWindow();
      List<String> names(Caller caller) => [
        for (final tool in toolsOf(caller)) tool.name,
      ];
      expect(names(person(window)), [
        'list_agents',
        'get_budgets',
        'list_sessions',
        'list_teams',
        'spawn_task',
        'open_agent',
        'run_team',
        'propose_team',
        'settings',
        'send_message',
        'close_agent',
        'clear_agent',
        'monitor',
        'stop_monitor',
        'list_monitors',
      ]);
      expect(names(child(window)), [
        'list_agents',
        'get_budgets',
        'spawn_task',
        'send_message',
        'close_agent',
        'monitor',
        'stop_monitor',
        'list_monitors',
      ]);
      expect(names(task(window)), ['send_message']);
      Caller teamAgent(TeamSide side) => Caller(
        role: Role.child,
        key: 0,
        agent: '7f3a9c2e',
        team: side,
        window: window,
      );
      expect(names(teamAgent(TeamSide.lead)), [
        'list_agents',
        'get_budgets',
        'spawn_task',
        'open_agent',
        'send_message',
        'close_agent',
        'clear_agent',
        'monitor',
        'stop_monitor',
        'list_monitors',
      ]);
      expect(names(teamAgent(TeamSide.member)), [
        'list_agents',
        'get_budgets',
        'spawn_task',
        'send_message',
        'close_agent',
        'monitor',
        'stop_monitor',
        'list_monitors',
      ]);
    });

    test("/mcp's list is main's fifteen and a long-lived child's eight", () {
      expect(
        [for (final t in toolNames(Role.person)) t.wire],
        [
          'list_agents',
          'get_budgets',
          'list_sessions',
          'list_teams',
          'spawn_task',
          'open_agent',
          'run_team',
          'propose_team',
          'settings',
          'send_message',
          'close_agent',
          'clear_agent',
          'monitor',
          'stop_monitor',
          'list_monitors',
        ],
      );
      expect(
        [for (final t in toolNames(Role.child)) t.wire],
        [
          'list_agents',
          'get_budgets',
          'spawn_task',
          'send_message',
          'close_agent',
          'monitor',
          'stop_monitor',
          'list_monitors',
        ],
      );
    });
  });

  group('schemas, as the original lists them', () {
    final window = FakeWindow();

    test('list_agents and list_sessions', () {
      expect(
        toolOf(person(window), 'list_agents').inputSchema,
        schema({
          'agent':
              'A runtime to read the models and modes of, as list_agents '
              'names it',
        }, []),
      );
      expect(toolOf(person(window), 'list_sessions').inputSchema, isNull);
    });

    test('spawn_task and open_agent', () {
      expect(
        toolOf(person(window), 'spawn_task').inputSchema,
        schema(
          {
            'agent': agentWords,
            'model': modelWords,
            'effort': effortWords,
            'prompt': 'The job, in full',
            'name':
                "A short name for it on screen; the prompt's first line if left "
                'out',
          },
          ['agent', 'prompt'],
        ),
      );
      expect(
        toolOf(person(window), 'open_agent').inputSchema,
        schema(
          {
            'agent': agentWords,
            'model': modelWords,
            'effort': effortWords,
            'prompt': 'Its first prompt, in full',
            'name':
                'A short name for it, which messages and the screen use; the '
                'runtime if left out',
          },
          ['agent', 'prompt'],
        ),
      );
    });

    test("send_message: main's to its child, a child's to its parent", () {
      expect(
        toolOf(person(window), 'send_message').inputSchema,
        schema(
          {
            'to': 'The agent, by the id open_agent answered or by its name',
            'text': 'What to tell it',
          },
          ['to', 'text'],
        ),
      );
      expect(
        toolOf(person(window), 'send_message').description,
        startsWith('Sends a message to a long-lived agent you opened.'),
      );
      for (final caller in [child(window), task(window)]) {
        expect(
          toolOf(caller, 'send_message').inputSchema,
          schema({'text': 'What to tell it'}, ['text']),
        );
        expect(
          toolOf(caller, 'send_message').description,
          startsWith('Sends a message to the agent that started you,'),
        );
      }
    });

    test("close_agent: main's closes its agents and tasks, a child's only "
        'its tasks', () {
      final mains = toolOf(person(window), 'close_agent');
      final childs = toolOf(child(window), 'close_agent');
      expect(
        mains.description,
        'Closes a long-lived agent you opened, stopping what it is doing; it '
        'takes no more messages. Also stops a task you started with '
        'spawn_task, which then sends no report; one that has already ended '
        'is said to have.',
      );
      expect(
        mains.inputSchema,
        schema(
          {
            'to':
                'The agent, by the id open_agent answered or by its name; or '
                'the task, by the id spawn_task answered or by its name',
          },
          ['to'],
        ),
      );
      expect(
        childs.description,
        'Stops a task you started with spawn_task, which then sends no '
        'report; one that has already ended is said to have. It closes no '
        'other agent.',
      );
      expect(
        childs.inputSchema,
        schema(
          {'to': 'The task, by the id spawn_task answered or by its name'},
          ['to'],
        ),
      );
    });

    test('clear_agent', () {
      expect(
        toolOf(person(window), 'clear_agent').inputSchema,
        schema(
          {'to': 'The agent, by the id open_agent answered or by its name'},
          ['to'],
        ),
      );
    });

    test(r'every schema names draft-07 first, as G2 sets it', () {
      for (final caller in [person(window), child(window), task(window)]) {
        for (final tool in toolsOf(caller)) {
          final keys = tool.inputSchema?.keys.toList();
          if (keys != null) expect(keys.first, r'$schema');
        }
      }
    });
  });

  group('serving', () {
    test(
      'an answer is two-space JSON, and the session is told the call',
      () async {
        final window = FakeWindow();
        final result = await toolOf(person(window), 'list_sessions').call({});
        expect(result.isError, isFalse);
        expect(result.structured, isNull);
        expect(
          result.text,
          const JsonEncoder.withIndent(
            '  ',
          ).convert(sessionsAnswer(person(window))),
        );
        final call = window.calls.single;
        expect(call.tool, ChordTool.listSessions);
        expect(call.input, isEmpty);
        expect(call.answer, sessionsAnswer(person(window)));
        expect(call.error, isNull);
      },
    );

    test('a refusal is the call failing with its words, and served as an '
        'error', () async {
      final window = FakeWindow();
      final result = await toolOf(
        person(window),
        'open_agent',
      ).call({'agent': 'fake', 'prompt': 'hi'});
      expect(result, (text: 'no agents here', isError: true, structured: null));
      expect(window.calls.single.error, 'no agents here');
      expect(window.calls.single.answer, isNull);
    });

    test(
      "a started task's id is served as its task; an agent's is not",
      () async {
        final window = FakeWindow()
          ..spawned = const Started(
            id: 't9',
            name: 'scan',
            agent: 'fake',
            model: 'fake-small',
            effort: 'low',
          )
          ..opened = const Started(
            id: 'a1b2c3d4',
            name: 'parser',
            agent: 'fake',
          );
        final spawned = await toolOf(
          person(window),
          'spawn_task',
        ).call({'agent': 'fake', 'prompt': 'scan'});
        expect(jsonDecode(spawned.text), {
          'id': 't9',
          'name': 'scan',
          'agent': 'fake',
          'model': 'fake-small',
          'effort': 'low',
        });
        expect(window.calls.last.task, 't9');
        await toolOf(
          person(window),
          'open_agent',
        ).call({'agent': 'fake', 'prompt': 'hi'});
        expect(window.calls.last.task, isNull);
      },
    );

    test('a message queued is served as queued; one queued later is served '
        'again in its place, sharing its asked id', () async {
      final window = FakeWindow()
        ..told = const Delivered(Delivery.queued, to: 'parser');
      final input = {'to': 'parser', 'text': 'hi'};
      final queued = await toolOf(person(window), 'send_message').call(input);
      expect(jsonDecode(queued.text), {'delivered': 'queued', 'to': 'parser'});
      expect(window.calls.single.queued, isTrue);
      expect(window.calls.single.asked, isNotNull);

      window.told = const Delivered(Delivery.sent, to: 'parser');
      await toolOf(person(window), 'send_message').call(input);
      final sent = window.calls.last;
      expect(sent.queued, isFalse);
      window.queue!();
      final again = window.later.single;
      expect(again.queued, isTrue);
      expect(again.asked, sent.asked);
      expect(again.answer, {'delivered': 'sent', 'to': 'parser'});
      expect(again.tool, ChordTool.sendMessage);
      expect(again.input, input);
    });

    test("a child's message to its parent says delivered alone", () async {
      final window = FakeWindow()..told = const Delivered(Delivery.sent);
      final result = await toolOf(
        task(window),
        'send_message',
      ).call({'text': 'done'});
      expect(jsonDecode(result.text), {'delivered': 'sent'});
    });

    test('close_agent answers in words with structured content', () async {
      final window = FakeWindow()..closed = const Closed('parser');
      final closed = await toolOf(
        person(window),
        'close_agent',
      ).call({'to': 'parser'});
      expect(closed.text, '{\n  "closed": "parser"\n}');
      expect(closed.structured, {'closed': 'parser'});
      window.closed = const Ended('scan');
      final ended = await toolOf(
        child(window),
        'close_agent',
      ).call({'to': 'scan'});
      expect((ended.text, ended.isError), ('scan has already ended', false));
      expect(ended.structured, {'ended': 'scan'});
      expect(window.calls.last.answer, {'ended': 'scan'});
    });

    test('clear_agent answers in words, with what was dropped', () async {
      final window = FakeWindow()
        ..cleared = const Cleared('parser', 'a1b2c3d4');
      final plain = await toolOf(
        person(window),
        'clear_agent',
      ).call({'to': 'parser'});
      expect(
        (plain.text, plain.isError),
        (
          'parser (id a1b2c3d4) has a fresh session; it knows nothing of '
              'earlier turns.',
          false,
        ),
      );
      expect(plain.structured, {'cleared': 'parser', 'id': 'a1b2c3d4'});
      window.cleared = const Cleared(
        'parser',
        'a1b2c3d4',
        dropped: '2 queued messages from main and docs were not delivered.',
      );
      final dropped = await toolOf(
        person(window),
        'clear_agent',
      ).call({'to': 'parser'});
      expect(
        dropped.text,
        'parser (id a1b2c3d4) has a fresh session; it knows nothing of '
        'earlier turns. 2 queued messages from main and docs were not '
        'delivered.',
      );
      expect(dropped.structured, {
        'cleared': 'parser',
        'id': 'a1b2c3d4',
        'dropped': '2 queued messages from main and docs were not delivered.',
      });
    });
  });
}

/// A window whose one runtime, `fake`, offers [offer].
final class _OfferWindow extends FakeWindow {
  _OfferWindow(this._offer);

  final RuntimeOffer _offer;

  @override
  List<String> runtimes() => ['fake'];

  @override
  Future<RuntimeOffer?> offer(
    String runtime, {
    required bool probe,
    int? key,
  }) async => _offer;
}

final class _TesterWindow extends FakeWindow {
  final forwarded = <({String method, Caller caller, Object? args})>[];
  final offerKeys = <int?>[];
  final callbacks = <void Function()>[];
  final servedCallers = <Caller>[];

  @override
  Future<RuntimeOffer?> offer(String runtime, {required bool probe, int? key}) {
    offerKeys.add(key);
    return super.offer(runtime, probe: probe, key: key);
  }

  @override
  Future<SpawnAnswer> spawn(Caller caller, SpawnArgs args) {
    forwarded.add((method: 'spawn', caller: caller, args: args));
    return super.spawn(caller, args);
  }

  @override
  Future<OpenAnswer> open(int key, SpawnArgs args, Caller caller) {
    expect(key, caller.key);
    forwarded.add((method: 'open', caller: caller, args: args));
    return super.open(key, args, caller);
  }

  @override
  MessageAnswer tell(
    Caller caller,
    String to,
    String text,
    void Function() queued,
  ) {
    forwarded.add((method: 'tell', caller: caller, args: (to, text)));
    callbacks.add(queued);
    return super.tell(caller, to, text, queued);
  }

  @override
  MessageAnswer message(Caller caller, String text, void Function() queued) {
    forwarded.add((method: 'message', caller: caller, args: text));
    callbacks.add(queued);
    return super.message(caller, text, queued);
  }

  @override
  CloseAnswer close(Caller caller, String to) {
    forwarded.add((method: 'close', caller: caller, args: to));
    return super.close(caller, to);
  }

  @override
  Future<ClearAnswer> clear(Caller caller, String to) {
    forwarded.add((method: 'clear', caller: caller, args: to));
    return super.clear(caller, to);
  }

  @override
  void served(Caller caller, ChordCall call) {
    servedCallers.add(caller);
    super.served(caller, call);
  }
}

void testerToolContractTests() {
  group('tester: tool forwarding and refusal contracts', () {
    test('every effect forwards exact caller and literal arguments', () async {
      final window = _TesterWindow();
      final caller = person(window, key: 47);
      const input = {
        'agent': 'fake',
        'model': 'model-id',
        'effort': 'high',
        'name': '界🙂e\u0301',
        'prompt': 'line 1\n<tag> \${literal}\x1b[31m',
      };
      for (final tool in ['spawn_task', 'open_agent']) {
        await toolOf(caller, tool).call(input);
        final forwarded = window.forwarded.last;
        expect(forwarded.caller, same(caller));
        final args = forwarded.args as SpawnArgs;
        expect(
          (args.agent, args.model, args.effort, args.name, args.prompt),
          (
            input['agent'],
            input['model'],
            input['effort'],
            input['name'],
            input['prompt'],
          ),
        );
      }
      await toolOf(caller, 'list_agents').call({'agent': 'fake'});
      expect(window.offerKeys, [47]);
      await toolOf(
        caller,
        'send_message',
      ).call({'to': 'opaque-id', 'text': input['prompt']});
      expect(window.forwarded.last.args, ('opaque-id', input['prompt']));
      for (final name in ['close_agent', 'clear_agent']) {
        await toolOf(caller, name).call({'to': 'opaque-id'});
        expect(window.forwarded.last.caller, same(caller));
        expect(window.forwarded.last.args, 'opaque-id');
      }
      for (final source in [child(window), task(window)]) {
        await toolOf(source, 'send_message').call({'text': input['prompt']});
        expect(window.forwarded.last.method, 'message');
        expect(window.forwarded.last.caller, same(source));
        expect(window.forwarded.last.args, input['prompt']);
      }
    });

    test(
      'every effect refusal is served once without structured success',
      () async {
        final window = _TesterWindow();
        for (final caller in [person(window), child(window), task(window)]) {
          for (final spec in toolsOf(
            caller,
          ).where((tool) => !tool.name.startsWith('list_'))) {
            final before = window.calls.length;
            final result = await spec.call({
              'team': 'bugfix',
              'job': 'x',
              'agent': 'fake',
              'prompt': 'hi',
              'to': 'parser',
              'text': 'hi',
              'id': 'm1',
              'command': 'watch',
              'description': 'log',
              'action': 'set',
              'path': ['theme'],
              'value': 'not-a-theme',
            });
            expect(result.isError, isTrue, reason: spec.name);
            expect(result.structured, isNull);
            expect(window.calls, hasLength(before + 1));
            expect(window.calls.last.error, result.text);
            expect(window.calls.last.answer, isNull);
            expect(window.calls.last.task, isNull);
            expect(window.servedCallers.last, same(caller));
          }
        }
      },
    );

    test(
      'interleaved late queue callbacks retain their original call ids',
      () async {
        final window = _TesterWindow()
          ..told = const Delivered(Delivery.sent, to: 'parser');
        final caller = person(window);
        await toolOf(
          caller,
          'send_message',
        ).call({'to': 'parser', 'text': 'first'});
        await toolOf(child(window), 'send_message').call({'text': 'second'});
        final first = window.calls[0], second = window.calls[1];
        expect(first.asked, isNot(second.asked));
        window.callbacks[1]();
        window.callbacks[0]();
        expect(window.later.map((call) => call.asked), [
          second.asked,
          first.asked,
        ]);
        expect(window.later.map((call) => call.input['text']), [
          'second',
          'first',
        ]);
        expect(window.later.every((call) => call.queued), isTrue);
      },
    );
  });
}

RunningMonitor _running(
  String id,
  String description,
  String command,
  int startedAt,
  int timeoutMs,
  int events,
) => RunningMonitor(
  MonitorInfo(
    id: id,
    description: description,
    command: command,
    startedAt: startedAt,
    timeoutMs: timeoutMs,
  ),
  events: events,
);

void _monitorTests() {
  group('monitors', () {
    test('the monitor tools say what the model reads: the id, how events '
        'come, and what runs', () {
      expect(
        monitorText(const StartedMonitor('m1', 'dev server errors', 600000)),
        'Started monitor m1 (dev server errors); it times out in 10m. Its '
        'output does not come in this answer: each batch of lines (up to 100, '
        'gathered over 200 ms) reaches you later as a message from "dev server '
        'errors · monitor", and so does its end. Keep working. stop_monitor '
        'with id "m1" stops it.',
      );
      expect(
        stopMonitorText(
          const StoppedMonitor('m1', 'dev server errors', 3, 252000),
        ),
        'Stopped m1 (dev server errors) after 4m 12s and 3 events.',
      );
      final running = [
        _running('m1', 'dev server errors', 'tail -f dev.log', 0, 600000, 3),
        _running('m2', 'CI run 4812', 'gh run watch 4812', 300000, 3600000, 0),
      ];
      expect(
        monitorsText(running, 360000),
        '2 running: m1 dev server errors (6m, 3 events), m2 CI run 4812 (1m, '
        'no events)',
      );
      expect(monitorsText(const [], 0), 'No monitors running');
      expect((monitorsAnswer(running)['monitors'] as List)[1], {
        'id': 'm2',
        'description': 'CI run 4812',
        'command': 'gh run watch 4812',
        'started_at': '1970-01-01T00:05:00.000Z',
        'events': 0,
        'timeout_ms': 3600000,
      });
    });

    test('monitor forwards what was asked, answers with words and the '
        'value, and is served; a refusal is the failure', () async {
      final window = FakeWindow()
        ..monitored = const StartedMonitor('m1', 'log', 1000);
      final result = await toolOf(person(window), 'monitor').call({
        'command': 'tail -f log',
        'description': 'log',
        'timeout_ms': 1000,
      });
      expect(window.asked.single, (
        command: 'tail -f log',
        description: 'log',
        timeoutMs: 1000,
      ));
      expect(result.isError, isFalse);
      expect(
        result.text,
        startsWith(
          'Started monitor m1 (log); it times out '
          'in 1s.',
        ),
      );
      expect(result.structured, {
        'id': 'm1',
        'description': 'log',
        'timeout_ms': 1000,
      });
      expect(window.calls.single.tool, ChordTool.monitor);
      expect(window.calls.single.answer, result.structured);

      window.stopped = const Refused('No running monitor m2 of yours');
      final refused = await toolOf(
        child(window),
        'stop_monitor',
      ).call({'id': 'm2'});
      expect(
        (refused.text, refused.isError),
        ('No running monitor m2 of yours', true),
      );
      expect(window.calls.last.error, 'No running monitor m2 of yours');

      window.running = [_running('m1', 'log', 'tail -f log', 0, 1000, 2)];
      final listed = await toolOf(person(window), 'list_monitors').call({});
      expect(listed.text, startsWith('1 running: m1 log ('));
      expect(listed.structured, monitorsAnswer(window.running));
      expect(window.calls.last.tool, ChordTool.listMonitors);
      expect(toolOf(person(window), 'list_monitors').inputSchema, isNull);
      expect(
        (toolOf(person(window), 'monitor').inputSchema!['properties']
            as Map)['timeout_ms'],
        containsPair('type', 'number'),
      );
    });
  });
}

const _bugfix = Team(
  description: 'Fixes a bug end to end',
  lead: TeamLead(agent: 'claude', model: 'opus', instructions: 'Lead it.\n'),
  members: [
    TeamMember(
      name: 'tester',
      role: 'Writes the failing test',
      agent: 'codex',
      mode: 'acceptEdits',
      instructions: 'Write it.\n',
    ),
  ],
  body: '# How it works',
);

FoundTeam _found(String name, {Team? team, String? problem}) => FoundTeam(
  name: name,
  file: '/w/.chord/teams/$name.md',
  place: TeamPlace.project,
  hides: false,
  team: team,
  problem: problem,
);

void _budgetsTests() {
  group('get_budgets', () {
    test("reads each provider's limits for main and long-lived agents, never "
        'for a task', () async {
      const Budgets read = (
        readAt: '2026-10-27T13:00:00.000Z',
        providers: [ProviderUnavailable('codex', 'Timed out after 10 s.')],
      );
      final window = FakeWindow()..budgetsRead = read;
      final spec = toolOf(person(window), 'get_budgets');
      expect(
        spec.description,
        startsWith("Reads each provider's usage limits now"),
      );
      expect(spec.inputSchema, {
        r'$schema': 'http://json-schema.org/draft-07/schema#',
        'type': 'object',
        'properties': {
          'agents': {
            'description': 'Runtime IDs from list_agents to read only those',
            'maxItems': 128,
            'type': 'array',
            'items': {'type': 'string', 'minLength': 1, 'maxLength': 128},
          },
        },
      });
      final result = await spec.call({
        'agents': ['codex'],
      });
      expect(window.budgetsAsked.single, ['codex']);
      expect(jsonDecode(result.text), budgetsJson(read));
      expect(result.structured, budgetsJson(read));
      expect(window.calls.last.tool, ChordTool.getBudgets);
      expect(window.calls.last.answer, budgetsJson(read));
      expect(
        toolsOf(child(window)).map((t) => t.name),
        contains('get_budgets'),
      );
      expect(
        toolsOf(task(window)).map((t) => t.name),
        isNot(contains('get_budgets')),
      );
    });

    test('a window that reads none answers that the limits could not be '
        'read', () async {
      final window = FakeWindow();
      final result = await toolOf(person(window), 'get_budgets').call(const {});
      expect(
        (result.text, result.isError),
        ('The limits could not be read.', true),
      );
      expect(window.budgetsAsked.single, isNull);
    });
  });
}

void _teamTests() {
  group('selected runs', () {
    final receipt = selectionReceipt(
      'a1b2c3d4',
      (name: 'bugfix', place: 'project'),
      freezeSelection(
        _bugfix,
        {'reason': 'Keep every role.'},
        const {},
        ['claude', 'codex'],
      ).frozen!,
    );
    final input = {
      'team': 'bugfix',
      'job': 'Fix 214.',
      'selection': {'reason': 'Keep every role.'},
    };

    test("its schema is the original's, selection with it", () {
      expect(
        toolOf(person(FakeWindow()), 'run_team').inputSchema,
        jsonDecode(
          File(
            p.join(
              portPackageDir(),
              'test',
              'fixtures',
              'run_team_schema.json',
            ),
          ).readAsStringSync(),
        ),
      );
    });

    test('a selected run is served under its run id, its receipt beside '
        'the words', () async {
      final window = FakeWindow()
        ..ran = Started(
          id: 'a1b2c3d4',
          name: 'bugfix',
          agent: 'claude',
          team: 'bugfix',
          receipt: receipt,
        );
      final result = await toolOf(person(window), 'run_team').call(input);
      expect(window.selections.single, {'reason': 'Keep every role.'});
      expect(result.isError, isFalse);
      expect(result.structured!['receipt'], receipt);
      expect(jsonDecode(result.text), result.structured);
      final served = window.calls.single;
      expect((served.asked, served.error), ('a1b2c3d4', null));
      expect(served.input, input);
    });

    test(
      'a refused selected run is a failure, its receipt still served',
      () async {
        final window = FakeWindow()
          ..ran = RunRefused(
            'Team launch a1b2c3d4 was refused before its first job; the '
            'attempted lead is closing.',
            id: 'a1b2c3d4',
            receipt: receipt,
          );
        final result = await toolOf(person(window), 'run_team').call(input);
        expect(result.isError, isTrue);
        expect(result.structured, {
          'error':
              'Team launch a1b2c3d4 was refused before its first job; the '
              'attempted lead is closing.',
          'id': 'a1b2c3d4',
          'receipt': receipt,
        });
        expect(window.calls.single.error, startsWith('Team launch a1b2c3d4'));
      },
    );

    test(
      'with a selection, a field the call does not know refuses it',
      () async {
        final window = FakeWindow();
        final result = await toolOf(
          person(window),
          'run_team',
        ).call({...input, 'extra': true});
        expect(
          (result.text, result.isError),
          ('Invalid run selection. No run started.', true),
        );
        expect(window.selections, isEmpty);
      },
    );
  });

  group('teams', () {
    test("list_teams answers each team's file whole, its open runs, and a "
        'broken file\'s problem', () async {
      final window = FakeWindow()
        ..teamsFound = (
          found: [
            _found('bugfix', team: _bugfix),
            _found(
              'triage',
              problem: 'members.0.name: must not contain the character "',
            ),
          ],
          runs: [(team: 'bugfix', name: 'bugfix 2', id: 'a1b2c3d4')],
        );
      final result = await toolOf(person(window), 'list_teams').call(const {});
      expect(jsonDecode(result.text), {
        'runs': [
          {'team': 'bugfix', 'name': 'bugfix 2', 'id': 'a1b2c3d4'},
        ],
        'teams': [
          {
            'name': 'bugfix',
            'description': 'Fixes a bug end to end',
            'body': '# How it works',
            'lead': {
              'agent': 'claude',
              'model': 'opus',
              'instructions': 'Lead it.\n',
            },
            'members': [
              {
                'name': 'tester',
                'agent': 'codex',
                'mode': 'acceptEdits',
                'instructions': 'Write it.\n',
                'role': 'Writes the failing test',
              },
            ],
            'runs': ['bugfix 2'],
          },
          {
            'name': 'triage',
            'problem':
                'members.0.name: must not contain the character "; it cannot '
                'run until its file is fixed',
          },
        ],
      });
      // The members' keys in the original's order.
      expect(
        ((jsonDecode(result.text) as Map)['teams'] as List)
            .first['members']
            .first
            .keys,
        ['name', 'agent', 'mode', 'instructions', 'role'],
      );
      expect(window.calls.single.tool, ChordTool.listTeams);
    });

    test("run_team hands the window the team and the job, served as the "
        "lead's start", () async {
      final window = FakeWindow()
        ..ran = const Started(
          id: 'a1b2c3d4',
          name: 'bugfix 2',
          agent: 'claude',
          model: 'opus',
          team: 'bugfix',
          effort: 'high',
        );
      final result = await toolOf(
        person(window),
        'run_team',
      ).call({'team': 'bugfix', 'job': 'Fix 214.'});
      expect(window.runArgs.single, (team: 'bugfix', job: 'Fix 214.'));
      expect(jsonDecode(result.text), {
        'id': 'a1b2c3d4',
        'name': 'bugfix 2',
        'agent': 'claude',
        'model': 'opus',
        'team': 'bugfix',
        'effort': 'high',
      });
      expect(window.calls.single.input, {'team': 'bugfix', 'job': 'Fix 214.'});
      expect((toolOf(person(window), 'run_team').inputSchema!['required']), [
        'team',
        'job',
      ]);
    });

    Caller teamAgent(FakeWindow window, TeamSide side) => Caller(
      role: Role.child,
      key: 0,
      agent: '7f3a9c2e',
      team: side,
      window: window,
    );

    test(
      "a lead's open_agent opens a member by its name in the team",
      () async {
        final window = FakeWindow()
          ..member = const Started(
            id: 'b2c3d4e5',
            name: 'tester',
            agent: 'codex',
            mode: 'acceptEdits',
          );
        final lead = teamAgent(window, TeamSide.lead);
        final spec = toolOf(lead, 'open_agent');
        expect(
          spec.inputSchema,
          schema(
            {
              'member': 'The member, by its name in the team',
              'prompt': 'Its first message from you, in full',
            },
            ['member', 'prompt'],
          ),
        );
        final result = await spec.call({'member': 'tester', 'prompt': 'Go.'});
        expect(window.memberArgs.single, (member: 'tester', prompt: 'Go.'));
        expect(jsonDecode(result.text), {
          'id': 'b2c3d4e5',
          'name': 'tester',
          'agent': 'codex',
          'mode': 'acceptEdits',
        });
      },
    );

    test("a lead's and a member's send_message and close_agent say what "
        'they reach', () {
      final window = FakeWindow();
      final lead = teamAgent(window, TeamSide.lead);
      final member = teamAgent(window, TeamSide.member);
      expect(
        toolOf(lead, 'send_message').description,
        startsWith('Sends a message to main, to one of your open members'),
      );
      expect(
        (toolOf(lead, 'send_message').inputSchema!['properties']! as Map)['to'],
        {
          'type': 'string',
          'description': "`main`, a member, or another run's lead, by name",
        },
      );
      expect(
        toolOf(member, 'send_message').description,
        startsWith('Sends a message to your lead, or to another open member'),
      );
      expect(
        toolOf(lead, 'close_agent').description,
        startsWith('Closes a long-lived agent you opened'),
      );
      expect(
        toolOf(member, 'close_agent').description,
        startsWith('Stops a task you started'),
      );
      expect(closesAgents(lead), isTrue);
      expect(closesAgents(member), isFalse);
    });
  });
}

void _forkTests() {
  test("a fork has main's tools; those that open, close or clear agents are "
      'refused it, served as failures', () async {
    final window = FakeWindow()
      ..opened = const Started(id: 'x', name: 'x', agent: 'fake')
      ..closed = const Closed('x')
      ..cleared = const Cleared('x', 'x');
    final fork = Caller(role: Role.person, key: 3, window: window, fork: true);
    expect(
      [for (final tool in toolsOf(fork)) tool.name],
      [for (final tool in toolsOf(person(window))) tool.name],
    );
    const refused =
        'This tool works only from main and its agents, not from a fork.';
    for (final (name, input) in [
      ('open_agent', {'agent': 'fake', 'prompt': 'go'}),
      ('close_agent', {'to': 'x'}),
      ('clear_agent', {'to': 'x'}),
      ('run_team', {'team': 'bugfix', 'job': 'x'}),
    ]) {
      final result = await toolOf(fork, name).call(input);
      expect((result.text, result.isError), (refused, true), reason: name);
      expect(window.calls.last.error, refused);
    }
    // The person's own session is not refused.
    expect(
      (await toolOf(person(window), 'close_agent').call({'to': 'x'})).isError,
      isFalse,
    );
  });
}

void _testerForkEffects() {
  group('CTUI-74 tester: fork refusals have no effects', () {
    test('open close and clear are served once without forwarding', () async {
      final window = _TesterWindow();
      final caller = Caller(
        role: Role.person,
        key: 9,
        fork: true,
        window: window,
      );
      for (final (name, input) in [
        ('open_agent', {'agent': 'fake', 'prompt': 'go'}),
        ('close_agent', {'to': 'existing'}),
        ('clear_agent', {'to': 'existing'}),
      ]) {
        final before = window.calls.length;
        final result = await toolOf(caller, name).call(input);
        expect(result.isError, isTrue);
        expect(result.structured, isNull);
        expect(window.forwarded, isEmpty);
        expect(window.calls, hasLength(before + 1));
        expect(window.calls.last.input, input);
        expect(window.calls.last.answer, isNull);
        expect(window.servedCallers.last, same(caller));
      }
    });
  });
}
