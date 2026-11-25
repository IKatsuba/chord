import 'dart:collection';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  _testerPickerExtentBoundaries();
  for (final count in [2000, 10000]) {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('exact Picker $count navigates visible rows at $size', (
        t,
      ) async {
        final items = [
          for (var i = 0; i < count; i++)
            PickerItem(value: i, label: 'Choice $i'),
        ];
        var projections = 0, builds = 0;
        final widths = <int>{};
        final picks = <int>[];
        await t.pumpWidget(
          Picker<int>(
            items: items,
            initialValue: count ~/ 2,
            maxVisibleRows: 8,
            itemExtentVersion: 0,
            itemExtentBuilder: (item, positions, width) {
              projections++;
              widths.add(width);
              return 1;
            },
            itemBuilder: (_, item, positions) {
              builds++;
              return Text(item.label);
            },
            onSelected: picks.add,
            onCanceled: () {},
          ),
          size: size,
        );
        expect(projections, count);
        expect(widths, {size.width - 4 - ('$count.'.length + 1)});
        expect(builds, lessThanOrEqualTo(32));
        projections = 0;
        builds = 0;
        await t.press('down');
        expect(projections, 0);
        expect(builds, lessThanOrEqualTo(32));
        await t.press('enter');
        expect(picks, [count ~/ 2 + 1]);
        builds = 0;
        await t.resize(Size(size.width - 10, size.height));
        expect(projections, count);
        expect(builds, lessThanOrEqualTo(32));
        projections = 0;
        await t.resize(Size(size.width - 10, size.height - 2));
        expect(projections, 0);
        await t.resize(size);
        expect(projections, count);
      });
    }
  }

  testWidgets(
    'default rows never reread all items on parent highlight updates',
    (t) async {
      final items = _CountingItems(10000);
      final changed = ValueNotifier(0);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: changed,
          builder: (_) => Picker<int>(
            items: items,
            maxVisibleRows: 8,
            onChanged: (value) {
              changed.value++;
            },
            onSelected: (_) {},
            onCanceled: () {},
          ),
        ),
      );
      items.reads = 0;
      await t.press('down');
      expect(items.reads, lessThan(100));
      expect(t.screen, shows('Choice 1'));
      t.dispose();
      changed.dispose();
    },
  );

  testWidgets('fallback reconciles changed individual heights at equal total', (
    t,
  ) async {
    final changed = ValueNotifier(0);
    final heights = [1, 3, 1, 1];
    final items = [
      for (var i = 0; i < 4; i++) PickerItem(value: i, label: '$i'),
    ];
    await t.pumpWidget(
      ListenableBuilder(
        listenable: changed,
        builder: (_) => Picker<int>(
          items: items,
          maxVisibleRows: 3,
          itemBuilder: (_, item, positions) => Text(
            [
              for (var row = 1; row <= heights[item.value]; row++)
                'choice ${item.value} line $row',
            ].join('\n'),
          ),
          onSelected: (_) {},
          onCanceled: () {},
        ),
      ),
    );
    expect(t.screen, shows('… +2 more'));
    heights[0] = 3;
    heights[1] = 1;
    changed.value++;
    await t.pump();
    expect(t.screen, shows('choice 0 line 3'));
    expect(t.screen.text, isNot(contains('more')));
    t.dispose();
    changed.dispose();
  });

  testWidgets('exact wrapping matches measured fallback through resize', (
    t,
  ) async {
    final items = [
      for (var i = 0; i < 12; i++)
        PickerItem(value: i, label: '$i 界 café é ${'word ' * (i + 1)}'),
    ];
    Widget picker(bool exact) => Picker<int>(
      items: items,
      maxVisibleRows: 8,
      initialValue: 4,
      countHiddenItemsAbove: true,
      showInitialSelectionAtTop: false,
      itemExtentVersion: 0,
      itemExtentBuilder: exact
          ? (item, positions, width) =>
                TextLayout.compute(TextSpan(item.label), maxWidth: width).height
          : null,
      itemBuilder: (_, item, positions) => Text(item.label),
      onSelected: (_) {},
      onCanceled: () {},
    );
    final screens = <String>[];
    await t.pumpWidget(picker(false), size: const Size(80, 24));
    for (final size in [
      const Size(80, 24),
      const Size(32, 10),
      const Size(120, 40),
    ]) {
      await t.resize(size);
      await t.press('down down up');
      screens.add(t.screen.text);
    }
    await t.pumpWidget(picker(true), size: const Size(80, 24));
    var at = 0;
    for (final size in [
      const Size(80, 24),
      const Size(32, 10),
      const Size(120, 40),
    ]) {
      await t.resize(size);
      await t.press('down down up');
      expect(t.screen.text, screens[at++]);
    }
  });

  testWidgets(
    'explicit revisions outlive inline callbacks; null observes captures',
    (t) async {
      final rebuild = ValueNotifier(0);
      final items = [
        for (var i = 0; i < 30; i++) PickerItem(value: i, label: '$i'),
      ];
      var height = 1, projections = 0;
      Object? revision = 0;
      await t.pumpWidget(
        ListenableBuilder(
          listenable: rebuild,
          builder: (_) => Picker<int>(
            items: items,
            maxVisibleRows: 8,
            itemExtentVersion: revision,
            itemExtentBuilder: (item, positions, width) {
              projections++;
              return height;
            },
            itemBuilder: (_, item, positions) =>
                SizedBox(height: height, child: Text(item.label)),
            onSelected: (_) {},
            onCanceled: () {},
          ),
        ),
      );
      projections = 0;
      rebuild.value++;
      await t.pump();
      expect(projections, 0);
      height = 2;
      revision = 1;
      rebuild.value++;
      await t.pump();
      expect(projections, 30);
      projections = 0;
      revision = null;
      rebuild.value++;
      await t.pump();
      expect(projections, 30);
      projections = 0;
      height = 3;
      rebuild.value++;
      await t.pump();
      expect(projections, 30);
      t.dispose();
      rebuild.dispose();
    },
  );

  testWidgets('items, ranking and number gutters invalidate exact mapping', (
    t,
  ) async {
    final changes = ValueNotifier(0);
    var items = [
      for (var i = 0; i < 20; i++) PickerItem(value: i, label: 'Choice $i'),
    ];
    var projections = 0, numbers = true;
    final widths = <int>{}, picks = <int>[];
    await t.pumpWidget(
      ListenableBuilder(
        listenable: changes,
        builder: (_) => Picker<int>(
          items: items,
          searchable: true,
          initialValue: 10,
          showNumbers: numbers,
          itemExtentVersion: 0,
          itemExtentBuilder: (item, positions, width) {
            projections++;
            widths.add(width);
            return 1;
          },
          itemBuilder: (_, item, positions) => Text(item.label),
          onSelected: picks.add,
          onCanceled: () {},
        ),
      ),
    );
    projections = 0;
    numbers = false;
    widths.clear();
    changes.value++;
    await t.pump();
    expect(projections, 20);
    expect(widths, {76});
    items = items.reversed.toList();
    changes.value++;
    await t.pump();
    await t.press('enter');
    expect(picks.last, 10);
    await t.press('/');
    await t.type('Choice 19');
    await t.press('enter enter');
    expect(picks.last, 19);
    items = [const PickerItem(value: 100, label: 'Choice 100')];
    changes.value++;
    await t.pump();
    expect(t.screen, shows('No matches.'));
    await t.press('enter');
    expect(picks.last, 19);
    t.dispose();
    changes.dispose();
  });

  testWidgets(
    'switching exact heights back to fallback replaces cached geometry',
    (t) async {
      final exact = ValueNotifier(true);
      final items = [
        for (var i = 0; i < 20; i++) PickerItem(value: i, label: 'Choice $i'),
      ];
      await t.pumpWidget(
        ListenableBuilder(
          listenable: exact,
          builder: (_) => Picker<int>(
            items: items,
            maxVisibleRows: 8,
            itemExtentVersion: 0,
            itemExtentBuilder: exact.value
                ? (item, positions, width) => 2
                : null,
            itemBuilder: (_, item, positions) =>
                SizedBox(height: exact.value ? 2 : 1, child: Text(item.label)),
            onSelected: (_) {},
            onCanceled: () {},
          ),
        ),
      );
      expect(t.screen.text, isNot(contains('Choice 6')));
      exact.value = false;
      await t.pump();
      expect(t.screen, shows('Choice 6'));
      expect(t.screen, shows('… +13 more'));
      t.dispose();
      exact.dispose();
    },
  );

  testWidgets('zero content height retains the visible choice furniture', (
    t,
  ) async {
    var picks = 0;
    await t.pumpWidget(
      Picker<int>(
        items: const [PickerItem(value: 1, label: '')],
        itemExtentVersion: 0,
        itemExtentBuilder: (_, positions, width) => 0,
        itemBuilder: (_, item, positions) => const SizedBox(height: 0),
        onSelected: (_) {
          picks++;
        },
        onCanceled: () {},
      ),
    );
    expect(t.screen, shows('1.'));
    await t.press('enter');
    expect(picks, 1);
  });

  testWidgets('exact tall rows read lines before changing selected choice', (
    t,
  ) async {
    final picks = <int>[];
    await t.pumpWidget(
      Picker<int>(
        items: const [
          PickerItem(value: 0, label: 'first'),
          PickerItem(value: 1, label: 'last'),
        ],
        maxVisibleRows: 3,
        itemExtentVersion: 0,
        itemExtentBuilder: (item, positions, width) => item.value == 0 ? 6 : 1,
        itemBuilder: (_, item, positions) => Text(
          item.value == 0
              ? 'first\nline 2\nline 3\nline 4\nline 5\nline 6'
              : item.label,
        ),
        onSelected: picks.add,
        onCanceled: () {},
      ),
    );
    await t.press('down down down enter');
    expect(picks, [0]);
    expect(t.screen, shows('line 6'));
    await t.press('down enter');
    expect(picks, [0, 1]);
  });
}

