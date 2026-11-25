// A task's log in the background's detail, as the original's
// BackgroundView.tsx keeps it: its place outlives the frame being taken
// off the screen, and with no row it is still laid out, out of sight, its
// lines counted at the state line's end and paged by the page keys.
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/background/background.dart';
import 'package:chord/ui/background/background_view.dart';
import 'package:chord/ui/background/view.dart';
import 'package:chord/ui/theme/theme.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const _now = 1000000;

const _task = BackgroundItem(
  kind: BackgroundKind.task,
  id: 't1',
  key: 1,
  name: 'Watch the build',
  startedAt: _now - 1000,
  status: ItemRunning(),
  runtime: 'fake',
);

/// A task whose log is [count] replies long.
Subagent _work(int count) => Subagent(
  't1',
  prompt: 'taskwait',
  entries: [
    for (var i = 1; i <= count; i++)
      AssistantEntry('t', TextRun.empty.plus('reply $i')),
  ],
);

void main() {
  final palette = paletteOf('dark', true);

  Future<void> draw(
    WidgetTester t, {
    required int rows,
    required ScrollController scroll,
    required LogScroller scroller,
    int? lines,
    void Function(int)? onLines,
    int count = 30,
  }) => t.pumpWidget(
    Column(
      children: [
        BackgroundBox(
          frame: backgroundFrame(
            const [_task],
            focus: null,
            detail: (key: 1, id: 't1'),
            at: null,
            said: 'Enter to go to its call',
            hinted: false,
            columns: 80,
            rows: rows,
            now: _now,
            work: _work(count),
            logLines: lines,
            logTop: scroll.isFollowing || scroll.contentRows == 0
                ? null
                : scroll.offset,
          ),
          palette: palette,
          logScroll: scroll,
          log: scroller,
          onLogLines: onLines,
        ),
      ],
    ),
    size: Size(80, rows),
  );

  testWidgets('paged up, its place is kept while the frame is off the screen '
      'and back', (t) async {
    final scroll = ScrollController(follow: Follow.bottom);
    addTearDown(scroll.dispose);
    final scroller = LogScroller();
    await draw(t, rows: 40, scroll: scroll, scroller: scroller);
    await t.pump();
    expect(scroll.isFollowing, isTrue);
    expect(scroller.scroll(ScrollStep.pageUp), isTrue);
    await t.pump();
    final read = scroll.offset;
    expect(scroll.isFollowing, isFalse);
    // A request takes the frame's place, then is answered.
    await t.pumpWidget(const SizedBox(), size: const Size(80, 40));
    await draw(t, rows: 40, scroll: scroll, scroller: scroller);
    await t.pump();
    expect([scroll.offset, scroll.isFollowing], [read, false]);
    expect(t.screen, shows('── ↓ '));
  });

  testWidgets('with no row its lines are still counted at the state line, and '
      'the page keys move it; given rows again it is where it was', (t) async {
    final scroll = ScrollController(follow: Follow.bottom);
    addTearDown(scroll.dispose);
    final scroller = LogScroller();
    int? lines;
    await draw(
      t,
      rows: 16,
      scroll: scroll,
      scroller: scroller,
      onLines: (told) => lines = told,
    );
    await t.pump();
    expect(lines, greaterThan(1));
    await draw(t, rows: 16, scroll: scroll, scroller: scroller, lines: lines);
    expect(t.screen, shows('lines above'));
    expect(t.screen, isNot(shows('reply 30')));
    expect(scroller.scroll(ScrollStep.pageUp), isTrue);
    await t.pump();
    final read = scroll.offset;
    expect(scroll.isFollowing, isFalse);
    await draw(t, rows: 16, scroll: scroll, scroller: scroller, lines: lines);
    expect(t.screen, shows('below'));
    // Rows again: read from where it was, as far as the larger room lets
    // it stand, and not following.
    await draw(t, rows: 40, scroll: scroll, scroller: scroller, lines: lines);
    await t.pump();
    expect(scroll.isFollowing, isFalse);
    expect(
      scroll.offset,
      read < scroll.contentRows - scroll.viewRows
          ? read
          : scroll.contentRows - scroll.viewRows,
    );
  });

  group('CTUI-36 tester: task log follow ownership', () {
    testWidgets(
      'growth while held or hidden keeps place; end resumes following',
      (t) async {
        final scroll = ScrollController(follow: Follow.bottom);
        addTearDown(scroll.dispose);
        final scroller = LogScroller();
        await draw(t, rows: 40, scroll: scroll, scroller: scroller);
        await t.pump();
        scroller.scroll(ScrollStep.pageUp);
        await t.pump();
        final held = scroll.offset;
        await draw(t, rows: 40, scroll: scroll, scroller: scroller, count: 60);
        await t.pump();
        expect(scroll.offset, held);
        expect(scroll.isFollowing, isFalse);
        await t.pumpWidget(const SizedBox(), size: const Size(80, 40));
        expect(scroller.scroll(ScrollStep.bottom), isFalse);
        await draw(t, rows: 40, scroll: scroll, scroller: scroller, count: 90);
        await t.pump();
        expect(scroll.offset, held);
        expect(scroll.isFollowing, isFalse);
        expect(scroller.scroll(ScrollStep.bottom), isTrue);
        await t.pump();
        expect(scroll.isFollowing, isTrue);
        await draw(t, rows: 40, scroll: scroll, scroller: scroller, count: 120);
        await t.pump();
        expect(t.screen, shows('reply 120'));
        expect(scroll.isFollowing, isTrue);
      },
    );

    testWidgets('empty log gains rows then survives repeated hidden mounts', (
      t,
    ) async {
      final scroll = ScrollController(follow: Follow.bottom);
      addTearDown(scroll.dispose);
      final scroller = LogScroller();
      await draw(t, rows: 16, scroll: scroll, scroller: scroller, count: 0);
      await t.pump();
      for (final count in [30, 60, 90]) {
        await t.pumpWidget(const SizedBox(), size: const Size(80, 16));
        await draw(
          t,
          rows: 16,
          scroll: scroll,
          scroller: scroller,
          count: count,
        );
        await t.pump();
        expect(scroll.isFollowing, isTrue);
        expect(scroll.contentRows, greaterThan(count));
      }
      await draw(t, rows: 40, scroll: scroll, scroller: scroller, count: 90);
      await t.pump();
      expect(t.screen, shows('reply 90'));
    });
  });
}
