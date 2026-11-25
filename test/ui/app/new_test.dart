// The window's `/new` (design CTUI-35 section 6, "`/new`"; interface draft
// I10), as the original's agents_host.ts newTyped and commands.ts run it:
// an idle child of main, on main's runtime or the named one, picked at
// once; each refusal said under the command where it was typed; and `/new `
// completing the window's agents by name, never `--name`.
import 'dart:async';

import 'package:chord/acp/connection.dart';
import 'package:chord/agents.dart';
import 'package:chord/agent_name.dart';
import 'package:chord/cli.dart' show Launch;
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/new_args.dart';
import 'package:chord/session/open_agents.dart';
import 'package:chord/session/tasks.dart' show wrapMessage;
import 'package:chord/server/tools.dart' show Started;
import 'package:chord/session/place.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/session/window_agents.dart';
import 'package:chord/ui/prompt/commands.dart' show agentItems;
import 'package:chord/ui/prompt/state.dart' show commandMenu;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/window_fold.dart' show mainKey;
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import '../../fixtures/runtimes.dart';
import '../../session/conversation_fake.dart';
import 'editor_window_test.dart' show EditorTerminal, plainLaunch, settle;

/// The window over a main that never starts, the host knowing [runtimes],
/// `fake` and `fake2` by default, and `parser` open behind main on a
/// scripted session; with [host] false, no host at all. `/new` describes
/// and ranks by [listed].
Future<({StartConnection connection, int parser})> _scripted(
  WidgetTester t,
  Size size, {
  bool host = true,
  List<String> runtimes = const ['fake', 'fake2'],
  Launch launch = plainLaunch,
  List<ListedAgent> listed = const [],
}) async {
  final hanging = Completer<Agent>();
  final connection =
      StartConnection(
          command: 'fake',
          cwd: '.',
          agent: 'fake',
          owner: Owned(),
          open:
              ({
                required command,
                env,
                required cwd,
                required onTraffic,
                required onPermission,
                relay,
                cancellationToken,
              }) => hanging.future,
        )
        ..listedAgents = listed
        ..start();
  addTearDown(connection.close);
  addTearDown(() {
    hanging.future.ignore();
    hanging.completeError(StateError('over'));
  });
  if (host) {
    connection.window = AgentsHost(
      runtimeNames: runtimes,
      startupOf: (_) => null,
      openChildSession:
          (
            runtime,
            start, {
            required initial,
            chordServer,
            required onTraffic,
            required cancellationToken,
          }) => Future.error(StateError('no runtime in a test')),
      agents: connection.agents,
      opened: (key) => connection.fold.dispatch(AgentOpened(key)),
      closed: (key, front) =>
          connection.fold.dispatch(SessionClosed(key, front)),
    );
  }
  final parser = connection.agents.openChild(
    const ChildInfo(
      id: 'id-parser',
      name: 'parser',
      runtime: 'fake',
      openedAt: 0,
    ),
    (emit, key) {
      connection.fold.dispatch(AgentOpened(key));
      final session = ScriptedSession();
      return Conversation(
        ({required onTraffic, required cancellationToken}) async => session,
      )..listen(emit);
    },
  )!;
  await t.pumpWidget(
    TranscriptWindow(
      launch: launch,
      connection: connection,
      terminal: EditorTerminal(),
    ),
    size: size,
  );
  await settle(t);
  return (connection: connection, parser: parser);
}

/// [typed] sent from the prompt.
Future<void> _send(WidgetTester t, String typed) async {
  await t.type(typed);
  await t.press('enter');
  await settle(t);
}

/// The notes [key]'s transcript holds, as command and words.
List<(String, String)> _notes(StartConnection connection, int key) => [
  for (final entry
      in connection.fold.stateOf(key)?.transcript.entries ??
          const <model.Entry>[])
    if (entry is model.NotedEntry && entry.failed) (entry.command, entry.text),
];

