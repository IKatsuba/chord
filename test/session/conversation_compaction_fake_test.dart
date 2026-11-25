// The original's tests/session/conversation_cycle_test.ts for Claude's
// compaction of an idle session (CHD-624 D2), on its fake agent: the
// compaction's opening update is marked unasked from chord's own state, a
// prompt waits behind it, and one asked in a person's turn stays plain.
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'session_fake.dart';

/// Why the fake's `idlecompactfail` compaction failed, as Claude says it.
const compactError = 'Not enough messages to compact.';

/// The chunk `idlecompactsays` sends after its compaction, untagged.
const idleChunk = 'Conversation compacted.';

bool _alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

/// A conversation on Claude's fake that takes compactions by id, started,
/// closed in tearDown.
final class _Fake {
  _Fake() {
    dir = Directory.systemTemp.createTempSync('chord-compaction-');
    conversation = Conversation(
      ({required onTraffic, required cancellationToken}) => openSession(
        agent: 'fake',
        command: fakeAgentCommand(null, ['--adapter', 'claude']),
        cwd: dir.path,
        open: fakeOpenerWith(
          onPid: pids.add,
          capabilities: acp.ClientCapabilities.fromJson({
            'session': {'compaction': <String, Object?>{}},
          }),
        ),
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

  late final Directory dir;
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

  Transcript get transcript => actions.fold(Transcript.empty, reduceTranscript);

  List<CompactionEntry> get compactions =>
      transcript.entries.whereType<CompactionEntry>().toList();

  List<UpdateAction> get marked => [
    for (final action in actions.whereType<UpdateAction>())
      if (action.unasked) action,
  ];

  bool get opened => actions.whereType<UpdateAction>().any(
    (a) => a.update.kind == 'compaction_update',
  );

  /// The idle compaction's last usage, the one with its cost.
  bool get costed => actions.whereType<UpdateAction>().any((a) {
    final json = a.update.toJson();
    return a.update.kind == 'usage_update' &&
        json['used'] == 41200 &&
        json['cost'] != null;
  });

  String get said => [
    for (final action in actions.whereType<UpdateAction>())
      if (action.update.kind == 'agent_message_chunk')
        ((action.update.toJson()['content'] as Map)['text'] as String),
  ].join();

  Future<void> send(String text) async {
    await until(() => events.any((e) => e is Connected));
    conversation.send(text);
  }

  /// Holds the fake's idle compaction until [release].
  void gate() => Directory(p.join(dir.path, '.fake-gate')).createSync();

  void release() =>
      File(p.join(dir.path, '.fake-gate', 'release')).writeAsStringSync('');
}

void main() {
  group("Claude's compaction of an idle session", () {
    test('is marked unasked under the last turn, and opens no cycle, no '
        'second result and no working', () async {
      final f = _Fake();
      await f.send('idlecompact');
      await f.until(() => f.costed);
      final turn = f.actions.whereType<PromptAction>().single.turnId;

      expect(f.actions.whereType<CycleStartedAction>(), isEmpty);
      expect(f.actions.whereType<ResultAction>(), hasLength(1));
      // Only its opening update carries the mark.
      expect(f.marked, hasLength(1));
      expect(f.marked.single.update.kind, 'compaction_update');
      expect(f.marked.single.turnId, turn);
      expect(f.transcript.turn, isA<Idle>());
      expect(
        [
          for (final e in f.compactions)
            (e.turnId, e.compaction.status, e.compaction.unasked),
        ],
        [(turn, 'completed', true)],
      );
    });

    test('a prompt sent while it runs waits behind it, and its entry is '
        'patched in place', () async {
      final f = _Fake();
      f.gate();
      await f.send('idlecompact');
      await f.until(() => f.opened);
      f.conversation.send('text');
      await f.until(
        () => f.actions.whereType<PromptAction>().any((a) => a.text == 'text'),
      );
      expect(f.transcript.turn, isNot(isA<Idle>()));
      f.release();
      await f.until(() => f.said.contains('Hello, world.'));

      final [first, second] = f.actions.whereType<PromptAction>().toList();
      expect(f.actions.whereType<CycleStartedAction>(), isEmpty);
      expect(
        [
          for (final e in f.compactions)
            (e.turnId, e.compaction.status, e.compaction.unasked),
        ],
        [(first.turnId, 'completed', true)],
      );
      expect(second.turnId, isNot(first.turnId));
    });

    test('one that fails is marked too, with its error', () async {
      final f = _Fake();
      await f.send('idlecompactfail');
      await f.until(
        () => f.compactions.any((e) => e.compaction.status == 'failed'),
      );
      final compaction = f.compactions.single.compaction;
      expect(
        (
          compaction.status,
          compaction.summary,
          compaction.error,
          compaction.unasked,
        ),
        ('failed', '', compactError, true),
      );
      expect(f.actions.whereType<CycleStartedAction>(), isEmpty);
    });

    // The owner's O1 a: a chunk nothing ties to the compaction, after a
    // quiet second, is Claude's own work, as `claudecyclebare`.
    test('an untagged chunk after it opens a cycle that stays working until '
        'the next prompt', () async {
      final f = _Fake();
      await f.send('idlecompactsays');
      await f.until(() => f.said.contains(idleChunk));
      final at = f.actions.indexWhere((a) => a is CycleStartedAction);
      expect(at, greaterThan(-1));
      expect(f.actions.skip(at).whereType<ResultAction>(), isEmpty);
      expect(f.transcript.turn, isNot(isA<Idle>()));
    });
  });

  group('idle compaction interruption boundaries', () {
    test('interrupting the prompt queued behind an idle compaction cancels it '
        'in place and the next turn runs', () async {
      final f = _Fake();
      f.gate();
      await f.send('idlecompact');
      await f.until(() => f.compactions.length == 1);
      final original = f.compactions.single;
      expect(original.compaction.unasked, isTrue);
      f.conversation.send('text');
      await f.until(
        () => f.actions.whereType<PromptAction>().any((a) => a.text == 'text'),
      );
      f.conversation.interrupt();
      await f.until(
        () => f.compactions.any((e) => e.compaction.status == 'cancelled'),
      );
      await f.until(
        () => f.actions.whereType<ResultAction>().any(
          (a) => switch (a.result) {
            TurnAnswered(:final cancelled) => cancelled,
            _ => false,
          },
        ),
      );
      final [entry] = f.compactions;
      expect(
        (
          entry.turnId,
          entry.compaction.id,
          entry.compaction.status,
          entry.compaction.unasked,
        ),
        (original.turnId, original.compaction.id, 'cancelled', true),
      );
      expect(f.actions.whereType<CycleStartedAction>(), isEmpty);
      f.conversation.send('text');
      await f.until(() => f.said.contains('Hello, world.'));
    });

    test("a compaction requested in a person's turn remains plain when "
        'cancelled', () async {
      final f = _Fake();
      await f.send('compact');
      await f.until(() => f.compactions.length == 1);
      expect(f.compactions.single.compaction.unasked, isFalse);
      f.conversation.interrupt();
      await f.until(
        () => f.compactions.any((e) => e.compaction.status == 'cancelled'),
      );
      expect(f.compactions.single.compaction.unasked, isFalse);
      expect(f.marked, isEmpty);
    });
  });
}
