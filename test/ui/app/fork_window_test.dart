// `/fork` in the window, as the original's tests/ui/app/AppFork_test.tsx
// has it (CHD-101): the fork is picked at once, listed after main as a
// fork, its view the conversation as it stood under a dim divider, and the
// command said on the agent it was typed on; refusals said under it,
// nothing opened. The divider's line and its record are the original's
// message_test and record shapes.
@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/session/agents_host.dart';
import 'package:chord/session/place.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/sessions.dart' show Resume;
import 'package:chord/session/replay.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/window_fold.dart' show mainKey;
import 'package:chord/ui/start_state.dart';
import 'package:chord/ui/transcript/message.dart' show forkedLine;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import '../../fixtures/runtimes.dart';
import 'editor_window_test.dart' show plainLaunch, settle;

/// The window over main on the fake, which forks unless [forks] is false;
/// [env] goes to the fake as well. With [stateDir], each session keeps its
/// record there; with [resume], main is that record resumed, on [runtimes].
Future<StartConnection> _fake(
  WidgetTester t,
  Size size, {
  bool forks = true,
  Map<String, String> env = const {},
  String? stateDir,
  Resume? resume,
  TestRuntimes? runtimes,
}) async {
  final own = runtimes == null;
  final fakes =
      runtimes ??
      TestRuntimes(
        fakes: {
          'fake': (scenario: null, flags: forks ? ['--fork'] : <String>[]),
        },
      );
  void failed(Object error) => fail('record: $error');
  final connection = StartConnection(
    command: fakes.commandOf('fake'),
    env: {...fakes.env, ...env},
    cwd: fakes.home.path,
    agent: 'fake',
    open: fakes.opener,
    resume: resume,
    recording: stateDir == null
        ? null
        : FileRecording(stateDir, failed: failed),
  );
  final fold = connection.fold;
  connection
    ..window = AgentsHost(
      runtimeNames: const ['fake'],
      startupOf: (runtime) =>
          SessionStart(command: fakes.commandOf(runtime), env: env),
      openChildSession: connection.openChild,
      openForkSession: connection.openChild,
      agents: connection.agents,
      opened: (key) => fold.dispatch(AgentOpened(key)),
      closed: (key, front) => fold.dispatch(SessionClosed(key, front)),
      recordingOf: stateDir == null
          ? null
          : (child) => FileRecording(stateDir, failed: failed, child: child),
      transcriptOf: (key) => fold.stateOf(key)?.transcript,
    )
    ..start();
  addTearDown(() async {
    await connection.close();
    if (own) fakes.dispose();
  });
  await t.pumpWidget(
    TranscriptWindow(launch: plainLaunch, connection: connection),
    size: size,
  );
  await _until(
    t,
    () => fold.stateOf(mainKey)?.start.phase == StartPhase.connected,
  );
  return connection;
}

Future<void> _until(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 1500 && !done(); i++) {
    await t.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: t.screen.text);
}

Future<void> _send(WidgetTester t, String typed) async {
  await t.type(typed);
  await t.press('enter');
  await settle(t);
}

/// [connection]'s turn on [key] over.
Future<void> _idle(WidgetTester t, StartConnection connection, int key) =>
    _until(
      t,
      () => connection.fold.stateOf(key)?.transcript.turn is model.Idle,
    );

/// The notes [key]'s transcript holds, as words and whether they failed.
List<(String, bool)> _notes(StartConnection connection, int key) => [
  for (final entry
      in connection.fold.stateOf(key)?.transcript.entries ??
          const <model.Entry>[])
    if (entry is model.NotedEntry) (entry.text, entry.failed),
];

/// The list's rows, from main's on.
List<String> _list(WidgetTester t) {
  final lines = t.screen.lines;
  final first = lines.indexWhere(
    (line) => line.startsWith('    main ') || line.startsWith('  ❯ main '),
  );
  return first < 0 ? const [] : lines.sublist(first);
}

/// The list's `❯` on [name], from the prompt.
Future<void> _toRow(WidgetTester t, String name) async {
  for (
    var i = 0;
    i < 8 && !_list(t).any((l) => l.startsWith('  ❯ $name '));
    i++
  ) {
    await t.press(i < 4 ? 'down' : 'up');
    await settle(t);
  }
  expect(_list(t), contains(startsWith('  ❯ $name ')), reason: t.screen.text);
}

/// Every record in [stateDir], as parsed.
Future<List<List<Object?>>> _records(String stateDir) async => [
  for (final file in Directory(recordsDir(stateDir)).listSync())
    if (file is File) parseRecord(await file.readAsString()),
];