/// The window over main on the fake, the host knowing `fake` and `fake2`,
/// both the original's fake agent.
Future<StartConnection> _fake(WidgetTester t, Size size) async {
  final runtimes = TestRuntimes(
    fakes: const {
      'fake': (scenario: null, flags: []),
      'fake2': (scenario: null, flags: []),
    },
  );
  final connection = StartConnection(
    command: runtimes.commandOf('fake'),
    env: runtimes.env,
    cwd: runtimes.home.path,
    agent: 'fake',
    open: runtimes.opener,
  );
  final fold = connection.fold;
  connection
    ..window = AgentsHost(
      runtimeNames: const ['fake', 'fake2'],
      startupOf: (runtime) =>
          SessionStart(command: runtimes.commandOf(runtime)),
      openChildSession: connection.openChild,
      agents: connection.agents,
      opened: (key) => fold.dispatch(AgentOpened(key)),
      closed: (key, front) => fold.dispatch(SessionClosed(key, front)),
    )
    ..start();
  addTearDown(() async {
    await connection.close();
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
  return connection;
}

Future<void> _until(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 1500 && !done(); i++) {
    await t.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: t.screen.text);
}

/// The list's rows, under the status line.
List<String> _list(WidgetTester t) {
  final lines = t.screen.lines;
  final first = lines.indexWhere(
    (line) => line.startsWith('    main ') || line.startsWith('  ❯ main '),
  );
  return first < 0 ? const [] : lines.sublist(first);
}

/// The completion list's rows, between its rule and the prompt box.
List<String> _offered(WidgetTester t) {
  final lines = t.screen.lines;
  final box = lines.indexWhere((line) => line.startsWith('╭'));
  final rule = lines.lastIndexWhere((line) => line.startsWith(' ──'), box);
  return rule < 0
      ? const []
      : [
          for (final line in lines.sublist(rule + 1, box))
            if (line.trim().isNotEmpty) line.trim(),
        ];
}

/// The child [connection] opened last, once its session is up.
Future<Child<Conversation>> _opened(
  WidgetTester t,
  StartConnection connection,
) async {
  await _until(
    t,
    () =>
        connection.agents.agents.children.isNotEmpty &&
        connection.fold
                .stateOf(connection.agents.agents.children.last.key)
                ?.start
                .phase ==
            StartPhase.connected,
  );
  await settle(t);
  return connection.agents.agents.children.last;
}

/// The rows of [t]'s transcript from the last `› /<command>` on, to the
/// next empty row after the call's.
List<String> _typedCall(WidgetTester t, String command) {
  final lines = t.screen.lines;
  final at = lines.lastIndexWhere((line) => line.trimRight() == ' › /$command');
  expect(at, isNot(-1), reason: t.screen.text);
  return [for (final line in lines.sublist(at, at + 4)) line.trimRight()];
}

void main() {
  _menuTests();
  _testerNewBoundaries();
  _asideTests();
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('at $size', () {
      _completionTests(size);
      _refusalTests(size);
      _openTests(size);
    });
  }
}

final _fakeOnly = agentItems(['fake'], const []);

void _menuTests() {
  test('the agent typed exactly is offered first', () {
    final menu = commandMenu(
      null,
      '/new fake',
      const [],
      agents: agentItems(['fake2', 'fake'], const []),
    );
    expect([for (final item in menu!.matches) item.name], ['fake', 'fake2']);
    expect(menu.selected!.of, 'new');
  });

  test('a second word puts the list of agents away', () {
    expect(
      commandMenu(null, '/new fake ', const [], agents: _fakeOnly),
      isNull,
    );
    expect(
      commandMenu(null, '/new fake --name', const [], agents: _fakeOnly),
      isNull,
    );
  });
}

