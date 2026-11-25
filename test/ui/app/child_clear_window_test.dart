// /clear with a long-lived child picked, on the original's fake in the
// window: as `clearFront` in the original's src/ui/app/sessions.ts, the
// child is cleared as the person's clear, `clearByPerson`, so main is told
// once its fresh session is up; the child keeps its name, id and colour
// with a fresh session and token, the person's queued prompt comes back
// into its box, and main and a sibling are left as they are.
@Tags(['fake_agent'])
library;

import 'package:chord/server/server.dart';
import 'package:chord/server/tools.dart' hide Cleared;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/place.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/window_agents.dart';
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

/// chord's server, the tokens it gave and took back seen.
final class _Seen implements ChordServer {
  _Seen(this._server);

  final ChordServer _server;

  /// Each token given, and the id of the child it was given for.
  final admitted = <({String token, String? agent})>[];
  final revoked = <String>[];

  @override
  String get url => _server.url;

  @override
  Admitted admit(Caller caller) {
    final given = _server.admit(caller);
    admitted.add((token: given.token, agent: caller.agent));
    return given;
  }

  @override
  void revoke(String token) {
    revoked.add(token);
    _server.revoke(token);
  }

  @override
  Future<void> close() => _server.close();

  /// The tokens child [id] was given, oldest first.
  List<String> of(String id) => [
    for (final each in admitted)
      if (each.agent == id) each.token,
  ];
}

/// Main on the fake in the window, with chord's server and the host as
/// the launch wires them.
final class _Rig {
  _Rig(this.connection, this.host, this.server);

  final StartConnection connection;
  final AgentsHost host;
  final _Seen server;

  WindowFold get fold => connection.fold;

  Caller get person => Caller(role: Role.person, key: mainKey, window: host);

  Transcript transcript(int key) => fold.stateOf(key)!.transcript;
}

