import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

List<PickerItem<String>> choices(int n) => [
  for (var i = 1; i <= n; i++) PickerItem(value: 'v$i', label: 'Choice $i'),
];

/// A picker in a box [height] rows tall, with what it gave in [log].
Widget boxed(
  List<String> log, {
  List<PickerItem<String>>? items,
  int height = 10,
  int maxVisibleRows = 8,
  bool searchable = false,
  String? initialValue,
  PickerItemBuilder<String>? itemBuilder,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    SizedBox(
      height: height,
      child: Picker<String>(
        items: items ?? choices(4),
        onSelected: log.add,
        onCanceled: () => log.add('cancel'),
        maxVisibleRows: maxVisibleRows,
        searchable: searchable,
        initialValue: initialValue,
        itemBuilder: itemBuilder,
      ),
    ),
    Text('below'),
  ],
);

List<String> keys(WidgetTester t) => [
  for (final b in t.focusManager.activeBindings) '${b.chord} ${b.description}',
];

void main() {
  testerEdges();
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('numbered rows with the highlight at $size', (t) async {
      final log = <String>[];
      await t.pumpWidget(boxed(log, initialValue: 'v2'), size: size);
      expect(t.screen.lines.take(4), [
        '  1. Choice 1',
        '❯ 2. Choice 2',
        '  3. Choice 3',
        '  4. Choice 4',
      ]);
      final dark = ThemeData.dark();
      expect(t.screen.styleAt(0, 1), dark.focus);
      // Marked by colour, never bold (CTUI-88).
      expect(t.screen.styleAt(5, 1), dark.focus);
      expect(t.screen.styleAt(5, 1), isNot(dark.focus.merge(Style.bold)));
      expect(t.screen.styleAt(5, 0), dark.text);
      await t.press('enter');
      expect(log, ['v2']);
    });
  }

  testWidgets('up and down stop at the ends, j and k too', (t) async {
    final log = <String>[];
    await t.pumpWidget(boxed(log));
    await t.press('up');
    await t.press('k');
    expect(t.screen.lines.first, '❯ 1. Choice 1');
    for (var i = 0; i < 6; i++) {
      await t.press('j');
    }
    expect(t.screen.lines[3], '❯ 4. Choice 4');
    await t.press('down');
    await t.press('enter');
    expect(log, ['v4']);
  });

  testWidgets('a number chooses its result, even out of sight', (t) async {
    final log = <String>[];
    await t.pumpWidget(boxed(log, items: choices(12), maxVisibleRows: 4));
    for (var i = 0; i < 8; i++) {
      await t.press('down');
    }
    expect(t.screen, isNot(shows('Choice 1 ')));
    await t.press('1');
    await t.press('9');
    expect(log, ['v1', 'v9']);
  });

  testWidgets('a long list scrolls without going round, with edges', (t) async {
    final log = <String>[];
    await t.pumpWidget(boxed(log, items: choices(12), maxVisibleRows: 5));
    expect(t.screen.lines.take(6), [
      '❯   1.  Choice 1',
      '    2.  Choice 2',
      '    3.  Choice 3',
      '  ↓ 4.  Choice 4',
      '    … +8 more',
      '',
    ]);
    for (var i = 0; i < 5; i++) {
      await t.press('down');
    }
    expect(t.screen.lines.take(5), [
      '  ↑ 3.  Choice 3',
      '    4.  Choice 4',
      '    5.  Choice 5',
      '❯ ↓ 6.  Choice 6',
      '    … +6 more',
    ]);
    for (var i = 0; i < 20; i++) {
      await t.press('down');
    }
    expect(t.screen.lines.take(6), [
      '  ↑ 8.  Choice 8',
      '    9.  Choice 9',
      '    10. Choice 10',
      '    11. Choice 11',
      '❯   12. Choice 12',
      '',
    ]);
    await t.press('down');
    await t.press('enter');
    expect(log, ['v12']);
  });

  testWidgets('scroll keys move the view, not the highlight', (t) async {
    final log = <String>[];
    await t.pumpWidget(boxed(log, items: choices(12), maxVisibleRows: 5));
    await t.press('end');
    expect(t.screen.lines.first, '  ↑ 8.  Choice 8');
    expect(t.screen, isNot(shows('❯')));
    await t.press('enter');
    expect(log, ['v1']);
    await t.press('home');
    expect(t.screen.lines.first, '❯   1.  Choice 1');
  });

  testWidgets('a tall row is read a line a press', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      boxed(
        log,
        items: const [
          PickerItem(value: 'a', label: 'a'),
          PickerItem(value: 'b', label: 'b1\nb2\nb3\nb4\nb5\nb6'),
          PickerItem(value: 'c', label: 'c'),
        ],
        maxVisibleRows: 4,
        itemBuilder: (_, item, _) => Text(item.label),
      ),
    );
    // As the original: the footer reserves a row until b is highlighted,
    // which takes the whole budget; then b is read a line a press.
    final steps = [
      ['❯   1. a', '    2. b1', '  ↓    b2', '    … +1 more'],
      ['    1. a', '❯   2. b1', '       b2', '  ↓    b3'],
      ['❯ ↑ 2. b1', '       b2', '       b3', '  ↓    b4'],
      ['  ↑    b2', '       b3', '       b4', '  ↓    b5'],
      ['  ↑    b3', '       b4', '       b5', '  ↓    b6'],
      ['  ↑    b4', '       b5', '       b6', '❯   3. c'],
    ];
    for (final (i, want) in steps.indexed) {
      if (i > 0) await t.press('down');
      expect(t.screen.lines.take(4), want, reason: 'step $i');
    }
    await t.press('up');
    expect(t.screen.lines[3], '    3. c', reason: 'b, from its last line');
    await t.press('up');
    expect(t.screen.lines.take(4), steps[4]);
  });

  testWidgets('a resize shows the highlighted row from its first line', (
    t,
  ) async {
    final log = <String>[];
    final height = ValueNotifier(6);
    await t.pumpWidget(
      ListenableBuilder(
        listenable: height,
        builder: (_) => boxed(
          log,
          items: choices(12),
          height: height.value,
          maxVisibleRows: 20,
        ),
      ),
    );
    for (var i = 0; i < 7; i++) {
      await t.press('down');
    }
    expect(t.screen, shows('❯ ↓ 8.'));
    height.value = 3;
    await t.pump();
    // From the highlighted row's first line, as the original's
    // fromFirstLine: it comes to the top.
    expect(t.screen.lines.take(4), [
      '❯ ↑ 8.  Choice 8',
      '  ↓ 9.  Choice 9',
      '    … +3 more',
      'below',
    ]);
  });

  testWidgets('with no rows for choices, only cancel acts', (t) async {
    final log = <String>[];
    await t.pumpWidget(boxed(log, height: 0));
    await t.press('enter');
    await t.press('1');
    await t.press('down');
    expect(log, isEmpty);
    expect(keys(t), ['escape Cancel picker']);
    await t.press('esc');
    expect(log, ['cancel']);
  });

  testWidgets('empty lists say so, and choose nothing', (t) async {
    final log = <String>[];
    await t.pumpWidget(boxed(log, items: const []));
    expect(t.screen.lines.first, 'No choices.');
    expect(t.screen.styleAt(0, 0), ThemeData.dark().dim);
    await t.press('enter');
    expect(log, isEmpty);
  });

  testWidgets('the filter: / edits, Enter or Esc finish, Esc cancels', (
    t,
  ) async {
    final log = <String>[];
    await t.pumpWidget(boxed(log, items: choices(12), searchable: true));
    expect(t.screen.lines.first, 'Filter:');
    expect(keys(t), contains('/ Edit filter'));
    await t.press('/');
    expect(keys(t), contains('escape Finish editing filter'));
    expect(keys(t), isNot(contains('enter Choose highlighted item')));
    // Keys that choose in navigation edit the query here.
    await t.type('1j');
    expect(t.screen.lines.first, startsWith('Filter: 1j'));
    expect(t.screen.lines[1], 'No matches.');
    await t.press('backspace');
    expect(t.screen.lines.take(5), [
      'Filter: 1',
      '❯ 1. Choice 1',
      '  2. Choice 10',
      '  3. Choice 11',
      '  4. Choice 12',
    ]);
    await t.press('esc');
    expect(log, isEmpty, reason: 'the first Esc only finishes editing');
    expect(t.screen.lines.first, 'Filter: 1');
    await t.press('j');
    await t.press('enter');
    expect(log, ['v10']);
    await t.press('esc');
    expect(log, ['v10', 'cancel']);
  });

  testWidgets('the highlight stays on its value while it matches', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      boxed(log, items: choices(12), searchable: true, initialValue: 'v11'),
    );
    await t.press('/');
    await t.type('1');
    expect(t.screen.lines[3], '❯ 3. Choice 11');
    await t.press('enter');
    await t.press('enter');
    expect(log, ['v11']);
  });

  testWidgets('the shortcuts panel lists what can act', (t) async {
    final log = <String>[];
    await t.pumpWidget(boxed(log, items: choices(2), searchable: true));
    expect(keys(t), [
      'up Previous choice',
      'k Previous choice',
      'down Next choice',
      'j Next choice',
      'enter Choose highlighted item',
      '1 Choose item 1',
      '2 Choose item 2',
      'pageup Scroll up a page',
      'pagedown Scroll down a page',
      'home Scroll to the top',
      'end Scroll to the bottom',
      '/ Edit filter',
      'escape Cancel picker',
    ]);
  });

  testWidgets('a builder gets the matched positions', (t) async {
    final log = <String>[];
    final seen = <String, List<int>>{};
    await t.pumpWidget(
      boxed(
        log,
        searchable: true,
        itemBuilder: (_, item, positions) {
          seen[item.label] = positions;
          return Text(item.label);
        },
      ),
    );
    await t.press('/');
    await t.type('c3');
    expect(seen['Choice 3'], [0, 7]);
  });

  testWidgets('new items keep the highlight on its value', (t) async {
    final log = <String>[];
    final items = ValueNotifier(choices(3));
    await t.pumpWidget(
      ListenableBuilder(
        listenable: items,
        builder: (_) => boxed(log, items: items.value, initialValue: 'v2'),
      ),
    );
    items.value = [const PickerItem(value: 'new', label: 'New'), ...choices(3)];
    await t.pump();
    expect(t.screen.lines[2], '❯ 3. Choice 2');
    await t.press('1');
    expect(log, ['new']);
  });

  testWidgets('KeyHelp lists the picker keys on the first frame', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Column(
        children: [
          SizedBox(
            height: 5,
            child: Picker<String>(
              items: choices(3),
              onSelected: log.add,
              onCanceled: () {},
            ),
          ),
          const KeyHelp(),
        ],
      ),
      size: const Size(200, 10),
    );
    expect(
      t.screen.lines[5],
      startsWith('up/k Previous choice  down/j Next choice'),
    );
    expect(t.screen.lines[5], contains('3 Choose item 3'));
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets(
      'the highlight is drawn only while the picker has focus, $size',
      (t) async {
        final log = <String>[];
        final prompt = FocusNode(debugLabel: 'prompt');
        await t.pumpWidget(
          Column(
            children: [
              Focus(focusNode: prompt, autofocus: true, child: Text('> ')),
              SizedBox(
                height: 5,
                child: Picker<String>(
                  items: choices(2),
                  searchable: true,
                  autofocus: false,
                  onSelected: log.add,
                  onCanceled: () {},
                ),
              ),
            ],
          ),
          size: size,
        );
        expect(t.screen.lines[2], '  1. Choice 1');
        expect(t.screen.styleAt(5, 2), ThemeData.dark().text);
        await t.press('tab');
        expect(t.screen.lines[2], '❯ 1. Choice 1');
        await t.press('/');
        expect(
          t.screen.lines[2],
          '❯ 1. Choice 1',
          reason: 'the editor is in it',
        );
        prompt.requestFocus();
        await t.pump();
        expect(t.screen.lines[2], '  1. Choice 1');
        prompt.dispose();
      },
    );
  }

  testWidgets('turning search off while editing gives the keys back', (
    t,
  ) async {
    final log = <String>[];
    final searchable = ValueNotifier(true);
    await t.pumpWidget(
      ListenableBuilder(
        listenable: searchable,
        builder: (_) =>
            boxed(log, items: choices(12), searchable: searchable.value),
      ),
    );
    await t.press('/');
    await t.type('11');
    searchable.value = false;
    await t.pump();
    // The query went, every choice is back, the highlight kept its value.
    expect(t.screen, shows('Choice 1 '.trim()));
    expect(t.screen, shows('❯   11. Choice 11'));
    await t.press('down');
    await t.press('enter');
    await t.press('esc');
    expect(log, ['v12', 'cancel']);
  });

  testWidgets('a new filter ranks the query again', (t) async {
    final log = <String>[];
    final filter = ValueNotifier<PickerFilter>(const FzfPickerFilter());
    // The same list each build: only the filter changes.
    final items = choices(3);
    await t.pumpWidget(
      ListenableBuilder(
        listenable: filter,
        builder: (_) => Column(
          children: [
            SizedBox(
              height: 6,
              child: Picker<String>(
                items: items,
                searchable: true,
                filter: filter.value,
                onSelected: log.add,
                onCanceled: () {},
              ),
            ),
          ],
        ),
      ),
    );
    await t.press('/');
    await t.type('2');
    expect(t.screen.lines[1], '❯ 1. Choice 2');
    filter.value = const _Reversed();
    await t.pump();
    // Ranked again, and the highlight stays on its value.
    expect(t.screen.lines.sublist(1, 4), [
      '  1. Choice 3',
      '❯ 2. Choice 2',
      '  3. Choice 1',
    ]);
    await t.press('enter');
    await t.press('1');
    expect(log, ['v3']);
  });

  testWidgets("a builder's lines take the highlighted row's style", (t) async {
    final log = <String>[];
    final prompt = FocusNode(debugLabel: 'prompt');
    await t.pumpWidget(
      Column(
        children: [
          Focus(focusNode: prompt, child: Text('> ')),
          SizedBox(
            height: 6,
            child: Picker<String>(
              items: const [
                PickerItem(value: 'a', label: 'first\nsecond'),
                PickerItem(value: 'b', label: 'other'),
              ],
              onSelected: log.add,
              onCanceled: () {},
              itemBuilder: (_, item, _) => item.value == 'b'
                  ? Text(item.label, style: const Style(fg: Colors.red))
                  : Text(item.label),
            ),
          ),
        ],
      ),
    );
    final dark = ThemeData.dark();
    final lit = dark.focus;
    expect(t.screen.lines.sublist(1, 4), [
      '❯ 1. first',
      '     second',
      '  2. other',
    ]);
    expect(t.screen.styleAt(5, 1), lit);
    expect(t.screen.styleAt(5, 2), lit, reason: 'every line of it');
    expect(t.screen.styleAt(5, 3).fg, Colors.red, reason: 'its own style wins');
    await t.press('down');
    expect(t.screen.styleAt(5, 1), dark.text);
    expect(t.screen.styleAt(5, 3), lit.merge(const Style(fg: Colors.red)));
    prompt.requestFocus();
    await t.pump();
    expect(
      t.screen.styleAt(5, 3),
      dark.text.merge(const Style(fg: Colors.red)),
    );
    prompt.dispose();
  });
}

