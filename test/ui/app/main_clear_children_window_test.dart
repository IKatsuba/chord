// Main's /clear with long-lived children open, on the original's fake in
// the window: as `clearFront` in the original's src/ui/app/sessions.ts,
// main's children close with the session it lets go, the list goes with
// them, /cost keeps each as `agent, closed`, nobody is told, and no record
// notes a close.
@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/server/server.dart';
import 'package:chord/server/tools.dart' hide Cleared;
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/place.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import '../../fixtures/runtimes.dart';
import 'editor_window_test.dart' show plainLaunch, settle;

/// Main on the fake in the window, kept in a record under its own state
/// directory, with chord's server and the host as the launch wires them.
final class _Rig {
  _Rig(this.connection, this.host, this.stateDir, this.recording);

  final StartConnection connection;
  final AgentsHost host;
  final String stateDir;
  final FileRecording recording;
  final children = <FileRecording>[];

  WindowFold get fold => connection.fold;

  Caller get person => Caller(role: Role.person, key: mainKey, window: host);

  Transcript transcript(int key) => fold.stateOf(key)!.transcript;
}

Future<_Rig> _window(WidgetTester t, Size size) async {
  final server = await serveChord();
  final runtimes = TestRuntimes();
  final stateDir = p.join(runtimes.home.path, 'state', 'chord');
  final recording = FileRecording(stateDir, failed: (_) {});
  final connection = StartConnection(
    command: runtimes.commandOf('fake'),
    env: runtimes.env,
    cwd: runtimes.home.path,
    agent: 'fake',
    open: runtimes.opener,
    recording: recording,
  );
  final fold = connection.fold;
  late final _Rig rig;
  final host = AgentsHost(
    runtimeNames: const ['fake'],
    startupOf: (runtime) => runtime == 'fake'
        ? SessionStart(command: runtimes.commandOf('fake'))
        : null,
    openChildSession: connection.openChild,
    agents: connection.agents,
    opened: (key) => fold.dispatch(AgentOpened(key)),
    closed: (key, front) => fold.dispatch(SessionClosed(key, front)),
    keepClosing: (key, {from, required name, runtime}) => fold.dispatch(
      SpendClosing(key, from: from, name: name, runtime: runtime),
    ),
    keptClosed: (key) => fold.dispatch(SpendClosed(key)),
    server: server,
    recordingOf: (child) {
      final kept = FileRecording(stateDir, failed: (_) {}, child: child);
      rig.children.add(kept);
      return kept;
    },
    transcriptOf: (key) => fold.stateOf(key)?.transcript,
  );
  rig = _Rig(connection, host, stateDir, recording);
  connection
    ..server = server
    ..window = host
    ..start();
  addTearDown(() async {
    await connection.close();
    await server.close();
    runtimes.dispose();
  });
  await t.pumpWidget(
    TranscriptWindow(launch: plainLaunch, connection: connection),
    size: size,
  );
  await _until(
    t,
    () => fold.stateOf(mainKey)?.start.phase == StartPhase.connected,
  );
  return rig;
}

Future<void> _until(WidgetTester t, bool Function() done) async {
  // Inside the test's own 30 seconds, so a wait that never ends says so.
  for (var i = 0; i < 750 && !done(); i++) {
    await t.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: t.screen.text);
}

/// Child [name] opened by the person, its first turn over.
Future<int> _open(WidgetTester t, _Rig rig, String name) async {
  await rig.host.open(
    mainKey,
    SpawnArgs(agent: 'fake', prompt: 'Read.', name: name),
    rig.person,
  );
  final key = rig.connection.agents.agents.children
      .singleWhere((child) => child.name == name)
      .key;
  await _until(t, () {
    final transcript = rig.fold.stateOf(key)?.transcript;
    return transcript != null &&
        transcript.turn is Idle &&
        transcript.entries.whereType<AssistantEntry>().isNotEmpty;
  });
  return key;
}

bool _mainIdle(_Rig rig) =>
    rig.transcript(mainKey).turn is Idle &&
    rig.connection.conversation.queuedFrom.isEmpty;

/// `/cost`'s table, from its heading to its total, without the margin.
Future<List<String>> _cost(WidgetTester t) async {
  await t.type('/cost');
  await t.press('enter');
  await settle(t);
  final lines = t.screen.lines;
  final head = lines.lastIndexWhere((row) => row.contains('This session'));
  expect(head, isNot(-1), reason: t.screen.text);
  final total = lines.indexWhere((row) => row.contains('Total'), head);
  expect(total, isNot(-1), reason: t.screen.text);
  final margin = lines[head].indexOf('This session');
  return [
    for (final row in lines.sublist(head, total + 1))
      row.substring(margin).trimRight(),
  ];
}

/// Every record under [stateDir], each as its entries.
Future<List<List<Map<String, Object?>>>> _records(String stateDir) async => [
  for (final file in Directory(recordsDir(stateDir)).listSync())
    if (file is File)
      parseRecord(await file.readAsString()).cast<Map<String, Object?>>(),
];

/// The agents list's rows under the prompt: `main` and each child, its
/// name then its runtime.
final _listRow = RegExp(r'^\s+(main|parser|docs)\s+fake ·');

