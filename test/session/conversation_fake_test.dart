// The conversation on the original's fake agent, folded into the window's
// state: the original's tests/session/conversation_fake_test.ts, the
// scenarios M1 plays.
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:chord/session/conversation.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/start_state.dart';
import 'package:test/test.dart';

import 'session_fake.dart';
import 'transcript/fold.dart';

const _crashWords =
    'fatal: out of memory reading tests/parse/fixtures/huge.json';

bool _alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

/// A conversation on the fake, started, its state folded as the window
/// folds it, closed in tearDown.
final class _Window {
  _Window({String? scenario}) {
    final dir = Directory.systemTemp.createTempSync('chord-conversation-');
    conversation = Conversation(
      ({required onTraffic, required cancellationToken}) => openSession(
        agent: 'fake',
        command: fakeAgentCommand(scenario),
        cwd: dir.path,
        open: fakeSessionOpener(pids.add),
        onTraffic: onTraffic,
        cancellationToken: cancellationToken,
      ),
    );
    conversation.listen((event) {
      events.add(event);
      state = reduceApp(state, event);
      for (final waiter in [..._waiters]) {
        if (waiter.$1(state)) {
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
  var state = AppState.starting;
  final _waiters = <(bool Function(AppState), Completer<void>)>[];

  /// Settles once the state holds [matches].
  Future<void> until(bool Function(AppState state) matches) {
    if (matches(state)) return Future.value();
    final done = Completer<void>();
    _waiters.add((matches, done));
    return done.future.timeout(const Duration(seconds: 20));
  }

  Future<void> connected() =>
      until((s) => s.start.phase == StartPhase.connected);

  Future<void> idleAfter(int entries) => until(
    (s) => s.transcript.turn is Idle && s.transcript.entries.length >= entries,
  );

  List<Object?> get entries => described(state.transcript)['entries'] as List;
}

void main() {
  test(
    'clear retires a running fake and opens a fresh agent with empty transcript',
    () async {
      final w = _Window();
      await w.connected();
      w.conversation.send('slow');
      await w.until(
        (state) =>
            state.transcript.entries.whereType<AssistantEntry>().isNotEmpty,
      );
      w.conversation.send('queued before clear');
      final old = w.pids.single;
      await w.conversation.clear();
      await w.connected();
      expect(w.pids, hasLength(2));
      expect(_alive(old), isFalse);
      expect(w.state.transcript.entries, isEmpty);
      expect(w.state.queue, isEmpty);
      expect(
        w.events.whereType<QueueWithdrawn>().single.prompts.single.text,
        'queued before clear',
      );
      w.conversation.send('text');
      await w.idleAfter(2);
      expect(
        w.state.transcript.entries.whereType<UserEntry>().single.text,
        'text',
      );
    },
    skip: fakeAgentSkip,
  );

  final skip = fakeAgentSkip;

  test("a reply folds into one block, the turn idle after the agent's "
      'answer', () async {
    final w = _Window();

    await w.connected();
    w.conversation.send('text');
    await w.idleAfter(2);

    expect(w.entries, [
      {'turnId': 'turn-1', 'kind': 'user', 'text': 'text'},
      {
        'turnId': 'turn-1',
        'kind': 'assistant',
        'text': 'Hello, world. This reply came in chunks.',
      },
    ]);
  }, skip: skip);

  test("a late update folds under its own turn while the next waits out the "
      'quiet', () async {
    final w = _Window();

    await w.connected();
    w.conversation.send('late');
    w.conversation.send('text');
    await w.idleAfter(4);

    expect(w.entries, [
      {'turnId': 'turn-1', 'kind': 'user', 'text': 'late'},
      {
        'turnId': 'turn-1',
        'kind': 'assistant',
        'text': 'Answered. Late, after the answer.',
      },
      {'turnId': 'turn-2', 'kind': 'user', 'text': 'text'},
      {
        'turnId': 'turn-2',
        'kind': 'assistant',
        'text': 'Hello, world. This reply came in chunks.',
      },
    ]);
  }, skip: skip);

  test(
    'a permission chosen is recorded and the turn goes on to its end',
    () async {
      final w = _Window();

      await w.connected();
      w.conversation.send('permission');
      await w.until((s) => s.transcript.turn is AwaitingPermission);

      final wait =
          (w.state.transcript.turn as AwaitingPermission).permissions.single;

      expect(wait.title, 'Write notes.txt');
      w.conversation.choose(wait.id, 'allow');
      await w.idleAfter(4);

      final answer = w.state.transcript.entries
          .whereType<PermissionEntry>()
          .single;

      expect(
        [answer.title, answer.option?.optionId],
        ['Write notes.txt', 'allow'],
      );
      expect(
        w.state.transcript.entries.whereType<ToolEntry>().single.call.status,
        'completed',
      );
    },
    skip: skip,
  );

  test(
    'Esc stops a slow turn: Interrupting, then Interrupted by user',
    () async {
      final w = _Window();

      await w.connected();
      w.conversation.send('slow');
      await w.until((s) => s.transcript.entries.length >= 2);
      w.conversation.interrupt();

      expect(w.state.transcript.turn, isA<Cancelling>());
      await w.idleAfter(3);
      expect(w.state.transcript.entries.last, isA<CancelledEntry>());
    },
    skip: skip,
  );

  test('an exit mid-turn fails the turn with the last words, and the window '
      'is gone', () async {
    final w = _Window();

    await w.connected();
    w.conversation.send('crash');
    await w.until((s) => s.start.phase == StartPhase.gone);
    await w.idleAfter(3);

    expect(w.entries.last, {
      'turnId': 'turn-1',
      'kind': 'error',
      'message': 'The agent exited: $_crashWords',
    });
    expect(w.state.start.stderrLines, contains(_crashWords));
  }, skip: skip);

  test('unknown update kinds and notifications draw nothing, and the turn '
      'ends', () async {
    final w = _Window();

    await w.connected();
    w.conversation.send('unknown');
    await w.until(
      (s) => s.transcript.turn is Idle && s.transcript.entries.isNotEmpty,
    );

    expect(
      w.state.transcript.entries.map((e) => e.runtimeType).toSet(),
      everyElement(isIn([UserEntry, AssistantEntry])),
    );
  }, skip: skip);
}
