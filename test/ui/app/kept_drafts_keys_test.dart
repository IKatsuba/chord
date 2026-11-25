// Drafts set aside with ↓ (CHD-493 U10, CTUI-35 I3), as the key steps and
// the reducers decide them: ↓ keeps a draft whole and empties the box, ↑
// brings it back with its images, bash mode and cursor, a shown one edited
// is edited in place, and sending it or ctrl+c takes it off the stack.
import 'package:chord/images.dart';
import 'package:chord/session/conversation.dart' show Cleared;
import 'package:chord/ui/app/keys.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/prompt/history.dart' as history;
import 'package:chord/ui/prompt/state.dart' show KeptDraft;
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

const PastedImage _image = (
  id: 1,
  mediaType: 'image/png',
  data: 'AAAA',
  bytes: 3,
);

KeyContext _context(
  AppState state, [
  history.History h = const history.History(),
]) => KeyContext(state: state, history: h, rows: 24);

/// [state] after the steps' dispatches, the box as their last ShowDraft
/// leaves it, and the history as their last HistoryStep leaves it.
({AppState state, history.History history}) _played(
  AppState state,
  history.History h,
  List<Step> steps,
) {
  for (final step in steps) {
    switch (step) {
      case Dispatch(:final action):
        state = reduceWindow(state, action);
      case ShowDraft(:final text, :final cursor):
        state = reduceWindow(state, DraftEditedAction(text, cursor));
      case HistoryStep(history: final next):
        h = next;
      default:
    }
  }
  return (state: state, history: h);
}

const _connected = AppState(
  start: StartState(phase: StartPhase.connected, sessionId: 's'),
);

