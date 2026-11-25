import 'package:chord/ui/status/status.dart';
import 'package:chord/ui/status/status_line.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

String text(LeaderLineView view) =>
    '${view.held}$leaderGap${view.items.map((item) => '${item.keys} ${item.words}').join(statusSeparator)}';

void main() {
  final held = [KeyCombo.parse('ctrl+x')];
  final bindings = [
    Binding(
      'ctrl+x a',
      'Answer waiting request',
      () {},
      id: 'session:attention',
    ),
  ];
  test('full, short and dropped items use the original width priorities', () {
    const full = 'ctrl+x …  a the one that waits · esc never mind';
    expect(text(leaderLine(held, bindings, 116)), full);
    expect(text(leaderLine(held, bindings, 76)), full);
    expect(text(leaderLine(held, bindings, cellWidth(full))), full);
    expect(
      text(leaderLine(held, bindings, cellWidth(full) - 1)),
      'ctrl+x …  a waits',
    );
    expect(text(leaderLine(held, bindings, 36)), 'ctrl+x …  a waits');
    expect(text(leaderLine(held, bindings, 17)), 'ctrl+x …  a waits');
    expect(leaderLine(held, bindings, 16).items, isEmpty);
    expect(leaderLine(held, bindings, 0).items, isEmpty);
  });
  test('only an enabled matching continuation offers attention', () {
    expect(
      leaderLine(held, [
        Binding(
          'ctrl+x a',
          'Attention',
          () {},
          enabled: false,
          id: 'session:attention',
        ),
      ], 80).items.map((item) => item.keys),
      ['esc'],
    );
    expect(
      leaderLine(
        [KeyCombo.parse('ctrl+y')],
        bindings,
        80,
      ).items.map((item) => item.keys),
      ['esc'],
    );
  });
  for (final width in [116, 76, 36, 16, 7, 0]) {
    testWidgets(
      'leader drops whole items before clipping held keys at width$width',
      (t) async {
        await t.pumpWidget(
          LeaderLine(held: held, bindings: bindings),
          size: Size(width, 1),
        );
        final expected = width >= 76
            ? 'ctrl+x …  a the one that waits · esc never mind'
            : width >= 17
            ? 'ctrl+x …  a waits'
            : width >= 8
            ? 'ctrl+x …'
            : width == 0
            ? ''
            : 'ctrl+x';
        expect(t.screen.text, expected);
        expect(t.screen.text, isNot(contains('...')));
      },
    );
  }

  group('tester: leader width and role boundaries', () {
    test(
      'every width chooses complete full or short items before dropping them',
      () {
        const full = 'ctrl+x …  a the one that waits · esc never mind';
        for (var width = 0; width <= 120; width++) {
          final view = leaderLine(held, bindings, width);
          if (width >= cellWidth(full)) {
            expect(text(view), full);
          } else if (width >= 17) {
            expect(text(view), 'ctrl+x …  a waits');
          } else {
            expect(view.items, isEmpty);
            expect(view.held, 'ctrl+x …');
          }
        }
      },
    );
    for (final (name, theme) in [
      ('dark', ThemeData.dark()),
      ('plain', ThemeData.plain()),
    ]) {
      testWidgets('rich keys and words keep their roles across resize, $name', (
        t,
      ) async {
        await t.pumpWidget(
          Theme(
            data: theme,
            child: LeaderLine(held: held, bindings: bindings),
          ),
          size: const Size(80, 1),
        );
        expect(t.screen.styleAt(0, 0).fg, theme.text.fg);
        expect(t.screen.styleAt(10, 0).fg, theme.text.fg);
        expect(t.screen.styleAt(12, 0).fg, theme.dim.fg);
        await t.resize(const Size(17, 1));
        expect(t.screen.text, 'ctrl+x …  a waits');
        expect(t.screen.styleAt(12, 0).fg, theme.dim.fg);
        await t.resize(const Size(1, 1));
        expect(cellWidth(t.screen.text), lessThanOrEqualTo(1));
        await t.resize(const Size(80, 1));
        expect(
          t.screen.text,
          'ctrl+x …  a the one that waits · esc never mind',
        );
      });
    }
  });
}