class _CountingItems extends ListBase<PickerItem<int>> {
  _CountingItems(this.length);
  @override
  final int length;
  var reads = 0;
  @override
  set length(int value) => throw UnsupportedError('Fixed length');
  @override
  PickerItem<int> operator [](int index) {
    reads++;
    return PickerItem(value: index, label: 'Choice $index');
  }

  @override
  void operator []=(int index, PickerItem<int> value) =>
      throw UnsupportedError('Read only');
}

void _testerPickerExtentBoundaries() {
  group('tester: U54c1 exact Picker boundaries', () {
    testWidgets('failed projection blocks input before another painted frame', (
      t,
    ) async {
      final height = ValueNotifier(1);
      final picks = <int>[];
      await t.pumpWidget(
        ListenableBuilder(
          listenable: height,
          builder: (_) => Picker<int>(
            items: const [
              PickerItem(value: 0, label: 'First'),
              PickerItem(value: 1, label: 'Second'),
            ],
            initialValue: 1,
            itemExtentVersion: height.value,
            itemExtentBuilder: (_, positions, width) => height.value,
            itemBuilder: (_, item, positions) => Text(item.label),
            onSelected: picks.add,
            onCanceled: () {},
          ),
        ),
      );
      height.value = -1;
      t.host.handleKey(const KeyEvent('enter'));
      t.host.handleKey(const KeyEvent('1'));
      t.host.handleKey(const KeyEvent('down'));
      expect(picks, isEmpty);
      height.value = 1;
      await t.pump();
      expect(picks, isEmpty);
      await t.press('enter');
      expect(picks, [1]);
      t.dispose();
      height.dispose();
    });

    testWidgets(
      'width and revision cycles keep only visible row states mounted',
      (t) async {
        final revision = ValueNotifier(0);
        final census = _TesterExtentCensus();
        await t.pumpWidget(
          ListenableBuilder(
            listenable: revision,
            builder: (_) => Picker<int>(
              items: [
                for (var i = 0; i < (revision.value.isEven ? 2000 : 10000); i++)
                  PickerItem(value: i, label: 'Choice $i'),
              ],
              maxVisibleRows: 8,
              showNumbers: revision.value % 3 != 0,
              itemExtentVersion: revision.value,
              itemExtentBuilder: (_, positions, width) => 1,
              itemBuilder: (_, item, positions) =>
                  _TesterExtentLife(census, item.label),
              onSelected: (_) {},
              onCanceled: () {},
            ),
          ),
          size: const Size(120, 40),
        );
        for (var i = 1; i <= 12; i++) {
          revision.value = i;
          await t.resize(i.isEven ? const Size(120, 40) : const Size(80, 24));
          await t.press('down down up');
          expect(census.live, inInclusiveRange(1, 8));
          expect(census.maximum, lessThanOrEqualTo(16));
        }
        await t.pumpWidget(const SizedBox());
        expect(census.live, 0);
        revision.value++;
        await t.pump();
        expect(census.live, 0);
        t.dispose();
        revision.dispose();
      },
    );

    testWidgets('negative exact content uses the normal build error boundary', (
      t,
    ) async {
      final errors = <Object>[];
      final picks = <int>[];
      await t.pumpWidget(
        ErrorBoundary(
          onError: (error, stack) => errors.add(error),
          errorBuilder: (_, error, stack) => Text('Extent rejected'),
          child: Picker<int>(
            items: const [PickerItem(value: 1, label: 'one')],
            itemExtentVersion: 0,
            itemExtentBuilder: (_, positions, width) => -1,
            itemBuilder: (_, item, positions) => const SizedBox(height: 1),
            onSelected: picks.add,
            onCanceled: () {},
          ),
        ),
      );
      expect(errors, [isA<ArgumentError>()]);
      expect(t.screen, shows('Extent rejected'));
      await t.press('down 1 enter');
      expect(picks, isEmpty);
    });

    testWidgets('mismatched exact content height fails during render', (
      t,
    ) async {
      await expectLater(
        t.pumpWidget(
          Picker<int>(
            items: const [PickerItem(value: 1, label: 'one')],
            itemExtentVersion: 0,
            itemExtentBuilder: (_, positions, width) => 2,
            itemBuilder: (_, item, positions) => const SizedBox(height: 1),
            onSelected: (_) {},
            onCanceled: () {},
          ),
        ),
        throwsStateError,
      );
    });

    testWidgets(
      'matching positions invalidate heights even when the sole result stays',
      (t) async {
        final projected = <List<int>>[];
        String content(List<int> positions) => List.generate(
          positions.length + 1,
          (i) => 'line ${i + 1}',
        ).join('\n');
        await t.pumpWidget(
          Picker<int>(
            items: const [PickerItem(value: 7, label: 'query target')],
            searchable: true,
            filter: const _TesterPositionFilter(),
            itemExtentVersion: 0,
            itemExtentBuilder: (_, positions, width) {
              projected.add(List.of(positions));
              return positions.length + 1;
            },
            itemBuilder: (_, item, positions) => Text(content(positions)),
            onSelected: (_) {},
            onCanceled: () {},
          ),
        );
        await t.press('/');
        await t.type('a');
        expect(projected.last, [0]);
        expect(t.screen, shows('line 2'));
        await t.type('b');
        expect(projected.last, [0, 1]);
        expect(t.screen, shows('line 3'));
        await t.press('backspace');
        expect(projected.last, [0]);
        expect(t.screen.text, isNot(contains('line 3')));
      },
    );

    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'exact and fallback keep Unicode, ANSI, keys and resize screens equal at $size',
        (t) async {
          final measured = await _testerReplayExtentPicker(t, false, size);
          final exact = await _testerReplayExtentPicker(t, true, size);
          expect(exact, measured);
        },
      );

      testWidgets('focus and enable changes reuse exact geometry at $size', (
        t,
      ) async {
        final enabled = ValueNotifier(true);
        final picker = FocusNode();
        final outside = FocusNode();
        final items = [
          for (var i = 0; i < 50; i++) PickerItem(value: i, label: 'Choice $i'),
        ];
        final changed = <int>[];
        final picks = <int>[];
        var projections = 0;
        await t.pumpWidget(
          ListenableBuilder(
            listenable: enabled,
            builder: (_) => Column(
              children: [
                Picker<int>(
                  items: items,
                  focusNode: picker,
                  enabled: enabled.value,
                  maxVisibleRows: 6,
                  itemExtentVersion: 0,
                  itemExtentBuilder: (_, positions, width) {
                    projections++;
                    return 1;
                  },
                  itemBuilder: (_, item, positions) => Text(item.label),
                  onChanged: (value) {
                    changed.add(value);
                    outside.requestFocus();
                  },
                  onSelected: picks.add,
                  onCanceled: () {},
                ),
                Focus(focusNode: outside, child: Text('Outside')),
              ],
            ),
          ),
          size: size,
        );
        projections = 0;
        await t.press('down');
        expect(changed, [1]);
        expect(outside.hasFocus, isTrue);
        await t.press('down enter');
        expect(picks, isEmpty);
        enabled.value = false;
        await t.pump();
        enabled.value = true;
        await t.pump();
        expect(outside.hasFocus, isTrue);
        picker.requestFocus();
        await t.pump();
        await t.press('enter');
        expect(picks, [1]);
        expect(projections, 0);
        t.dispose();
        enabled.dispose();
        picker.dispose();
        outside.dispose();
      });
    }
  });
}

