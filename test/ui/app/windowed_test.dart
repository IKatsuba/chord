// The window split as the original's state.ts splits it: each session's
// own state by its key, the window's beside it, and the front's view.
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/scrolls.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/shortcuts/state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

const mainKey = 1;
const child = 2;

/// A window of main, with child opened behind it and both up.
WindowedState twoSessions() {
  var state = WindowedState.of(AppState.starting, mainKey);
  state = reduceWindowed(state, const AgentOpened(child));
  for (final key in [mainKey, child]) {
    state = reduceWindowed(
      state,
      const SessionHeard(mainKey, Connected('s', AgentState.empty)),
    );
    state = reduceWindowed(
      state,
      SessionHeard(key, const Connected('s', AgentState.empty)),
    );
  }
  return state;
}

WindowedState prompted(WindowedState state, int key, String turnId) =>
    reduceWindowed(
      state,
      SessionHeard(key, Transcribed(PromptAction(turnId, 'hi $key', 0))),
    );

void main() {
  testerWindowSplitTests();
  test('an event for a session behind changes only that session', () {
    final before = twoSessions();
    final after = prompted(before, child, 't1');
    expect(
      identical(after.sessions[mainKey], before.sessions[mainKey]),
      isTrue,
    );
    expect(
      identical(
        after.sessions[child]!.transcript,
        before.sessions[child]!.transcript,
      ),
      isFalse,
    );
    expect(after.front, mainKey);
    expect(
      identical(after.frontState.transcript, before.frontState.transcript),
      isTrue,
    );
  });

  test('a session shown again brings back its draft, cursor and queue as '
      'left', () {
    var state = twoSessions();
    state = reduceWindowed(
      state,
      const FrontActed(DraftEditedAction('mainKey draft', 4)),
    );
    state = reduceWindowed(state, const SessionShown(child));
    expect(state.frontState.draft, '');
    state = reduceWindowed(
      state,
      const FrontActed(DraftEditedAction('child draft', 2)),
    );
    state = prompted(state, child, 't1');
    state = reduceWindowed(
      state,
      const SessionHeard(child, Queued('t2', 'next')),
    );
    state = reduceWindowed(state, const SessionShown(mainKey));
    expect(state.frontState.draft, 'mainKey draft');
    expect(state.frontState.cursor, 4);
    expect(state.frontState.queue, isEmpty);
    state = reduceWindowed(state, const SessionShown(child));
    expect(state.frontState.draft, 'child draft');
    expect(state.frontState.cursor, 2);
    expect([for (final q in state.frontState.queue) q.text], ['next']);
  });

  test("the window's own fields survive a switch", () {
    var state = twoSessions();
    for (final action in const <AppAction>[
      ToggleExpandedAction(),
      ThemeChosenAction('dark'),
      VimToggledAction(true),
      QuitArmedAction(),
    ]) {
      state = reduceWindowed(state, FrontActed(action));
    }
    final window = state.window;
    state = reduceWindowed(state, const SessionShown(child));
    state = reduceWindowed(state, const SessionShown(mainKey));
    expect(identical(state.window, window), isTrue);
    expect(state.frontState.expanded, isTrue);
    expect(state.frontState.theme, 'dark');
    expect(state.frontState.vim, isNotNull);
    expect(state.frontState.quitArmed, isTrue);
  });

  test("a session behind never changes the window's own fields", () {
    var state = twoSessions();
    state = reduceWindowed(
      state,
      const FrontActed(ShortcutsChangedAction(HelpToggled())),
    );
    final window = state.window;
    state = reduceWindowed(state, const SessionHeard(child, Cleared()));
    expect(identical(state.window, window), isTrue);
    expect(state.frontState.shortcuts.help, isTrue);
  });

  test('an intent on a session behind lands there, not on the front', () {
    var state = twoSessions();
    state = reduceWindowed(
      state,
      const SessionActed(child, DraftEditedAction('for the child', 0)),
    );
    expect(state.frontState.draft, '');
    expect(state.sessions[child]!.draft, 'for the child');
  });

  test('a closed session goes, and the front moves to the one given', () {
    var state = twoSessions();
    state = reduceWindowed(state, const SessionShown(child));
    state = reduceWindowed(state, const SessionClosed(child, mainKey));
    expect(state.sessions.keys, [mainKey]);
    expect(state.front, mainKey);
    expect(reduceWindowed(state, const SessionShown(child)).front, mainKey);
  });

  test('the front view is the reducers\' AppState, unchanged for one '
      'session', () {
    const app = AppState(draft: 'x', theme: 'light', expanded: true);
    final state = WindowedState.of(app, mainKey);
    final front = state.frontState;
    expect(front.draft, 'x');
    expect(front.theme, 'light');
    expect(front.expanded, isTrue);
  });

  group('each session keeps its own scroll controller', () {
    test('a session shown again finds its controller where it was left', () {
      final scrolls = SessionScrolls();
      addTearDown(scrolls.dispose);
      final mains = scrolls.of(mainKey);
      final childs = scrolls.of(child);
      expect(identical(scrolls.of(mainKey), mains), isTrue);
      expect(identical(childs, mains), isFalse);
      expect(mains.follow, Follow.bottom);
    });

    test('a cleared session gets a new controller, the old one disposed', () {
      final scrolls = SessionScrolls();
      addTearDown(scrolls.dispose);
      final old = scrolls.of(child);
      final fresh = scrolls.cleared(child);
      expect(identical(fresh, old), isFalse);
      expect(old.isDisposed, isTrue);
      scrolls.closed(child);
      expect(fresh.isDisposed, isTrue);
    });
  });
}

