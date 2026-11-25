import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

const bottom = Follow.bottom;
const none = Follow.none;

ScrollState measured(
  ScrollState s,
  int content,
  int view, {
  int? top,
  Follow follow = bottom,
}) => reduceMeasured(s, content: content, view: view, top: top, follow: follow);

ScrollState after(
  ScrollState s,
  List<ScrollStep> steps, {
  Follow follow = bottom,
}) => steps.fold(s, (state, step) => reduceScrolled(state, step, follow));

ScrollState withNews(ScrollState s) => ScrollState(
  content: s.content,
  view: s.view,
  top: s.top,
  following: s.following,
  news: true,
);

/// The original's 120x40 mock: 90 rows of transcript in a 33-row area.
final tall = measured(ScrollState.initial(bottom), 90, 33);

void main() {
  group("the original's tests (scroll_test.ts)", () {
    test('a page is the view less two rows', () {
      expect(tall.pageRows, 31);
      expect(measured(ScrollState.initial(bottom), 90, 2).pageRows, 1);
    });

    test('the view follows the bottom until a key moves it up', () {
      expect(tall.following, isTrue);
      expect(tall.rowsBelow, 0);

      final back = after(tall, [ScrollStep.pageUp]);
      expect(back.following, isFalse);
      expect(back.top, 26);
      // Plain geometry; the original's rule count, 32, adds the row it covers.
      expect(back.rowsBelow, 31);
      expect(after(tall, [ScrollStep.lineUp]).top, 56);
      expect(after(tall, [ScrollStep.top]).top, 0);
    });

    test('new rows below do not move the view, and count as below', () {
      final grown = measured(after(tall, [ScrollStep.pageUp]), 130, 33);
      expect(grown.top, 26);
      expect(grown.rowsBelow, 71);
      expect(measured(tall, 130, 33).following, isTrue);
    });

    test('the way back down follows again once it reaches the bottom', () {
      final back = after(tall, [ScrollStep.pageUp, ScrollStep.pageUp]);
      expect(after(back, [ScrollStep.pageDown]).following, isFalse);
      expect(
        after(back, [ScrollStep.pageDown, ScrollStep.pageDown]).following,
        isTrue,
      );
      expect(
        after(tall, [ScrollStep.lineUp, ScrollStep.lineDown]).following,
        isTrue,
      );
      expect(
        after(tall, [ScrollStep.top, ScrollStep.bottom]).following,
        isTrue,
      );
      expect(after(tall, [ScrollStep.pageDown]), same(tall));
    });

    test('up at the top, or with nothing to scroll, does nothing', () {
      final top = after(tall, [ScrollStep.top]);
      expect(after(top, [ScrollStep.lineUp]), same(top));
      expect(after(top, [ScrollStep.pageUp]), same(top));

      final short = measured(ScrollState.initial(bottom), 10, 33);
      for (final step in [
        ScrollStep.pageUp,
        ScrollStep.lineUp,
        ScrollStep.top,
      ]) {
        expect(after(short, [step]), same(short));
      }
    });

    test('a view that comes to fit everything follows again', () {
      final fits = measured(withNews(after(tall, [ScrollStep.pageUp])), 30, 33);
      expect(fits.following, isTrue);
      expect(fits.news, isFalse);
    });

    test('a relayout keeps the row it is given, within the transcript', () {
      final back = after(tall, [ScrollStep.pageUp]);
      expect(measured(back, 100, 33, top: 40).top, 40);
      expect(measured(back, 50, 33, top: 40).top, 17);
      expect(measured(back, 50, 33).top, 17);
      expect(measured(back, 90, 33), same(back));
    });

    test('the bottom clears the news', () {
      final back = withNews(after(tall, [ScrollStep.pageUp]));
      expect(after(back, [ScrollStep.bottom]).news, isFalse);
    });
  });

  group('Follow.bottom, case by case', () {
    final back = after(tall, [ScrollStep.pageUp]);

    test('M1: content, view and top unchanged give the identical state', () {
      expect(measured(back, 90, 33, top: 26), same(back));
      expect(measured(tall, 90, 33), same(tall));
    });

    test('M2: content that now fits follows, news cleared', () {
      final next = measured(withNews(back), 33, 33);
      expect(next.following, isTrue);
      expect(next.news, isFalse);
    });

    test('M3: while following only content and view change', () {
      final next = measured(tall, 120, 20, top: 7);
      expect(next.following, isTrue);
      expect((next.content, next.view), (120, 20));
      expect(next.offset, 100);
    });

    test('M4: scrolled back, top is clamped to the bottom', () {
      expect(measured(back, 40, 33, top: 30).top, 7);
      expect(measured(back, 200, 33, top: -3).top, 0);
      expect(measured(back, 200, 33).following, isFalse);
    });

    test('S1: bottom follows and clears news', () {
      final next = after(withNews(back), [ScrollStep.bottom]);
      expect(next.following, isTrue);
      expect(next.news, isFalse);
      expect(after(tall, [ScrollStep.bottom]), same(tall));
    });

    test('S2: with content that fits nothing moves', () {
      final short = measured(ScrollState.initial(bottom), 10, 33);
      for (final step in ScrollStep.values) {
        expect(after(short, [step]), same(short));
      }
    });

    test('S3: down while following is unchanged', () {
      expect(after(tall, [ScrollStep.lineDown]), same(tall));
      expect(after(tall, [ScrollStep.pageDown]), same(tall));
    });

    test('S4: down reaching the end follows, news cleared', () {
      final next = after(withNews(back), [ScrollStep.pageDown]);
      expect(next.following, isTrue);
      expect(next.news, isFalse);
    });

    test('S5: down short of the end moves top', () {
      final up = after(tall, [ScrollStep.top]);
      final next = after(up, [ScrollStep.lineDown]);
      expect(next.top, 1);
      expect(next.following, isFalse);
    });

    test('S6: up at the top is unchanged', () {
      final top = withNews(after(tall, [ScrollStep.top]));
      expect(after(top, [ScrollStep.lineUp]), same(top));
    });

    test('S7: up stops following and keeps news', () {
      final next = after(withNews(back), [ScrollStep.lineUp]);
      expect(next.top, 25);
      expect(next.following, isFalse);
      expect(next.news, isTrue);
    });

    test('jumpTo is S5/S7, and S4 once it reaches the end', () {
      expect(reduceJump(tall, 10, bottom).top, 10);
      expect(reduceJump(tall, 10, bottom).following, isFalse);
      expect(reduceJump(tall, 57, bottom), same(tall));
      expect(reduceJump(tall, 500, bottom), same(tall));
      expect(reduceJump(back, 40, bottom).top, 40);
      expect(reduceJump(back, -5, bottom).top, 0);
      expect(reduceJump(withNews(back), 57, bottom).following, isTrue);
      expect(reduceJump(withNews(back), 57, bottom).news, isFalse);
    });

    test('news is set only off the end', () {
      expect(reduceNews(tall, bottom), same(tall));
      expect(reduceNews(back, bottom).news, isTrue);
    });
  });

  group('Follow.none', () {
    final start = measured(ScrollState.initial(none), 90, 33, follow: none);

    test('starts at its initial offset, never following', () {
      expect(start.following, isFalse);
      expect(start.top, 0);
      final at = measured(
        ScrollState.initial(none, top: 40),
        90,
        33,
        follow: none,
      );
      expect(at.top, 40);
      expect(measured(at, 50, 33, follow: none).top, 17);
    });

    test('M2: content that fits puts top at 0', () {
      final down = reduceJump(start, 30, none);
      final fit = measured(down, 20, 33, follow: none);
      expect(fit.top, 0);
      expect(fit.following, isFalse);
    });

    test('S1 and S4 put top on the bottom row, never following', () {
      final end = after(start, [ScrollStep.bottom], follow: none);
      expect(end.top, 57);
      expect(end.following, isFalse);
      final near = reduceJump(start, 50, none);
      final paged = after(near, [ScrollStep.pageDown], follow: none);
      expect(paged.top, 57);
      expect(paged.following, isFalse);
      expect(after(end, [ScrollStep.bottom], follow: none), same(end));
      expect(after(end, [ScrollStep.lineDown], follow: none), same(end));
    });

    test('steps move top within the content', () {
      final down = after(start, [ScrollStep.pageDown], follow: none);
      expect(down.top, 31);
      expect(after(down, [ScrollStep.lineUp], follow: none).top, 30);
      expect(after(down, [ScrollStep.top], follow: none).top, 0);
      expect(after(start, [ScrollStep.lineUp], follow: none), same(start));
    });

    test('a fitting list that grows past its room does not move', () {
      var s = measured(ScrollState.initial(none), 2, 10, follow: none);
      s = measured(s, 50, 10, follow: none);
      expect(s.top, 0);
      expect(s.following, isFalse);
      expect(s.rowsBelow, 40);
    });

    test('growth never moves the view, and there is never news', () {
      final down = reduceJump(start, 57, none);
      expect(measured(down, 200, 33, follow: none).top, 57);
      expect(reduceNews(down, none), same(down));
    });
  });
  group('tester: reducer boundaries and repeated updates', () {
    for (final follow in Follow.values) {
      for (final view in [0, 1]) {
        test('$follow pages one row with a $view-row view', () {
          var state = measured(
            ScrollState.initial(follow),
            4,
            view,
            follow: follow,
          );
          state = after(state, [ScrollStep.bottom], follow: follow);
          expect(state.offset, 4 - view);
          expect(state.pageRows, 1);
          state = after(state, [ScrollStep.pageUp], follow: follow);
          expect(state.offset, 3 - view);
          expect(state.following, isFalse);
          state = after(state, [ScrollStep.pageDown], follow: follow);
          expect(state.offset, 4 - view);
          expect(state.following, follow == bottom);
        });
      }

      test('$follow clamps initial offsets on first measurement', () {
        final negative = ScrollState.initial(follow, top: -10);
        expect(negative.top, 0);
        final state = measured(
          ScrollState.initial(follow, top: 1000),
          20,
          5,
          follow: follow,
        );
        expect(state.offset, 15);
        expect(state.following, follow == bottom);
      });

      test(
        '$follow preserves valid geometry through resize and empty content',
        () {
          var state = measured(
            ScrollState.initial(follow),
            90,
            40,
            follow: follow,
          );
          state = reduceJump(state, 17, follow);
          for (final (content, view) in [
            (90, 24),
            (90, 0),
            (90, 1),
            (90, 120),
            (90, 40),
            (0, 0),
            (0, 24),
          ]) {
            state = measured(state, content, view, follow: follow);
            expect(state.offset, inInclusiveRange(0, state.bottomTop));
            expect(
              state.offset + state.view + state.rowsBelow,
              content > view ? content : view,
            );
            expect(state.news, isFalse);
            if (follow == none) expect(state.following, isFalse);
          }
        },
      );
    }

    test(
      'one thousand growth measurements preserve a reader and explicit news',
      () {
        var state = reduceJump(tall, 10, bottom);
        state = reduceNews(state, bottom);
        expect(reduceNews(state, bottom), same(state));
        for (var content = 91; content <= 1090; content++) {
          state = measured(state, content, 33);
          expect(state.offset, 10);
          expect(state.news, isTrue);
          expect(state.following, isFalse);
          expect(state.rowsBelow, content - 43);
        }
        state = reduceJump(state, state.bottomTop, bottom);
        expect(state.following, isTrue);
        expect(state.news, isFalse);
        expect(measured(state, 1091, 33).offset, 1058);
      },
    );

    test('relayout onto the bottom stays detached until a downward step', () {
      var state = reduceNews(reduceJump(tall, 26, bottom), bottom);
      state = measured(state, 59, 33);
      expect(state.offset, 26);
      expect(state.rowsBelow, 0);
      expect(state.following, isFalse);
      expect(state.news, isTrue);
      state = measured(state, 60, 33);
      expect(state.offset, 26);
      expect(state.rowsBelow, 1);
      state = after(state, [ScrollStep.lineDown]);
      expect(state.following, isTrue);
      expect(state.news, isFalse);
    });
  });
  group('S4 held scroll', () {
    test(
      'fit to overflow preserves held offset and release leaves restoration to caller',
      () {
        final fit = measured(ScrollState.initial(bottom), 2, 3);
        final held = reduceHeld(fit);
        expect((held.held, held.following, held.offset), (true, false, 0));
        final grown = measured(held, 10, 3);
        expect((grown.held, grown.following, grown.offset), (true, false, 0));
        final released = reduceReleased(grown, bottom);
        expect(
          (released.held, released.following, released.offset),
          (false, false, 0),
        );
        expect(after(released, [ScrollStep.bottom]).following, isTrue);
      },
    );

    for (final follow in Follow.values) {
      test(
        'all movement and measurement paths stay detached while held $follow',
        () {
          final initial = measured(
            ScrollState.initial(follow),
            90,
            33,
            follow: follow,
          );
          final held = reduceHeld(initial);
          final steps = [
            for (final step in ScrollStep.values)
              reduceScrolled(held, step, follow),
            reduceJump(held, 1000, follow),
            reduceJump(held, -100, follow),
            measured(held, 120, 20, top: 7, follow: follow),
            measured(held, 10, 33, follow: follow),
          ];
          for (final state in steps) {
            expect(state.held, isTrue);
            expect(state.following, isFalse);
            expect(state.offset, inInclusiveRange(0, state.bottomTop));
          }
        },
      );

      test('fitting release performs normal normalization $follow', () {
        var state = reduceHeld(
          measured(ScrollState.initial(follow), 90, 33, follow: follow),
        );
        state = measured(state, 10, 33, follow: follow);
        expect(state.following, isFalse);
        final released = reduceReleased(state, follow);
        expect(released.held, isFalse);
        expect(released.following, follow == bottom);
        expect(released.offset, 0);
        expect(reduceReleased(released, follow), same(released));
      });
    }

    test(
      'hold snapshots following offset and is idempotent without clearing reader news',
      () {
        final held = reduceHeld(tall);
        expect(held.offset, tall.bottomTop);
        expect(held.news, isFalse);
        expect(reduceHeld(held), same(held));
        final reader = reduceNews(reduceJump(tall, 10, bottom), bottom);
        final readerHold = reduceHeld(reader);
        expect((readerHold.offset, readerHold.news), (10, true));
        expect(reduceReleased(readerHold, bottom).news, isTrue);
      },
    );
  });
}
