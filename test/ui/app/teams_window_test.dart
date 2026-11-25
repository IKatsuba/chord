// A team in the window: its lead and members in the list under the
// prompt, folded where the list does not fit, a member's first line and
// box naming its run, the team part's line at the top of a member's
// transcript, and `x` on a lead armed while any of its team works. The
// original's tests/ui/agents/Teams_test.tsx and TeamsList_test.tsx, on
// scripted sessions.
import 'dart:async';

import 'package:chord/acp/connection.dart';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/cli.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/session/window_agents.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/window_fold.dart' show mainKey;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../session/conversation_fake.dart';
import 'editor_window_test.dart' show EditorTerminal, settle;

typedef Team = ({
  StartConnection connection,
  int lead,
  int tester,
  int coder,
  void Function(int key, ConversationEvent event) emit,
});

/// The window over a main that never starts, with run `bugfix` open, its
/// members `tester` and `coder` under it, and `parser`, a plain child,
/// after them, each on a scripted session.
Future<Team> _window(WidgetTester t, Size size) async {
  final hanging = Completer<Agent>();
  final connection = StartConnection(
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
  )..start();
  addTearDown(connection.close);
  addTearDown(() {
    hanging.future.ignore();
    hanging.completeError(StateError('over'));
  });
  // The host closes what `x` closes, as the launch wires it.
  connection.window = AgentsHost(
    runtimeNames: const ['fake'],
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
    closed: (key, front) => connection.fold.dispatch(SessionClosed(key, front)),
  );
  final emits = <int, void Function(ConversationEvent)>{};
  int open(String name, {String? team, String? lead}) =>
      connection.agents.openChild(
        ChildInfo(
          id: 'id-$name',
          name: name,
          runtime: 'fake',
          openedAt: 0,
          team: team,
          lead: lead,
        ),
        (emit, key) {
          emits[key] = emit;
          connection.fold.dispatch(AgentOpened(key));
          final session = ScriptedSession();
          return Conversation(
            ({required onTraffic, required cancellationToken}) async => session,
          )..listen(emit);
        },
      )!;
  connection.fold.heard(mainKey, const Connected('m', AgentState.empty));
  final lead = open('bugfix', team: 'bugfix');
  final tester = open('tester', team: 'bugfix', lead: 'id-bugfix');
  final coder = open('coder', team: 'bugfix', lead: 'id-bugfix');
  open('parser');
  await t.pumpWidget(
    TranscriptWindow(
      launch: const Launch(
        name: 'fake',
        agent: null,
        agentCommand: 'fake',
        version: '0.0.1',
        directory: '.',
      ),
      connection: connection,
      terminal: EditorTerminal(),
    ),
    size: size,
  );
  await settle(t);
  return (
    connection: connection,
    lead: lead,
    tester: tester,
    coder: coder,
    emit: (key, event) => emits[key]!(event),
  );
}

/// The list's lines, under the status line.
List<String> _list(WidgetTester t) {
  final lines = t.screen.lines;
  final first = lines.indexWhere(
    (line) => line.startsWith('    main ') || line.startsWith('  ❯ main '),
  );
  return first < 0
      ? const []
      : [for (final line in lines.sublist(first)) line.trimRight()];
}

/// The status line, above the list.
String _status(WidgetTester t) {
  final lines = t.screen.lines;
  return lines[lines.length - _list(t).length - 1].trim();
}

/// Session [key] in front, as a pick in the list or ctrl+x a puts it.
Future<void> _show(WidgetTester t, Team w, int key) async {
  w.connection.agents.pick(key);
  w.connection.fold.dispatch(SessionShown(key));
  await settle(t);
}

