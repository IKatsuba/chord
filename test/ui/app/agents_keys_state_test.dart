// The list of agents' keys as plain Dart: what a key asks for, what the
// reducer keeps, and the words the status line says, as the original's
// state.ts, keys.ts, closing.ts, session/busy.ts and status.ts
// waitsNotice.
import 'package:chord/notify.dart' show InputAsk, PermissionAsk;
import 'package:chord/session/busy.dart';
import 'package:chord/session/conversation.dart' show QueuedPrompt;
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/session/waits.dart';
import 'package:chord/ui/agents/agents.dart';
import 'package:chord/ui/app/closing.dart';
import 'package:chord/ui/app/keys.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window_fold.dart' show mainKey;
import 'package:chord/ui/prompt/history.dart' as history;
import 'package:chord/ui/shortcuts/bindings.dart' as keymap;
import 'package:chord/ui/shortcuts/state.dart';
import 'package:chord/ui/status/status.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

KeyContext _context(
  AppState state, {
  bool agents = true,
  bool listKeys = false,
  history.History walk = const history.History(),
}) => KeyContext(
  state: state,
  history: walk,
  rows: 24,
  agents: agents,
  listKeys: listKeys,
);

List<Step> _list(String key, [AppState state = const AppState()]) =>
    keySteps(Chord.parse(key), _context(state, listKeys: true));

AppAction _action(List<Step> steps) => (steps.single as Dispatch).action;

AgentRow _row(int key, String name, {bool picked = false}) =>
    AgentRow(key: key, name: name, runtime: 'fake', wait: idle, picked: picked);