void _asideTests() {
  test('main hears of the agent /new opened ahead of its next prompt, from '
      'chord, in the original words', () async {
    final mainSession = ScriptedSession();
    late final OpenAgents<Conversation> agents;
    agents = OpenAgents(
      conversation: (agent, emit, key) => Conversation(
        ({required onTraffic, required cancellationToken}) async => mainSession,
      )..listen(emit),
      heard: (key, event, wait) {},
    );
    agents.start('fake');
    final host = AgentsHost(
      runtimeNames: const ['fake', 'fake2'],
      startupOf: (_) => const SessionStart(),
      openChildSession:
          (
            runtime,
            start, {
            required initial,
            chordServer,
            required onTraffic,
            required cancellationToken,
          }) async => ScriptedSession(),
      agents: agents,
      opened: (_) {},
    );
    addTearDown(() => agents.closeAll());
    final main = agents.agents.main!.conversation;
    await Future.doWhile(() async {
      await Future<void>.delayed(Duration.zero);
      return main.session == null;
    });
    final shown = <int>[];
    final answer = await host.newTyped(
      'fake2 --name code review',
      show: shown.add,
    );
    expect(answer, isA<Started>());
    expect(shown, [agents.agents.children.single.key]);
    expect(mainSession.turns, isEmpty);
    main.send('go on');
    await Future<void>.delayed(Duration.zero);
    expect(
      mainSession.turns.single.text,
      '${wrapMessage(const model.MessageFrom('chord'), 'The person opened @code review (fake2) with /new; it has no prompt yet. It reports to you, and send_message reaches it.')}'
      '\n\ngo on',
    );
  });
}

/// Every runtime a window started on `fake` by `--agent-command` knows, as
/// the original's knownAgents gives them: main's first, then the catalog's.
final _known = ['fake', for (final agent in listAgents()) agent.name];

/// The catalog as `chord agents` lists it with only cursor's, fx's and
/// opencode's own CLIs on PATH, as the capture beside the original found.
Future<List<ListedAgent>> _listed() {
  final onPath = {
    for (final name in ['cursor', 'fx', 'opencode'])
      findAgent(name)!.start.command.first,
  };
  return listedAgents(
    (command) async => onPath.contains(command) ? command : null,
  );
}

/// The window's launch with [offered] as the `offeredAgents` setting.
Launch _offering(List<String> offered) => Launch(
  name: plainLaunch.name,
  agent: plainLaunch.agent,
  agentCommand: plainLaunch.agentCommand,
  version: plainLaunch.version,
  directory: plainLaunch.directory,
  offered: offered,
);

/// The dark palette's highlight, as the original's capture draws it.
const _lit = RgbColor(177, 185, 249);