void main() {
  _testerMainClearAsks();
  final skip = fakeAgentSkip;
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('at $size', () {
      testWidgets("main's /clear closes its open child: the list goes, "
          '/cost keeps it as agent, closed, nobody is told and no record '
          'notes the close', (t) async {
        final rig = await _window(t, size);
        final fold = rig.fold;
        final parser = await _open(t, rig, 'parser');
        final docs = await _open(t, rig, 'docs');
        // docs closed by the person first, as in the captures: main hears
        // of it, and its record notes it.
        rig.host.closeByPerson(docs);
        await _until(
          t,
          () =>
              fold.windowed.value.closing.isEmpty &&
              _mainIdle(rig) &&
              rig.transcript(mainKey).entries.whereType<UserEntry>().isNotEmpty,
        );
        expect(
          t.screen.lines.where(_listRow.hasMatch),
          hasLength(2),
          reason: t.screen.text,
        );
        final firstMain = rig.connection.conversation.session!.id;
        final parserId = rig.connection.agents.agents.children.single.id;

        await t.type('/clear');
        await t.press('enter');
        await _until(
          t,
          () =>
              rig.connection.agents.agents.children.isEmpty &&
              fold.windowed.value.closing.isEmpty &&
              fold.stateOf(mainKey)!.start.phase == StartPhase.connected &&
              rig.connection.conversation.session?.id != firstMain,
        );
        expect(fold.stateOf(parser), isNull);
        await settle(t);

        // The list is gone with its last child.
        expect(
          t.screen.lines.where(_listRow.hasMatch),
          isEmpty,
          reason: t.screen.text,
        );

        // As the original's capture after /clear: parser after docs, both
        // `agent, closed`. Every turn here costs the fake's $0.0125.
        expect(await _cost(t), [
          'This session           Cost  Tokens',
          'main           not reported       —',
          r'before /clear       $0.0125   2,000',
          r'docs                $0.0125   2,000  agent, closed',
          r'parser              $0.0125   2,000  agent, closed',
          r'Total               $0.0375   6,000  fake not reported',
        ]);

        // Nobody is told: the fresh main hears nothing and runs no turn.
        for (var i = 0; i < 25; i++) {
          await t.pump(const Duration(milliseconds: 20));
        }
        final fresh = rig.transcript(mainKey);
        expect(fresh.entries.whereType<UserEntry>(), isEmpty);
        expect(fresh.turn, isA<Idle>());
        expect(rig.connection.conversation.queuedFrom, isEmpty);

        // Main's first record notes docs' close, which the person made,
        // and not parser's; parser's own record notes none.
        await rig.recording.flushed();
        for (final child in rig.children) {
          await child.flushed();
        }
        final records = await _records(rig.stateDir);
        final first = records.singleWhere(
          (entries) => entries.first['sessionId'] == firstMain,
        );
        final docsId = first
            .where((line) => line['type'] == 'closed')
            .map((line) => line['agent'])
            .toList();
        expect(docsId, hasLength(1));
        expect(docsId.single, isNot(parserId));
        final own = records.singleWhere(
          (entries) => entries.first['id'] == parserId,
        );
        expect(own.first['parent'], firstMain);
        expect(own.where((line) => line['type'] == 'closed'), isEmpty);
        expect(own.where((line) => line['type'] == 'cancel'), isEmpty);
      }, skip: skip);
    });
  }
}

void _testerMainClearAsks() {
  group('CTUI-35 tester: main clear with a hidden child ask', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'withdraws pending child permission and accepts a fresh main turn at $size',
        (t) async {
          final rig = await _window(t, size);
          expect(rig.connection.conversation.send('hello'), isTrue);
          await _until(
            t,
            () =>
                _mainIdle(rig) &&
                rig
                    .transcript(mainKey)
                    .entries
                    .whereType<UserEntry>()
                    .isNotEmpty,
          );
          final before = rig.connection.conversation.session!.id;
          await rig.host.open(
            mainKey,
            const SpawnArgs(
              agent: 'fake',
              prompt: 'permission',
              name: '界🙂e\u0301',
            ),
            rig.person,
          );
          final child = rig.connection.agents.agents.children.single;
          await _until(
            t,
            () => rig.transcript(child.key).turn is AwaitingPermission,
          );
          expect(rig.fold.front, mainKey);
          await t.type('/clear');
          await t.press('enter');
          await _until(
            t,
            () =>
                rig.connection.agents.agents.children.isEmpty &&
                rig.fold.windowed.value.closing.isEmpty &&
                rig.connection.conversation.session != null &&
                rig.connection.conversation.session!.id != before,
          );
          expect(rig.fold.stateOf(child.key), isNull);
          expect(rig.transcript(mainKey).asking, isEmpty);
          expect(
            rig.transcript(mainKey).entries.whereType<UserEntry>(),
            isEmpty,
          );
          expect(rig.connection.conversation.queuedFrom, isEmpty);
          expect(rig.connection.conversation.send('text'), isTrue);
          await _until(
            t,
            () =>
                _mainIdle(rig) &&
                rig
                    .transcript(mainKey)
                    .entries
                    .whereType<AssistantEntry>()
                    .isNotEmpty,
          );
          expect(
            rig
                .transcript(mainKey)
                .entries
                .whereType<UserEntry>()
                .map((entry) => entry.text),
            ['text'],
          );
          expect(rig.transcript(mainKey).asking, isEmpty);
          final fresh = rig.transcript(mainKey);
          await t.pump(const Duration(seconds: 2));
          expect(rig.transcript(mainKey).entries.length, fresh.entries.length);
        },
        skip: fakeAgentSkip,
      );
    }
  });
}
