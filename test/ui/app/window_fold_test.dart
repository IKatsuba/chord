// One ordered event path: every agent's events fold into its own state in
// the order they come, shown or not, and the window draws the front's.
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/turn_costs.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/record_history.dart';

const child = 2;
const up = Connected('s', AgentState.empty);

ConversationEvent said(String turnId, String text) =>
    Transcribed(PromptAction(turnId, text, 1));

void main() {
  foldReentryTests();
  testerFoldLifecycleTests();
  testerVisibleDraftGate();
  test("a hidden child's events fold into its own state, leaving the "
      "front's as it was", () {
    final fold = WindowFold(AppState.starting);
    final front = fold.app.value;
    var notified = 0;
    fold.app.addListener(() => notified++);
    fold.dispatch(const AgentOpened(child));
    fold.heard(child, up);
    fold.heard(child, said('c1', 'for the child'));
    expect(identical(fold.app.value, front), isTrue);
    expect(notified, 0);
    expect(
      fold
          .stateOf(child)!
          .transcript
          .entries
          .whereType<UserEntry>()
          .single
          .text,
      'for the child',
    );
    fold.dispatch(const SessionShown(child));
    expect(notified, 1);
    expect(fold.front, child);
    expect(
      fold.app.value.transcript.entries.whereType<UserEntry>().single.text,
      'for the child',
    );
  });

  test("events fold in the order they come, into each key's state", () {
    final fold = WindowFold(AppState.starting);
    fold.dispatch(const AgentOpened(child));
    for (final (key, text) in [
      (mainKey, 'one'),
      (child, 'two'),
      (mainKey, 'three'),
      (child, 'four'),
    ]) {
      fold.heard(key, said('t$text', text));
    }
    List<String> prompts(int key) => [
      for (final entry
          in fold.stateOf(key)!.transcript.entries.whereType<UserEntry>())
        entry.text,
    ];
    expect(prompts(mainKey), ['one', 'three']);
    expect(prompts(child), ['two', 'four']);
  });

  test('what the window writes lands in the front session and the window', () {
    final fold = WindowFold(AppState.starting);
    fold.dispatch(const AgentOpened(child));
    fold.app.value = reduceWindow(
      fold.app.value,
      const DraftEditedAction('typed', 5),
    );
    expect(fold.windowed.value.sessions[mainKey]!.draft, 'typed');
    expect(fold.windowed.value.sessions[child]!.draft, '');
  });

  test("a late event of a closing session's still counts its spend once "
      'the close settles', () {
    final fold = WindowFold(AppState.starting);
    fold.dispatch(const AgentOpened(child));
    fold.heard(child, up);
    fold.dispatch(const SpendClosing(child));
    fold.dispatch(const SessionClosed(child, mainKey));
    fold.dispatch(
      const ClosingHeard(
        child,
        Transcribed(
          UsageAction(
            'c1',
            TurnFigures(turnId: 'c1', usage: {'inputTokens': 120}),
          ),
        ),
      ),
    );
    expect(fold.windowed.value.kept, isEmpty);
    fold.dispatch(const SpendClosed(child));
    expect(fold.windowed.value.closing, isEmpty);
    expect(fold.windowed.value.kept.single.spent!.turns['c1'], {
      'inputTokens': 120,
    });
    // A late event after the close settled finds nothing to fold.
    fold.dispatch(
      const ClosingHeard(child, Transcribed(PromptAction('x', 'x', 1))),
    );
    expect(fold.windowed.value.kept, hasLength(1));
  });

  test("main's events come through the agents, which fold its wait first", () {
    final connection = StartConnection(command: 'unused', cwd: '.');
    addTearDown(connection.close);
    expect(connection.app, same(connection.fold.app));
    expect(connection.agents.agents.main, isNull);
  });

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('a hidden child is drawn once picked, and main again after, '
        'at $size', (t) async {
      final connection = StartConnection(command: 'unused', cwd: '.');
      addTearDown(connection.close);
      connection.app.value = reduceApp(
        const AppState(start: StartState(phase: StartPhase.connected)),
        said('m1', 'asked of main'),
      );
      final fold = connection.fold;
      fold.dispatch(const AgentOpened(child));
      fold.heard(child, up);
      fold.heard(child, said('c1', 'asked of the child'));
      await t.pumpWidget(recordHistoryPreview(connection), size: size);
      expect(t.screen, shows('asked of main'));
      expect(t.screen, isNot(shows('asked of the child')));
      fold.dispatch(const SessionShown(child));
      await t.pump();
      expect(t.screen, shows('asked of the child'));
      expect(t.screen, isNot(shows('asked of main')));
      fold.dispatch(const SessionShown(mainKey));
      await t.pump();
      expect(t.screen, shows('asked of main'));
    });
  }
}