void main() {
  group('↓ from the prompt', () {
    test('an empty draft not walking goes into the list while there are '
        'children', () {
      expect(
        _action(newerSteps(_context(const AppState()))),
        isA<AgentsFocusedAction>().having((a) => a.focused, 'focused', true),
      );
      expect(newerSteps(_context(const AppState(), agents: false)), isEmpty);
    });

    test('a draft is set aside first, and a walk steps on', () {
      final steps = newerSteps(_context(const AppState(draft: 'half')));
      expect((steps.first as Dispatch).action, isA<DraftKeptAction>());
      const walking = history.History(prompts: ['one'], index: 0);
      expect(
        newerSteps(
          _context(const AppState(), walk: walking),
        ).whereType<Dispatch>().map((step) => step.action),
        isNot(contains(isA<AgentsFocusedAction>())),
      );
    });
  });

  group('the list with the keys', () {
    test('↑ k and ↓ j move, Enter and Esc go back, x closes', () {
      expect((_list('up').single as MoveAgent).by, -1);
      expect((_list('k').single as MoveAgent).by, -1);
      expect((_list('down').single as MoveAgent).by, 1);
      expect((_list('j').single as MoveAgent).by, 1);
      for (final key in ['enter', 'esc']) {
        expect(
          _action(_list(key)),
          isA<AgentsFocusedAction>().having((a) => a.focused, 'focused', false),
        );
      }
      expect(_list('x').single, isA<CloseAgent>());
    });

    test(
      'ctrl+c arms and quits, never clearing a draft; ctrl+d quits; '
      'ctrl+o and the scroll keys keep theirs; any other key does nothing',
      () {
        const draft = AppState(draft: 'kept', agentsFocus: true);
        expect(_action(_list('ctrl+c', draft)), isA<QuitArmedAction>());
        expect(
          _list('ctrl+c', const AppState(quitArmed: true)).single,
          isA<Quit>(),
        );
        expect(_list('ctrl+d', draft).single, isA<Quit>());
        expect(_action(_list('ctrl+o')), isA<ToggleExpandedAction>());
        expect(_action(_list('pageup')), isA<TranscriptScrolledAction>());
        for (final key in ['tab', '!', '?', 'ctrl+g', 'ctrl+v', 'ctrl+r']) {
          expect(_list(key), isEmpty, reason: key);
        }
      },
    );

    test('a close armed goes with any key but x', () {
      const armed = AppState(agentCloseArmed: 7);
      expect(
        _action(_list('k', armed).take(1).toList()),
        isA<AgentCloseDisarmedAction>(),
      );
      expect(_list('x', armed).single, isA<CloseAgent>());
      for (final key in ['ctrl+x a', 'ctrl+x b']) {
        expect(
          (_list(key, armed).first as Dispatch).action,
          isA<AgentCloseDisarmedAction>(),
          reason: key,
        );
      }
    });

    test('its bindings are described, Esc is no file action, and x is '
        'agents:close', () {
      final bindings = windowBindings(
        () => _context(const AppState(agentsFocus: true), listKeys: true),
        (_) {},
      );
      String? described(String key) =>
          bindings.where((b) => b.chord == Chord.parse(key)).single.description;
      expect(described('up'), 'Pick the agent above');
      expect(described('j'), 'Pick the agent below');
      expect(described('enter'), 'Write to the picked agent');
      expect(described('esc'), 'Back to the picked agent');
      final close = bindings.where((b) => b.chord == Chord.parse('x')).single;
      expect(close.id, 'agents:close');
      expect(
        bindings.where((b) => b.chord == Chord.parse('esc')).single.id,
        isNull,
      );
      expect(
        liveContexts(_context(const AppState(), listKeys: true)),
        contains(keymap.KeyContext.agents),
      );
      // Without the keys, none of the list's own.
      final prompt = windowBindings(() => _context(const AppState()), (_) {});
      expect(prompt.where((b) => b.id == 'agents:close'), isEmpty);
    });
  });

  group('ctrl+x a', () {
    test("the front agent's held request first, else the agent that waits "
        'longest', () {
      expect(
        keySteps(Chord.parse('ctrl+x a'), _context(const AppState())).single,
        isA<AttendSession>(),
      );
      final held = AppState(
        agentsFocus: true,
        transcript: model.Transcript(
          turn: model.AwaitingPermission('t', 0, const [
            model.PermissionWait('p'),
          ], between: true),
        ),
      );
      final steps = keySteps(Chord.parse('ctrl+x a'), _context(held));
      expect(_action(steps), isA<AttendRequestAction>());
      final attended = reduceWindow(held, _action(steps));
      expect(attended.attended, 'p');
      // The keys go into the request from the list.
      expect(attended.agentsFocus, isFalse);
    });
  });

  group('the reducer', () {
    test('the list taking the keys closes the panel; either way an armed '
        'close and a row read by line go', () {
      const view = AgentsView(key: 2, width: 76, limit: 4, top: 1);
      const before = AppState(
        shortcuts: ShortcutsState(help: true),
        agentCloseArmed: 2,
        agentsView: view,
      );
      final focused = reduceWindow(before, const AgentsFocusedAction(true));
      expect(focused.agentsFocus, isTrue);
      expect(focused.shortcuts.help, isFalse);
      expect(focused.agentCloseArmed, isNull);
      expect(focused.agentsView, isNull);
      final left = reduceWindow(
        reduceWindow(focused, const AgentsScrolledAction(view)),
        const AgentsFocusedAction(false),
      );
      expect(left.agentsFocus, isFalse);
      expect(left.agentsView, isNull);
    });

    test('a note of the agents goes when the draft is touched, a quit or a '
        'close is armed, or another agent comes in front', () {
      const noted = AppState(sessionsNote: 'Nothing waits on you');
      expect(
        reduceWindow(noted, const DraftEditedAction('a', 1)).sessionsNote,
        isNull,
      );
      expect(reduceWindow(noted, const QuitArmedAction()).sessionsNote, isNull);
      expect(
        reduceWindow(noted, const AgentCloseArmedAction(2)).sessionsNote,
        isNull,
      );
      var windowed = reduceWindowed(
        WindowedState.of(noted, mainKey),
        const AgentOpened(2),
      );
      expect(windowed.frontState.sessionsNote, 'Nothing waits on you');
      windowed = reduceWindowed(windowed, const SessionShown(2));
      expect(windowed.frontState.sessionsNote, isNull);
    });

    test('the window part keeps the list focus, an armed close and the note '
        'across a switch; a close disarms', () {
      var windowed = reduceWindowed(
        WindowedState.of(
          const AppState(agentsFocus: true, agentCloseArmed: 2),
          mainKey,
        ),
        const AgentOpened(2),
      );
      windowed = reduceWindowed(windowed, const SessionShown(2));
      expect(windowed.frontState.agentsFocus, isTrue);
      expect(windowed.frontState.agentCloseArmed, 2);
      windowed = reduceWindowed(windowed, const SessionClosed(2, mainKey));
      expect(windowed.front, mainKey);
      expect(windowed.frontState.agentCloseArmed, isNull);
      expect(windowed.frontState.agentsFocus, isTrue);
    });
  });

  group('x', () {
    test('main closes nothing; an idle child closes; a busy one arms, then '
        'closes', () {
      expect(
        agentClose(child: false, busy: null, armed: false),
        AgentClose.note,
      );
      expect(mainCloseNote, 'main is the session · ctrl+d quits');
      expect(
        agentClose(child: true, busy: null, armed: false),
        AgentClose.close,
      );
      expect(
        agentClose(child: true, busy: const BusyWorking(), armed: false),
        AgentClose.arm,
      );
      expect(
        agentClose(child: true, busy: const BusyWorking(), armed: true),
        AgentClose.close,
      );
    });

    test('what keeps a child busy, the most pressing first', () {
      expect(busyOf(model.Transcript.empty, const []), isNull);
      expect(
        busyOf(
          const model.Transcript(
            turn: model.AwaitingPermission('t', 0, [model.PermissionWait('p')]),
          ),
          const [QueuedPrompt('q', 'next')],
        ),
        isA<BusyPermission>(),
      );
      expect(
        busyOf(
          const model.Transcript(
            turn: model.Working('t', 0),
            asking: [model.FormWait('f', 'Name it')],
          ),
          const [],
        ),
        isA<BusyInput>(),
      );
      // A message from another agent, a steer and a taken prompt are not
      // the person's.
      expect(
        busyOf(const model.Transcript(turn: model.Working('t', 0)), const [
          QueuedPrompt('a', 'mine'),
          QueuedPrompt('b', 'mine too'),
          QueuedPrompt('c', 'from main', from: model.MessageFrom('main')),
          QueuedPrompt('d', 'steered', steering: true),
        ]),
        isA<BusyQueued>().having((b) => b.count, 'count', 2),
      );
      expect(
        busyOf(const model.Transcript(turn: model.Working('t', 0)), const []),
        isA<BusyWorking>(),
      );
    });

    test('the armed line, word for word', () {
      expect(
        agentCloseArmedLine('parser', const BusyWorking(), 'x'),
        'parser is working · x again to stop it and close',
      );
      expect(
        agentCloseArmedLine('docs', const BusyPermission(), 'd'),
        'docs waits for your permission · d again to stop it and close',
      );
      expect(
        agentCloseArmedLine('docs', const BusyInput(), 'x'),
        'docs asks for input · x again to stop it and close',
      );
      expect(
        agentCloseArmedLine('docs', const BusyQueued(1), 'x'),
        'docs has 1 prompt queued · x again to stop it and close',
      );
      expect(
        agentCloseArmedLine('docs', const BusyQueued(2), 'x'),
        'docs has 2 prompts queued · x again to stop it and close',
      );
    });
  });

  group('the waits notice of the agents not shown', () {
    AgentWaiting asking(String name, num since, {bool input = false}) => (
      name: name,
      wait: AgentWait(
        asking: (
          on: input ? const InputAsk('Name it') : const PermissionAsk(),
          since: since,
        ),
      ),
    );
    AgentWaiting failed(String name, num since, Failure failure) => (
      name: name,
      wait: AgentWait(
        exited: failure == Failure.exited,
        unseen: Unseen(UnseenKind.failed, since: since, failure: failure),
      ),
    );

    test('one asking is named, many counted', () {
      expect(
        agentsWaitsNotice([asking('docs', 5)], 'ctrl+x a')!.text,
        '● docs needs your permission',
      );
      expect(
        agentsWaitsNotice([asking('docs', 5, input: true)], null)!.text,
        '● docs asks for input',
      );
      final many = agentsWaitsNotice([
        asking('docs', 5),
        asking('main', 3),
      ], 'ctrl+x a')!;
      expect(many.text, '● 2 agents wait');
      expect(many.tone, StatusTone.waits);
      expect(
        waitsParts(many, true).single.text,
        '● 2 agents wait · ctrl+x a to go',
      );
      expect(waitsParts(many, false).single.text, '● 2 agents wait · ctrl+x a');
    });

    test('a request outranks a failure; failures counted by kind, gravest '
        'first; a reply or nothing says nothing', () {
      expect(
        agentsWaitsNotice([
          failed('parser', 1, Failure.exited),
          asking('docs', 5),
        ], null)!.text,
        '● docs needs your permission',
      );
      final one = agentsWaitsNotice([
        failed('parser', 1, Failure.exited),
      ], null)!;
      expect(one.text, '✗ parser exited');
      expect(one.tone, StatusTone.ended);
      expect(
        agentsWaitsNotice([failed('docs', 1, Failure.turn)], null)!.text,
        "✗ docs's turn failed",
      );
      expect(
        agentsWaitsNotice([failed('docs', 1, Failure.start)], null)!.text,
        '✗ docs failed to start',
      );
      expect(
        agentsWaitsNotice([
          failed('a', 2, Failure.turn),
          failed('b', 1, Failure.exited),
          failed('c', 3, Failure.turn),
        ], null)!.text,
        '✗ 1 exited · 2 turns failed',
      );
      expect(
        agentsWaitsNotice([
          (
            name: 'docs',
            wait: const AgentWait(unseen: Unseen(UnseenKind.replied, since: 1)),
          ),
        ], null),
        isNull,
      );
      expect(agentsWaitsNotice(const [], null), isNull);
    });
  });

  group('↑ ↓ in the list, pure', () {
    final rows = [
      _row(1, 'main', picked: true),
      _row(2, 'parser'),
      _row(3, 'docs'),
    ];
    ListMove move(List<AgentRow> rows, int by) =>
        listMove(rows, by, limit: 6, width: 76, now: 0, view: null);

    test('↑ from main gives the keys back', () {
      expect(move(rows, -1).leave, isTrue);
    });

    test('↓ picks the next, and the last stays the last', () {
      expect(move(rows, 1).pick, 2);
      final last = [
        _row(1, 'main'),
        _row(2, 'parser'),
        _row(3, 'docs', picked: true),
      ];
      final stays = move(last, 1);
      expect(stays.pick, 3);
      expect(stays.viewed, isFalse);
    });
  });
}
