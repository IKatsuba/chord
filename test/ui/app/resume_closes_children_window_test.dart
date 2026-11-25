// /resume of another session with long-lived children open, on the
// original's fake in the window: as `pickSession` in the original's
// src/ui/app/sessions.ts, main's children close with the session it
// leaves, before the switch, the closed list is forgotten, nobody is told,
// and /cost keeps each as `agent, closed`.
@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/server/server.dart';
import 'package:chord/server/tools.dart' hide Cleared;
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/place.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/sessions.dart' show SessionRecord;
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import '../../fixtures/runtimes.dart';
import 'editor_window_test.dart' show plainLaunch, settle;
import 'resume_window_test.dart' show Fixture;

const _target = '33333333-3333-4333-8333-333333333333';

/// Main on the fake in the window, with chord's server and the host as
/// the launch wires them, and one earlier session to resume.
final class _Rig {
  _Rig(this.connection, this.host);

  final StartConnection connection;
  final AgentsHost host;

  WindowFold get fold => connection.fold;

  Caller get person => Caller(role: Role.person, key: mainKey, window: host);

  Transcript transcript(int key) => fold.stateOf(key)!.transcript;
}

Future<_Rig> _window(WidgetTester t, Size size) async {
  final server = await serveChord();
  final runtimes = TestRuntimes();
  final connection = StartConnection(
    command: runtimes.commandOf('fake'),
    env: runtimes.env,
    cwd: runtimes.home.path,
    agent: 'fake',
    open: runtimes.opener,
  );
  final fold = connection.fold;
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
    transcriptOf: (key) => fold.stateOf(key)?.transcript,
  );
  connection
    ..server = server
    ..window = host
    ..start();
  addTearDown(() async {
    await connection.close();
    await server.close();
    runtimes.dispose();
  });
  final records = Fixture(Directory(runtimes.home.path));
  await records.saved(_target, agent: 'fake', cwd: connection.cwd);
  await t.pumpWidget(
    TranscriptWindow(
      launch: plainLaunch,
      connection: connection,
      readSessionRecords: records.read,
    ),
    size: size,
  );
  await _until(
    t,
    () => fold.stateOf(mainKey)?.start.phase == StartPhase.connected,
  );
  return _Rig(connection, host);
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

/// The messages chord delivered to main.
List<String> _fromChord(_Rig rig) => [
  for (final entry in rig.transcript(mainKey).entries.whereType<UserEntry>())
    if (entry.from?.name == 'chord') entry.text,
];

/// What the person's close of [to] answers: why there is none to close.
String _noChild(_Rig rig, String to) =>
    switch (rig.host.close(rig.person, to)) {
      Refused(:final error) => error,
      final other => 'not refused: $other',
    };

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

