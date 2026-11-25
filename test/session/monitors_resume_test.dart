// A resumed session's monitors, as the original's record.ts and
// conversation.ts read its past: ids go on from it, how each ended answers
// stop_monitor, those left running are named once after the past, and the
// agent is told of them in a turn of its own; none is restarted.
import 'dart:async';

import 'package:chord/server/tools.dart' show Refused, StartedMonitor;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/monitors.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/tasks.dart' show wrapMessage;
import 'package:chord/session/transcript/types.dart';
import 'package:chord/shell.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

ServedAction _served(ChordTool tool, Map<String, Object?> answer) =>
    ServedAction('t', ChordCall(tool: tool, input: const {}, answer: answer));

/// A record's lines: three monitors started, m3 stopped by its agent, m1
/// ended on its own, m2 still sending when the session was left.
List<Map<String, Object?>> _record() {
  Map<String, Object?> served(ChordTool tool, Map<String, Object?> answer) => {
    'type': 'served',
    'turnId': 't0',
    'call': ChordCall(tool: tool, input: const {}, answer: answer).toJson(),
  };
  Map<String, Object?> message(String turnId, MessageFrom from, String text) =>
      {
        'type': 'prompt',
        'turnId': turnId,
        'prompt': wrapMessage(from, text),
        'images': 0,
        'at': 1,
        'from': from.toJson(),
      };
  return [
    {
      'type': 'session',
      'version': 1,
      'sessionId': 's',
      'agent': 'a',
      'cwd': '/w',
      'at': 0,
    },
    {
      'type': 'prompt',
      'turnId': 't0',
      'prompt': 'monitors',
      'images': 0,
      'at': 0,
    },
    served(ChordTool.monitor, {
      'id': 'm1',
      'description': 'log',
      'timeout_ms': 1000,
    }),
    served(ChordTool.monitor, {
      'id': 'm2',
      'description': 'dev server errors',
      'timeout_ms': 1000,
    }),
    served(ChordTool.monitor, {
      'id': 'm3',
      'description': 'tests',
      'timeout_ms': 1000,
    }),
    served(ChordTool.stopMonitor, {'id': 'm3', 'description': 'tests'}),
    {
      'type': 'result',
      'turnId': 't0',
      'result': {'status': 'completed', 'stopReason': 'end_turn'},
    },
    message(
      't1',
      const MessageFrom('log', monitor: (id: 'm1', end: MonitorExited(0))),
      'Exited with code 0 after 1s.',
    ),
    {
      'type': 'result',
      'turnId': 't1',
      'result': {'status': 'completed', 'stopReason': 'end_turn'},
    },
    message(
      't2',
      const MessageFrom('dev server errors', monitor: (id: 'm2', end: null)),
      'ERROR boom',
    ),
    {
      'type': 'result',
      'turnId': 't2',
      'result': {'status': 'completed', 'stopReason': 'end_turn'},
    },
  ];
}

