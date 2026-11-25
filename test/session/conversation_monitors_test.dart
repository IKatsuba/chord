// A conversation's monitors, as the original's conversation.ts keeps them:
// each batch a message to its agent, queued behind a running turn and
// joined there by later batches, its end the last, the agent's stop
// silent and the person's told, and a close or a clear stopping the rest
// without a word.
import 'dart:async';

import 'package:chord/server/tools.dart'
    show Refused, StartedMonitor, StoppedMonitor;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/monitors.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/shell.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

/// A command the test speaks for: [line] prints, [exit] ends it, and a stop
/// ends it as stopped.
final class _Command extends ShellProcess {
  _Command({this.start});

  /// While set, whether it started is known only once it completes.
  final Completer<String?>? start;
  final _ended = Completer<ShellEnd>();

  @override
  Future<String?> get failed => start?.future ?? Future.value();
  var stops = 0;
  void Function(String line) _print = (_) {};

  @override
  Future<ShellEnd> get ended => _ended.future;

  ShellProcess run(String command, String cwd, void Function(String) onLine) {
    _print = onLine;
    return this;
  }

  void line(String text) => _print(text);

  void exit(int code) {
    if (!_ended.isCompleted) _ended.complete(ShellEnd(code: code));
  }

  @override
  void stop() {
    stops += 1;
    if (!_ended.isCompleted) _ended.complete(const ShellEnd(stopped: true));
  }
}

final class _Rig {
  _Rig(this.async) {
    conversation = Conversation(({
      required onTraffic,
      required cancellationToken,
    }) {
      session = ScriptedSession();
      return Future.value(session);
    });
    conversation.listen(events.add);
    conversation.start();
    async.flushMicrotasks();
  }

  final FakeAsync async;
  late ScriptedSession session;
  late final Conversation conversation;
  final events = <ConversationEvent>[];

  /// Starts a monitor on [command], as [description].
  Object start(_Command command, String description, {num? timeoutMs}) {
    Object? answer;
    asked(command, description, timeoutMs: timeoutMs).then((v) => answer = v);
    async.flushMicrotasks();
    return answer!;
  }

  /// [start]'s call, whose answer may wait.
  Future<Object> asked(
    _Command command,
    String description, {
    num? timeoutMs,
  }) => conversation.startMonitor(
    (command: 'watch', description: description, timeoutMs: timeoutMs),
    '/w',
    run: command.run,
  );

  /// The messages that went to the agent as turns, with their senders.
  List<(String, MessageFrom?)> get delivered => [
    for (final event in events)
      if (event case Transcribed(
        action: PromptAction(:final text, :final from),
      ))
        (text, from),
  ];

  /// Each running list the window was shown, as `id:events`.
  List<List<String>> get shown => [
    for (final event in events)
      if (event is MonitorsChanged)
        [
          for (final monitor in event.running)
            '${monitor.info.id}:${monitor.events}',
        ],
  ];

  void answerTurns() {
    for (final turn in session.turns) {
      turn.answer();
    }
    async.flushMicrotasks();
  }

  /// [answerTurns], then the quiet a queued turn waits for.
  void settle() {
    answerTurns();
    async.elapse(const Duration(milliseconds: quietMs));
  }
}

const _batch = Duration(milliseconds: batchMs);

/// A command whose stop is left to the test, which may fail its end.
final class _HeldStop extends _Command {
  @override
  void stop() => stops += 1;

  void fail() => _ended.completeError(StateError('end failed'));
}

