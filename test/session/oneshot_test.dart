// `chord -p`'s one turn over an agent in memory: the original's
// tests/session/oneshot_test.ts cases the port reaches.
import 'dart:io';
import 'dart:async';

import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart' show MemoryAgentProcess;
import 'package:chord/session/oneshot.dart';
import 'package:chord/session/session.dart' show SessionOpener;
import 'package:chord/session/starting.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

Map<String, Object?> _select(
  String id,
  String category,
  List<String> values,
  String current,
) => {
  'id': id,
  'name': id,
  'type': 'select',
  'category': category,
  'currentValue': current,
  'options': [
    for (final v in values) {'value': v, 'name': v},
  ],
};

/// An agent in memory that answers as a script says, and what it heard.
final class _Agent {
  _Agent({
    this.modes = const ['default', 'plan'],
    this.efforts = const ['low', 'high'],
    this.permission,
    this.usage = const {'inputTokens': 10, 'outputTokens': 2},
    this.cost,
    this.stopReason = 'end_turn',
    this.lastWords = false,
  }) {
    process = MemoryAgentProcess(
      onSignal: (signal) {
        if (process.exited) return;
        // As an agent says its last as it is stopped.
        if (lastWords && !process.exited) {
          _update({
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': ' Bye.'},
          });
          _update({
            'sessionUpdate': 'usage_update',
            'used': 12,
            'size': 100,
            'cost': {'amount': 0.75, 'currency': 'USD'},
            '_meta': {
              'chord/filled': ['cost'],
            },
          });
        }
        process.exit(
          signal == ProcessSignal.sigterm
              ? const Exit(143, 'SIGTERM')
              : const Exit(137, 'SIGKILL'),
        );
        process.closeStdout();
        process.closeStderr();
      },
    );
  }

  final List<String> modes, efforts;
  final Map<String, Object?>? permission;
  final Map<String, num>? usage;
  final num? cost;
  final String stopReason;
  final bool lastWords;
  late final MemoryAgentProcess process;
  late String mode = modes.isEmpty ? '' : modes.first;
  late String effort = efforts.isEmpty ? '' : efforts.first;
  final _answered = <Object?>{};
  Map<String, Object?>? permissionAnswer;
  Object? _promptId;

  List<Map<String, Object?>> get options => [
    if (modes.isNotEmpty) _select('mode', 'mode', modes, mode),
    if (efforts.isNotEmpty) _select('effort', 'thought_level', efforts, effort),
  ];

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

  /// Answers what chord asked since the last step.
  void step() {
    for (final message in [...process.stdin.messages]) {
      final id = message['id'];
      if (message['method'] == null &&
          id == 'ask-1' &&
          permissionAnswer == null) {
        permissionAnswer = message['result'] as Map<String, Object?>?;
        _finish();
        continue;
      }
      if (id == null || !_answered.add(id) || message['method'] == null) {
        continue;
      }
      final params = message['params'] as Map<String, Object?>? ?? const {};
      switch (message['method']) {
        case 'initialize':
          _send({
            'id': id,
            'result': {'protocolVersion': 1},
          });
        case 'session/new':
          _send({
            'id': id,
            'result': {'sessionId': 's1', 'configOptions': options},
          });
        case 'session/set_config_option':
          if (params['configId'] == 'mode') mode = params['value'] as String;
          if (params['configId'] == 'effort') {
            effort = params['value'] as String;
          }
          _send({
            'id': id,
            'result': {'configOptions': options},
          });
        case 'session/prompt':
          _promptId = id;
          if (permission != null) {
            _send({
              'id': 'ask-1',
              'method': 'session/request_permission',
              'params': {
                'sessionId': 's1',
                'toolCall': {'toolCallId': 'w1', 'title': 'Write notes.txt'},
                'options': [
                  {'optionId': 'yes', 'name': 'Allow', 'kind': 'allow_once'},
                  {'optionId': 'no', 'name': 'Deny', 'kind': 'reject_once'},
                ],
                ...permission!,
              },
            });
          } else {
            _finish();
          }
        default:
          _send({'id': id, 'result': <String, Object?>{}});
      }
    }
  }