void main() {
  test("a past's monitors: the next id, how each ended, and those left "
      'running', () {
    final past = monitorsPast([
      _served(ChordTool.monitor, {
        'id': 'm1',
        'description': 'log',
        'timeout_ms': 1000,
      }),
      _served(ChordTool.monitor, {
        'id': 'm2',
        'description': 'CI',
        'timeout_ms': 1000,
      }),
      _served(ChordTool.monitor, {
        'id': 'm3',
        'description': 'tests',
        'timeout_ms': 1000,
      }),
      _served(ChordTool.stopMonitor, {'id': 'm3', 'description': 'tests'}),
      const ServedAction(
        't',
        ChordCall(tool: ChordTool.monitor, input: {}, error: 'refused'),
      ),
      const PromptAction(
        't',
        'done',
        0,
        from: MessageFrom('log', monitor: (id: 'm1', end: MonitorExited(0))),
      ),
      const PromptAction(
        't',
        'a line',
        0,
        from: MessageFrom('CI', monitor: (id: 'm2', end: null)),
      ),
    ]);
    expect(past.last, 3);
    expect(past.ended, {'m3': 'stopped', 'm1': 'exit code 0'});
    expect(past.left, [(id: 'm2', description: 'CI')]);
    final none = monitorsPast(const []);
    expect([none.last, none.ended, none.left], [0, isEmpty, isEmpty]);
  });

  test('a resumed record draws its events again, names the monitors left '
      'running last, and keeps that across the record worker', () {
    final history = recordActions(_record());
    final actions = history.actions;
    expect(actions.last, isA<MonitorsLeftAction>());
    expect((actions.last as MonitorsLeftAction).monitors, [
      (id: 'm2', description: 'dev server errors'),
    ]);
    final event = actions.whereType<PromptAction>().firstWhere(
      (p) => p.from?.monitor?.id == 'm2',
    );
    expect(event.text, 'ERROR boom');
    // Across the worker's JSON as well.
    final again = PreparedHistory.fromJson(history.toJson()).actions;
    expect((again.last as MonitorsLeftAction).monitors, [
      (id: 'm2', description: 'dev server errors'),
    ]);
  });

  test('a resumed session tells its agent of the monitors it left running, '
      'goes on from their ids, and refuses to stop one it left', () {
    fakeAsync((async) {
      final events = <ConversationEvent>[];
      late ScriptedSession session;
      final conversation = Conversation(({
        required onTraffic,
        required cancellationToken,
      }) {
        session = ScriptedSession()..prepared = recordActions(_record());
        return Future.value(session);
      });
      conversation.listen(events.add);
      conversation.start();
      async.flushMicrotasks();
      expect(
        session.turns.single.text,
        wrapMessage(
          const MessageFrom('chord'),
          'Your monitor m2 (dev server errors) was running when this session '
          'was left. chord stopped it then, and nothing restarts it; start it '
          'again with monitor if you still need it.',
        ),
      );
      expect(
        (conversation.stopMonitor('m2') as Refused).error,
        'm2 was running when this session was left and was not restarted; '
        'monitor starts another',
      );
      expect(
        (conversation.stopMonitor('m1') as Refused).error,
        'm1 already ended: exit code 0',
      );
      expect(
        (conversation.stopMonitor('m3') as Refused).error,
        'm3 already ended: stopped',
      );
      Object? started;
      conversation
          .startMonitor(
            (command: 'watch', description: 'next', timeoutMs: null),
            '/w',
            run: (command, cwd, onLine) => _Idle(),
          )
          .then((value) => started = value);
      async.flushMicrotasks();
      expect((started as StartedMonitor).id, 'm4');
      session.turns.single.answer();
      async.flushMicrotasks();
    });
  });

  group('CTUI-36 tester: resumed monitor ownership', () {
    test(
      'invalid and refused answers consume no ids or end valid monitors',
      () {
        final past = monitorsPast([
          _served(ChordTool.monitor, {'id': 'm9', 'description': 'last'}),
          _served(ChordTool.monitor, {'id': 'm2', 'description': 'earlier'}),
          _served(ChordTool.monitor, {'id': 100, 'description': 'bad id'}),
          _served(ChordTool.monitor, {'id': 'm100', 'description': 7}),
          const ServedAction(
            't',
            ChordCall(
              tool: ChordTool.monitor,
              input: {},
              answer: {'id': 'm200', 'description': 'refused'},
              error: 'not started',
            ),
          ),
          const ServedAction(
            't',
            ChordCall(
              tool: ChordTool.stopMonitor,
              input: {},
              answer: {'id': 'm9'},
              error: 'not stopped',
            ),
          ),
        ]);
        expect(past.last, 9);
        expect(past.ended, isEmpty);
        expect(past.left, [
          (id: 'm9', description: 'last'),
          (id: 'm2', description: 'earlier'),
        ]);
      },
    );

    test('two resumed sessions tell only their own agent once', () {
      fakeAsync((async) {
        final conversations = <Conversation>[];
        final sessions = <ScriptedSession>[];
        for (final name in ['watch A', 'watch B']) {
          final record = _record();
          for (final line in record) {
            if (line['type'] == 'served') {
              final call = line['call'] as Map;
              final answer = call['answer'];
              if (answer is Map && answer['id'] == 'm2') {
                answer['description'] = name;
              }
            }
          }
          final conversation = Conversation(({
            required onTraffic,
            required cancellationToken,
          }) {
            final session = ScriptedSession()..prepared = recordActions(record);
            sessions.add(session);
            return Future.value(session);
          });
          conversations.add(conversation);
          conversation.start();
          async.flushMicrotasks();
        }
        expect(sessions[0].turns.single.text, contains('m2 (watch A)'));
        expect(sessions[0].turns.single.text, isNot(contains('watch B')));
        expect(sessions[1].turns.single.text, contains('m2 (watch B)'));
        for (var i = 0; i < sessions.length; i++) {
          expect(conversations[i].monitors, isEmpty);
          expect(conversations[i].monitorsHeld, 0);
          sessions[i].turns.single.answer();
        }
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: quietMs));
        for (var i = 0; i < sessions.length; i++) {
          expect(sessions[i].turns, hasLength(1));
          conversations[i].send('next');
          async.flushMicrotasks();
          expect(sessions[i].turns, hasLength(2));
          sessions[i].turns.last.answer();
          unawaited(conversations[i].close());
        }
        async.flushMicrotasks();
      });
    });

    test('an entirely ended past has no left note or resumed agent turn', () {
      final record = _record()
        ..add({
          'type': 'served',
          'turnId': 't2',
          'call': ChordCall(
            tool: ChordTool.stopMonitor,
            input: const {},
            answer: const {'id': 'm2'},
          ).toJson(),
        });
      final history = recordActions(record);
      expect(history.actions.whereType<MonitorsLeftAction>(), isEmpty);
      fakeAsync((async) {
        late ScriptedSession session;
        final conversation = Conversation(({
          required onTraffic,
          required cancellationToken,
        }) {
          session = ScriptedSession()..prepared = history;
          return Future.value(session);
        });
        conversation.start();
        async.flushMicrotasks();
        expect(session.turns, isEmpty);
        expect(conversation.monitors, isEmpty);
        unawaited(conversation.close());
        async.flushMicrotasks();
      });
    });
  });
}

/// A command that prints nothing until stopped.
final class _Idle extends ShellProcess {
  final _ended = Completer<ShellEnd>();

  @override
  Future<ShellEnd> get ended => _ended.future;

  @override
  void stop() {
    if (!_ended.isCompleted) _ended.complete(const ShellEnd(stopped: true));
  }
}
