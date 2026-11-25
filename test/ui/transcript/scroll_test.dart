// Original scroll_test.ts: rule/rowsBelow cases, the held ones (CHD-397)
// through the framework's reducers. Mount windows are omitted.
import 'package:chord/ui/transcript/scroll.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

String rule(ScrollState scroll, int width) =>
    indicator(scroll, width, 'end').map((s) => s.text).join();

ScrollState measured(ScrollState s, int content, int view) =>
    reduceMeasured(s, content: content, view: view, follow: Follow.bottom);

ScrollState after(ScrollState s, ScrollStep step) =>
    reduceScrolled(s, step, Follow.bottom);

final initial = ScrollState.initial(Follow.bottom);

void main() {
  const back = ScrollState(content: 90, view: 33, top: 26);
  test('following has no rule; scrolling counts its covered row', () {
    expect(
      rowsBelow(const ScrollState(content: 90, view: 33, following: true)),
      isNull,
    );
    expect(indicator(const ScrollState(following: true), 78, 'end'), isEmpty);
    expect(rowsBelow(back), 32);
    expect(rowsBelow(const ScrollState(content: 130, view: 33, top: 26)), 72);
  });
  test('the rule says how much is below and the key back', () {
    expect(
      rule(back, 78),
      '── ↓ 32 lines below · end to jump to the bottom ${'─' * 30}',
    );
    expect(
      rule(const ScrollState(content: 90, view: 33, top: 57), 30),
      '── ↓ 1 line below ${'─' * 12}',
    );
  });
  test('the rule names new output in words and in the accent', () {
    const news = ScrollState(content: 90, view: 33, top: 26, news: true);
    final segments = indicator(news, 118, 'end');
    expect(segments.map((s) => s.accent), [false, true, false]);
    expect(segments[1].text, '↓ new output');
    expect(
      rule(news, 118).substring(0, 64),
      '── ↓ new output · 32 lines below · end to jump to the bottom ───',
    );
    expect(rule(news, 40), '── ↓ new output · 32 lines below ${'─' * 7}');
  });
  test('a view scrolled back to bottom without a press keeps its rule', () {
    const bottom = ScrollState(content: 90, view: 33, top: 57);
    expect(rowsBelow(bottom), 1);
    expect(rule(bottom, 40), startsWith('── ↓ 1 line below'));
  });
  test(
    'no bottom key omits its hint and tiny widths leave clipping to Below',
    () {
      expect(
        indicator(back, 80, null).map((s) => s.text).join(),
        isNot(contains('jump')),
      );
      expect(rule(back, 0), '── ↓ 32 lines below ');
    },
  );

  test('a press at the bottom draws no rule until output goes below it '
      '(CHD-397)', () {
    final held = reduceHeld(measured(initial, 100, 20));
    expect(rowsBelow(held), isNull);
    expect(indicator(held, 80, 'end'), isEmpty);
    final short = reduceHeld(measured(initial, 10, 20));
    expect(rowsBelow(short), isNull);
    expect(indicator(short, 80, 'end'), isEmpty);
    // 30 rows arrive under the press: 30 below, and the row the rule covers.
    final grown = measured(held, 130, 20);
    expect(rowsBelow(grown), 31);
    expect(rule(grown, 40), startsWith('── ↓ 31 lines below'));
  });

  test('a view scrolled back to the bottom with no press keeps its rule '
      '(CHD-397)', () {
    const back = ScrollState(content: 100, view: 20, top: 80);
    expect(rowsBelow(back), 1);
    expect(rule(back, 40), startsWith('── ↓ 1 line below'));
  });

  test('tester: a drag remains held through narrow, zero-row and restored '
      'layouts', () {
    var state = reduceHeld(measured(initial, 90, 33));
    for (final view in [18, 0, 33, 200, 18]) {
      state = measured(state, 100, view);
      expect(state.held, isTrue);
      expect(state.following, isFalse);
      expect(state.top, greaterThanOrEqualTo(0));
      state = after(state, ScrollStep.bottom);
      expect(state.following, isFalse);
    }
    expect(
      after(reduceReleased(state, Follow.bottom), ScrollStep.bottom).following,
      isTrue,
    );
  });

  test('tester: growth that still fits has no rule, and the first overflow '
      'counts the covered row (CHD-397)', () {
    var state = reduceHeld(measured(initial, 10, 20));
    for (final content in [19, 20]) {
      state = measured(state, content, 20);
      expect(rowsBelow(state), isNull);
      expect(
        indicator(
          ScrollState(
            content: state.content,
            view: state.view,
            top: state.top,
            held: state.held,
            news: true,
          ),
          80,
          'end',
        ),
        isEmpty,
      );
    }
    state = measured(state, 21, 20);
    expect(rowsBelow(state), 2);
    expect(rule(state, 80), contains('2 lines below'));
    expect(rowsBelow(measured(state, 20, 20)), isNull);
  });

  test('tester: moving up during a press shows the count and returning to '
      'the bottom hides it (CHD-397)', () {
    final held = reduceHeld(measured(initial, 90, 33));
    final back = after(held, ScrollStep.lineUp);
    expect(rowsBelow(back), 2);
    expect(rule(back, 80), contains('2 lines below'));
    expect(rowsBelow(after(back, ScrollStep.lineDown)), isNull);
    expect(rowsBelow(after(back, ScrollStep.bottom)), isNull);
  });
}