  void _finish() {
    _update({
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': 'Done in $mode.'},
    });
    if (cost != null) {
      _update({
        'sessionUpdate': 'usage_update',
        'used': 10,
        'size': 100,
        'cost': {'amount': cost, 'currency': 'USD'},
      });
    }
    _send({
      'id': _promptId,
      'result': {'stopReason': stopReason, 'usage': ?usage},
    });
  }
}

/// Runs one turn on [agent] under fake time, with what each hook heard.
({OneshotOutcome outcome, List<String> said, List<String> stderr}) _run(
  _Agent agent, {
  StartingValue? effort,
  StartingValue? mode,
  bool allowAll = false,
}) {
  late OneshotOutcome outcome;
  final said = <String>[], stderr = <String>[];
  fakeAsync((async) {
    var done = false;
    runOneshot(
      agent: 'memory',
      command: 'memory',
      cwd: '/w',
      prompt: 'hello',
      open: agent.open,
      effort: effort,
      mode: mode,
      allowAll: allowAll,
      onUpdate: (update) {
        if (update.toJson()['content'] case {'text': final String text}) {
          said.add(text);
        }
      },
      onRefused: (call) => stderr.add('refused ${call.title}'),
      onAllowed: (call) => stderr.add('allowed ${call.title}'),
      onStartingRefused: (refusal) => stderr.add('could not $refusal'),
    ).then((value) {
      outcome = value;
      done = true;
    });
    for (var i = 0; i < 300 && !done; i++) {
      async.flushMicrotasks();
      agent.step();
      async.elapse(const Duration(milliseconds: 100));
    }
    expect(done, isTrue);
    async.flushMicrotasks();
    expect(agent.process.exited, isTrue);
    expect(async.nonPeriodicTimerCount, 0);
  });
  return (outcome: outcome, said: said, stderr: stderr);
}

