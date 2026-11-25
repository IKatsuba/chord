import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/keys.dart';
import 'package:chord/ui/app/selection.dart' show SelectionKind;
import 'package:chord/session/agent_state.dart';
import 'package:chord/ui/pickers/pickers.dart';
import 'package:chord/ui/pickers/state.dart';
import '../../session/settings_test.dart' show select, value;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/prompt/history.dart' as history;
import 'package:chord/ui/prompt/prompt.dart';
import 'package:chord/ui/shortcuts/keys.dart' as catalog;
import 'package:chord/ui/shortcuts/state.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/permission.dart';

KeyContext context([
  AppState state = const AppState(),
  history.History h = const history.History(),
]) => KeyContext(state: state, history: h, rows: 24);
List<Step> press(String chord, [AppState state = const AppState()]) =>
    keySteps(Chord.parse(chord), context(state));
AppState waiting({
  bool held = false,
  bool overflow = false,
  bool help = false,
  bool panelOverflow = false,
}) => AppState(
  transcript: model.Transcript(
    turn: model.AwaitingPermission('turn', 0, [
      permissionFixture(),
    ], between: held),
  ),
  requestOverflows: overflow,
  shortcuts: ShortcutsState(help: help, panelOverflows: panelOverflow),
);
AppAction dispatched(List<Step> steps) => (steps.single as Dispatch).action;

