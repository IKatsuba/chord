// The list of the window's agents with the keys (design CTUI-35 section 6,
// "Keys"; interface draft I6), as the original's state.ts agentsCommand,
// keys.ts newerSteps and sessions.ts moveAgent, closePicked and attend:
// ↓ from an empty prompt goes in, ↑ ↓ j k pick at once, Enter, Esc and ↑
// at the top come back, `x` closes, ctrl+x a goes where the person is
// waited on, and a box holding the keys hands ↓ from its last row to the
// list.
import 'dart:async';
import 'dart:convert';

import 'package:chord/acp/connection.dart';
import 'package:chord/cli.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/questions.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/session/window_agents.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/window_fold.dart' show mainKey;
import 'package:chord/ui/shortcuts/bindings.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import 'package:fake_async/fake_async.dart';
import 'quit_window_test.dart' show settled;

import '../../../tool/permission.dart' show permissionFixture;
import '../../session/conversation_fake.dart';
import 'editor_window_test.dart' show EditorTerminal, settle;

/// The window over a main that never starts, with `parser` and `docs`
/// open behind it on scripted sessions; [emit] reports an event as child
/// [key]'s conversation would.
typedef Agents = ({
  StartConnection connection,
  int parser,
  int docs,
  void Function(int key, ConversationEvent event) emit,
});