Future<_Rig> _window(WidgetTester t, Size size) async {
  final server = _Seen(await serveChord());
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
  await t.pumpWidget(
    TranscriptWindow(launch: plainLaunch, connection: connection),
    size: size,
  );
  await _until(
    t,
    () => fold.stateOf(mainKey)?.start.phase == StartPhase.connected,
  );
  return _Rig(connection, host, server);
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

/// The messages chord delivered to main.
List<String> _fromChord(_Rig rig) => [
  for (final entry in rig.transcript(mainKey).entries.whereType<UserEntry>())
    if (entry.from?.name == 'chord') entry.text,
];

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
  _testerRepeatedPickedClear();
  final skip = fakeAgentSkip;
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('at $size', () {
      testWidgets("a picked child's /clear tells main the original's message "
          'once; the child keeps its name, id and colour with a fresh '
          'session and token, its queued prompt back in its box, and main '
          'and a sibling are left as they are', (t) async {
        final rig = await _window(t, size);
        final fold = rig.fold;
        final parser = await _open(t, rig, 'parser');
        final docs = await _open(t, rig, 'docs');
        Child<Conversation> child(String name) => rig
            .connection
            .agents
            .agents
            .children
            .singleWhere((each) => each.name == name);
        final before = child('parser');
        final docsBefore = child('docs');
        final childSession = fold.stateOf(parser)!.start.sessionId;
        final docsSession = fold.stateOf(docs)!.start.sessionId;
        final mainSession = rig.connection.conversation.session!.id;
        final mainEntries = rig.transcript(mainKey).entries.length;
        final tokens = rig.server.of(before.id);
        expect(childSession, isNotNull);
        expect(tokens, hasLength(1));

        rig.connection.agents.pick(parser);
        fold.dispatch(SessionShown(parser));
        await settle(t);
        // A turn that runs until it is stopped, and a prompt queued
        // behind it.
        await t.type('readsheld');
        await t.press('enter');
        await _until(t, () => fold.stateOf(parser)!.transcript.turn is! Idle);
        await t.type('later please');
        await t.press('enter');
        await _until(t, () => fold.stateOf(parser)!.queue.isNotEmpty);

        await t.type('/clear');
        await t.press('enter');
        await _until(
          t,
          () =>
              fold.stateOf(parser)?.start.phase == StartPhase.connected &&
              fold.stateOf(parser)?.start.sessionId != childSession &&
              _fromChord(rig).isNotEmpty &&
              rig.transcript(mainKey).turn is Idle,
        );
        await settle(t);

        // The original's words, from clearByPerson, once.
        expect(_fromChord(rig), [
          matches(
            RegExp(
              r"^The person cleared parser's context \(fake( · [^,]+)?, id "
              '${RegExp.escape(before.id)}'
              r'\)\. It is open with a fresh session and knows nothing of '
              r'earlier turns; your next message is its first\.$',
            ),
          ),
        ]);

        // The same child, a fresh session under a fresh token, the old
        // one taken back, still in front with nothing run.
        final after = child('parser');
        expect(after.key, parser);
        expect(after.id, before.id);
        expect(after.info.colour, before.info.colour);
        expect(fold.front, parser);
        expect(rig.server.of(before.id), [tokens.single, isNot(tokens.single)]);
        expect(rig.server.revoked, contains(tokens.single));
        expect(
          fold.stateOf(parser)!.transcript.entries.whereType<UserEntry>(),
          isEmpty,
        );

        // The person's queued prompt is back in the child's box, not sent.
        expect(fold.stateOf(parser)!.queue, isEmpty);
        expect(fold.stateOf(parser)!.draft, 'later please');
        expect(t.screen, shows('later please'));

        // Main's session is the one it had, only the message added; the
        // sibling is open as it was.
        expect(rig.connection.conversation.session!.id, mainSession);
        expect(
          rig.transcript(mainKey).entries.length,
          greaterThan(mainEntries),
        );
        final sibling = child('docs');
        expect(sibling.key, docs);
        expect(sibling.id, docsBefore.id);
        expect(fold.stateOf(docs)!.start.sessionId, docsSession);
        expect(rig.server.of(docsBefore.id), hasLength(1));

        // Told once: nothing more comes after a while.
        for (var i = 0; i < 25; i++) {
          await t.pump(const Duration(milliseconds: 20));
        }
        expect(_fromChord(rig), hasLength(1));

        // The child's old session still counts, kept as clearChild keeps it
        // under a retired key of its own, apart from its fresh one.
        rig.connection.agents.pick(mainKey);
        fold.dispatch(const SessionShown(mainKey));
        await settle(t);
        expect(await _cost(t), [
          'This session          Cost  Tokens',
          r'main               $0.0125   2,000',
          'parser        not reported       —  agent',
          r'docs               $0.0125   2,000  agent',
          r'parser             $0.0125   2,000  agent, closed',
          r'Total              $0.0375   6,000  parser not reported',
        ]);
      }, skip: skip);
    });
  }
}

void _testerRepeatedPickedClear() {
  group('CTUI-35 tester: repeated picked-child clear', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'two clears keep the child selected and tell main once per fresh context at $size',
        (t) async {
          final rig = await _window(t, size);
          final parser = await _open(t, rig, 'parser'),
              docs = await _open(t, rig, 'docs');
          final child = rig.connection.agents.agents.children.singleWhere(
            (c) => c.key == parser,
          );
          final mainSession = rig.connection.conversation.session!.id;
          final docsSession = rig.fold.stateOf(docs)!.start.sessionId;
          rig.connection.agents.pick(parser);
          rig.fold.dispatch(SessionShown(parser));
          await settle(t);
          for (var i = 0; i < 2; i++) {
            final before = rig.fold.stateOf(parser)!.start.sessionId;
            await t.type('/clear');
            await t.press('enter');
            await _until(
              t,
              () =>
                  rig.fold.stateOf(parser)!.start.phase ==
                      StartPhase.connected &&
                  rig.fold.stateOf(parser)!.start.sessionId != before &&
                  _fromChord(rig).length == i + 1 &&
                  rig.transcript(mainKey).turn is Idle,
            );
            expect(rig.fold.front, parser);
            expect(rig.connection.conversation.session!.id, mainSession);
            expect(rig.fold.stateOf(docs)!.start.sessionId, docsSession);
          }
          final tokens = rig.server.of(child.id);
          expect(tokens, hasLength(3));
          expect(tokens.toSet(), hasLength(3));
          expect(rig.server.revoked, containsAll(tokens.take(2)));
          expect(_fromChord(rig), hasLength(2));
          expect(
            _fromChord(rig).every(
              (text) => text.contains("The person cleared parser's context"),
            ),
            isTrue,
          );
        },
        skip: fakeAgentSkip,
      );
    }
  });
}