/// A record's entries of [type].
List<Map<String, Object?>> _typed(List<Object?> record, String type) => [
  for (final entry in record)
    if (entry case {'type': final String kind} when kind == type)
      entry as Map<String, Object?>,
];

/// What told [key] the person cleared or closed one of its agents.
List<String> _told(StartConnection connection, int key) => [
  for (final entry
      in connection.fold.stateOf(key)?.transcript.entries ??
          const <model.Entry>[])
    if (entry case model.UserEntry(
      :final text,
    ) when text.contains('The person'))
      text,
];

void main() {
  test('a fork says where it parted, by its source and the local time, cut '
      'to its cells', () {
    final at = DateTime(2026, 10, 28, 22, 10).millisecondsSinceEpoch;
    expect(forkedLine('main', at, 80), '── forked from main · 22:10 ──');
    expect(forkedLine('a long fork name', at, 20), hasLength(20));
  });

  test('a record keeps where a fork parted, and replays it across the '
      "worker's JSON", () {
    final history = recordActions([
      {
        'type': 'session',
        'version': 1,
        'sessionId': 's',
        'agent': 'a',
        'cwd': '/w',
        'at': 0,
      },
      {'type': 'forked', 'turnId': 'forked-1', 'from': 'main', 'at': 5},
      {'type': 'prompt', 'turnId': 't1', 'prompt': 'go', 'images': 0, 'at': 6},
    ]);
    model.ForkedAction? forked(List<model.TranscriptAction> actions) =>
        actions.whereType<model.ForkedAction>().singleOrNull;
    final said = forked(history.actions);
    expect(
      (said?.turnId, said?.from, said?.at),
      ('history-forked-1', 'main', 5),
    );
    final again = forked(PreparedHistory.fromJson(history.toJson()).actions);
    expect((again?.from, again?.at), ('main', 5));
  });

  final skip = fakeAgentSkip;
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('at $size', () {
      testWidgets(
        'it is picked at once, listed after main as a fork, its view the '
        'conversation as it stood under the divider, and main says where '
        'it went',
        (t) async {
          final connection = await _fake(t, size);
          await _send(t, 'text');
          await _idle(t, connection, mainKey);
          await t.type('/fork');
          await settle(t);
          expect(
            t.screen.text,
            contains('Fork the conversation into a new agent'),
          );
          await t.press('enter');
          await _until(t, () => t.screen.text.contains('── forked from main'));
          final fork = connection.agents.agents.children.single;
          expect(connection.agents.agents.picked, fork.key);
          final screen = t.screen.text;
          expect(screen, contains('╭─ fork '));
          expect(screen, contains('forked from main'));
          expect(screen, contains('    fork  fork · fake'));
          expect(screen, contains('This reply came in chunks.'));
          // The copy comes first, then where it parted.
          final entries = connection.fold.stateOf(fork.key)!.transcript.entries;
          expect(entries.last, isA<model.ForkedEntry>());
          expect(entries.whereType<model.AssistantEntry>(), isNotEmpty);
          expect(_notes(connection, mainKey), [('Forked into fork', false)]);
          expect(_notes(connection, fork.key), isEmpty);
        },
        skip: skip,
      );

      testWidgets('a fork forks too, said on the fork it was typed on', (
        t,
      ) async {
        final connection = await _fake(t, size);
        await _send(t, '/fork');
        await _until(t, () => t.screen.text.contains('╭─ fork '));
        final first = connection.agents.agents.children.single;
        await _idle(t, connection, first.key);
        await _send(t, '/fork parser');
        await _until(t, () => t.screen.text.contains('╭─ parser '));
        expect(t.screen.text, contains('forked from fork'));
        expect(connection.agents.agents.children.last.forkedFrom, 'fork');
        expect(_notes(connection, first.key), [('Forked into parser', false)]);
      }, skip: skip);

      testWidgets('an agent that does not fork is refused under the command, '
          'nothing opened', (t) async {
        final connection = await _fake(t, size, forks: false);
        await _send(t, '/fork');
        await _until(t, () => _notes(connection, mainKey).isNotEmpty);
        expect(_notes(connection, mainKey), [
          ('This agent does not fork sessions', true),
        ]);
        expect(connection.agents.agents.children, isEmpty);
        expect(t.screen.text, isNot(contains('╭─ fork')));
      }, skip: skip);

      testWidgets('a fork the agent refuses is said under the command, nothing '
          'opened', (t) async {
        final connection = await _fake(
          t,
          size,
          env: const {'CHORD_FAKE_REFUSE_FORK': '1'},
        );
        await _send(t, '/fork');
        await _until(t, () => _notes(connection, mainKey).isNotEmpty);
        final (text, failed) = _notes(connection, mainKey).single;
        // The agent's own words, on one line, as the original says them.
        final source = connection.conversation.session!.id;
        expect(
          (text, failed),
          ('Could not fork: Resource not found: $source', true),
        );
        await _until(t, () => connection.agents.agents.children.isEmpty);
        expect(t.screen.text, isNot(contains('fork · fake')));
      }, skip: skip);

      testWidgets(
        "/clear on a picked fork gives it a fresh session and empties "
        "its view, the source's copy and divider gone, no one told; main's "
        '/clear leaves it open',
        (t) async {
          final connection = await _fake(t, size);
          await _send(t, '/echo source-marker');
          await _idle(t, connection, mainKey);
          await _send(t, '/fork');
          await _until(t, () => t.screen.text.contains('── forked from main'));
          final fork = connection.agents.agents.children.single;
          await _idle(t, connection, fork.key);
          final before = fork.conversation.session?.id;
          await _send(t, '/clear');
          await _until(
            t,
            () =>
                fork.conversation.session?.id != null &&
                fork.conversation.session?.id != before,
          );
          await _until(t, () => !t.screen.text.contains('── forked from main'));
          expect(connection.agents.agents.picked, fork.key);
          expect(t.screen.text, contains('╭─ fork '));
          expect(t.screen.text, isNot(contains('source-marker')));
          expect(
            connection.fold
                .stateOf(fork.key)!
                .transcript
                .entries
                .whereType<model.ForkedEntry>(),
            isEmpty,
          );
          expect(_told(connection, mainKey), isEmpty);
          // Main's /clear leaves the fork open, its row in the list.
          await _toRow(t, 'main');
          await t.press('enter');
          await settle(t);
          await _send(t, '/clear');
          await _until(t, () => !t.screen.text.contains('source-marker'));
          expect(connection.agents.agents.children.single.key, fork.key);
          expect(_list(t).join('\n'), contains('fork  fork · fake'));
        },
        skip: skip,
      );

      testWidgets('x closes a picked fork, the list goes with it, main in view '
          'and told nothing', (t) async {
        final connection = await _fake(t, size);
        await _send(t, '/fork');
        await _until(t, () => t.screen.text.contains('╭─ fork '));
        final fork = connection.agents.agents.children.single;
        await _idle(t, connection, fork.key);
        await _toRow(t, 'fork');
        await t.press('x');
        await _until(t, () => connection.agents.agents.children.isEmpty);
        await settle(t);
        expect(connection.fold.front, mainKey);
        expect(t.screen.text, isNot(contains('fork · fake')));
        expect(t.screen.text, isNot(contains('╭─ fork')));
        expect(_told(connection, mainKey), isEmpty);
      }, skip: skip);

      testWidgets('a fork resumed is a session of its own: its record starts '
          "at the divider, the source's conversation not in it", (t) async {
        final runtimes = TestRuntimes(
          fakes: {
            'fake': (scenario: null, flags: ['--fork']),
          },
        );
        addTearDown(runtimes.dispose);
        final stateDir = p.join(runtimes.home.path, 'state', 'chord');
        final connection = await _fake(
          t,
          size,
          stateDir: stateDir,
          runtimes: runtimes,
        );
        await _send(t, '/echo source-marker');
        await _idle(t, connection, mainKey);
        await _send(t, '/fork alpha');
        await _until(t, () => t.screen.text.contains('── forked from main'));
        final fork = connection.agents.agents.children.single;
        await _idle(t, connection, fork.key);
        await _send(t, '/echo fork-marker');
        await _idle(t, connection, fork.key);
        final forkId = fork.conversation.session!.id;
        List<Object?>? record;
        await _until(t, () {
          record = null;
          for (final each in Directory(recordsDir(stateDir)).listSync()) {
            if (each is! File) continue;
            final entries = parseRecord(each.readAsStringSync());
            final header = _typed(entries, 'session').firstOrNull;
            if (header?['sessionId'] == forkId &&
                _typed(entries, 'prompt').isNotEmpty) {
              record = entries;
            }
          }
          return record != null;
        });
        final header = _typed(record!, 'session').single;
        expect((header['name'], header['parent']), ('alpha', null));
        expect(
          [for (final e in _typed(record!, 'forked')) e['from']],
          ['main'],
        );
        expect(
          [for (final e in _typed(record!, 'prompt')) e['prompt']],
          ['/echo fork-marker'],
        );
        expect(await _records(stateDir), hasLength(2));
        final path = [
          for (final each in Directory(recordsDir(stateDir)).listSync())
            if (each is File &&
                _typed(
                      parseRecord(each.readAsStringSync()),
                      'session',
                    ).firstOrNull?['sessionId'] ==
                    forkId)
              each.path,
        ].single;
        await connection.close();

        // Resumed on its own, the divider and its own turn, nothing of main's.
        final resumed = await _fake(
          t,
          size,
          stateDir: stateDir,
          runtimes: runtimes,
          resume: Resume(
            sessionId: forkId,
            cwd: runtimes.home.path,
            record: path,
          ),
        );
        await _until(t, () => t.screen.text.contains('── forked from main'));
        final entries = resumed.fold.stateOf(mainKey)!.transcript.entries;
        expect(entries.whereType<model.ForkedEntry>(), hasLength(1));
        expect(t.screen.text, isNot(contains('source-marker')));
        expect(resumed.agents.agents.children, isEmpty);
      }, skip: skip);
    });
  }

  group('CTUI-74 tester: fork snapshot and record boundaries', () {
    test(
      'a Unicode divider fits every tiny cell budget without split graphemes',
      () {
        final at = DateTime(2026, 10, 28, 22, 10).millisecondsSinceEpoch;
        for (var width = 0; width <= 80; width++) {
          final line = forkedLine('界🙂e\u0301' * 10, at, width);
          expect(cellWidth(line), lessThanOrEqualTo(width));
          expect(line, isNot(contains('\uFFFD')));
        }
      },
    );

    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'the live snapshot stays fixed while source and fork get new replies at $size',
        (t) async {
          final connection = await _fake(t, size);
          await _send(t, '/echo before-fork');
          await _idle(t, connection, mainKey);
          await _send(t, '/fork');
          await _until(t, () => t.screen.text.contains('── forked from main'));
          final fork = connection.agents.agents.children.single;
          await _idle(t, connection, fork.key);
          await _toRow(t, 'main');
          await t.press('enter');
          await settle(t);
          await _send(t, '/echo source-after');
          await _idle(t, connection, mainKey);
          await _toRow(t, 'fork');
          await t.press('enter');
          await settle(t);
          await _send(t, '/echo fork-after');
          await _idle(t, connection, fork.key);
          List<String> prompts(int key) => [
            for (final entry
                in connection.fold.stateOf(key)!.transcript.entries)
              if (entry is model.UserEntry) entry.text,
          ];
          expect(prompts(mainKey), contains('/echo source-after'));
          expect(prompts(mainKey), isNot(contains('/echo fork-after')));
          expect(prompts(fork.key), contains('/echo before-fork'));
          expect(prompts(fork.key), contains('/echo fork-after'));
          expect(prompts(fork.key), isNot(contains('/echo source-after')));
          await t.resize(
            size.width == 120 ? const Size(80, 24) : const Size(120, 40),
          );
          await t.pump();
          expect(connection.agents.agents.picked, fork.key);
          expect(t.screen.text, contains('fork-after'));
        },
        skip: skip,
      );

      testWidgets(
        'a fork of a fork records only its own divider and prompts at $size',
        (t) async {
          final runtimes = TestRuntimes(
            fakes: {
              'fake': (scenario: null, flags: ['--fork']),
            },
          );
          addTearDown(runtimes.dispose);
          final stateDir = p.join(runtimes.home.path, 'state', 'chord');
          final connection = await _fake(
            t,
            size,
            runtimes: runtimes,
            stateDir: stateDir,
          );
          await _send(t, '/echo source-marker');
          await _idle(t, connection, mainKey);
          await _send(t, '/fork alpha');
          await _until(t, () => t.screen.text.contains('╭─ alpha '));
          final alpha = connection.agents.agents.children.single;
          await _idle(t, connection, alpha.key);
          await _send(t, '/echo alpha-marker');
          await _idle(t, connection, alpha.key);
          await _send(t, '/fork beta');
          await _until(t, () => t.screen.text.contains('╭─ beta '));
          final beta = connection.agents.agents.children.last;
          await _idle(t, connection, beta.key);
          expect(
            connection.fold
                .stateOf(beta.key)!
                .transcript
                .entries
                .whereType<model.ForkedEntry>(),
            hasLength(2),
          );
          await _send(t, '/echo beta-marker');
          await _idle(t, connection, beta.key);
          await connection.close();
          final record = (await _records(
            stateDir,
          )).singleWhere((r) => _typed(r, 'session').single['name'] == 'beta');
          expect(_typed(record, 'session').single['parent'], isNull);
          expect(_typed(record, 'forked').map((e) => e['from']), ['alpha']);
          expect(_typed(record, 'prompt').map((e) => e['prompt']), [
            '/echo beta-marker',
          ]);
          final replayed = recordActions(record);
          expect(
            replayed.actions.whereType<model.ForkedAction>(),
            hasLength(1),
          );
        },
        skip: skip,
      );
    }
  });
}