Future<Agents> _window(
  WidgetTester t,
  Size size, {
  List<Object?> blocks = const [],
}) async {
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
  int open(String name, int colour) => connection.agents.openChild(
    ChildInfo(
      id: 'id-$name',
      name: name,
      runtime: 'fake',
      openedAt: 0,
      colour: colour,
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
  // Main up, so the status line says what the keys do rather than that
  // it starts.
  connection.fold.heard(mainKey, const Connected('m', AgentState.empty));
  final parser = open('parser', 0);
  final docs = open('docs', 1);
  await t.pumpWidget(
    TranscriptWindow(
      launch: Launch(
        name: 'fake',
        agent: null,
        agentCommand: 'fake',
        version: '0.0.1',
        directory: '.',
        keymap: blocks.isEmpty
            ? null
            : readKeybindings(jsonEncode({'bindings': blocks})).keymap,
      ),
      connection: connection,
      terminal: EditorTerminal(),
    ),
    size: size,
  );
  await settle(t);
  return (
    connection: connection,
    parser: parser,
    docs: docs,
    emit: (key, event) => emits[key]!(event),
  );
}

/// The list's lines, under the status line.
List<String> _list(WidgetTester t) {
  final lines = t.screen.lines;
  final first = lines.indexWhere(
    (line) => line.startsWith('    main ') || line.startsWith('  ❯ main '),
  );
  return first < 0 ? const [] : lines.sublist(first);
}

/// The status line, above the list.
String _status(WidgetTester t) {
  final lines = t.screen.lines;
  return lines[lines.length - _list(t).length - 1];
}

/// The row the list's `❯` is on, by the agent's name.
String? _picked(WidgetTester t) {
  for (final line in _list(t)) {
    if (line.startsWith('  ❯ ')) return line.substring(4).split(' ').first;
  }
  return null;
}

/// Child [key] runs a turn.
void _working(Agents w, int key) =>
    w.emit(key, const Transcribed(model.PromptAction('turn', 'go on', 0)));

/// Child [key] asks for a permission in a running turn.
void _asking(Agents w, int key, {String id = 'fixture'}) {
  _working(w, key);
  final fixture = permissionFixture();
  w.emit(
    key,
    Transcribed(
      model.PermissionRequestedAction(
        'turn',
        model.PermissionWait(
          id,
          title: fixture.title,
          options: fixture.options,
        ),
      ),
    ),
  );
}

const _questions = Questions(QuestionsAgent.claude, [
  Question(
    id: 'q',
    text: 'Which language?',
    options: [
      QuestionOption(value: 'dart', title: 'Dart'),
      QuestionOption(value: 'go', title: 'Go'),
    ],
    multiSelect: false,
    required: true,
  ),
]);

void main() {
  _testerListBoundaries();
  _testerCloseDeadlines();
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    final wide = size.width == 120;
    final hint = wide
        ? '↑ ↓ to pick · enter to write to it · x to close · esc to go back'
        : '↑ ↓ pick · enter write · x close · esc back';

    // CTUI-171: the original's box gives the keys back on a mouse down.
    testWidgets('a press on the prompt box takes the keys back from the '
        'list, at $size', (t) async {
      final w = await _window(t, size);
      final fold = w.connection.fold;
      await t.press('down');
      await t.pump();
      expect(fold.app.value.agentsFocus, isTrue);
      // Inside the box: the row under its top border, the last one drawn
      // above the status line.
      final top = t.screen.lines.lastIndexWhere((l) => l.startsWith('╭'));
      await t.mouse(
        MouseEvent(
          MouseEventKind.press,
          position: Offset(4, top + 1),
          button: MouseButton.primary,
        ),
      );
      await t.mouse(
        MouseEvent(
          MouseEventKind.release,
          position: Offset(4, top + 1),
          button: MouseButton.primary,
        ),
      );
      await t.pump();
      expect(fold.app.value.agentsFocus, isFalse);
      expect(_picked(t), isNull);
      await t.type('back');
      await t.pump();
      expect(fold.app.value.draft, 'back');
    });

    testWidgets('↓ ↓ from a draft goes into the list, the draft kept, at '
        '$size', (t) async {
      final w = await _window(t, size);
      final fold = w.connection.fold;
      await t.type('half a thought');
      await t.press('down');
      await t.pump();
      expect(fold.app.value.draft, '');
      expect(fold.app.value.agentsFocus, isFalse);
      expect(_picked(t), isNull);
      await t.press('down');
      await t.pump();
      expect(fold.app.value.agentsFocus, isTrue);
      expect(_picked(t), 'main');
      expect(_status(t), startsWith('  $hint'));
      // A stray key types nothing while the list has the keys.
      await t.type('q');
      await t.pump();
      expect(fold.app.value.draft, '');
      // ↑ from the first row gives the keys back, and ↑ again brings the
      // draft that was set aside.
      await t.press('up');
      await t.pump();
      expect(fold.app.value.agentsFocus, isFalse);
      expect(_picked(t), isNull);
      await t.press('up');
      await t.pump();
      expect(fold.app.value.draft, 'half a thought');
    });

    testWidgets('↑ ↓ j k move the pick, and the view switches at once, at '
        '$size', (t) async {
      final w = await _window(t, size);
      final fold = w.connection.fold;
      await t.press('down');
      await t.pump();
      await t.press('down');
      await t.pump();
      expect(_picked(t), 'parser');
      expect(fold.front, w.parser);
      expect(w.connection.agents.agents.picked, w.parser);
      expect(t.screen, shows('╭─ parser'));
      await t.press('j');
      await t.pump();
      expect(_picked(t), 'docs');
      expect(fold.front, w.docs);
      expect(t.screen, shows('╭─ docs'));
      // The last stays the last.
      await t.press('down');
      await t.pump();
      expect(_picked(t), 'docs');
      await t.press('k');
      await t.pump();
      expect(_picked(t), 'parser');
      expect(fold.front, w.parser);
      await t.press('up');
      await t.pump();
      expect(_picked(t), 'main');
      expect(fold.front, mainKey);
      expect(t.screen, isNot(shows('╭─ ')));
      expect(fold.app.value.agentsFocus, isTrue);
    });

    for (final key in const ['enter', 'esc']) {
      testWidgets('$key gives the keys back to the picked agent, at $size', (
        t,
      ) async {
        final w = await _window(t, size);
        final fold = w.connection.fold;
        await t.press('down');
        await t.pump();
        await t.press('down');
        await t.pump();
        await t.press(key);
        await t.pump();
        expect(fold.app.value.agentsFocus, isFalse);
        expect(_picked(t), isNull);
        expect(_status(t), isNot(contains(hint)));
        await t.type('for the parser');
        await t.pump();
        expect(fold.stateOf(w.parser)!.draft, 'for the parser');
        expect(fold.stateOf(mainKey)!.draft, '');
      });
    }

    testWidgets('x closes an idle child at once, at $size', (t) async {
      final w = await _window(t, size);
      await t.press('down');
      await t.pump();
      await t.press('down');
      await t.pump();
      await t.press('x');
      await settle(t);
      final roster = w.connection.agents.agents;
      expect([for (final child in roster.children) child.name], ['docs']);
      expect(w.connection.fold.front, mainKey);
      expect(_list(t).join('\n'), isNot(contains('parser')));
      expect(w.connection.fold.app.value.agentCloseArmed, isNull);
    });

    testWidgets('x on a working child arms with the note, and closes on the '
        'second, at $size', (t) async {
      final w = await _window(t, size);
      _working(w, w.parser);
      await t.pump();
      await t.press('down');
      await t.pump();
      await t.press('down');
      await t.pump();
      await t.press('x');
      await t.pump();
      expect(w.connection.fold.app.value.agentCloseArmed, w.parser);
      expect(
        _status(t).trim(),
        'parser is working · x again to stop it and close',
      );
      expect(w.connection.agents.agents.children, hasLength(2));
      await t.press('x');
      await settle(t);
      expect(
        [for (final child in w.connection.agents.agents.children) child.name],
        ['docs'],
      );
    });

    testWidgets('another key between the two presses of x disarms, at $size', (
      t,
    ) async {
      final w = await _window(t, size);
      _working(w, w.parser);
      await t.pump();
      await t.press('down');
      await t.pump();
      await t.press('down');
      await t.pump();
      await t.press('x');
      await t.pump();
      await t.type('q');
      await t.pump();
      expect(w.connection.fold.app.value.agentCloseArmed, isNull);
      await t.press('x');
      await t.pump();
      expect(w.connection.agents.agents.children, hasLength(2));
    });

    testWidgets('ctrl+x a between the two presses of x disarms too, at '
        '$size', (t) async {
      final w = await _window(t, size);
      _working(w, w.parser);
      await t.pump();
      await t.press('down');
      await t.pump();
      await t.press('down');
      await t.pump();
      await t.press('x');
      await t.pump();
      expect(w.connection.fold.app.value.agentCloseArmed, w.parser);
      await t.press('ctrl+x a');
      await t.pump();
      expect(w.connection.fold.app.value.agentCloseArmed, isNull);
      await t.press('x');
      await t.pump();
      // Armed again, not closed.
      expect(w.connection.agents.agents.children, hasLength(2));
    });

    testWidgets('x on main closes nothing and says why, at $size', (t) async {
      final w = await _window(t, size);
      await t.press('down');
      await t.pump();
      await t.press('x');
      await settle(t);
      expect(w.connection.agents.agents.children, hasLength(2));
      expect(_status(t), contains('main is the session · ctrl+d quits'));
    });

    testWidgets('the panel names the list keys and the background, at '
        '$size', (t) async {
      final w = await _window(t, size);
      await t.press('?');
      await t.pump();
      expect(w.connection.fold.app.value.shortcuts.help, isTrue);
      expect(t.screen, shows('↑ ↓ for prompts, agents, background'));
      expect(t.screen, shows('x to close an agent, stop background'));
      expect(t.screen, shows('enter for background, details, a call'));
      // Going into the list closes the panel, which would sit where the
      // list's hint is.
      await t.press('esc');
      await t.pump();
      await t.press('?');
      await t.pump();
      w.connection.fold.app.value = reduceWindow(
        w.connection.fold.app.value,
        const AgentsFocusedAction(true),
      );
      await t.pump();
      expect(w.connection.fold.app.value.shortcuts.help, isFalse);
      expect(t.screen, isNot(shows('x to close an agent')));
    });

    testWidgets('agents:close rebound to d moves the hint, the key and the '
        'panel, at $size', (t) async {
      final w = await _window(
        t,
        size,
        blocks: [
          {
            'context': 'Agents',
            'bindings': {'d': 'agents:close', 'x': null},
          },
        ],
      );
      await t.press('?');
      await t.pump();
      expect(t.screen, shows('d to close an agent'));
      expect(t.screen, isNot(shows('x to close an agent')));
      await t.press('esc');
      await t.pump();
      await t.press('down');
      await t.pump();
      expect(
        _status(t),
        contains(wide ? 'd to close · esc to go back' : 'd close · esc back'),
      );
      await t.press('down');
      await t.pump();
      await t.press('x');
      await settle(t);
      expect(w.connection.agents.agents.children, hasLength(2));
      await t.press('d');
      await settle(t);
      expect(
        [for (final child in w.connection.agents.agents.children) child.name],
        ['docs'],
      );
    });

    testWidgets('ctrl+x a goes to the oldest asker, then the next, at $size', (
      t,
    ) async {
      final w = await _window(t, size);
      _asking(w, w.docs);
      await t.pump(const Duration(milliseconds: 5));
      _asking(w, w.parser);
      await t.pump();
      expect(_status(t), contains('● 2 agents wait'));
      await t.press('ctrl+x a');
      await t.pump();
      expect(w.connection.fold.front, w.docs);
      expect(t.screen, shows('╭─ docs'));
      await t.press('ctrl+x a');
      await t.pump();
      expect(w.connection.fold.front, w.parser);
      expect(t.screen, shows('╭─ parser'));
    });

    testWidgets('ctrl+x a with none waiting says so, until the draft is '
        'touched, at $size', (t) async {
      final w = await _window(t, size);
      await t.press('ctrl+x a');
      await t.pump();
      expect(_status(t), contains('Nothing waits on you'));
      expect(w.connection.fold.front, mainKey);
      await t.type('a');
      await t.pump();
      expect(_status(t), isNot(contains('Nothing waits on you')));
    });

    testWidgets('a permission hands ↓ from its last choice to the list and '
        'gets its place back, at $size', (t) async {
      final w = await _window(t, size);
      _asking(w, w.parser);
      await t.press('ctrl+x a');
      await t.pump();
      await t.pump();
      expect(w.connection.fold.front, w.parser);
      expect(t.screen, shows('❯ 1. Allow once'));
      await t.press('down');
      await t.press('down');
      await t.pump();
      expect(t.screen, shows('❯ 3. Deny'));
      expect(w.connection.fold.app.value.agentsFocus, isFalse);
      // The last choice does not wrap while there is a list to go to.
      await t.press('down');
      await t.pump();
      await t.pump();
      expect(w.connection.fold.app.value.agentsFocus, isTrue);
      expect(_picked(t), 'parser');
      expect(t.screen, isNot(shows('❯ 3. Deny')));
      expect(t.screen, isNot(shows('❯ 1. Allow once')));
      // Moving through the list answers nothing.
      await t.press('up');
      await t.pump();
      await t.press('down');
      await t.pump();
      expect(_picked(t), 'parser');
      await t.press('enter');
      await t.pump();
      await t.pump();
      expect(w.connection.fold.app.value.agentsFocus, isFalse);
      expect(t.screen, shows('❯ 3. Deny'));
      await t.press('up');
      await t.pump();
      expect(t.screen, shows('❯ 2. Always allow'));
    });

    testWidgets('a link hands ↓ from Decline to the list and gets its place '
        'back, at $size', (t) async {
      final w = await _window(t, size);
      _working(w, w.parser);
      w.emit(
        w.parser,
        const Transcribed(
          model.ElicitationRequestedAction(
            'turn',
            model.LinkWait('link', 'Sign in', 'https://example.com/in'),
          ),
        ),
      );
      await t.press('ctrl+x a');
      await t.pump();
      await t.pump();
      expect(t.screen, shows('❯ 1. Open in the browser'));
      await t.press('down');
      await t.pump();
      expect(t.screen, shows('❯ 2. Decline'));
      await t.press('down');
      await t.pump();
      await t.pump();
      expect(w.connection.fold.app.value.agentsFocus, isTrue);
      expect(t.screen, isNot(shows('❯ 2. Decline')));
      expect(t.screen, isNot(shows('Enter to choose · Esc to cancel')));
      await t.press('esc');
      await t.pump();
      await t.pump();
      expect(w.connection.fold.app.value.agentsFocus, isFalse);
      expect(t.screen, shows('❯ 2. Decline'));
      expect(t.screen, shows('Enter to choose · Esc to cancel'));
    });

    testWidgets('a form hands ↓ from its buttons to the list and gets its '
        'place back, at $size', (t) async {
      final w = await _window(t, size);
      _working(w, w.parser);
      w.emit(
        w.parser,
        const Transcribed(
          model.ElicitationRequestedAction(
            'turn',
            model.FormWait(
              'form',
              'Name it',
              schema: {
                'type': 'object',
                'properties': {
                  'name': {'type': 'string', 'title': 'Name'},
                },
              },
            ),
          ),
        ),
      );
      await t.press('ctrl+x a');
      await t.pump();
      await t.pump();
      await t.type('kept');
      await t.press('down');
      await t.pump();
      expect(w.connection.fold.app.value.agentsFocus, isFalse);
      await t.press('down');
      await t.pump();
      await t.pump();
      expect(w.connection.fold.app.value.agentsFocus, isTrue);
      expect(_picked(t), 'parser');
      await t.press('enter');
      await t.pump();
      await t.pump();
      expect(w.connection.fold.app.value.agentsFocus, isFalse);
      // Back on its buttons, the name as typed: ↑ goes to the field.
      await t.press('up');
      await t.type('!');
      await t.pump();
      expect(t.screen, shows('kept!'));
    });

    testWidgets('a form keeps what was typed while another agent is in '
        'front, at $size', (t) async {
      final w = await _window(t, size);
      _working(w, w.parser);
      w.emit(
        w.parser,
        const Transcribed(
          model.ElicitationRequestedAction(
            'turn',
            model.FormWait(
              'form',
              'Name it',
              schema: {
                'type': 'object',
                'properties': {
                  'name': {'type': 'string', 'title': 'Name'},
                },
              },
            ),
          ),
        ),
      );
      await t.press('ctrl+x a');
      await t.pump();
      await t.pump();
      await t.type('kept');
      await t.press('down');
      await t.pump();
      await t.press('down');
      await t.pump();
      await t.pump();
      // docs in front: parser's form is not on screen for a while.
      await t.press('down');
      await t.pump();
      await t.pump();
      expect(_picked(t), 'docs');
      await t.press('up');
      await t.pump();
      await t.pump();
      expect(_picked(t), 'parser');
      await t.press('enter');
      await t.pump();
      await t.pump();
      await t.press('up');
      await t.type('!');
      await t.pump();
      expect(t.screen, shows('kept!'));
    });

    testWidgets('a plan hands ↓ from its Note to the list and gets its '
        'place back, at $size', (t) async {
      final w = await _window(t, size);
      _working(w, w.parser);
      w.emit(
        w.parser,
        const Transcribed(
          model.PlanRequestedAction(
            'turn',
            model.PlanWait('plan', model.PlanAgent.cursor, toolCallId: 'c'),
          ),
        ),
      );
      await t.pump();
      // parser picked through the list, and into its plan.
      await t.press('down');
      await t.pump();
      await t.press('down');
      await t.pump();
      await t.press('enter');
      await t.pump();
      await t.pump();
      expect(w.connection.fold.front, w.parser);
      await t.press('down');
      await t.pump();
      await t.press('down');
      await t.pump();
      await t.pump();
      expect(t.screen, shows('❯ Note'));
      await t.type('smaller');
      await t.press('down');
      await t.pump();
      await t.pump();
      expect(w.connection.fold.app.value.agentsFocus, isTrue);
      expect(t.screen, isNot(shows('❯ Note')));
      await t.press('enter');
      await t.pump();
      await t.pump();
      expect(t.screen, shows('❯ Note'));
      await t.type(' still');
      await t.pump();
      expect(t.screen, shows('smaller still'));
    });

    testWidgets('a question box hands ↓ from its last row to the list and '
        'gets its place back, at $size', (t) async {
      final w = await _window(t, size);
      _working(w, w.parser);
      w.emit(
        w.parser,
        const Transcribed(
          model.ElicitationRequestedAction(
            'turn',
            model.FormWait('ask', 'Which?', questions: _questions),
          ),
        ),
      );
      await t.press('ctrl+x a');
      await t.pump();
      await t.pump();
      final fold = w.connection.fold;
      var presses = 0;
      while (!fold.app.value.agentsFocus && presses < 12) {
        await t.press('down');
        await t.pump();
        await t.pump();
        presses++;
      }
      expect(fold.app.value.agentsFocus, isTrue);
      expect(presses, greaterThan(1));
      expect(_picked(t), 'parser');
      // The list's `❯` alone: the box draws none while away.
      expect(t.screen.lines.where((line) => line.contains('❯')), hasLength(1));
      await t.press('esc');
      await t.pump();
      await t.pump();
      expect(fold.app.value.agentsFocus, isFalse);
      // Back on the last row: ↓ goes into the list again at once.
      await t.press('down');
      await t.pump();
      await t.pump();
      expect(fold.app.value.agentsFocus, isTrue);
    });
  }
}

void _testerListBoundaries() {
  group('CTUI-35 tester: list focus and request boundaries', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'rebound busy close needs two uninterrupted presses at $size',
        (t) async {
          final w = await _window(
            t,
            size,
            blocks: [
              {
                'context': 'Agents',
                'bindings': {'d': 'agents:close', 'x': null},
              },
            ],
          );
          _working(w, w.parser);
          await t.press('down');
          await t.press('down');
          await t.press('d');
          expect(w.connection.app.value.agentCloseArmed, w.parser);
          expect(_status(t), contains('d again to stop it and close'));
          await t.press('x');
          expect(w.connection.app.value.agentCloseArmed, isNull);
          await t.press('d');
          expect(w.connection.agents.agents.children, hasLength(2));
          await t.press('d');
          await settle(t);
          expect(w.connection.agents.agents.children.map((c) => c.name), [
            'docs',
          ]);
        },
      );

      testWidgets(
        'unrelated list keys disarm without editing any prompt at $size',
        (t) async {
          final w = await _window(t, size);
          _working(w, w.parser);
          await t.press('down');
          await t.press('down');
          for (final key in [
            'left',
            'right',
            'backspace',
            'delete',
            'space',
            'tab',
            'shift+tab',
            'ctrl+r',
            'ctrl+g',
            '!',
          ]) {
            await t.press('x');
            expect(w.connection.app.value.agentCloseArmed, w.parser);
            await t.press(key);
            expect(w.connection.app.value.agentCloseArmed, isNull, reason: key);
            expect(w.connection.app.value.agentsFocus, isTrue, reason: key);
            expect(w.connection.fold.front, w.parser, reason: key);
            expect(w.connection.fold.stateOf(mainKey)!.draft, '', reason: key);
            expect(w.connection.fold.stateOf(w.parser)!.draft, '', reason: key);
            expect(w.connection.fold.stateOf(w.docs)!.draft, '', reason: key);
            expect(w.connection.agents.agents.children, hasLength(2));
          }
        },
      );

      testWidgets(
        'a tall picked row reads one line before changing agent at $size',
        (t) async {
          final w = await _window(t, size);
          final session = ScriptedSession();
          final tall = w.connection.agents.openChild(
            ChildInfo(
              id: 'tall',
              name: List.filled(240, '界🙂').join(),
              runtime: 'fake',
              openedAt: 0,
            ),
            (emit, key) {
              w.connection.fold.dispatch(AgentOpened(key));
              return Conversation(
                ({required onTraffic, required cancellationToken}) async =>
                    session,
              )..listen(emit);
            },
          )!;
          await settle(t);
          for (var i = 0; i < 4; i++) {
            await t.press('down');
          }
          expect(w.connection.fold.front, tall);
          final before = w.connection.app.value.agentsView?.top ?? 0;
          for (var line = 1; line <= 4; line++) {
            await t.press('down');
            expect(w.connection.fold.front, tall);
            expect(w.connection.app.value.agentsView!.top, before + line);
          }
          expect(t.screen.lines.any((line) => line.startsWith('  ↑ ')), isTrue);
          expect(t.screen.lines.any((line) => line.startsWith('  ↓ ')), isTrue);
          await t.press('up');
          expect(w.connection.fold.front, tall);
          expect(w.connection.app.value.agentsView!.top, before + 3);
          await t.press('up');
          expect(w.connection.fold.front, w.docs);
        },
      );

      testWidgets(
        'a form survives picking another agent and a hidden resize at $size',
        (t) async {
          final w = await _window(t, size);
          _working(w, w.parser);
          w.emit(
            w.parser,
            const Transcribed(
              model.ElicitationRequestedAction(
                'turn',
                model.FormWait(
                  'saved-form',
                  'Name it',
                  schema: {
                    'type': 'object',
                    'properties': {
                      'name': {'type': 'string', 'title': 'Name'},
                    },
                  },
                ),
              ),
            ),
          );
          await t.press('ctrl+x a');
          await t.pump();
          await t.type('界draft');
          await t.press('down');
          await t.press('down');
          expect(w.connection.app.value.agentsFocus, isTrue);
          await t.press('down');
          expect(w.connection.fold.front, w.docs);
          await t.resize(
            size.width == 120 ? const Size(80, 24) : const Size(120, 40),
          );
          await t.press('up');
          expect(w.connection.fold.front, w.parser);
          await t.press('enter');
          await t.pump();
          await t.press('up');
          await t.type('!');
          await t.pump();
          expect(t.screen, shows('界draft!'));
        },
      );
    }
  });
}