void main() {
  group('tester: CTUI-28 oneshot ordering and cleanup', () {
    test(
      'allow-all prefers allow-once even when allow-always is listed first',
      () {
        final agent = _Agent(
          permission: const {
            'options': [
              {'optionId': 'always', 'name': 'Always', 'kind': 'allow_always'},
              {'optionId': 'once', 'name': 'Once', 'kind': 'allow_once'},
              {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_once'},
            ],
          },
        );
        final result = _run(agent, allowAll: true);
        expect(agent.permissionAnswer, {
          'outcome': {'outcome': 'selected', 'optionId': 'once'},
        });
        expect(result.stderr, ['allowed Write notes.txt']);
      },
    );

    test(
      'allow-all falls back to allow-always and to refusal when neither allow option exists',
      () {
        final always = _Agent(
          permission: const {
            'options': [
              {'optionId': 'always', 'name': 'Always', 'kind': 'allow_always'},
              {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_once'},
            ],
          },
        );
        _run(always, allowAll: true);
        expect(always.permissionAnswer, {
          'outcome': {'outcome': 'selected', 'optionId': 'always'},
        });
        final denied = _Agent(
          permission: const {
            'options': [
              {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_always'},
            ],
          },
        );
        final result = _run(denied, allowAll: true);
        expect(denied.permissionAnswer, {
          'outcome': {'outcome': 'selected', 'optionId': 'deny'},
        });
        expect(result.stderr, ['refused Write notes.txt']);
        final cancelled = _Agent(
          permission: const {
            'options': [
              {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
            ],
          },
        );
        _run(cancelled);
        expect(cancelled.permissionAnswer, {
          'outcome': {'outcome': 'cancelled'},
        });
      },
    );

    test(
      'a slow update callback preserves order through transport close and delays completion',
      () {
        fakeAsync((async) {
          final agent = _Agent(cost: 0.25, lastWords: true);
          final gate = Completer<void>();
          final heard = <String>[];
          OneshotOutcome? outcome;
          runOneshot(
            agent: 'memory',
            command: 'memory',
            cwd: '/w',
            prompt: 'hello',
            open: agent.open,
            onRefused: (_) {},
            onUpdate: (update) {
              final json = update.toJson();
              heard.add(
                json['content'] is Map
                    ? (json['content'] as Map)['text'] as String
                    : 'cost ${(json['cost'] as Map)['amount']}',
              );
              if (heard.length == 1) return gate.future;
            },
          ).then((value) => outcome = value);
          for (var step = 0; step < 300 && !agent.process.exited; step++) {
            async.flushMicrotasks();
            agent.step();
            async.elapse(const Duration(milliseconds: 100));
          }
          expect(agent.process.exited, isTrue);
          expect(heard, ['Done in default.']);
          expect(outcome, isNull);
          gate.complete();
          async.flushMicrotasks();
          expect(heard, [
            'Done in default.',
            'cost 0.25',
            ' Bye.',
            'cost 0.75',
          ]);
          expect(outcome!.cost, (amount: 0.75, currency: 'USD'));
          expect(outcome!.costEstimated, isTrue);
          expect(async.nonPeriodicTimerCount, 0);
        });
      },
    );

    test(
      'startup diagnostic failure closes the acquired agent without sending a prompt',
      () {
        fakeAsync((async) {
          final agent = _Agent();
          Object? caught;
          runOneshot(
            agent: 'memory',
            command: 'memory',
            cwd: '/w',
            prompt: 'never sent',
            open: agent.open,
            mode: const StartingValue('unoffered'),
            onUpdate: (_) {},
            onRefused: (_) {},
            onStartingRefused: (_) =>
                Future<void>.error(StateError('diagnostic failed')),
          ).then<void>(
            (_) => fail('unexpected success'),
            onError: (Object error) {
              caught = error;
            },
          );
          for (var step = 0; step < 300 && caught == null; step++) {
            async.flushMicrotasks();
            agent.step();
            async.elapse(const Duration(milliseconds: 100));
          }
          expect(caught, isA<StateError>());
          expect(agent.process.exited, isTrue);
          expect(
            agent.process.stdin.messages.where(
              (m) => m['method'] == 'session/prompt',
            ),
            isEmpty,
          );
          expect(async.nonPeriodicTimerCount, 0);
        });
      },
    );

    test(
      'a startup permission waits for its asynchronous diagnostic before setup continues',
      () {
        fakeAsync((async) {
          final agent = _Agent();
          final gate = Completer<void>();
          final order = <String>[];
          Object? setter;
          OneshotOutcome? outcome;
          runOneshot(
            agent: 'memory',
            command: 'memory',
            cwd: '/w',
            prompt: 'hello',
            open: agent.open,
            mode: const StartingValue('plan'),
            onUpdate: (_) {},
            onRefused: (_) async {
              order.add('diagnostic');
              await gate.future;
              order.add('diagnostic done');
            },
          ).then((value) => outcome = value);
          for (var step = 0; step < 20 && setter == null; step++) {
            async.flushMicrotasks();
            final setters = agent.process.stdin.messages
                .where((m) => m['method'] == 'session/set_config_option')
                .toList();
            if (setters.isNotEmpty) {
              setter = setters.single['id'];
              agent._answered.add(setter);
              break;
            }
            agent.step();
          }
          expect(setter, isNotNull);
          agent._send({
            'id': 'startup-ask',
            'method': 'session/request_permission',
            'params': {
              'sessionId': 's1',
              'toolCall': {'toolCallId': 'setup', 'title': 'Setup'},
              'options': [
                {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_once'},
              ],
            },
          });
          async.flushMicrotasks();
          expect(order, ['diagnostic']);
          expect(
            agent.process.stdin.messages.where((m) => m['id'] == 'startup-ask'),
            isEmpty,
          );
          expect(
            agent.process.stdin.messages.where(
              (m) => m['method'] == 'session/prompt',
            ),
            isEmpty,
          );
          gate.complete();
          async.flushMicrotasks();
          expect(order, ['diagnostic', 'diagnostic done']);
          expect(
            agent.process.stdin.messages.singleWhere(
              (m) => m['id'] == 'startup-ask',
            )['result'],
            {
              'outcome': {'outcome': 'selected', 'optionId': 'deny'},
            },
          );
          agent.mode = 'plan';
          agent._send({
            'id': setter,
            'result': {'configOptions': agent.options},
          });
          for (var step = 0; step < 300 && outcome == null; step++) {
            async.flushMicrotasks();
            agent.step();
            async.elapse(const Duration(milliseconds: 100));
          }
          expect(outcome, isNotNull);
          expect(agent.process.exited, isTrue);
          expect(async.nonPeriodicTimerCount, 0);
        });
      },
    );
  });
  test('one turn: its reply, its usage and cost, and the session id', () {
    final run = _run(_Agent(cost: 0.25));
    expect(run.said, ['Done in default.']);
    expect(run.outcome.sessionId, 's1');
    expect(run.outcome.usage, {'inputTokens': 10, 'outputTokens': 2});
    expect(run.outcome.cost, (amount: 0.25, currency: 'USD'));
    expect(run.outcome.costEstimated, isFalse);
    expect((run.outcome.result as TurnAnswered).stopReason, 'end_turn');
  });

  test('a permission is refused, and the hook says so', () {
    final agent = _Agent(permission: const {});
    final run = _run(agent);
    expect(run.stderr, ['refused Write notes.txt']);
    expect(agent.permissionAnswer, {
      'outcome': {'outcome': 'selected', 'optionId': 'no'},
    });
  });

  test(
    'allowing every permission answers allow once, and the hook names it',
    () {
      final agent = _Agent(permission: const {});
      final run = _run(agent, allowAll: true);
      expect(run.stderr, ['allowed Write notes.txt']);
      expect(agent.permissionAnswer, {
        'outcome': {'outcome': 'selected', 'optionId': 'yes'},
      });
    },
  );

  test('a permission a safety review sent is refused even under allowAll', () {
    final agent = _Agent(
      permission: const {
        '_meta': {
          'chord/permission': {
            'review': {'outcome': 'caution', 'reason': 'Too risky.'},
          },
        },
      },
    );
    final run = _run(agent, allowAll: true);
    expect(run.stderr, ['refused Write notes.txt']);
    expect(agent.permissionAnswer, {
      'outcome': {'outcome': 'selected', 'optionId': 'no'},
    });
  });

  test('the effort and mode are set before the prompt, and a refusal is '
      'said with where it was set', () {
    final agent = _Agent();
    final run = _run(
      agent,
      effort: const StartingValue('high', from: 'set by --effort'),
      mode: const StartingValue('yolo', from: 'set in .chord/settings.json'),
    );
    expect(agent.effort, 'high');
    expect(run.stderr, [
      'could not start in yolo mode, set in .chord/settings.json: the agent '
          'offers default, plan',
    ]);
    expect(run.said, ['Done in default.']);
    final ok = _Agent();
    _run(
      ok,
      mode: const StartingValue('plan', from: 'set by --permission-mode'),
    );
    expect(ok.mode, 'plan');
  });

  test('an agent with no modes is said to offer none, and the turn runs', () {
    final run = _run(
      _Agent(modes: const []),
      mode: const StartingValue('plan', from: 'set by --permission-mode'),
    );
    expect(run.stderr, [
      'could not start in plan mode, set by --permission-mode: the agent '
          'offers no modes',
    ]);
    expect(run.said, hasLength(1));
  });

  test('a turn that stops short comes back as it ended', () {
    final run = _run(_Agent(stopReason: 'max_tokens', usage: null));
    expect((run.outcome.result as TurnAnswered).stopReason, 'max_tokens');
    expect(run.outcome.usage, isNull);
  });
  test('an effort asked of an agent with none is said, and the turn runs', () {
    final run = _run(
      _Agent(efforts: const []),
      effort: const StartingValue('high', from: 'set by --effort'),
    );
    expect(run.stderr, [
      'could not start on high effort, set by --effort: the agent offers no '
          'efforts',
    ]);
    expect(run.said, hasLength(1));
  });

  test('what the agent says as it is stopped still reaches the turn, its '
      'last cost winning', () {
    final run = _run(_Agent(cost: 0.25, lastWords: true));
    expect(run.said, ['Done in default.', ' Bye.']);
    expect(run.outcome.cost, (amount: 0.75, currency: 'USD'));
    expect(run.outcome.costEstimated, isTrue);
  });
}