void _completionTests(Size size) {
  testWidgets('/new is listed among the commands with what it does', (t) async {
    await _scripted(t, size);
    await t.type('/ne');
    await settle(t);
    expect(_offered(t).first, startsWith('/new'));
    expect(t.screen, shows('Open a new agent beside main and go to it'));
  });

  testWidgets('/new lists the agents by name, and Tab completes one', (
    t,
  ) async {
    await _scripted(t, size);
    await t.type('/new ');
    await settle(t);
    expect(_offered(t), ['fake', 'fake2']);
    await t.press('down');
    await t.press('tab');
    await settle(t);
    expect(t.screen, shows('› /new fake2'));
    // A second word: the list is put away, and Enter runs what is typed.
    expect(_offered(t), isEmpty);
  });

  testWidgets("/new lists main's runtime first, then those that will start, "
      'each with its note, as the original does', (t) async {
    final listed = await _listed();
    await _scripted(t, size, runtimes: _known, listed: listed);
    await t.type('/new ');
    await settle(t);
    // The capture beside the original at 80x24: fake, unlisted, has no
    // note; cursor's, fx's and opencode's CLIs found; the registry's next.
    const captured = [
      'fake',
      'cursor              Cursor',
      'fx                  fx',
      'opencode            OpenCode',
      'agoragentic-acp     Agoragentic',
      'auggie              Auggie CLI',
    ];
    // Taller, the registry's go on in the catalog's order.
    final more = [
      for (final agent in listed)
        if (agent.from == AgentRunner.npx || agent.from == AgentRunner.uvx)
          '${agent.name.padRight(20)}${agentNote(agent)}',
    ].skip(2);
    final rows = size.height ~/ 4;
    expect(_offered(t), [...captured, ...more].take(rows));
    // No own CLI PATH lacks is in sight: they are last.
    expect(t.screen, isNot(shows('not on PATH')));

    final lines = t.screen.lines;
    final top = lines.indexWhere((line) => line.trimRight() == '  fake');
    expect(top, isNot(-1), reason: t.screen.text);
    // The highlighted name in the palette's highlight; the rest dim, name
    // and note alike, in the terminal's own colour.
    expect(t.screen.styleAt(2, top).fg, _lit);
    expect(t.screen.styleAt(2, top).isDim, isFalse);
    for (var y = top + 1; y < top + rows; y++) {
      for (final x in [2, 22]) {
        expect(t.screen.styleAt(x, y).isDim, isTrue, reason: '($x, $y)');
        expect(t.screen.styleAt(x, y).fg, isNull, reason: '($x, $y)');
      }
    }
  });

  testWidgets('/new names an agent exactly typed first, with its note', (
    t,
  ) async {
    await _scripted(t, size, runtimes: _known, listed: await _listed());
    await t.type('/new cursor');
    await settle(t);
    expect(_offered(t).first, matches(RegExp(r'^cursor +Cursor$')));
  });

  testWidgets('with offeredAgents, /new lists its names in its order', (
    t,
  ) async {
    await _scripted(
      t,
      size,
      runtimes: _known,
      listed: await _listed(),
      launch: _offering(['opencode', 'kiro', 'missing', 'cursor']),
    );
    await t.type('/new ');
    await settle(t);
    expect(_offered(t), [
      // The name column is the longest name shown and two.
      'opencode  OpenCode',
      'kiro      Kiro · not on PATH',
      'cursor    Cursor',
    ]);
  });

  testWidgets('no --name is offered', (t) async {
    await _scripted(t, size);
    await t.type('/new --');
    await settle(t);
    expect(_offered(t), isEmpty);
    expect(t.screen, isNot(shows('--name')));
    await t.press('ctrl+c');
    await t.type('/new fake --');
    await settle(t);
    expect(_offered(t), isEmpty);
  });

  testWidgets('Enter on a highlighted agent runs /new on it', (t) async {
    final w = await _scripted(t, size);
    await t.type('/new fa');
    await t.press('down');
    await t.press('enter');
    await settle(t);
    // Main never started: the agent named is read, and refused there.
    expect(_notes(w.connection, mainKey), [
      ('new fake2', 'This session is closing; no agent can start from it'),
    ]);
  });
}