void _testerCloseDeadlines() {
  group('CTUI-35 tester: agent close deadline lifecycle', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      test('expiry, rearm and unmount own their timers at $size', () {
        fakeAsync((async) {
          final t = WidgetTester();
          final pending = Completer<Agent>();
          pending.future.ignore();
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
                }) => pending.future,
          )..start();
          final session = ScriptedSession();
          final child = connection.agents.openChild(
            const ChildInfo(
              id: 'timer-child',
              name: 'parser',
              runtime: 'fake',
              openedAt: 0,
            ),
            (emit, key) {
              connection.fold.dispatch(AgentOpened(key));
              return Conversation(
                ({required onTraffic, required cancellationToken}) async =>
                    session,
              )..listen(emit);
            },
          )!;
          try {
            connection.fold.heard(
              mainKey,
              const Connected('m', AgentState.empty),
            );
            settled(
              async,
              t.pumpWidget(
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
              ),
            );
            connection.fold.heard(
              child,
              const Transcribed(model.PromptAction('turn', 'go', 0)),
            );
            settled(async, t.press('down'));
            settled(async, t.press('down'));
            settled(async, t.press('x'));
            async.elapse(const Duration(milliseconds: 1999));
            expect(connection.app.value.agentCloseArmed, child);
            async.elapse(const Duration(milliseconds: 1));
            expect(connection.app.value.agentCloseArmed, isNull);
            settled(async, t.press('x'));
            async.elapse(const Duration(milliseconds: 1500));
            settled(async, t.press('space'));
            settled(async, t.press('x'));
            async.elapse(const Duration(milliseconds: 501));
            expect(connection.app.value.agentCloseArmed, child);
          } finally {
            t.dispose();
            pending.completeError(StateError('fixture closed'));
            settled(async, connection.close());
          }
          expect(async.pendingTimers, isEmpty);
        });
      });
    }
  });
}