void main() {
  // CTUI-114: a monitor stopped in one error zone (the agent's call in
  // chord's) is waited for by a close from another (the way out's); its end,
  // failed, must reach that close rather than hold it.
  test('a close from another zone hears a monitor stopped elsewhere whose '
      'end failed', () {
    fakeAsync((async) {
      final rig = _Rig(async);
      late _HeldStop command;
      void inOtherZone(void Function() body) =>
          runZonedGuarded(body, (_, _) {});
      inOtherZone(() {
        command = _HeldStop();
        rig.start(command, 'held');
        rig.conversation.stopMonitor('m1');
      });
      async.flushMicrotasks();
      expect(command.stops, 1);
      Object? outcome;
      rig.conversation.close().then<void>(
        (_) => outcome = 'closed',
        onError: (Object error) => outcome = error,
      );
      async.flushMicrotasks();
      inOtherZone(command.fail);
      async.elapse(const Duration(seconds: 5));
      expect(outcome, isA<StateError>());
    });
  });

  test('each batch is a turn for the agent, and its end the last', () {
    fakeAsync((async) {
      final rig = _Rig(async);
      final command = _Command();
      final started = rig.start(command, 'steps');
      expect(started, isA<StartedMonitor>());
      expect((started as StartedMonitor).toJson(), {
        'id': 'm1',
        'description': 'steps',
        'timeout_ms': 600000,
      });
      command.line('one');
      async.elapse(_batch);
      rig.answerTurns();
      command
        ..line('two')
        ..line('three');
      async.elapse(_batch);
      rig.answerTurns();
      async.elapse(const Duration(seconds: 2));
      command.exit(3);
      async.flushMicrotasks();

      const from = MessageFrom('steps', monitor: (id: 'm1', end: null));
      expect(rig.delivered, [
        ('one', from),
        ('two\nthree', from),
        (
          'Exited with code 3 after 2s.',
          const MessageFrom(
            'steps',
            monitor: (id: 'm1', end: MonitorExited(3)),
          ),
        ),
      ]);
      // What the agent reads names the monitor and how it ended.
      expect(
        rig.session.turns.last.text,
        '<message from="steps · monitor · exit code 3" monitor="m1">\n'
        'Exited with code 3 after 2s.\n</message>',
      );
      // The running list had it, then lost it.
      expect(rig.shown, [
        ['m1:0'],
        ['m1:1'],
        ['m1:2'],
        <String>[],
      ]);
      expect(rig.conversation.monitors, isEmpty);
      expect(
        [for (final e in rig.conversation.endedMonitors) e.end],
        [const MonitorExited(3)],
      );
      expect(
        (rig.conversation.stopMonitor('m1') as Refused).error,
        'm1 already ended: exit code 3',
      );
    });
  });

  test('a batch that comes while the agent is in a turn waits behind it, '
      'later batches joining it', () {
    fakeAsync((async) {
      final rig = _Rig(async);
      rig.conversation.send('work');
      async.flushMicrotasks();
      final command = _Command();
      rig.start(command, 'log');
      command.line('first');
      async.elapse(_batch);
      command.line('second');
      async.elapse(_batch);
      final queued = [
        for (final event in rig.events)
          if (event is Queued && event.from?.monitor != null) event,
      ];
      // One message, reported again as the second batch joined it.
      expect({for (final q in queued) q.turnId}, hasLength(1));
      expect([for (final q in queued) q.text], ['first', 'first\nsecond']);
      expect([for (final (_, from) in rig.delivered) ?from], isEmpty);

      rig.settle();
      expect(rig.delivered.last.$1, 'first\nsecond');
      expect(
        rig.session.turns.last.text,
        '<message from="log · monitor" monitor="m1">\nfirst\nsecond\n'
        '</message>',
      );
      // Its end, while that message is still queued, joins it too.
      rig.conversation.send('more');
      async.flushMicrotasks();
      command.line('third');
      async.elapse(_batch);
      command
        ..line('fourth')
        ..exit(1);
      async.flushMicrotasks();
      rig.settle();
      // The first message's turn, then the person's, then the monitor's.
      rig.settle();
      expect(rig.delivered.last, (
        'third\nfourth\nExited with code 1 after 1s.',
        const MessageFrom('log', monitor: (id: 'm1', end: MonitorExited(1))),
      ));
    });
  });

  test("the agent's stop_monitor stops it with no message, the person's "
      'with one; a closing session stops the rest', () {
    fakeAsync((async) {
      final rig = _Rig(async);
      final agent = _Command(), person = _Command(), left = _Command();
      rig.start(agent, 'mine');
      rig.start(person, 'theirs');
      rig.start(left, 'left');
      async.elapse(const Duration(seconds: 3));

      final stopped = rig.conversation.stopMonitor('m1');
      expect((stopped as StoppedMonitor).toJson(), {
        'id': 'm1',
        'description': 'mine',
        'events': 0,
        'ran_ms': 3000,
      });
      person.line('half a batch');
      rig.conversation.stopMonitor('m2', by: StoppedBy.person);
      async.flushMicrotasks();
      expect([agent.stops, person.stops, left.stops], [1, 1, 0]);
      expect(rig.delivered, [
        (
          'half a batch\nThe person stopped it after 3s.',
          const MessageFrom(
            'theirs',
            monitor: (id: 'm2', end: MonitorStopped()),
          ),
        ),
      ]);
      expect(
        (rig.conversation.stopMonitor('m1') as Refused).error,
        'm1 already ended: stopped',
      );
      expect(
        (rig.conversation.stopMonitor('m9') as Refused).error,
        'No running monitor m9 of yours; list_monitors names them',
      );
      expect(
        [for (final e in rig.conversation.endedMonitors) e.info.id],
        ['m1', 'm2'],
      );

      rig.answerTurns();
      final delivered = rig.delivered.length;
      unawaited(rig.conversation.close());
      async.flushMicrotasks();
      expect(left.stops, 1);
      expect(rig.delivered, hasLength(delivered));
      expect(rig.conversation.monitors, isEmpty);
      expect(
        rig.start(_Command(), 'late'),
        isA<Refused>().having(
          (r) => r.error,
          'error',
          'This session has closed',
        ),
      );
    });
  });

  test('a /clear stops its monitors without a word, and the new session '
      'starts again at m1', () {
    fakeAsync((async) {
      final rig = _Rig(async);
      final old = _Command();
      rig.start(old, 'old');
      unawaited(rig.conversation.clear());
      async.flushMicrotasks();
      expect(old.stops, 1);
      expect(rig.conversation.monitors, isEmpty);
      expect(rig.conversation.endedMonitors, isEmpty);
      final fresh = rig.start(_Command(), 'new');
      expect((fresh as StartedMonitor).id, 'm1');
      expect(rig.delivered, isEmpty);
    });
  });

  test('an agent that exits takes its monitors with it, and no turn '
      'follows', () {
    fakeAsync((async) {
      final rig = _Rig(async);
      final command = _Command();
      rig.start(command, 'log');
      rig.session.exit();
      async.flushMicrotasks();
      expect(command.stops, 1);
      expect(rig.conversation.monitors, isEmpty);
      command.line('late');
      async.elapse(_batch * 2);
      expect(rig.delivered, isEmpty);
    });
  });

  test('a close waits for a monitor still starting, which it stops once up, '
      'unregistered and unheard', () {
    fakeAsync((async) {
      final rig = _Rig(async);
      final start = Completer<String?>();
      final command = _Command(start: start);
      Object? answer;
      rig.asked(command, 'slow').then((value) => answer = value);
      expect(rig.conversation.monitorsHeld, 1);
      var closed = false;
      rig.conversation.close().then((_) => closed = true);
      async.flushMicrotasks();
      expect(closed, isFalse);
      start.complete(null);
      async.flushMicrotasks();
      expect(command.stops, 1);
      expect(answer, isA<Refused>());
      expect(closed, isTrue);
      expect(rig.conversation.monitors, isEmpty);
      expect(rig.conversation.monitorsHeld, 0);
      expect(rig.delivered, isEmpty);
    });
  });

  test('a /clear while one starts lets it go; a shell that does not start '
      'gives its id back', () {
    fakeAsync((async) {
      final rig = _Rig(async);
      final start = Completer<String?>();
      final slow = _Command(start: start);
      Object? answer;
      rig.asked(slow, 'slow').then((value) => answer = value);
      unawaited(rig.conversation.clear());
      async.flushMicrotasks();
      start.complete(null);
      async.flushMicrotasks();
      expect(slow.stops, 1);
      expect(answer, isA<Refused>());
      expect(rig.conversation.monitors, isEmpty);

      final refused = rig.start(
        _Command(start: Completer<String?>()..complete('sh did not start')),
        'broken',
      );
      expect(
        (refused as Refused).error,
        'Could not start the command: sh did not start',
      );
      expect((rig.start(_Command(), 'next') as StartedMonitor).id, 'm1');
    });
  });

  group('CTUI-36 tester: conversation monitor isolation', () {
    test('a thousand busy-turn updates coalesce with exact dropped counts', () {
      fakeAsync((async) {
        final rig = _Rig(async);
        rig.conversation.send('busy');
        async.flushMicrotasks();
        final command = _Command();
        rig.start(command, 'log');
        for (var batch = 0; batch < 20; batch++) {
          for (var line = 0; line < 50; line++) {
            command.line('${batch * 50 + line}');
          }
          async.elapse(_batch);
        }
        final queued = rig.events
            .whereType<Queued>()
            .where((q) => q.from?.monitor != null)
            .toList();
        expect({for (final q in queued) q.turnId}, hasLength(1));
        expect(queued.last.text.split('\n').take(100), [
          for (var i = 0; i < 100; i++) '$i',
        ]);
        expect(
          queued.last.text.split('\n').last,
          '… 900 more lines not delivered (an event carries at most 100)',
        );
        command.exit(0);
        async.flushMicrotasks();
        rig.settle();
        final delivered = rig.delivered.where((p) => p.$2?.monitor != null);
        expect(delivered, hasLength(1));
        expect(delivered.single.$2?.monitor?.end, const MonitorExited(0));
        expect(
          delivered.single.$1,
          endsWith(
            '… 900 more lines not delivered (an event carries at most 100)\n'
            'Exited with code 0 after 4s.',
          ),
        );
        rig.answerTurns();
        unawaited(rig.conversation.close());
        async.flushMicrotasks();
      });
    });

    test(
      'same monitor ids in two sessions keep messages and stops separate',
      () {
        fakeAsync((async) {
          final a = _Rig(async), b = _Rig(async);
          final ca = _Command(), cb = _Command();
          expect((a.start(ca, 'A') as StartedMonitor).id, 'm1');
          expect((b.start(cb, 'B') as StartedMonitor).id, 'm1');
          ca.line('only A');
          cb.line('only B');
          async.elapse(_batch);
          expect(a.delivered.single.$1, 'only A');
          expect(b.delivered.single.$1, 'only B');
          a.conversation.stopMonitor('m1');
          async.flushMicrotasks();
          expect(ca.stops, 1);
          expect(cb.stops, 0);
          expect(a.conversation.monitors, isEmpty);
          expect(b.conversation.monitors, hasLength(1));
          b.answerTurns();
          cb.exit(3);
          async.flushMicrotasks();
          expect(b.delivered.last.$2?.monitor?.end, const MonitorExited(3));
          expect(a.delivered, hasLength(1));
          a.answerTurns();
          b.answerTurns();
          unawaited(a.conversation.close());
          unawaited(b.conversation.close());
          async.flushMicrotasks();
        });
      },
    );

    test(
      'a late old start after clear cannot replace fresh m1 or its events',
      () {
        fakeAsync((async) {
          final rig = _Rig(async);
          final gate = Completer<String?>();
          final old = _Command(start: gate);
          Object? oldAnswer;
          rig.asked(old, 'old').then((v) => oldAnswer = v);
          unawaited(rig.conversation.clear());
          async.flushMicrotasks();
          final fresh = _Command();
          expect((rig.start(fresh, 'new') as StartedMonitor).id, 'm1');
          gate.complete(null);
          async.flushMicrotasks();
          expect(oldAnswer, isA<Refused>());
          expect(old.stops, 1);
          old.line('obsolete');
          fresh.line('current');
          async.elapse(_batch);
          expect(rig.delivered.single.$1, 'current');
          expect(rig.delivered.single.$2?.name, 'new');
          expect(rig.conversation.monitors.single.info.description, 'new');
          expect(rig.conversation.monitorsHeld, 1);
          rig.answerTurns();
          unawaited(rig.conversation.close());
          async.flushMicrotasks();
        });
      },
    );
  });
}