void _refusalTests(Size size) {
  for (final (typed, said) in [
    ('/new fake --name', noName),
    ('/new --name', noName),
    ('/new fake extra', notName),
    ('/new fake --name=x', notName),
    ('/new --name a"b', 'An agent name ${agentNameProblem('a"b')}'),
    ('/new --name main', 'The name main is taken in this window'),
    ('/new --name chord', 'The name chord is taken in this window'),
    ('/new fake --name parser', 'The name parser is taken in this window'),
  ]) {
    testWidgets('$typed is refused where it was typed: $said', (t) async {
      final w = await _scripted(t, size);
      await _send(t, typed);
      expect(_notes(w.connection, mainKey), [(typed.substring(1), said)]);
      expect(t.screen, shows(typed));
      expect(t.screen, shows(said.split(' ').take(4).join(' ')));
      // Nothing opened, and main still in front.
      expect(w.connection.agents.agents.children, hasLength(1));
      expect(w.connection.fold.front, mainKey);
    });
  }

  testWidgets('the words of a name refused name its character', (t) async {
    final w = await _scripted(t, size);
    await _send(t, '/new --name a"b');
    expect(
      _notes(w.connection, mainKey).single.$2,
      'An agent name must not contain the character "',
    );
  });

  testWidgets('a refusal typed in a child is said in its view, not main\'s', (
    t,
  ) async {
    final w = await _scripted(t, size);
    w.connection.fold.dispatch(SessionShown(w.parser));
    await settle(t);
    await _send(t, '/new --name parser');
    expect(_notes(w.connection, w.parser), [
      ('new --name parser', 'The name parser is taken in this window'),
    ]);
    expect(_notes(w.connection, mainKey), isEmpty);
    expect(t.screen, shows('The name parser is taken in this window'));
  });

  testWidgets('with no agents host, the session has closed', (t) async {
    final w = await _scripted(t, size, host: false);
    await _send(t, '/new');
    expect(_notes(w.connection, mainKey), [('new', 'This session has closed')]);
  });
}

void _openTests(Size size) {
  final skip = fakeAgentSkip;

  testWidgets("/new opens an idle child on main's runtime and picks it", (
    t,
  ) async {
    final c = await _fake(t, size);
    await _send(t, '/new');
    final child = await _opened(t, c);
    expect((child.name, child.runtime), ('fake', 'fake'));
    expect(c.fold.front, child.key);
    expect(t.screen, shows('╭─ fake ─'));
    expect(_list(t).last, startsWith('    fake '));
    // Idle: no prompt went to it, and none to main.
    final state = c.fold.stateOf(child.key)!;
    expect(state.transcript.entries.whereType<model.UserEntry>(), isEmpty);
    expect(state.transcript.turn, isA<model.Idle>());
    expect(
      c.fold.stateOf(mainKey)!.transcript.entries.whereType<model.UserEntry>(),
      isEmpty,
    );
  }, skip: skip);

  testWidgets('/new on a named runtime and name opens it and picks it', (
    t,
  ) async {
    final c = await _fake(t, size);
    await _send(t, '/new fake2 --name code review');
    final child = await _opened(t, c);
    expect((child.name, child.runtime), ('code review', 'fake2'));
    expect(c.fold.front, child.key);
    expect(t.screen, shows('╭─ code review ─'));
    expect(_list(t).last, startsWith('    code review  fake2'));
    expect(
      c.fold
          .stateOf(child.key)!
          .transcript
          .entries
          .whereType<model.UserEntry>(),
      isEmpty,
    );
    // Its name is now taken, and the refusal is said in its view.
    await _send(t, '/new --name code review');
    expect(_notes(c, child.key), [
      (
        'new --name code review',
        'The name code review is taken in this window',
      ),
    ]);
    expect(c.agents.agents.children, hasLength(1));
  }, skip: skip);

  testWidgets("/new draws its open_agent call in main's view as main's own, "
      'wherever it was typed', (t) async {
    final c = await _fake(t, size);
    await _send(t, '/new fake2 --name code review');
    final first = await _opened(t, c);
    // Typed again in the child's view: drawn in main's, not the child's.
    await _send(t, '/new --name docs');
    final second = await _opened(t, c);
    expect(second.name, 'docs');
    for (final child in [first, second]) {
      expect(
        c.fold
            .stateOf(child.key)!
            .transcript
            .entries
            .whereType<model.TypedCallEntry>(),
        isEmpty,
      );
    }
    c.fold.dispatch(SessionShown(mainKey));
    await settle(t);
    final calls = c.fold
        .stateOf(mainKey)!
        .transcript
        .entries
        .whereType<model.TypedCallEntry>()
        .toList();
    expect(
      [for (final each in calls) each.command],
      ['new fake2 --name code review', 'new --name docs'],
    );
    expect(calls.first.call.answer, {
      'id': first.id,
      'name': 'code review',
      'agent': 'fake2',
    });
    expect(_typedCall(t, 'new fake2 --name code review'), [
      ' › /new fake2 --name code review',
      '',
      ' ⏺ Open(code review) · fake2',
      '   ⎿  opened with /new',
    ]);
    expect(_typedCall(t, 'new --name docs'), [
      ' › /new --name docs',
      '',
      ' ⏺ Open(docs) · fake',
      '   ⎿  opened with /new',
    ]);
    // The command's marker dim and its words as typed; the verb bold, the
    // name as the text is, the runtime dim, as an agent's own call.
    final y = t.screen.lines.lastIndexWhere(
      (line) => line.startsWith(' ⏺ Open(docs)'),
    );
    final typed = y - 2;
    expect(t.screen.styleAt(1, typed).isDim, isTrue);
    expect(t.screen.styleAt(3, typed).isDim, isFalse);
    expect(t.screen.styleAt(3, y).isBold, isTrue);
    expect(t.screen.styleAt(8, y).isBold, isFalse);
    expect(t.screen.styleAt(8, y).isDim, isFalse);
    expect(t.screen.styleAt(16, y).isDim, isTrue);
    expect(t.screen.styleAt(1, y).fg, isNotNull);
  }, skip: skip);

  testWidgets('/new of an agent chord does not know says the ones it does', (
    t,
  ) async {
    final c = await _fake(t, size);
    await _send(t, '/new nope');
    expect(_notes(c, mainKey), [
      ('new nope', 'No agent named nope; chord knows fake, fake2'),
    ]);
    expect(c.agents.agents.children, isEmpty);
    expect(c.fold.front, mainKey);
  }, skip: skip);
}

void _testerNewBoundaries() {
  group('CTUI-35 tester: new child boundaries', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'Unicode child opens idle; duplicate refusal stays in that child at $size',
        (t) async {
          final c = await _fake(t, size);
          const name = '界🙂e\u0301';
          await _send(t, '/new --name $name');
          final child = await _opened(t, c);
          expect(child.name, name);
          expect(c.fold.front, child.key);
          expect(t.screen, shows('╭─ $name'));
          expect(
            c.fold
                .stateOf(child.key)!
                .transcript
                .entries
                .whereType<model.UserEntry>(),
            isEmpty,
          );
          await _send(t, '/new --name $name');
          expect(c.agents.agents.children, hasLength(1));
          expect(_notes(c, child.key), [
            ('new --name $name', 'The name $name is taken in this window'),
          ]);
          expect(_notes(c, mainKey), isEmpty);
          expect(
            c.fold
                .stateOf(mainKey)!
                .transcript
                .entries
                .whereType<model.TypedCallEntry>(),
            hasLength(1),
          );
        },
        skip: fakeAgentSkip,
      );

      testWidgets(
        'a full window refuses a ninth before start and keeps name-refusal precedence at $size',
        (t) async {
          final c = await _fake(t, size);
          for (var i = 0; i < maxChildren; i++) {
            final session = ScriptedSession();
            c.agents.openChild(
              ChildInfo(
                id: 'cap$i',
                name: 'agent$i',
                runtime: 'fake',
                openedAt: 0,
              ),
              (emit, key) {
                c.fold.dispatch(AgentOpened(key));
                return Conversation(
                  ({required onTraffic, required cancellationToken}) async =>
                      session,
                )..listen(emit);
              },
            );
          }
          await settle(t);
          await _send(t, '/new --name overflow');
          expect(c.agents.agents.children, hasLength(maxChildren));
          expect(c.fold.front, mainKey);
          expect(
            _notes(c, mainKey).last.$2,
            'This session has 8 agents open; close_agent one first',
          );
          await _send(t, '/new --name agent0');
          expect(
            _notes(c, mainKey).last.$2,
            'The name agent0 is taken in this window',
          );
          expect(
            c.fold
                .stateOf(mainKey)!
                .transcript
                .entries
                .whereType<model.TypedCallEntry>(),
            isEmpty,
          );
        },
        skip: fakeAgentSkip,
      );
    }
  });
}