void main() {
  _testerKeptMetadata();
  test('↓ on a draft not walking keeps it whole and empties the box; ↑ '
      'brings back its text, images, bash mode and cursor', () {
    final typed = reduceWindow(
      reduceWindow(_connected, const ImagesAddedAction([_image])),
      const DraftEditedAction('one X\ntwo [Image #1]', 5),
    );
    final down = newerSteps(_context(typed));
    expect(down.first, isA<Dispatch>());
    expect((down.first as Dispatch).action, isA<DraftKeptAction>());
    final aside = _played(typed, const history.History(), down);
    expect((aside.state.draft, aside.state.cursor), ('', 0));
    expect(aside.state.images, isEmpty);
    expect(aside.state.kept.single.text, 'one X\ntwo [Image #1]');
    expect(aside.state.kept.single.images, [_image]);

    final up = olderSteps(_context(aside.state, aside.history));
    final back = _played(aside.state, aside.history, up);
    expect((back.state.draft, back.state.cursor), ('one X\ntwo [Image #1]', 5));
    expect(back.state.images, [_image]);
    // Typing goes on where the cursor was: `one X|two` → `one XYtwo`.
    final cursor = back.state.cursor;
    final draft = back.state.draft;
    expect(
      '${draft.substring(0, cursor)}Y${draft.substring(cursor)}',
      'one XY\ntwo [Image #1]',
    );
  });

  test('a bash draft comes back in bash mode', () {
    final typed = reduceWindow(
      reduceWindow(_connected, const BashModeAction(true)),
      const DraftEditedAction('ls -la', 2),
    );
    final aside = _played(
      typed,
      const history.History(),
      newerSteps(_context(typed)),
    );
    expect(aside.state.bash, isFalse);
    expect(aside.state.kept.single.bash, isTrue);
    final back = _played(
      aside.state,
      aside.history,
      olderSteps(_context(aside.state, aside.history)),
    );
    expect(
      (back.state.bash, back.state.draft, back.state.cursor),
      (true, 'ls -la', 2),
    );
  });

  test('a recalled prompt puts the cursor at its end', () {
    const h = history.History(prompts: ['sent before']);
    final up = olderSteps(_context(_connected, h));
    expect((up.last as ShowDraft).cursor, 'sent before'.length);
  });

  test('↓ from a recalled prompt steps to the draft before setting it '
      'aside', () {
    const h = history.History(prompts: ['old']);
    const typed = AppState(draft: 'mine', cursor: 2);
    final up = _played(typed, h, olderSteps(_context(typed, h)));
    expect(up.state.draft, 'old');
    final down = newerSteps(_context(up.state, up.history));
    expect(
      down.whereType<Dispatch>().map((d) => d.action),
      isNot(contains(isA<DraftKeptAction>())),
    );
    final restored = _played(up.state, up.history, down);
    expect((restored.state.draft, restored.history.index), ('mine', null));
    expect(restored.state.kept, isEmpty);
    final aside = _played(
      restored.state,
      restored.history,
      newerSteps(_context(restored.state, restored.history)),
    );
    expect((aside.state.draft, aside.state.kept.single.text), ('', 'mine'));
  });

  test('↓ from an empty draft with nothing walked does nothing', () {
    expect(newerSteps(_context(const AppState())), isEmpty);
  });

  test('↑ shows the newest kept draft, then older, then prompts', () {
    const state = AppState(
      kept: [
        KeptDraft(text: 'first', cursor: 0),
        KeptDraft(text: 'second', cursor: 1),
      ],
    );
    const h = history.History(prompts: ['sent']);
    var walked = _played(state, h, olderSteps(_context(state, h)));
    expect(walked.state.draft, 'second');
    walked = _played(
      walked.state,
      walked.history,
      olderSteps(_context(walked.state, walked.history)),
    );
    expect(walked.state.draft, 'first');
    walked = _played(
      walked.state,
      walked.history,
      olderSteps(_context(walked.state, walked.history)),
    );
    expect(walked.state.draft, 'sent');
  });

  test('a shown kept draft edited is edited in place when the walk moves '
      'off it', () {
    const state = AppState(kept: [KeptDraft(text: 'draft', cursor: 5)]);
    final up = _played(
      state,
      const history.History(),
      olderSteps(_context(state)),
    );
    final edited = reduceWindow(up.state, const DraftEditedAction('draft!', 6));
    final down = _played(
      edited,
      up.history,
      newerSteps(_context(edited, up.history)),
    );
    expect(down.state.draft, '');
    expect(down.state.kept.single.text, 'draft!');
    expect(down.state.kept.single.cursor, 6);
    final again = _played(
      down.state,
      down.history,
      olderSteps(_context(down.state, down.history)),
    );
    expect((again.state.draft, again.state.cursor), ('draft!', 6));
  });

  test('sending a shown kept draft takes it off the stack and ends the '
      'walk', () {
    final state = _connected._withKept(['other', 'shown']);
    final up = _played(
      state,
      const history.History(),
      olderSteps(_context(state)),
    );
    final steps = submitSteps('shown', _context(up.state, up.history));
    expect(steps.last, isA<Send>());
    final sent = _played(up.state, up.history, steps);
    expect([for (final k in sent.state.kept) k.text], ['other']);
    expect(sent.history.index, isNull);
  });

  test('a local command sent from a shown kept draft takes it too', () {
    final state = _connected._withKept(['/clear']);
    final up = _played(
      state,
      const history.History(),
      olderSteps(_context(state)),
    );
    final sent = _played(
      up.state,
      up.history,
      submitSteps('/clear', _context(up.state, up.history)),
    );
    expect(sent.state.kept, isEmpty);
  });

  test('a bash command run from a shown kept draft takes it', () {
    final state = AppState(
      start: _connected.start,
      kept: const [KeptDraft(text: 'ls', cursor: 2, bash: true)],
    );
    final up = _played(
      state,
      const history.History(),
      olderSteps(_context(state)),
    );
    expect(up.state.bash, isTrue);
    final steps = submitSteps('ls', _context(up.state, up.history));
    expect(steps.last, isA<RunShellCommand>());
    expect(_played(up.state, up.history, steps).state.kept, isEmpty);
  });

  test('a prompt the agent cannot take yet leaves the kept draft', () {
    const state = AppState(
      start: StartState(phase: StartPhase.gone),
      kept: [KeptDraft(text: 'shown', cursor: 0)],
    );
    final up = _played(
      state,
      const history.History(),
      olderSteps(_context(state)),
    );
    final sent = _played(
      up.state,
      up.history,
      submitSteps('shown', _context(up.state, up.history)),
    );
    expect(sent.state.kept.single.text, 'shown');
  });

  test('ctrl+c on a shown kept draft takes it off the stack', () {
    final state = _connected._withKept(['shown']);
    final up = _played(
      state,
      const history.History(),
      olderSteps(_context(state)),
    );
    final cleared = _played(
      up.state,
      up.history,
      keySteps(Chord.parse('ctrl+c'), _context(up.state, up.history)),
    );
    expect(cleared.state.draft, '');
    expect(cleared.state.kept, isEmpty);
    expect(cleared.history.index, isNull);
  });

  test(
    'sending another prompt and ctrl+c on another draft leave the stack',
    () {
      final state = reduceWindow(
        _connected._withKept(['kept']),
        const DraftEditedAction('other', 5),
      );
      final h = const history.History();
      expect(
        _played(state, h, submitSteps('other', _context(state, h))).state.kept,
        hasLength(1),
      );
      expect(
        _played(
          state,
          h,
          keySteps(Chord.parse('ctrl+c'), _context(state, h)),
        ).state.kept,
        hasLength(1),
      );
    },
  );

  test('/clear keeps the stack, as it keeps the draft', () {
    final state = _connected._withKept(['kept']);
    final cleared = reduceApp(state, const Cleared());
    expect(cleared.kept.single.text, 'kept');
  });

  test('kept drafts are each agent\'s own in the windowed state', () {
    final windowed = reduceWindowed(
      reduceWindowed(
        reduceWindowed(
          WindowedState.of(const AppState(draft: 'main draft'), 0),
          const AgentOpened(1),
        ),
        const FrontActed(DraftKeptAction()),
      ),
      const SessionShown(1),
    );
    expect(windowed.frontState.kept, isEmpty);
    expect(windowed.sessions[0]!.kept.single.text, 'main draft');
    // The child's ↑ walks no draft of main's.
    expect(olderSteps(_context(windowed.frontState)), isEmpty);
  });
}

