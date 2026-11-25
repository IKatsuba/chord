// The window tells its terminal where the agent stands, as the original's
// App does (tests/ui/app/AppStatus_test.tsx, renderer_test.ts): a program
// status record after each change and each key, a notification when the
// agent starts waiting on the person, and nothing of chord's left on the
// terminal while it is lent or once it is given back.
import 'dart:async';

import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart' show MemoryAgentProcess;
import 'package:chord/cli.dart';
import 'package:chord/notify.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/transcript/types.dart'
    show
        PermissionRequestedAction,
        PermissionWait,
        PromptAction,
        ResultAction,
        TurnAnswered;
import 'package:chord/session/window_agents.dart' show ChildInfo;
import 'package:chord/ui/app/state.dart' show AgentOpened, SessionShown;
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'selection_window_test.dart' show RecordingTerminal;
import '../../session/conversation_fake.dart';
import 'window_fake_test.dart' show until;

const launch = Launch(
  name: 'memory',
  agent: null,
  agentCommand: 'memory',
  version: '0.0.1',
  directory: '/w',
);

const iterm = Notifications(
  channel: NotifChannel.auto,
  env: TerminalEnv(termProgram: 'iTerm.app'),
);

/// An in-memory agent: it opens a session, holds each prompt until told,
/// and asks what a test sends it.
final class _Agent {
  _Agent() {
    process = MemoryAgentProcess(
      onSignal: (_) {
        if (process.exited) return;
        process.exit(const Exit(143, 'SIGTERM'));
        process.closeStdout();
        process.closeStderr();
      },
    );
    _timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
      for (final message in [...process.stdin.messages]) {
        final id = message['id'];
        final method = message['method'];
        if (id == null || method == null || !_seen.add(id)) continue;
        if (method == 'session/prompt') {
          prompts.add(id);
          continue;
        }
        process.send({
          'jsonrpc': '2.0',
          'id': id,
          'result': method == 'initialize'
              ? {'protocolVersion': 1}
              : {'sessionId': 's1'},
        });
      }
    });
  }

  late final MemoryAgentProcess process;
  late final Timer _timer;
  final _seen = <Object?>{};

  /// The prompts not yet answered, by request id.
  final prompts = <Object?>[];

  StartConnection connect() => StartConnection(
    command: 'memory',
    cwd: '/w',
    agent: 'memory',
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
        }) => connectAgent(
          process,
          onTraffic: onTraffic,
          onPermission: onPermission,
          relay: relay,
          cancellationToken: cancellationToken,
        ),
  )..start();

  /// Ends the oldest turn held.
  void answer() => process.send({
    'jsonrpc': '2.0',
    'id': prompts.removeAt(0),
    'result': {'stopReason': 'end_turn'},
  });

  void ask() => process.send({
    'jsonrpc': '2.0',
    'id': 'ask-1',
    'method': 'session/request_permission',
    'params': {
      'sessionId': 's1',
      'toolCall': {'toolCallId': 'write-1', 'title': 'Write notes.txt'},
      'options': [
        {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
      ],
    },
  });

  void stop() => _timer.cancel();
}

Future<(_Agent, RecordingTerminal)> _open(
  WidgetTester t,
  Size size, {
  Notifications? notifications = iterm,
}) async {
  final agent = _Agent();
  final connection = agent.connect();
  final terminal = RecordingTerminal();
  addTearDown(() async {
    agent.stop();
    await connection.close();
  });
  await t.pumpWidget(
    TranscriptWindow(
      launch: launch,
      connection: connection,
      terminal: terminal,
      notifications: notifications,
    ),
    size: size,
  );
  await until(() => connection.app.value.start.phase == StartPhase.connected);
  await t.pump();
  return (agent, terminal);
}