Future<List<String>> _testerReplayExtentPicker(
  WidgetTester t,
  bool exact,
  Size size,
) async {
  final items = [
    for (var i = 0; i < 20; i++)
      PickerItem(
        value: i,
        label: '$i 界🙂e\u0301\x1b[31mA\x1b[0m ${'word ' * (i % 4 + 1)}',
      ),
  ];
  await t.pumpWidget(
    Picker<int>(
      key: ValueKey(exact),
      items: items,
      initialValue: 8,
      maxVisibleRows: 6,
      wrapNavigation: true,
      countHiddenItemsAbove: true,
      showInitialSelectionAtTop: false,
      itemExtentVersion: 0,
      itemExtentBuilder: exact
          ? (item, positions, width) =>
                TextLayout.compute(TextSpan(item.label), maxWidth: width).height
          : null,
      itemBuilder: (_, item, positions) => Text(item.label),
      onSelected: (_) {},
      onCanceled: () {},
    ),
    size: size,
  );
  final screens = <String>[t.screen.text];
  for (final keys in [
    'down down up j k',
    'home end pageup pagedown',
    'shift+up shift+down',
    '1 enter esc',
  ]) {
    await t.press(keys);
    screens.add(t.screen.text);
  }
  for (final next in [
    const Size(8, 4),
    const Size(1, 1),
    const Size(0, 0),
    size,
  ]) {
    await t.resize(next);
    screens.add(t.screen.text);
  }
  expect(screens.every((screen) => !screen.contains('\x1b')), isTrue);
  return screens;
}

class _TesterPositionFilter implements PickerFilter {
  const _TesterPositionFilter();
  @override
  List<PickerMatch> match(String query, List<String> labels) => [
    PickerMatch(
      index: 0,
      matchedPositions: List.generate(query.length, (i) => i),
    ),
  ];
}

class _TesterExtentCensus {
  var live = 0, maximum = 0;
}

class _TesterExtentLife extends StatefulWidget {
  const _TesterExtentLife(this.census, this.label);
  final _TesterExtentCensus census;
  final String label;
  @override
  State<_TesterExtentLife> createState() => _TesterExtentLifeState();
}

class _TesterExtentLifeState extends State<_TesterExtentLife> {
  @override
  void initState() {
    super.initState();
    widget.census.live++;
    if (widget.census.live > widget.census.maximum) {
      widget.census.maximum = widget.census.live;
    }
  }

  @override
  void dispose() {
    widget.census.live--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
}