extension on AppState {
  AppState _withKept(List<String> texts) {
    var state = this;
    for (final text in texts) {
      state = reduceWindow(
        reduceWindow(state, DraftEditedAction(text, text.length)),
        const DraftKeptAction(),
      );
    }
    return state;
  }
}

void _testerKeptMetadata() {
  group('CTUI-35 tester: kept metadata and duplicate text', () {
    const secondImage = (id: 2, mediaType: 'image/png', data: 'BBBB', bytes: 3);
    test(
      'edits replace only the shown snapshot, including bash, cursor and referenced images',
      () {
        const initial = AppState(
          kept: [
            KeptDraft(text: 'older [Image #1]', cursor: 2, images: [_image]),
            KeptDraft(text: 'newer', cursor: 3),
          ],
        );
        var walked = _played(
          initial,
          const history.History(),
          olderSteps(_context(initial)),
        );
        var edited = reduceWindow(
          walked.state,
          const DraftEditedAction('界e\u0301 [Image #2]', 3),
        );
        edited = reduceWindow(edited, const ImagesAddedAction([secondImage]));
        edited = reduceWindow(edited, const BashModeAction(true));
        walked = _played(
          edited,
          walked.history,
          olderSteps(_context(edited, walked.history)),
        );
        expect(walked.state.draft, 'older [Image #1]');
        final saved = walked.state.kept.last;
        expect(
          (saved.text, saved.cursor, saved.bash),
          ('界e\u0301 [Image #2]', 3, true),
        );
        expect(saved.images, [secondImage]);
        expect(walked.state.kept.first.images, [_image]);
        walked = _played(
          walked.state,
          walked.history,
          newerSteps(_context(walked.state, walked.history)),
        );
        expect(
          (walked.state.draft, walked.state.cursor, walked.state.bash),
          (saved.text, 3, true),
        );
        expect(walked.state.images, contains(secondImage));
        expect(walked.state.kept, hasLength(2));
      },
    );

    test(
      'identical text is still two drafts and ctrl+c removes only the shown one',
      () {
        const state = AppState(
          kept: [
            KeptDraft(text: 'same', cursor: 1),
            KeptDraft(text: 'same', cursor: 3, bash: true),
          ],
        );
        final up = _played(
          state,
          const history.History(),
          olderSteps(_context(state)),
        );
        expect((up.state.cursor, up.state.bash), (3, true));
        final dropped = _played(
          up.state,
          up.history,
          keySteps(Chord.parse('ctrl+c'), _context(up.state, up.history)),
        );
        expect(dropped.state.kept, hasLength(1));
        final older = _played(
          dropped.state,
          dropped.history,
          olderSteps(_context(dropped.state, dropped.history)),
        );
        expect(
          (older.state.draft, older.state.cursor, older.state.bash),
          ('same', 1, false),
        );
      },
    );

    test(
      'setting aside snapshots only referenced images before its source list changes',
      () {
        final images = <PastedImage>[_image, secondImage];
        final state = AppState(
          draft: 'keep [Image #1]',
          cursor: 4,
          images: images,
        );
        final aside = reduceWindow(state, const DraftKeptAction());
        images.clear();
        expect(aside.kept.single.images, [_image]);
        expect(() => aside.kept.single.images.clear(), throwsUnsupportedError);
        expect(aside.images, isEmpty);
        expect(reduceApp(aside, const Cleared()).kept.single.images, [_image]);
      },
    );
  });
}
