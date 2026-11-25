// The background frame's arithmetic and its hint, as the original's
// BackgroundView.tsx lays them out, and the view's keys.
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/prompt/history.dart' as history;
import 'package:chord/ui/app/keys.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/background/background.dart';
import 'package:chord/ui/background/state.dart';
import 'package:chord/ui/background/view.dart';
import 'package:chord_tui/chord_tui.dart' show Chord, ScrollStep;
import 'package:test/test.dart';

const _now = 1000000;

BackgroundItem _monitor(String id, ItemStatus status) => BackgroundItem(
  kind: BackgroundKind.monitor,
  id: id,
  key: 1,
  name: 'build $id',
  startedAt: _now - 1000,
  status: status,
  events: 0,
  command: 'make',
);

void main() {
  test('the rows take half the window less the frame, giving way to a hint '
      'that wraps', () {
    expect(backgroundRowLimit(40), 14);
    expect(backgroundRowLimit(24), 6);
    expect(backgroundRowLimit(40, 3), 12);
    expect(backgroundRowLimit(4, 9), 1);
  });

  test("the hint names a row's keys, a detail's, and none to stop once its "
      'item ended; a stop error stands in their place', () {
    final items = [
      _monitor('m1', const ItemRunning()),
      _monitor('m2', const ItemEnded(BackgroundGroup.stopped, _now)),
    ];
    expect(hintMode(items, null), HintMode.details);
    expect(hintMode(items, (key: 1, id: 'm1')), HintMode.detail);
    expect(hintMode(items, (key: 1, id: 'm2')), HintMode.ended);
    String said(HintMode mode, [String? hint]) => backgroundHint(
      hint,
      mode,
      stop: 'x',
      close: 'Esc to close',
      back: 'Esc ← to go back',
    );
    expect(
      said(HintMode.details),
      'Enter for details · x to stop · Esc to close',
    );
    expect(
      said(HintMode.detail),
      'Enter to go to its call · ↑ ↓ for the others · x to stop · Esc ← to go back',
    );
    expect(
      said(HintMode.ended),
      'Enter to go to its call · ↑ ↓ for the others · Esc ← to go back',
    );
    expect(
      said(HintMode.details, 'could not stop: gone'),
      'could not stop: gone',
    );
    // With no key bound to stop or close, those parts are left out.
    expect(backgroundHint(null, HintMode.details), 'Enter for details');
  });

  test('the frame says how many are in the session, or which one its detail '
      'is and whether it ended; its height is every line it draws', () {
    final items = [
      _monitor('m1', const ItemRunning()),
      _monitor('m2', const ItemEnded(BackgroundGroup.stopped, _now)),
    ];
    BackgroundFrame frame(ItemRef? detail) => backgroundFrame(
      items,
      focus: null,
      detail: detail,
      at: null,
      said: 'Enter for details',
      hinted: false,
      columns: 80,
      rows: 24,
      now: _now,
    );
    final rows = frame(null);
    expect(rows.note, ' · 2 in this session');
    expect(rows.body, hasLength(2));
    expect(rows.height, 6 + 2 + 1);
    expect(frame((key: 1, id: 'm2')).note, ' · m2, 2 of 2 · ended');
    expect(frame((key: 1, id: 'm1')).note, ' · m1, 1 of 2');
  });

  test("the view's keys: ↑ ↓ j k move, enter opens, x stops, the page keys "
      'scroll, ← and esc go back from a detail, esc closes the rows', () {
    KeyContext context({bool inDetail = false}) => KeyContext(
      state: AppState.starting,
      history: const history.History(),
      rows: 24,
      viewKeys: true,
      inDetail: inDetail,
    );
    List<Step> steps(String key, {bool inDetail = false}) =>
        keySteps(Chord.parse(key), context(inDetail: inDetail));
    expect(
      steps('up').single,
      isA<MoveBackground>().having((s) => s.by, 'by', -1),
    );
    expect(
      steps('j').single,
      isA<MoveBackground>().having((s) => s.by, 'by', 1),
    );
    expect(steps('enter').single, isA<GoToCall>());
    expect(steps('x').single, isA<StopBackground>());
    expect(
      steps('pagedown').single,
      isA<ScrollBackground>().having(
        (s) => s.step,
        'step',
        ScrollStep.pageDown,
      ),
    );
    BackgroundAction? dispatched(List<Step> steps) => switch (steps.single) {
      Dispatch(action: BackgroundChangedAction(:final action)) => action,
      _ => null,
    };
    expect(dispatched(steps('escape')), isA<BackgroundClosed>());
    expect(
      dispatched(steps('escape', inDetail: true)),
      isA<BackgroundDetailClosed>(),
    );
    expect(
      dispatched(steps('left', inDetail: true)),
      isA<BackgroundDetailClosed>(),
    );
    expect(steps('left'), isEmpty);
    expect(steps('a'), isEmpty);
    // Enter on the summary line opens the view over the requests waiting.
    final summary = KeyContext(
      state: const AppState(
        transcript: Transcript(
          turn: AwaitingPermission('t', 0, [PermissionWait('p1')]),
        ),
      ),
      history: const history.History(),
      rows: 24,
      listKeys: true,
      onSummary: true,
    );
    expect(
      switch (keySteps(Chord.parse('enter'), summary).single) {
        Dispatch(
          action: BackgroundChangedAction(
            action: BackgroundOpened(:final over),
          ),
        ) =>
          over,
        _ => null,
      },
      ['p1'],
    );
    expect(keySteps(Chord.parse('x'), summary), isEmpty);
  });

  test("a task's detail pins its name and state, then its log in the room "
      'left, as tall as its lines once laid out', () {
    const task = BackgroundItem(
      kind: BackgroundKind.task,
      id: 't1',
      key: 1,
      name: 'Watch the build',
      startedAt: _now - 1000,
      status: ItemRunning(),
      runtime: 'fake',
    );
    const work = Subagent('t1', prompt: 'taskwait', description: 'Watch');
    BackgroundFrame frame({int? lines, int rows = 40}) => backgroundFrame(
      const [task],
      focus: null,
      detail: (key: 1, id: 't1'),
      at: null,
      said: 'Enter to go to its call',
      hinted: false,
      columns: 120,
      rows: rows,
      now: _now,
      work: work,
      logLines: lines,
    );
    final open = frame();
    expect(
      [for (final l in open.body) l.cells.map((c) => c.text).join()],
      ['Watch the build', 'working 1s · 0 tool uses · task · fake · main'],
    );
    expect(open.log?.task, 'taskwait');
    expect(open.log?.rows, backgroundRowLimit(40) - 2);
    expect(frame(lines: 3).log?.rows, 3);
    expect(frame(lines: 3).height, 6 + 2 + 3 + 1);
    expect(frame(lines: 99).log?.rows, backgroundRowLimit(40) - 2);
    // A room too short for the state line's wrapping: one line each, then
    // the log gives way.
    expect(frame(rows: 14).log?.rows, 0);
    // With no row for the log, what is out of view is said at the state
    // line's end, which gives it its cells.
    final none = frame(rows: 16, lines: 5);
    expect(none.log?.rows, 0);
    final state = none.body.last.cells.map((c) => c.text).join();
    expect(state, endsWith('↑ 4 lines above'));
    expect(state, startsWith('working 1s · '));
    expect(state.length, 116);
    // No work found: its row alone, as a monitor's detail lines.
    final bare = backgroundFrame(
      const [task],
      focus: null,
      detail: (key: 1, id: 't1'),
      at: null,
      said: '',
      hinted: false,
      columns: 120,
      rows: 40,
      now: _now,
    );
    expect(bare.log, isNull);
  });
}