/// Every label, last first, whatever the query.
class _Reversed implements PickerFilter {
  const _Reversed();

  @override
  List<PickerMatch> match(String query, List<String> labels) => [
    for (var i = labels.length - 1; i >= 0; i--)
      PickerMatch(index: i, matchedPositions: const []),
  ];
}

void testerEdges() {
  group('tester: Picker interaction and lifecycle boundaries', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'custom rich content follows themes and focus without losing explicit style at $size',
        (t) async {
          final outside = FocusNode();
          final theme = ValueNotifier(0);
          addTearDown(outside.dispose);
          addTearDown(theme.dispose);
          final themes = [
            ThemeData.dark(),
            ThemeData.light(),
            ThemeData.plain(),
          ];
          await t.pumpWidget(
            ListenableBuilder(
              listenable: theme,
              builder: (_) => Theme(
                data: themes[theme.value],
                child: Column(
                  children: [
                    Focus(focusNode: outside, child: Text('outside')),
                    SizedBox(
                      height: 7,
                      child: Picker<String>(
                        items: const [PickerItem(value: 'a', label: 'a')],
                        onSelected: (_) {},
                        onCanceled: () {},
                        itemBuilder: (_, item, positions) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('界🙂e\u0301'),
                            const Text.rich(
                              TextSpan(
                                '',
                                children: [
                                  TextSpan('plain'),
                                  TextSpan(
                                    ' red',
                                    style: Style(fg: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            size: size,
          );
          for (var i = 0; i < themes.length; i++) {
            theme.value = i;
            await t.pump();
            final lit = themes[i].focus;
            expect(t.screen.styleAt(5, 1), lit);
            expect(t.screen.styleAt(5, 2), lit);
            expect(
              t.screen.styleAt(11, 2),
              lit.merge(const Style(fg: Colors.red)),
            );
            outside.requestFocus();
            await t.pump();
            expect(t.screen, isNot(shows('❯')));
            expect(t.screen.styleAt(5, 1), themes[i].text);
            expect(
              t.screen.styleAt(11, 2),
              themes[i].text.merge(const Style(fg: Colors.red)),
            );
            await t.press('tab');
            expect(t.screen.styleAt(5, 1), lit);
          }
        },
      );
    }

    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'page keys preserve selection and line keys resume it at $size',
        (t) async {
          final log = <String>[];
          await t.pumpWidget(
            boxed(log, items: choices(30), maxVisibleRows: 5),
            size: size,
          );
          await t.press('pagedown');
          await t.press('pagedown');
          expect(t.screen, isNot(shows('❯')));
          await t.press('enter');
          expect(log, ['v1']);
          await t.press('pageup');
          await t.press('home');
          expect(t.screen.lines.first, startsWith('❯'));
          await t.press('end');
          await t.press('k');
          await t.press('j');
          await t.press('enter');
          expect(log.last, 'v2');
        },
      );

      testWidgets('no-row keys never become a pending choice at $size', (
        t,
      ) async {
        final log = <String>[];
        final height = ValueNotifier(5);
        addTearDown(height.dispose);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: height,
            builder: (_) => boxed(log, height: height.value, searchable: true),
          ),
          size: size,
        );
        await t.press('down');
        height.value = 1;
        await t.pump();
        for (final key in [
          'enter',
          '1',
          '9',
          'up',
          'down',
          'j',
          'k',
          'home',
          'end',
          'pageup',
          'pagedown',
        ]) {
          await t.press(key);
        }
        expect(log, isEmpty);
        expect(keys(t), ['/ Edit filter', 'escape Cancel picker']);
        height.value = 5;
        await t.pump();
        expect(log, isEmpty);
        await t.press('enter');
        expect(log, ['v2']);
      });

      testWidgets(
        'replacement after a thousand updates cannot select stale items at $size',
        (t) async {
          final log = <String>[];
          final items = ValueNotifier(choices(12));
          addTearDown(items.dispose);
          await t.pumpWidget(
            ListenableBuilder(
              listenable: items,
              builder: (_) =>
                  boxed(log, items: items.value, initialValue: 'v7'),
            ),
            size: size,
          );
          for (var i = 0; i < 1000; i++) {
            items.value = [PickerItem(value: 'new$i', label: '界🙂e\u0301 $i')];
          }
          await t.pump();
          await t.press('7');
          expect(log, isEmpty);
          await t.press('enter');
          expect(log, ['new999']);
          expect(t.screen, shows('界🙂e\u0301 999'));
        },
      );

      testWidgets(
        'removing an active filter editor removes its keys and listeners at $size',
        (t) async {
          final log = <String>[];
          final show = ValueNotifier(true);
          addTearDown(show.dispose);
          await t.pumpWidget(
            ListenableBuilder(
              listenable: show,
              builder: (_) =>
                  show.value ? boxed(log, searchable: true) : Text('removed'),
            ),
            size: size,
          );
          await t.press('/');
          await t.paste('界🙂e\u0301');
          show.value = false;
          await t.pump();
          await t.paste('later');
          for (final key in ['tab', 'shift+tab', 'enter', '1', 'esc', 'down']) {
            await t.press(key);
          }
          expect(log, isEmpty);
          expect(t.screen.text, 'removed');
          expect(t.focusManager.activeBindings, isEmpty);
        },
      );

      testWidgets(
        'custom Unicode rows clip within a narrow window then recover at $size',
        (t) async {
          final log = <String>[];
          await t.pumpWidget(
            boxed(
              log,
              items: const [
                PickerItem(value: 'a', label: '界🙂e\u0301\x1b[31mR\x1b[0m'),
                PickerItem(value: 'b', label: '🙂界e\u0301'),
              ],
              itemBuilder: (_, item, _) => Text(item.label),
            ),
            size: size,
          );
          expect(t.screen, shows('界🙂e\u0301R'));
          for (final next in const [Size(1, 1), Size(0, 0), Size(8, 4)]) {
            await t.resize(next);
          }
          await t.resize(size);
          expect(t.screen, shows('界🙂e\u0301R'));
          await t.press('2');
          expect(log, ['b']);
        },
      );
    }

    testWidgets('a column supplies unbounded height with a finite row cap', (
      t,
    ) async {
      final log = <String>[];
      await t.pumpWidget(
        Column(
          children: [
            Picker(
              items: choices(30),
              maxVisibleRows: 4,
              onSelected: log.add,
              onCanceled: () {},
            ),
            Text('after'),
          ],
        ),
      );
      expect(t.screen.lines[4], 'after');
      expect(t.screen.lines.take(4).last, contains('more'));
    });
  });
}