List<String> promptsOf(AppState state) => [
  for (final entry in state.transcript.entries.whereType<UserEntry>())
    entry.text,
];

void foldReentryTests() {
  group('the fold, written and re-entered', () {
    test("the window's writes keep a closing session and what closed ones "
        'spent', () {
      final fold = WindowFold(AppState.starting);
      fold.dispatch(const AgentOpened(child));
      fold.dispatch(const SpendClosing(child));
      fold.dispatch(const SessionClosed(child, mainKey));
      fold.app.value = reduceWindow(
        fold.app.value,
        const DraftEditedAction('typing', 6),
      );
      fold.dispatch(
        const ClosingHeard(
          child,
          Transcribed(
            UsageAction(
              'c1',
              TurnFigures(turnId: 'c1', usage: {'inputTokens': 7}),
            ),
          ),
        ),
      );
      fold.app.value = reduceWindow(
        fold.app.value,
        const DraftEditedAction('typing on', 9),
      );
      fold.dispatch(const SpendClosed(child));
      fold.app.value = reduceWindow(
        fold.app.value,
        const DraftEditedAction('typed', 5),
      );
      expect(fold.windowed.value.kept.single.spent!.turns['c1'], {
        'inputTokens': 7,
      });
      expect(fold.app.value.draft, 'typed');
    });

    test('an event folded by a listener while another is told leaves the '
        "front's view at the newest", () {
      final fold = WindowFold(AppState.starting);
      var once = true;
      fold.windowed.addListener(() {
        if (!once) return;
        once = false;
        fold.heard(mainKey, said('t2', 'second'));
      });
      fold.heard(mainKey, said('t1', 'first'));
      expect(promptsOf(fold.app.value), ['first', 'second']);
      expect(promptsOf(fold.windowed.value.frontState), ['first', 'second']);
    });

    test('a front switch made by a listener is the one shown', () {
      final fold = WindowFold(AppState.starting);
      fold.dispatch(const AgentOpened(child));
      fold.heard(child, said('c1', 'for the child'));
      var once = true;
      fold.windowed.addListener(() {
        if (!once) return;
        once = false;
        fold.dispatch(const SessionShown(child));
      });
      fold.heard(mainKey, said('m1', 'for main'));
      expect(fold.front, child);
      expect(promptsOf(fold.app.value), ['for the child']);
    });

    test("a listener folding again during the window's write keeps both", () {
      final fold = WindowFold(AppState.starting);
      var once = true;
      fold.windowed.addListener(() {
        if (!once) return;
        once = false;
        fold.heard(mainKey, said('t1', 'heard meanwhile'));
      });
      fold.app.value = reduceWindow(
        fold.app.value,
        const DraftEditedAction('written', 7),
      );
      expect(fold.app.value.draft, 'written');
      expect(promptsOf(fold.app.value), ['heard meanwhile']);
    });

    test("a listener writing the window while an event is told works on "
        "what it heard, and both stay", () {
      final fold = WindowFold(AppState.starting);
      var once = true;
      List<String>? read;
      fold.windowed.addListener(() {
        if (!once) return;
        once = false;
        read = promptsOf(fold.stateOf(mainKey)!);
        fold.app.value = reduceWindow(
          fold.app.value,
          const DraftEditedAction('typed', 5),
        );
      });
      fold.heard(mainKey, said('t1', 'first'));
      expect(read, ['first']);
      expect(promptsOf(fold.app.value), ['first']);
      expect(fold.app.value.draft, 'typed');
      expect(promptsOf(fold.windowed.value.frontState), ['first']);
      expect(fold.windowed.value.frontState.draft, 'typed');
    });

    test("a listener's event on a session behind leaves the write shown", () {
      final fold = WindowFold(AppState.starting);
      fold.dispatch(const AgentOpened(child));
      var once = true;
      fold.windowed.addListener(() {
        if (!once) return;
        once = false;
        fold.heard(child, said('c1', 'behind'));
      });
      final written = reduceWindow(
        fold.app.value,
        const DraftEditedAction('written', 7),
      );
      fold.app.value = written;
      expect(fold.app.value, same(written));
      expect(promptsOf(fold.stateOf(child)!), ['behind']);
    });
  });
}