void testerWindowSplitTests() {
  group('tester: window split and controller boundaries', () {
    test(
      'one thousand hidden draft updates preserve front and global state',
      () {
        final original = reduceWindowed(
          twoSessions(),
          const FrontActed(ThemeChosenAction('light')),
        );
        var state = original;
        for (var i = 0; i < 1000; i++) {
          state = reduceWindowed(
            state,
            SessionActed(child, DraftEditedAction('界🙂e\u0301 $i', 1)),
          );
        }
        expect(state.sessions[mainKey], same(original.sessions[mainKey]));
        expect(state.window, same(original.window));
        final shown = reduceWindowed(state, const SessionShown(child));
        expect(shown.frontState.draft, '界🙂e\u0301 999');
        expect(shown.frontState.cursor, 1);
        expect(shown.frontState.theme, 'light');
        expect(original.sessions[child]!.draft, '');
      },
    );

    test('late events and intents for a removed key cannot recreate it', () {
      final closed = reduceWindowed(
        twoSessions(),
        const SessionClosed(child, mainKey),
      );
      for (final action in <WindowedAction>[
        const SessionHeard(child, Connected('late', AgentState.empty)),
        const SessionActed(child, DraftEditedAction('late', 1)),
        const SessionShown(child),
      ]) {
        expect(reduceWindowed(closed, action), same(closed));
      }
      expect(closed.sessions.keys, [mainKey]);
    });

    test('split and compose preserve session and window notices together', () {
      const original = AppState(
        draft: '界🙂e\u0301',
        cursor: 1,
        bash: true,
        pendingMode: 'plan',
        held: ['held'],
        attended: 'ask',
        omittedHistory: true,
        requestOverflows: true,
        imageCount: 7,
        since: 23,
        quitArmed: true,
        closing: true,
        notes: 9,
        expanded: true,
        draftHeld: 'draft-held',
        steerRefused: (id: 8, refused: true),
        theme: 'light',
        themePreview: 'dark',
        mcpPanel: true,
        pasteFailed: 'paste',
        pasteFailedUntilStarted: true,
        keysFailed: 'keys',
        editorFailed: 'editor',
      );
      final restored = appStateOf(windowOf(original), sessionOf(original));
      expect(
        [
          restored.draft,
          restored.cursor,
          restored.bash,
          restored.pendingMode,
          restored.held,
          restored.attended,
          restored.omittedHistory,
          restored.requestOverflows,
          restored.imageCount,
          restored.since,
          restored.quitArmed,
          restored.closing,
          restored.notes,
          restored.expanded,
          restored.draftHeld,
          restored.steerRefused,
          restored.theme,
          restored.themePreview,
          restored.mcpPanel,
          restored.pasteFailed,
          restored.pasteFailedUntilStarted,
          restored.keysFailed,
          restored.editorFailed,
        ],
        [
          original.draft,
          original.cursor,
          original.bash,
          original.pendingMode,
          original.held,
          original.attended,
          original.omittedHistory,
          original.requestOverflows,
          original.imageCount,
          original.since,
          original.quitArmed,
          original.closing,
          original.notes,
          original.expanded,
          original.draftHeld,
          original.steerRefused,
          original.theme,
          original.themePreview,
          original.mcpPanel,
          original.pasteFailed,
          original.pasteFailedUntilStarted,
          original.keysFailed,
          original.editorFailed,
        ],
      );
    });

    test(
      'resetting one registry entry preserves peers and window disposal releases all',
      () {
        final scrolls = SessionScrolls();
        final main = scrolls.of(mainKey), other = scrolls.of(child);
        scrolls.closed(999);
        final fresh = scrolls.cleared(child);
        expect(other.isDisposed, isTrue);
        expect(main.isDisposed, isFalse);
        expect(scrolls.of(mainKey), same(main));
        expect(fresh.isFollowing, isTrue);
        scrolls.dispose();
        expect(main.isDisposed, isTrue);
        expect(fresh.isDisposed, isTrue);
        scrolls.dispose();
      },
    );
  });
}
