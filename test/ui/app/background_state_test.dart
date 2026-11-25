// The window's part of the background: each session's monitors as its
// conversation reports them, the summary line's focus and the view, as the
// original's ui/app/state.ts keeps them.
import 'package:chord/session/conversation.dart';
import 'package:chord/session/monitors.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/background/state.dart';
import 'package:test/test.dart';

const _m1 = RunningMonitor(
  MonitorInfo(
    id: 'm1',
    description: 'log',
    command: 'tail -f log',
    startedAt: 0,
    timeoutMs: 1000,
  ),
);

void main() {
  test("a session's monitors are its own, carried with it when another is "
      'picked, and gone with its clear', () {
    final state = reduceApp(
      AppState.starting,
      const MonitorsChanged([_m1], []),
    );
    expect(state.monitors, [_m1]);
    final session = sessionOf(state);
    expect(session.monitors, [_m1]);
    expect(appStateOf(windowOf(AppState.starting), session).monitors, [_m1]);
    expect(reduceApp(state, const Cleared()).monitors, isEmpty);
  });

  test("the summary line's ❯ and the view are the window's: kept across "
      "sessions, the ❯ off it once the list loses the keys, both gone as it "
      'closes', () {
    var state = reduceWindow(
      AppState.starting,
      const AgentsFocusedAction(true),
    );
    state = reduceWindow(state, const SummaryFocusedAction(true));
    expect(state.summaryFocus, isTrue);
    expect(
      identical(reduceWindow(state, const SummaryFocusedAction(true)), state),
      isTrue,
    );
    state = reduceWindow(
      state,
      const BackgroundChangedAction(BackgroundOpened(['p1'])),
    );
    expect(state.backgroundView?.over, ['p1']);
    final window = windowOf(state);
    expect(
      [window.summaryFocus, window.backgroundView?.over],
      [
        true,
        ['p1'],
      ],
    );
    final other = appStateOf(window, sessionOf(AppState.starting));
    expect(other.summaryFocus, isTrue);
    expect(
      reduceWindow(state, const AgentsFocusedAction(false)).summaryFocus,
      isFalse,
    );
    expect(
      reduceWindow(
        state,
        const BackgroundChangedAction(BackgroundClosed()),
      ).backgroundView,
      isNull,
    );
    final closed = reduceApp(state, const Closing());
    expect([closed.summaryFocus, closed.backgroundView], [false, null]);
  });
}