void main() {
  testerChildStatusLifecycle();
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('a turn is working, then done with the notification, then '
        'idle at the next key, each change once, at $size', (t) async {
      final (agent, terminal) = await _open(t, size);
      expect(terminal.statuses, [
        const ProgramStatus(ProgramState.idle, app: 'chord'),
      ]);
      await t.type('slow');
      await t.press('enter');
      await until(() => agent.prompts.isNotEmpty);
      await t.pump();
      // Working at once; named by its first prompt once it is sent.
      expect(terminal.statuses.skip(1), [
        const ProgramStatus(ProgramState.working, app: 'chord'),
        const ProgramStatus(ProgramState.working, app: 'chord', title: 'slow'),
      ]);
      agent.answer();
      await until(() => terminal.statuses.last?.state == ProgramState.done);
      expect(
        terminal.statuses.last,
        const ProgramStatus(
          ProgramState.done,
          app: 'chord',
          title: 'slow',
          message: 'memory is waiting for your input',
        ),
      );
      expect(terminal.notified, [
        ('memory is waiting for your input', NotificationChannel.osc9, ''),
      ]);
      final sent = terminal.statuses.length;
      await t.press('x');
      expect(terminal.statuses.sublist(sent), [
        const ProgramStatus(ProgramState.idle, app: 'chord', title: 'slow'),
      ]);
      // A draw that changes nothing reports nothing.
      await t.press('y');
      expect(terminal.statuses, hasLength(sent + 1));
    });

    testWidgets('a permission blocks and notifies, at $size', (t) async {
      final (agent, terminal) = await _open(t, size);
      agent.ask();
      await until(() => terminal.statuses.last?.state == ProgramState.blocked);
      expect(
        terminal.statuses.last,
        const ProgramStatus(
          ProgramState.blocked,
          app: 'chord',
          kind: ProgramStatusKind.permission,
          message: 'memory needs your permission: Write notes.txt',
        ),
      );
      expect(terminal.notified, [
        (
          'memory needs your permission: Write notes.txt',
          NotificationChannel.osc9,
          '',
        ),
      ]);
    });

    testWidgets('the channel settings chose is the one told; off tells '
        'nothing, at $size', (t) async {
      final (agent, terminal) = await _open(
        t,
        size,
        notifications: const Notifications(
          channel: NotifChannel.off,
          env: TerminalEnv(termProgram: 'iTerm.app'),
        ),
      );
      agent.ask();
      await until(() => terminal.statuses.last?.state == ProgramState.blocked);
      expect(terminal.notified, isEmpty);
    });

    testWidgets('a lent terminal is told again once back; the window writes '
        'nothing while it is away or as it goes, at $size', (t) async {
      final (_, terminal) = await _open(t, size);
      const idle = ProgramStatus(ProgramState.idle, app: 'chord');
      expect(terminal.statuses, [idle]);
      // The terminal clears the record itself as it is lent (its release);
      // the window writes nothing to a terminal that is not its own.
      terminal.events.add(TerminalState.suspended);
      expect(terminal.statuses, [idle]);
      terminal.events.add(TerminalState.active);
      expect(terminal.statuses, [idle, idle]);
      // Given back on a forced way out: nothing more of the window's.
      terminal.events.add(TerminalState.inactive);
      expect(terminal.statuses, [idle, idle]);
      terminal.events.add(TerminalState.active);
      final sent = terminal.statuses.length;
      // A quit that comes of the terminal going away disposes the window
      // first: it writes nothing then, which a hung-up terminal would fail.
      await t.pumpWidget(const SizedBox(), size: size);
      expect(terminal.statuses, hasLength(sent));
      expect(terminal.notified, isEmpty);
    });

    testWidgets('a new connection starts where its own agent stands: the old '
        "permission does not block it, and its own notifies, at $size", (
      t,
    ) async {
      final old = _Agent(), fresh = _Agent();
      final first = old.connect();
      final terminal = RecordingTerminal();
      final shown = ValueNotifier(first);
      addTearDown(() async {
        old.stop();
        fresh.stop();
        await first.close();
      });
      await t.pumpWidget(
        ListenableBuilder(
          listenable: shown,
          builder: (context) => TranscriptWindow(
            launch: launch,
            connection: shown.value,
            terminal: terminal,
            notifications: iterm,
          ),
        ),
        size: size,
      );
      await until(() => first.app.value.start.phase == StartPhase.connected);
      old.ask();
      await until(() => terminal.statuses.last?.state == ProgramState.blocked);
      final second = fresh.connect();
      addTearDown(second.close);
      shown.value = second;
      await t.pump();
      expect(
        terminal.statuses.last,
        const ProgramStatus(ProgramState.idle, app: 'chord'),
      );
      await until(() => second.app.value.start.phase == StartPhase.connected);
      fresh.ask();
      await until(() => terminal.notified.length == 2);
      expect(terminal.statuses.last?.state, ProgramState.blocked);
    });

    testWidgets('a new terminal is told and the old one cleared, lent or '
        'not, at $size', (t) async {
      final agent = _Agent();
      final connection = agent.connect();
      addTearDown(() async {
        agent.stop();
        await connection.close();
      });
      final first = RecordingTerminal();
      final shown = ValueNotifier(first);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: shown,
          builder: (context) => TranscriptWindow(
            launch: launch,
            connection: connection,
            terminal: shown.value,
            notifications: iterm,
          ),
        ),
        size: size,
      );
      final second = RecordingTerminal();
      shown.value = second;
      await t.pump();
      expect(first.statuses, [
        const ProgramStatus(ProgramState.idle, app: 'chord'),
        null,
      ]);
      expect(second.statuses, [
        const ProgramStatus(ProgramState.idle, app: 'chord'),
      ]);
      // Replaced while lent: the new one is still told, and the lent one,
      // which cleared itself as it was lent, is told nothing.
      second.events.add(TerminalState.suspended);
      final third = RecordingTerminal();
      shown.value = third;
      await t.pump();
      expect(second.statuses, [
        const ProgramStatus(ProgramState.idle, app: 'chord'),
      ]);
      expect(third.statuses, [
        const ProgramStatus(ProgramState.idle, app: 'chord'),
      ]);
    });

    testWidgets("a child's wait notifies by its name and a member's with "
        "its run's, and the record names who waits longest, at $size", (
      t,
    ) async {
      final agent = _Agent();
      final connection = agent.connect();
      final terminal = RecordingTerminal();
      addTearDown(() async {
        agent.stop();
        await connection.close();
      });
      final emits = <String, void Function(ConversationEvent)>{};
      void open(ChildInfo info) =>
          connection.agents.openChild(info, (emit, key) {
            connection.fold.dispatch(AgentOpened(key));
            emits[info.id] = emit;
            return Conversation(
              ({required onTraffic, required cancellationToken}) async =>
                  ScriptedSession(),
            );
          });
      open(
        const ChildInfo(
          id: 'a1',
          name: 'parser',
          runtime: 'codex',
          openedAt: 0,
        ),
      );
      open(
        const ChildInfo(
          id: 'l1',
          name: 'bugfix',
          runtime: 'codex',
          team: 'bugfix',
          openedAt: 0,
        ),
      );
      open(
        const ChildInfo(
          id: 'm1',
          name: 'tester',
          runtime: 'codex',
          team: 'bugfix',
          lead: 'l1',
          openedAt: 0,
        ),
      );
      await t.pumpWidget(
        TranscriptWindow(
          launch: launch,
          connection: connection,
          terminal: terminal,
          notifications: iterm,
        ),
        size: size,
      );
      await until(
        () => connection.app.value.start.phase == StartPhase.connected,
      );
      void ask(String id) {
        final emit = emits[id]!;
        emit(Connected('s-$id', AgentState.empty));
        emit(Transcribed(PromptAction('t-$id', 'hi', 0)));
        emit(
          Transcribed(
            PermissionRequestedAction(
              't-$id',
              PermissionWait('p-$id', title: 'Write $id'),
            ),
          ),
        );
      }

      ask('a1');
      await t.pump();
      expect(terminal.notified, [
        (
          'parser needs your permission: Write a1',
          NotificationChannel.osc9,
          '',
        ),
      ]);
      expect(
        terminal.statuses.last,
        const ProgramStatus(
          ProgramState.blocked,
          app: 'chord',
          kind: ProgramStatusKind.permission,
          message: 'parser needs your permission: Write a1',
        ),
      );
      ask('m1');
      await t.pump();
      expect(
        terminal.notified.last.$1,
        'tester (bugfix) needs your permission: Write m1',
      );
      // The record stays on the one asked first.
      expect(
        terminal.statuses.last?.message,
        'parser needs your permission: Write a1',
      );
    });

    testWidgets("the record's title stays main's while a child with its own "
        'first prompt is picked, at $size', (t) async {
      final agent = _Agent();
      final connection = agent.connect();
      final terminal = RecordingTerminal();
      addTearDown(() async {
        agent.stop();
        await connection.close();
      });
      final session = ScriptedSession();
      final child = connection.agents.openChild(
        const ChildInfo(
          id: 'a1',
          name: 'parser',
          runtime: 'codex',
          openedAt: 0,
        ),
        (emit, key) {
          connection.fold.dispatch(AgentOpened(key));
          return Conversation(
            ({required onTraffic, required cancellationToken}) async => session,
          )..listen(emit);
        },
      )!;
      await t.pumpWidget(
        TranscriptWindow(
          launch: launch,
          connection: connection,
          terminal: terminal,
          notifications: iterm,
        ),
        size: size,
      );
      await until(
        () => connection.app.value.start.phase == StartPhase.connected,
      );
      await t.type('main task');
      await t.press('enter');
      await until(() => agent.prompts.isNotEmpty);
      await t.pump();
      expect(terminal.statuses.last?.title, 'main task');
      connection.fold.dispatch(SessionShown(child));
      await t.pump();
      await t.type('child task');
      await t.press('enter');
      await until(() => session.turns.isNotEmpty);
      await t.pump();
      expect(connection.agents.conversationOf(child)!.firstPrompt, isNotNull);
      expect(terminal.statuses.last?.title, 'main task');
    });
  }

  group('tester: status delivery ownership', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('only the latest status returns after suspension at $size', (
        t,
      ) async {
        final (agent, terminal) = await _open(t, size);
        await t.type('draft 👩‍💻 é');
        await t.press('enter');
        await until(() => agent.prompts.isNotEmpty);
        terminal.events.add(TerminalState.suspended);
        final cleared = terminal.statuses.length;
        agent.answer();
        await until(() => terminal.notified.isNotEmpty);
        await t.resize(
          size.width == 80 ? const Size(120, 40) : const Size(80, 24),
        );
        expect(terminal.statuses, hasLength(cleared));
        terminal.events.add(TerminalState.active);
        expect(terminal.statuses.sublist(cleared), [
          const ProgramStatus(
            ProgramState.done,
            app: 'chord',
            title: 'draft 👩‍💻 é',
            message: 'memory is waiting for your input',
          ),
        ]);
        terminal.events.add(TerminalState.active);
        expect(terminal.statuses, hasLength(cleared + 1));
      });

      testWidgets(
        'removed window ignores late answer and terminal events at $size',
        (t) async {
          final (agent, terminal) = await _open(t, size);
          await t.type('slow');
          await t.press('enter');
          await until(() => agent.prompts.isNotEmpty);
          final sent = terminal.statuses.length;
          await t.pumpWidget(const SizedBox(), size: size);
          // Terminal release owns clearing; disposal must not write to a
          // potentially hung-up output stream.
          expect(terminal.statuses, hasLength(sent));
          agent.answer();
          terminal.events.add(TerminalState.suspended);
          terminal.events.add(TerminalState.active);
          await t.pump();
          expect(terminal.statuses, hasLength(sent));
          expect(terminal.notified, isEmpty);
        },
      );

      testWidgets('replaced terminal cannot suspend its successor at $size', (
        t,
      ) async {
        final agent = _Agent();
        final connection = agent.connect();
        addTearDown(() async {
          agent.stop();
          await connection.close();
        });
        final first = RecordingTerminal();
        final second = RecordingTerminal();
        final shown = ValueNotifier(first);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: shown,
            builder: (_) => TranscriptWindow(
              launch: launch,
              connection: connection,
              terminal: shown.value,
              notifications: iterm,
            ),
          ),
          size: size,
        );
        await until(
          () => connection.app.value.start.phase == StartPhase.connected,
        );
        shown.value = second;
        await t.pump();
        final firstCount = first.statuses.length;
        first.events.add(TerminalState.suspended);
        first.events.add(TerminalState.active);
        agent.ask();
        await until(() => second.statuses.last?.state == ProgramState.blocked);
        expect(first.statuses, hasLength(firstCount));
        expect(first.notified, isEmpty);
        expect(second.notified, hasLength(1));
      });
    }
  });
}