void main() {
  _testerResumeGuardsWithChildren();
  final skip = fakeAgentSkip;
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('at $size', () {
      testWidgets('/resume of another session closes the open child and '
          'forgets the closed one: the resumed main knows of neither, '
          'nobody is told, and /cost keeps both as agent, closed', (t) async {
        final rig = await _window(t, size);
        final fold = rig.fold;
        final parser = await _open(t, rig, 'parser');
        final docs = await _open(t, rig, 'docs');
        // docs closed by the person first: main hears of it, and the
        // closed list holds it.
        rig.host.closeByPerson(docs);
        await _until(
          t,
          () =>
              fold.windowed.value.closing.isEmpty &&
              _mainIdle(rig) &&
              _fromChord(rig).isNotEmpty,
        );
        expect(rig.connection.agents.agents.closed, hasLength(1));
        expect(
          _noChild(rig, 'docs'),
          'docs is closed; open_agent starts '
          'another',
        );

        await t.type('/resume');
        await t.press('enter');
        await settle(t);
        expect(t.screen, shows('Resume a session'));
        await t.press('enter');
        await _until(
          t,
          () =>
              rig.connection.agents.agents.children.isEmpty &&
              fold.windowed.value.closing.isEmpty &&
              fold.stateOf(mainKey)!.start.phase == StartPhase.connected &&
              fold.stateOf(mainKey)!.start.sessionId == _target,
        );
        expect(fold.stateOf(parser), isNull);
        expect(fold.front, mainKey);
        await settle(t);
        expect(t.screen, shows('Saved past $_target'));

        // The closed list is forgotten with the session that had it.
        expect(rig.connection.agents.agents.closed, isEmpty);
        const none = 'in this session; list_sessions names them';
        expect(_noChild(rig, 'parser'), 'No agent parser is open $none');
        expect(_noChild(rig, 'docs'), 'No agent docs is open $none');

        // Nobody is told: the resumed main hears nothing and runs no turn.
        for (var i = 0; i < 25; i++) {
          await t.pump(const Duration(milliseconds: 20));
        }
        expect(_fromChord(rig), isEmpty);
        expect(rig.transcript(mainKey).turn, isA<Idle>());

        // As the original: main's left session is `before /clear`, each
        // child `agent, closed`. Every turn here costs the fake's $0.0125.
        expect(await _cost(t), [
          'This session           Cost  Tokens',
          'main           not reported       —',
          r'before /clear       $0.0125   2,000',
          r'docs                $0.0125   2,000  agent, closed',
          r'parser              $0.0125   2,000  agent, closed',
          r'Total               $0.0375   6,000  fake not reported',
        ]);
      }, skip: skip);
    });
  }
}

void _testerResumeGuardsWithChildren() {
  group('CTUI-35 tester: resume guards preserve children', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'a main turn starting after the picker opens prevents child removal at $size',
        (t) async {
          final rig = await _window(t, size);
          await _open(t, rig, 'parser');
          await _open(t, rig, 'docs');
          final ids = rig.connection.agents.agents.children
              .map((c) => c.id)
              .toList();
          final main = rig.connection.conversation.session!.id;
          await t.type('/resume');
          await t.press('enter');
          await settle(t);
          expect(t.screen, shows('Resume a session'));
          expect(rig.connection.conversation.send('readsheld'), isTrue);
          await _until(t, () => rig.transcript(mainKey).turn is! Idle);
          await t.press('enter');
          await settle(t);
          expect(rig.connection.agents.agents.children.map((c) => c.id), ids);
          expect(rig.connection.conversation.session!.id, main);
          expect(rig.fold.windowed.value.closing, isEmpty);
          expect(t.screen, isNot(shows('Saved past $_target')));
          rig.connection.conversation.interrupt();
        },
        skip: fakeAgentSkip,
      );

      testWidgets(
        'another-directory refusal preserves both live and remembered closed children at $size',
        (t) async {
          final rig = await _window(t, size);
          final parser = await _open(t, rig, 'parser'),
              docs = await _open(t, rig, 'docs');
          rig.host.closeByPerson(docs);
          await _until(
            t,
            () =>
                rig.fold.windowed.value.closing.isEmpty &&
                _mainIdle(rig) &&
                _fromChord(rig).isNotEmpty,
          );
          final main = rig.connection.conversation.session!.id;
          await t.pumpWidget(
            TranscriptWindow(
              launch: plainLaunch,
              connection: rig.connection,
              readSessionRecords: ({cancellationToken}) async => [
                SessionRecord(
                  path: 'elsewhere.jsonl',
                  sessionId: _target,
                  agent: 'fake',
                  cwd: 'another-project',
                  lastUsedAt: 1,
                  prompt: 'Elsewhere',
                ),
              ],
            ),
            size: size,
          );
          await t.type('/resume');
          await t.press('enter');
          await settle(t);
          await t.press('ctrl+a');
          await settle(t);
          expect(t.screen, shows('Elsewhere'));
          await t.press('enter');
          await settle(t);
          expect(rig.connection.agents.agents.children.single.key, parser);
          expect(rig.connection.agents.agents.closed, hasLength(1));
          expect(rig.connection.conversation.session!.id, main);
          expect(rig.fold.windowed.value.closing, isEmpty);
          expect(t.screen, isNot(shows('Saved past $_target')));
        },
        skip: fakeAgentSkip,
      );
    }
  });
}
