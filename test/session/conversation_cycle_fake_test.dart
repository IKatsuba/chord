// The original's tests/session/conversation_cycle_test.ts on its fake agent
// (CHD-426): Claude's cycle after its turn, codebuddy's marked one, a
// prompt taking one over, Esc in one and a request held inside one.
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'session_fake.dart';

bool _alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

/// A conversation on the fake with [flags], started, closed in tearDown.
final class _Fake {
  _Fake(List<String> flags) {
    final dir = Directory.systemTemp.createTempSync('chord-cycle-');
    conversation = Conversation(
      ({required onTraffic, required cancellationToken}) => openSession(
        agent: 'fake',
        command: fakeAgentCommand(null, flags),
        cwd: dir.path,
        open: fakeSessionOpener(pids.add),
        onTraffic: onTraffic,
        cancellationToken: cancellationToken,
      ),
    );
    conversation.listen((event) {
      events.add(event);
      for (final waiter in [..._waiters]) {
        if (waiter.$1()) {
          _waiters.remove(waiter);
          waiter.$2.complete();
        }
      }
    });
    addTearDown(() async {
      await conversation.close();
      expect(pids.where(_alive), isEmpty, reason: 'the agent is running');
      dir.deleteSync(recursive: true);
    });
    conversation.start();
  }

  late final Conversation conversation;
  final pids = <int>[];
  final events = <ConversationEvent>[];
  final _waiters = <(bool Function(), Completer<void>)>[];

  Future<void> until(bool Function() holds) {
    if (holds()) return Future.value();
    final done = Completer<void>();
    _waiters.add((holds, done));
    return done.future.timeout(const Duration(seconds: 20));
  }

  List<TranscriptAction> get actions => [
    for (final event in events)
      if (event case Transcribed(:final action)) action,
  ];

  /// The actions from the first cycle on.
  List<TranscriptAction> get cycle {
    final at = actions.indexWhere((a) => a is CycleStartedAction);
    return at < 0 ? const [] : actions.sublist(at);
  }

  /// What the agent said in [of], joined.
  static String said(List<TranscriptAction> of) => [
    for (final action in of)
      if (action case UpdateAction(
        :final update,
      ) when update.kind == 'agent_message_chunk')
        ((update.toJson()['content'] as Map)['text'] as String),
  ].join();

  Future<void> send(String text) async {
    await until(() => events.any((e) => e is Connected));
    conversation.send(text);
  }
}

void main() {
  group("an agent's own cycle on the fake", () {
    test("Claude's: its work after the turn has gone quiet is a cycle of its "
        'own, ended by the autonomous usage', () async {
      final f = _Fake(['--adapter', 'claude']);
      await f.send('claudecycle');
      await f.until(() => f.cycle.any((a) => a is ResultAction));
      final turn = f.actions.whereType<PromptAction>().single.turnId;
      final cycle = f.cycle;
      final id = cycle.first.turnId;
      expect(id, isNot(turn));
      expect(
        cycle
            .where((a) => a is UpdateAction || a is ResultAction)
            .every((a) => a.turnId == id),
        isTrue,
      );
      expect(
        _Fake.said(cycle),
        'The background build ended; reading its log. The build passed.',
      );
      final result = cycle.whereType<ResultAction>().single.result;
      expect((result as TurnAnswered).stopReason, acp.StopReason.endTurn);
    });

    test("an agent that is not Claude's has no unmarked cycle: its work after "
        'the turn folds under that turn', () async {
      final f = _Fake(const []);
      await f.send('claudecycle');
      await f.until(() => _Fake.said(f.actions).contains('The build passed.'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(f.cycle, isEmpty);
      final turn = f.actions.whereType<PromptAction>().single.turnId;
      final from = f.actions.indexWhere((a) => a is PromptAction);
      expect(
        f.actions
            .skip(from)
            .whereType<UpdateAction>()
            .every((a) => a.turnId == turn),
        isTrue,
      );
    });

    test(
      "codebuddy's: its marker starts a cycle and session_end ends it",
      () async {
        final f = _Fake(const []);
        await f.send('codebuddycycle');
        await f.until(() => f.cycle.any((a) => a is ResultAction));
        expect(
          _Fake.said(f.cycle),
          'The background task drained; all checks are green.',
        );
        expect(f.cycle.last, isA<ResultAction>());
      },
    );

    test(
      'a prompt sent while a cycle runs goes at once and takes it over',
      () async {
        final f = _Fake(['--adapter', 'claude']);
        await f.send('claudecyclebare');
        await f.until(() => f.cycle.isNotEmpty);
        f.conversation.send('text');
        await f.until(() => _Fake.said(f.actions).contains('Hello, world.'));
        expect(
          [for (final p in f.actions.whereType<PromptAction>()) p.text],
          ['claudecyclebare', 'text'],
        );
        expect(f.events.whereType<Queued>(), isEmpty);
      },
    );

    test('Esc sends session/cancel for it, and the cycle ends as a cancelled '
        'turn does', () async {
      final f = _Fake(['--adapter', 'claude', '--say-cancels']);
      await f.send('claudecyclebare');
      await f.until(() => _Fake.said(f.cycle).contains('The build passed.'));
      final id = f.cycle.first.turnId;
      f.conversation.interrupt();
      final after = f.cycle.where(
        (a) => a is CancelAction || a is ResultAction,
      );
      expect(
        [for (final a in after) (a.runtimeType, a.turnId)],
        [(CancelAction, id), (ResultAction, id)],
      );
      expect(
        (after.last as ResultAction).result,
        isA<TurnAnswered>().having(
          (r) => r.stopReason,
          'stopReason',
          acp.StopReason.cancelled,
        ),
      );
      await f.until(
        () => _Fake.said(f.actions).contains('Cancel heard with no turn.'),
      );
      f.conversation.send('cancels');
      await f.until(
        () => _Fake.said(f.actions).contains('Cancels with no turn:'),
      );
      expect(_Fake.said(f.actions), contains('Cancels with no turn: 1.'));
    });

    test('a request asked in a cycle is held between turns; answered, the '
        'cycle ends on its usage', () async {
      final f = _Fake(['--adapter', 'claude']);
      await f.send('claudecycleask');
      await f.until(() => f.cycle.any((a) => a is PermissionRequestedAction));
      final asked = f.cycle.whereType<PermissionRequestedAction>().single;
      expect((asked.turnId, asked.between), (f.cycle.first.turnId, true));
      f.conversation.choose(asked.wait.id, 'allow');
      await f.until(() => f.cycle.any((a) => a is ResultAction));
      expect(_Fake.said(f.cycle), contains('Permission: allow.'));
    });
  }, skip: fakeAgentSkip);
}