void main() {
  group('CTUI-37 tester: team window transitions', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'member stream and focus survive tiny room then resize at $size',
        (t) async {
          final w = await _window(t, size);
          await _show(t, w, w.tester);
          w.emit(
            w.tester,
            const Transcribed(
              model.PromptAction(
                'tester-burst',
                'Write it.',
                0,
                from: model.MessageFrom('bugfix', reachable: true),
                team: (
                  team: 'bugfix',
                  member: 'tester',
                  text: '界🙂é\nsecond instruction',
                ),
              ),
            ),
          );
          for (var i = 0; i < 1000; i++) {
            w.emit(
              w.tester,
              Transcribed(
                model.UpdateAction(
                  'tester-burst',
                  acp.SessionUpdate.fromJson({
                    'sessionUpdate': 'agent_message_chunk',
                    'content': {
                      'type': 'text',
                      'text': i == 999 ? 'final-chunk' : 'x',
                    },
                  }),
                ),
              ),
            );
          }
          await t.resize(const Size(0, 1));
          await t.resize(const Size(1, 1));
          await t.resize(const Size(30, 12));
          await t.resize(size);
          await settle(t);
          expect(w.connection.fold.front, w.tester);
          expect(t.screen.lines.join('\n'), contains('╭─ tester · bugfix ─'));
          expect(
            w.connection.fold
                .stateOf(w.tester)!
                .transcript
                .entries
                .whereType<model.AssistantEntry>()
                .single
                .text
                .text,
            '${'x' * 999}final-chunk',
          );
          await _show(t, w, mainKey);
          await _show(t, w, w.tester);
          await t.press('ctrl+o');
          await t.press('shift+home');
          await settle(t);
          expect(t.screen.lines.join('\n'), contains('界🙂é'));
          expect(t.screen.lines.join('\n'), contains('second instruction'));
        },
      );
    }
  });
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets("the run's members nest under its lead, which reads as a "
        'team, at $size', (t) async {
      await _window(t, size);
      final list = _list(t);
      if (size.height == 40) {
        // Five rows fit the limit of six: nothing folds.
        expect(
          [for (final line in list) line.split(RegExp(r'\s{2,}'))[1]],
          ['main', 'bugfix', '├─ tester', '└─ coder', 'parser'],
        );
        expect(list[1], contains('team · fake'));
      } else {
        // Five rows past the limit of four: the team folds to its lead.
        expect(list, hasLength(3));
        expect(list[1], contains('bugfix'));
        expect(list[1], contains('team · fake · 3 agents'));
        expect(list.join('\n'), isNot(contains('tester')));
      }
    });

    testWidgets("a member's first line names its run's lead, and its box the "
        'run, at $size', (t) async {
      final w = await _window(t, size);
      await _show(t, w, w.tester);
      final screen = t.screen.lines.join('\n');
      expect(
        screen,
        contains("tester · fake · bugfix's member · opened by @bugfix"),
      );
      expect(screen, contains('╭─ tester · bugfix ─'));
      // Picked, its team unfolds wherever the list is short.
      expect(_list(t).join('\n'), contains('├─ tester'));
      await _show(t, w, w.lead);
      expect(
        t.screen.lines.join('\n'),
        contains('bugfix · team · fake · opened by @main'),
      );
    });

    testWidgets("a member's team part is one dim line at the top of its "
        'transcript, its text under ctrl+o, at $size', (t) async {
      final w = await _window(t, size);
      await _show(t, w, w.tester);
      w.emit(
        w.tester,
        const Transcribed(
          model.PromptAction(
            't1',
            'Write the test.',
            0,
            from: model.MessageFrom('bugfix', reachable: true),
            team: (
              team: 'bugfix',
              member: 'tester',
              text: 'You are tester.\nWrite the smallest test.',
            ),
          ),
        ),
      );
      await settle(t);
      final screen = t.screen.lines.join('\n');
      expect(
        screen,
        contains(
          "⏺ bugfix's instructions for tester · 2 lines (ctrl+o to expand)",
        ),
      );
      expect(screen, isNot(contains('Write the smallest test.')));
      await t.press('ctrl+o');
      await settle(t);
      final opened = t.screen.lines.join('\n');
      expect(opened, contains("⏺ bugfix's instructions for tester · 2 lines"));
      expect(opened, isNot(contains('(ctrl+o to expand)')));
      expect(
        opened,
        contains(
          "⏺ bugfix's instructions for tester · 2 lines\n   You are tester.\n   Write the smallest test.",
        ),
      );
    });

    testWidgets('x on a lead whose member works arms naming its members, and '
        'closes the team on the second, at $size', (t) async {
      final w = await _window(t, size);
      w.emit(
        w.coder,
        const Transcribed(model.PromptAction('turn', 'go on', 0)),
      );
      await t.pump();
      await t.press('down');
      await t.pump();
      await t.press('down');
      await t.pump();
      await t.press('x');
      await t.pump();
      expect(w.connection.fold.app.value.agentCloseArmed, w.lead);
      expect(
        _status(t),
        'bugfix and its 2 members are working · x again to stop them and '
        'close',
      );
      await t.press('x');
      await settle(t);
      expect(
        [for (final child in w.connection.agents.agents.children) child.name],
        ['parser'],
      );
    });

    testWidgets('x on an idle team closes it at once, at $size', (t) async {
      final w = await _window(t, size);
      await t.press('down');
      await t.pump();
      await t.press('down');
      await t.pump();
      await t.press('x');
      await settle(t);
      expect(
        [for (final child in w.connection.agents.agents.children) child.name],
        ['parser'],
      );
    });
  }
}