void main() {
  // CTUI-86: a form, link, questions or plan takes ctrl+c to stop the turn,
  // which takes it with it, as the original's keyCommand; a selection
  // shown copies first, and a form held back between turns leaves ctrl+c
  // to the prompt.
  test('ctrl+c with a form open stops the turn, after a selection copy', () {
    const form = model.FormWait('f', 'Set up');
    const plan = model.PlanWait(
      'p',
      model.PlanAgent.cursor,
      toolCallId: 'call',
    );
    for (final transcript in const [
      model.Transcript(turn: model.Working('t', 0), asking: [form]),
      model.Transcript(
        turn: model.Working('t', 0),
        planAsks: [model.PlanAsk('t', plan)],
      ),
    ]) {
      final state = AppState(transcript: transcript, draft: 'typed');
      expect(press('ctrl+c', state).single, isA<Interrupt>());
      expect(
        press(
          'ctrl+c',
          AppState(transcript: transcript, quitArmed: true),
        ).single,
        isA<Interrupt>(),
      );
      expect(
        keySteps(
          Chord.parse('ctrl+c'),
          KeyContext(
            state: state,
            history: const history.History(),
            rows: 24,
            selection: SelectionKind.shown,
          ),
        ).single,
        isA<CopySelection>(),
      );
    }
    const between = model.FormWait('f', 'Set up', between: true);
    final held = AppState(
      transcript: const model.Transcript(asking: [between]),
    );
    expect(dispatched(press('ctrl+c', held)), isA<QuitArmedAction>());
  });
  test(
    'Ctrl+C clears every nonempty draft, including spaces, before another press can arm',
    () {
      for (final draft in ['hello', ' ', '界\n']) {
        final steps = press(
          'ctrl+c',
          AppState(draft: draft, cursor: endOf(draft), quitArmed: true),
        );
        expect(steps, hasLength(2));
        expect((steps.first as Dispatch).action, isA<DraftClearedAction>());
        final shown = steps.last as ShowDraft;
        expect([shown.text, shown.cursor], ['', startCursor]);
      }
      expect(dispatched(press('ctrl+c')), isA<QuitArmedAction>());
      expect(
        press('ctrl+c', const AppState(quitArmed: true)).single,
        isA<Quit>(),
      );
    },
  );
  test('Ctrl+D only quits exactly empty drafts', () {
    expect(press('ctrl+d').single, isA<Quit>());
    expect(press('ctrl+d', const AppState(draft: ' ')), isEmpty);
    expect(press('ctrl+d', waiting(help: true)).single, isA<Quit>());
  });
  test('Escape closes help before permission rejection or interrupt', () {
    expect(
      (dispatched(press('esc', waiting(help: true))) as ShortcutsChangedAction)
          .action,
      isA<HelpClosed>(),
    );
    expect((press('esc', waiting()).single as RejectPermission).id, 'fixture');
    expect(press('esc', waiting(held: true)).single, isA<Interrupt>());
    expect(press('esc').single, isA<Interrupt>());
  });
  test('question mark only toggles on exactly empty input', () {
    expect(
      (dispatched(press('?')) as ShortcutsChangedAction).action,
      isA<HelpToggled>(),
    );
    expect(press('?', const AppState(draft: ' ')), isEmpty);
    expect(press('?', const AppState(draft: '?')), isEmpty);
  });
  test('details and attention are reducer steps independent of turn state', () {
    expect(dispatched(press('ctrl+o')), isA<ToggleExpandedAction>());
    expect(
      reduceWindow(const AppState(), dispatched(press('ctrl+o'))).expanded,
      isTrue,
    );
    final held = waiting(held: true);
    final attended = reduceWindow(held, dispatched(press('ctrl+x a', held)));
    expect(attended.attended, 'fixture');
    expect(heldBack(attended), isFalse);
  });
  test(
    'all scroll aliases prefer overflowing panel, then active request, then transcript',
    () {
      const expected = {
        'pageup': ScrollStep.pageUp,
        'shift+pageup': ScrollStep.pageUp,
        'pagedown': ScrollStep.pageDown,
        'shift+pagedown': ScrollStep.pageDown,
        'shift+up': ScrollStep.lineUp,
        'shift+down': ScrollStep.lineDown,
        'home': ScrollStep.top,
        'shift+home': ScrollStep.top,
        'end': ScrollStep.bottom,
        'shift+end': ScrollStep.bottom,
      };
      for (final entry in expected.entries) {
        expect(
          (press(
                    entry.key,
                    waiting(overflow: true, help: true, panelOverflow: true),
                  ).single
                  as ScrollPanel)
              .step,
          entry.value,
        );
        expect(
          (press(entry.key, waiting(overflow: true, help: true)).single
                  as ScrollRequest)
              .step,
          entry.value,
        );
        expect(
          (dispatched(press(entry.key, waiting(held: true, overflow: true)))
                  as TranscriptScrolledAction)
              .step,
          entry.value,
        );
        expect(
          (dispatched(press(entry.key)) as TranscriptScrolledAction).step,
          entry.value,
        );
      }
    },
  );
  test('transcript scrolling reduces the measured framework snapshot', () {
    const before = AppState(
      scroll: ScrollState(content: 100, view: 20, following: true),
    );
    final after = reduceWindow(before, dispatched(press('pageup', before)));
    expect(after.scroll.offset, 62);
    expect(after.scroll.following, isFalse);
    expect(
      reduceWindow(after, dispatched(press('end', after))).scroll.following,
      isTrue,
    );
  });
  test('unmatched editing and text keys are left to the framework', () {
    for (final key in [
      'a',
      'up',
      'down',
      'enter',
      'shift+enter',
      'alt+left',
      'ctrl+z',
    ]) {
      expect(press(key), isEmpty, reason: key);
    }
  });
  test(
    'submit keeps backslash continuation and native grapheme cursor placement',
    () {
      const state = AppState(draft: '界é\\tail', cursor: 3);
      final continuedSteps = submitSteps(state.draft, context(state));
      final shown = continuedSteps.single as ShowDraft;
      expect(shown.text, '界é\ntail');
      expect(shown.cursor, 3);
      expect(continued('x', -1), isNull);
      expect(continued('x', 9), isNull);
    },
  );
  test(
    'submit delegates accepted text once, without clearing or recording it early',
    () {
      const ready = AppState(start: StartState(phase: StartPhase.connected));
      expect(
        (submitSteps(' hello ', context(ready)).single as Send).text,
        ' hello ',
      );
      expect(submitSteps('  ', context(ready)), isEmpty);
      expect(submitSteps('hello', context()), isEmpty);
      expect(
        submitSteps(
          'hello',
          context(const AppState(start: StartState(phase: StartPhase.gone))),
        ).single,
        isA<Send>(),
      );
    },
  );
  test(
    'history steps preserve order, restore draft and put cursor at the end',
    () {
      const h = history.History(prompts: ['old', '界é']);
      final older = olderSteps(context(const AppState(draft: 'draft'), h));
      expect(older.first, isA<HistoryStep>());
      expect((older.last as ShowDraft).text, '界é');
      expect((older.last as ShowDraft).cursor, 2);
      final newer = newerSteps(
        context(
          const AppState(draft: '界é'),
          (older.first as HistoryStep).history,
        ),
      );
      expect((newer.last as ShowDraft).text, 'draft');
      expect(olderSteps(context()), isEmpty);
      expect(newerSteps(context()), isEmpty);
    },
  );
  test(
    'choice intents require the shown attended permission and a real option',
    () {
      final state = waiting();
      final step =
          chooseSteps('fixture', 'allow', context(state)).single
              as ChoosePermission;
      expect([step.id, step.optionId], ['fixture', 'allow']);
      expect(chooseSteps('other', 'allow', context(state)), isEmpty);
      expect(chooseSteps('fixture', 'unknown', context(state)), isEmpty);
      expect(
        chooseSteps('fixture', 'allow', context(waiting(held: true))),
        isEmpty,
      );
    },
  );
  test('every registered app chord has a catalog row', () {
    final listed = {
      for (final row in catalog.shortcuts)
        for (final key in row.presses) Chord.parse(key),
    };
    for (final binding in windowBindings(() => context(), (_) {})) {
      expect(listed, contains(binding.chord), reason: binding.chord.toString());
    }
  });
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'registered Actions play each matched app chord once at $size',
      (t) async {
        final played = <List<Step>>[];
        await t.pumpWidget(
          Actions(
            bindings: windowBindings(() => context(), played.add),
            child: Focus(autofocus: true, child: Text('keys')),
          ),
          size: size,
        );
        for (final key in windowKeyDescriptions.keys) {
          final before = played.length;
          await t.press(key);
          expect(played.length, before + 1, reason: key);
          expect(
            played.last.isNotEmpty,
            !const {
              'shift+tab',
              'ctrl+shift+c',
              'backspace',
              'shift+backspace',
            }.contains(key),
            reason: key,
          );
        }
        for (final phase in [SelectionKind.shown, SelectionKind.copying]) {
          await t.pumpWidget(
            Actions(
              bindings: windowBindings(
                () => KeyContext(
                  state: const AppState(),
                  history: const history.History(),
                  rows: size.height,
                  selection: phase,
                ),
                played.add,
              ),
              child: Focus(autofocus: true, child: Text('keys')),
            ),
            size: size,
          );
          final before = played.length;
          await t.press('ctrl+shift+c');
          expect(played.length, before + 1);
          expect(played.last.single, isA<CopySelection>());
        }
        final before = played.length;
        await t.press('a');
        expect(played.length, before);
      },
    );
    testWidgets(
      'live pick Actions invoke all four real commands with catalog coverage at $size',
      (t) async {
        final played = <List<Step>>[];
        KeyContext current() => const KeyContext(
          state: AppState(),
          history: history.History(),
          rows: 24,
          picking: true,
        );
        final bindings = windowBindings(current, played.add);
        final listed = {
          for (final row in catalog.shortcuts)
            for (final press in row.presses) Chord.parse(press),
        };
        for (final binding in bindings) {
          expect(listed, contains(binding.chord));
        }
        await t.pumpWidget(
          Actions(
            bindings: bindings,
            child: Focus(autofocus: true, child: Text('pick keys')),
          ),
          size: size,
        );
        await t.press('up down c esc');
        expect(played, hasLength(4));
        expect((played[0].single as MoveCodePick).by, -1);
        expect((played[1].single as MoveCodePick).by, 1);
        expect(played[2].single, isA<CopyCodePick>());
        expect(played[3].single, isA<EndCodePick>());
      },
    );
    testWidgets(
      'every catalog alias reaches app, editor or choice Actions at $size',
      (t) async {
        final reached = <Chord>{};
        final controller = TextAreaController();
        addTearDown(controller.dispose);
        await t.pumpWidget(
          Actions(
            bindings: windowBindings(() => context(), (_) {}),
            child: TextArea(controller: controller, autofocus: true),
          ),
          size: size,
        );
        reached.addAll(
          t.focusManager.activeBindings.map((binding) => binding.chord),
        );
        await t.pumpWidget(
          Picker<int>(
            items: [
              for (var i = 1; i <= 9; i++) PickerItem(value: i, label: '$i'),
            ],
            onSelected: (_) {},
            onCanceled: () {},
          ),
          size: size,
        );
        reached.addAll(
          t.focusManager.activeBindings.map((binding) => binding.chord),
        );
        await t.pumpWidget(
          SettingsPicker(
            state: const SettingsPickerState('model'),
            agent: AgentState(
              configOptions: [
                select('model', 'model', [value('m')], current: 'm'),
                select('effort', 'thought_level', [
                  value('low'),
                  value('high'),
                ], current: 'low'),
              ],
            ),
            agentName: 'fake',
            windowRows: size.height,
            onAction: (_) {},
            onSelected: (_) {},
            onCanceled: () {},
          ),
          size: size,
        );
        reached.addAll(
          t.focusManager.activeBindings.map((binding) => binding.chord),
        );
        await t.pumpWidget(
          Actions(
            bindings: windowBindings(
              () => const KeyContext(
                state: AppState(),
                history: history.History(),
                rows: 24,
                picking: true,
              ),
              (_) {},
            ),
            child: Focus(autofocus: true, child: Text('pick keys')),
          ),
          size: size,
        );
        reached.addAll(
          t.focusManager.activeBindings.map((binding) => binding.chord),
        );
        // The list of agents with the keys: its moves, its way back and
        // its close.
        await t.pumpWidget(
          Actions(
            bindings: windowBindings(
              () => const KeyContext(
                state: AppState(agentsFocus: true),
                history: history.History(),
                rows: 24,
                agents: true,
                listKeys: true,
              ),
              (_) {},
            ),
            child: Focus(autofocus: true, child: Text('list keys')),
          ),
          size: size,
        );
        reached.addAll(
          t.focusManager.activeBindings.map((binding) => binding.chord),
        );
        for (final row in catalog.shortcuts) {
          for (final alias in row.presses) {
            expect(
              reached,
              contains(Chord.parse(alias)),
              reason: '${row.key}: $alias',
            );
          }
        }
      },
    );
  }

  group('tester: pure key decision boundaries', () {
    test('draft clear precedes cursor replacement in competing contexts', () {
      for (final base in [
        waiting(),
        waiting(held: true),
        waiting(help: true),
      ]) {
        final edited = reduceWindow(
          base,
          const DraftEditedAction('👩‍💻e\u0301 ', 2),
        );
        final armed = reduceWindow(edited, const QuitArmedAction());
        final steps = press('ctrl+c', armed);
        expect(steps.map((s) => s.runtimeType), [Dispatch, ShowDraft]);
        final cleared = reduceWindow(armed, (steps.first as Dispatch).action);
        expect(
          [cleared.draft, cleared.cursor, cleared.quitArmed],
          ['', startCursor, false],
        );
        expect(cleared.transcript, same(base.transcript));
        expect(
          [(steps.last as ShowDraft).text, (steps.last as ShowDraft).cursor],
          ['', startCursor],
        );
        expect(dispatched(press('ctrl+c', cleared)), isA<QuitArmedAction>());
      }
    });

    test(
      'registered callbacks read current state rather than registration state',
      () {
        var state = const AppState();
        final played = <List<Step>>[];
        final binding = windowBindings(
          () => context(state),
          played.add,
        ).singleWhere((b) => b.chord == Chord.parse('ctrl+c'));
        state = const AppState(quitArmed: true);
        binding.onInvoke();
        expect(played.single.single, isA<Quit>());
        state = const AppState(draft: ' ', cursor: 1);
        binding.onInvoke();
        expect(played.last.map((s) => s.runtimeType), [Dispatch, ShowDraft]);
        expect(state.draft, ' ');
      },
    );

    test('grapheme continuation precedes startup send gating', () {
      for (final phase in StartPhase.values) {
        const draft = '👩‍💻e\u0301\\tail';
        final state = AppState(
          draft: draft,
          cursor: 3,
          start: StartState(phase: phase),
        );
        final steps = submitSteps(draft, context(state));
        expect(steps, hasLength(1));
        expect((steps.single as ShowDraft).text, '👩‍💻e\u0301\ntail');
        expect((steps.single as ShowDraft).cursor, 3);
      }
      for (final cursor in [-1, 0, 1, 2, 4, 99]) {
        expect(
          continued('👩‍💻e\u0301\\tail', cursor),
          isNull,
          reason: '$cursor',
        );
      }
      expect(endOf('👩‍💻e\u0301界'), 3);
    });

    test('a complete history walk restores the Unicode multiline draft', () {
      const draft = '👩‍💻\ne\u0301界';
      const initial = history.History(prompts: ['oldest', 'newest']);
      final first = olderSteps(context(const AppState(draft: draft), initial));
      expect(first.map((s) => s.runtimeType), [HistoryStep, ShowDraft]);
      final second = olderSteps(
        context(
          const AppState(draft: 'newest'),
          (first.first as HistoryStep).history,
        ),
      );
      final oldest = (second.first as HistoryStep).history;
      expect((second.last as ShowDraft).text, 'oldest');
      expect(
        olderSteps(context(const AppState(draft: 'oldest'), oldest)),
        isEmpty,
      );
      final newer = newerSteps(context(const AppState(), oldest));
      final restored = newerSteps(
        context(const AppState(), (newer.first as HistoryStep).history),
      );
      expect(restored.map((s) => s.runtimeType), [HistoryStep, ShowDraft]);
      expect((restored.last as ShowDraft).text, draft);
      expect((restored.last as ShowDraft).cursor, 4);
      expect((restored.first as HistoryStep).history.index, isNull);
    });

    test(
      'held choices require attention and stale permission ids remain inert',
      () {
        final held = waiting(held: true);
        expect(chooseSteps('fixture', 'allow', context(held)), isEmpty);
        final attended = reduceWindow(
          held,
          dispatched(press('ctrl+x a', held)),
        );
        final steps = chooseSteps('fixture', 'always', context(attended));
        expect(steps, hasLength(1));
        final choice = steps.single as ChoosePermission;
        expect([choice.id, choice.optionId], ['fixture', 'always']);
        expect(chooseSteps('stale', 'always', context(attended)), isEmpty);
        expect(chooseSteps('fixture', 'always', context()), isEmpty);
      },
    );

    test(
      'stale overflow flags and tiny row counts preserve scroll ownership',
      () {
        for (final rows in [0, 1, 24, 40]) {
          const inactive = AppState(
            shortcuts: ShortcutsState(panelOverflows: true),
          );
          final steps = keySteps(
            Chord.parse('pageup'),
            KeyContext(
              state: inactive,
              history: const history.History(),
              rows: rows,
            ),
          );
          expect(
            (steps.single as Dispatch).action,
            isA<TranscriptScrolledAction>(),
          );
          expect(
            keySteps(
              Chord.parse('pageup'),
              KeyContext(
                state: waiting(overflow: true),
                history: const history.History(),
                rows: rows,
              ),
            ).single,
            isA<ScrollRequest>(),
          );
        }
      },
    );
  });
}