void testerChildStatusLifecycle() {
  group('CTUI-93 tester: child status delivery', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'keys acknowledge only the shown agent and removal detaches child waits at $size',
        (t) async {
          final agent = _Agent();
          final connection = agent.connect();
          final terminal = RecordingTerminal();
          addTearDown(() async {
            agent.stop();
            await connection.close();
          });
          late void Function(ConversationEvent) emit;
          final child = connection.agents.openChild(
            const ChildInfo(
              id: 'child',
              name: 'parser',
              runtime: 'fake',
              openedAt: 0,
            ),
            (heard, key) {
              connection.fold.dispatch(AgentOpened(key));
              emit = heard;
              return Conversation(
                ({required onTraffic, required cancellationToken}) async =>
                    ScriptedSession(),
              );
            },
          )!;
          await t.pumpWidget(
            TranscriptWindow(
              launch: launch,
              connection: connection,
              terminal: terminal,
              notifications: iterm,
            ),
            size: size,
          );
          await until(
            () => connection.app.value.start.phase == StartPhase.connected,
          );
          emit(Connected('child', AgentState.empty));
          emit(Transcribed(PromptAction('c', 'child task', 0)));
          emit(Transcribed(ResultAction('c', const TurnAnswered('end_turn'))));
          await t.pump();
          expect(terminal.statuses.last?.state, ProgramState.done);
          expect(
            terminal.notified.single.$1,
            'parser is waiting for your input',
          );
          await t.press('x');
          await t.resize(
            size.width == 80 ? const Size(120, 40) : const Size(80, 24),
          );
          expect(terminal.statuses.last?.state, ProgramState.done);
          connection.agents.pick(child);
          connection.fold.dispatch(SessionShown(child));
          await t.pump();
          expect(terminal.statuses.last?.state, ProgramState.idle);
          final sent = terminal.statuses.length;
          final told = terminal.notified.length;
          await t.pumpWidget(const SizedBox(), size: size);
          emit(
            Transcribed(
              PermissionRequestedAction(
                'c',
                PermissionWait('late', title: 'Late write'),
              ),
            ),
          );
          await t.pump();
          expect(terminal.statuses, hasLength(sent));
          expect(terminal.notified, hasLength(told));
        },
      );
    }
  });
}