void testerFoldLifecycleTests() {
  group('tester: ordered fold and window subscription lifecycle', () {
    test(
      'an app listener can switch front without losing either session draft',
      () {
        final fold = WindowFold(AppState.starting);
        fold.dispatch(const AgentOpened(child));
        fold.dispatch(
          const SessionActed(child, DraftEditedAction('child draft', 5)),
        );
        var switched = false;
        fold.app.addListener(() {
          if (switched) return;
          switched = true;
          expect(fold.stateOf(mainKey)!.draft, 'main draft');
          fold.dispatch(const SessionShown(child));
          fold.heard(mainKey, said('nested', 'hidden after switch'));
        });
        fold.app.value = reduceWindow(
          fold.app.value,
          const DraftEditedAction('main draft', 4),
        );
        expect(fold.front, child);
        expect(fold.app.value.draft, 'child draft');
        expect(fold.stateOf(mainKey)!.draft, 'main draft');
        expect(promptsOf(fold.stateOf(mainKey)!), ['hidden after switch']);
        fold.app.dispose();
        fold.windowed.dispose();
      },
    );

    test(
      'close before start is repeatable and never calls the opener',
      () async {
        var opened = 0;
        final connection = StartConnection(
          command: 'unused',
          cwd: '.',
          open:
              ({
                required command,
                env,
                required cwd,
                required onTraffic,
                required onPermission,
                relay,
                cancellationToken,
              }) {
                opened++;
                throw StateError('must not open');
              },
        );
        await connection.close();
        connection.start();
        await connection.close();
        expect(opened, 0);
        expect(connection.app.value.closing, isTrue);
        expect(connection.agents.agents.main, isNull);
      },
    );
  });
}

void testerVisibleDraftGate() {
  group('tester: unit 11 visible draft carry-forward gate', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'hidden burst becomes visible and detached window receives no late work at $size',
        (tester) async {
          final connection = StartConnection(command: 'unused', cwd: '.');
          addTearDown(connection.close);
          connection.app.value = reduceApp(
            const AppState(start: StartState(phase: StartPhase.connected)),
            said('m', 'main remains'),
          );
          final fold = connection.fold;
          fold.dispatch(const AgentOpened(child));
          fold.heard(child, up);
          await tester.pumpWidget(recordHistoryPreview(connection), size: size);
          for (var i = 0; i < 1000; i++) {
            fold.dispatch(
              SessionActed(child, DraftEditedAction('hidden $i', 3)),
            );
          }
          fold.heard(child, said('c', 'hidden burst complete'));
          await tester.pump();
          expect(tester.screen, shows('main remains'));
          expect(tester.screen, isNot(shows('hidden burst complete')));
          fold.dispatch(const SessionShown(child));
          await tester.pump();
          await tester.pump();
          await tester.resize(
            size.width == 120 ? const Size(80, 24) : const Size(120, 40),
          );
          expect(tester.screen, shows('hidden burst complete'));
          expect(fold.app.value.draft, 'hidden 999');
          await tester.pumpWidget(const SizedBox());
          fold.dispatch(const SessionShown(mainKey));
          fold.heard(child, said('late', 'after removal'));
          await tester.pump();
          expect(tester.screen, isNot(shows('after removal')));
        },
      );
    }
  });
}
