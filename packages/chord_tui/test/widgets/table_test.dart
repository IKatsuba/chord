import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// [table] at the top left, its own width, with a marker row under it.
Widget loose(Widget table) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [table, Text('under')],
);

TableRow row(List<String> cells) =>
    TableRow(children: [for (final c in cells) Text(c)]);

void main() {
  testerEdges();
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('aligned columns with a gap at $size', (t) async {
      await t.pumpWidget(
        loose(
          Table(
            columnGap: 2,
            columnWidths: const {
              0: IntrinsicColumnWidth(maxWidth: 32),
              1: FixedColumnWidth(9),
              2: FlexColumnWidth(),
            },
            children: [
              row(['Name', 'Transport', 'Command or URL']),
              row(['memory', 'stdio', 'npx -y memory']),
            ],
          ),
        ),
        size: size,
      );
      expect(t.screen.lines.take(3), [
        'Name    Transport  Command or URL',
        'memory  stdio      npx -y memory',
        'under',
      ]);
    });
  }

  testWidgets('a row is as tall as its tallest cell', (t) async {
    await t.pumpWidget(
      loose(
        SizedBox(
          width: 20,
          child: Table(
            columnGap: 1,
            columnWidths: const {0: FixedColumnWidth(4)},
            children: [
              row(['a', 'one two three four']),
              row(['b', 'x']),
            ],
          ),
        ),
      ),
    );
    // The flex column gets 20 - 4 - 1 = 15 cells and wraps.
    expect(t.screen.lines.take(4), [
      'a    one two three',
      '     four',
      'b    x',
      'under',
    ]);
  });

  testWidgets('equal flex columns share the width, the rest in order', (
    t,
  ) async {
    await t.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 11,
          child: Table(
            children: [
              TableRow(
                children: [
                  Text('aaaaaaaaaa', softWrap: false),
                  Text('bbbbbbbbbb', softWrap: false),
                  Text('cccccccccc', softWrap: false),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    expect(t.screen.lines.first, 'aaaabbbbccc');
  });

  testWidgets('too narrow: flex gets nothing and the table is clipped', (
    t,
  ) async {
    await t.pumpWidget(
      Column(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 8,
              child: Table(
                columnWidths: const {
                  0: FixedColumnWidth(6),
                  1: FixedColumnWidth(6),
                },
                children: [
                  row(['abcdef', 'ghijkl']),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    expect(t.screen.lines.first, 'abcdefgh');
  });

  testWidgets('a cell cuts its own text with an ellipsis', (t) async {
    await t.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 10,
          child: Table(
            columnWidths: const {0: FixedColumnWidth(6)},
            children: [
              TableRow(
                children: [
                  Text(
                    'a long name',
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  Text('end'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    expect(t.screen.lines.first, 'a lon…end');
  });

  testWidgets('wide graphemes are measured in cells', (t) async {
    await t.pumpWidget(
      loose(
        Table(
          columnGap: 1,
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            row(['日本', 'x']),
            row(['a', 'y']),
          ],
        ),
      ),
    );
    expect(t.screen.lines.take(2), ['日本 x', 'a    y']);
  });

  testWidgets('a grid draws edges, separators and padding', (t) async {
    await t.pumpWidget(
      loose(
        Table(
          border: const TableBorder.all(),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            row(['Name', 'Kind']),
            row(['a', 'two\nlines']),
          ],
        ),
      ),
    );
    expect(t.screen.lines.take(6), [
      '┌──────┬───────┐',
      '│ Name │ Kind  │',
      '│ a    │ two   │',
      '│      │ lines │',
      '└──────┴───────┘',
      'under',
    ]);
    expect(t.screen.styleAt(0, 0), ThemeData.dark().border);
  });

  testWidgets('no rows draw nothing', (t) async {
    await t.pumpWidget(loose(Table()));
    expect(t.screen.lines.first, 'under');
    await t.pumpWidget(loose(Table(border: const TableBorder.all())));
    expect(t.screen.lines.first, 'under');
  });

  test('a ragged row is rejected', () {
    expect(
      () => Table(
        children: [
          row(['a', 'b']),
          row(['c']),
        ],
      ),
      throwsArgumentError,
    );
  });

  testWidgets('keyed rows keep their cells\' state when they move', (t) async {
    final first = TextEditingController(text: 'one');
    final order = ValueNotifier(true);
    TableRow keyed(String k) => TableRow(
      key: ValueKey(k),
      children: [
        Text(k),
        _Counter(label: k),
      ],
    );
    await t.pumpWidget(
      ListenableBuilder(
        listenable: order,
        builder: (_) => loose(
          Table(
            columnGap: 1,
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: order.value
                ? [keyed('a'), keyed('b')]
                : [keyed('b'), keyed('a')],
          ),
        ),
      ),
    );
    expect(t.screen.lines.take(2), ['a a0', 'b b0']);
    _Counter.bump('a');
    await t.pump();
    expect(t.screen.lines.first, 'a a1');
    order.value = false;
    await t.pump();
    expect(t.screen.lines.take(2), ['b b0', 'a a1']);
    first.dispose();
  });
}

class _Counter extends StatefulWidget {
  const _Counter({required this.label});

  final String label;

  static final _states = <String, _CounterState>{};

  static void bump(String label) => _states[label]!.bump();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var n = 0;

  @override
  void initState() {
    super.initState();
    _Counter._states[widget.label] = this;
  }

  void bump() => setState(() => n++);

  @override
  Widget build(BuildContext context) => Text('${widget.label}$n');
}

void testerEdges() {
  group('tester: Table boundaries and keyed resource lifetime', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('grid recovers from zero/one cells with Unicode at $size', (
        t,
      ) async {
        await t.pumpWidget(
          Table(
            border: const TableBorder.all(),
            columnWidths: const {0: FixedColumnWidth(5)},
            children: [
              row(['界🙂e\u0301', '\x1b[31mR\x1b[0m']),
            ],
          ),
          size: size,
        );
        expect(t.screen.charAt(2, 1), '界');
        expect(t.screen.charAt(4, 1), '🙂');
        expect(t.screen.charAt(6, 1), 'e\u0301');
        for (final next in const [Size.zero, Size(1, 1), Size(5, 2)]) {
          await t.resize(next);
          expect(t.screen.buffer.size, next);
        }
        await t.resize(size);
        expect(t.screen.charAt(2, 1), '界');
        expect(t.screen.charAt(4, 1), '🙂');
        expect(t.screen.charAt(10, 1), 'R');
      });
      testWidgets('wide glyphs do not spill across cell boundaries at $size', (
        t,
      ) async {
        await t.pumpWidget(
          loose(
            Table(
              columnGap: 1,
              columnWidths: const {
                0: FixedColumnWidth(3),
                1: FixedColumnWidth(3),
              },
              children: [
                TableRow(
                  children: [
                    Text('🙂界', softWrap: false),
                    Text('e\u0301🙂界', softWrap: false),
                  ],
                ),
              ],
            ),
          ),
          size: size,
        );
        expect(t.screen.charAt(0, 0), '🙂');
        expect(t.screen.charAt(2, 0), ' ');
        expect(t.screen.charAt(3, 0), ' ');
        expect(t.screen.charAt(4, 0), 'e\u0301');
        expect(t.screen.charAt(5, 0), '🙂');
        expect(t.screen.lines[1], 'under');
      });
    }
    testWidgets('both unbounded axes use natural flex and intrinsic widths', (
      t,
    ) async {
      await t.pumpWidget(
        Row(
          children: [
            Column(
              children: [
                Table(
                  columnGap: 1,
                  columnWidths: const {0: IntrinsicColumnWidth()},
                  children: [
                    row(['界🙂', 'xy']),
                    row(['a', 'long']),
                  ],
                ),
                Text('after'),
              ],
            ),
          ],
        ),
      );
      expect(t.screen.lines.take(3), ['界🙂 xy', 'a    long', 'after']);
    });
    testWidgets('keyed rows keep draft focus and live resources when moved', (
      t,
    ) async {
      final order = ValueNotifier(['a', 'b', 'c']);
      final stream = StreamController<int>.broadcast(sync: true);
      final probe = _TesterTableProbe(stream);
      addTearDown(order.dispose);
      addTearDown(stream.close);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: order,
          builder: (_) => Table(
            columnWidths: const {
              0: FixedColumnWidth(3),
              1: FixedColumnWidth(12),
            },
            children: [
              for (final label in order.value)
                TableRow(
                  key: ValueKey(label),
                  children: [Text(label), _TesterTableCell(label, probe)],
                ),
            ],
          ),
        ),
      );
      final saved = Map.of(probe.states);
      final a = saved['a']!;
      a.node.requestFocus();
      await t.paste('界🙂e\u0301');
      order.value = ['c', 'a', 'b'];
      await t.pump();
      await t.resize(const Size(120, 40));
      await t.resize(const Size(80, 24));
      expect(t.focusManager.primaryFocus, a.node);
      expect(a.editing.text, '界🙂e\u0301');
      for (final label in saved.keys) {
        expect(probe.states[label], same(saved[label]));
      }
      for (var i = 1; i <= 1000; i++) {
        stream.add(i);
      }
      await t.pump();
      expect(t.screen, shows('event 1000'));
      expect(a.editing.text, '界🙂e\u0301');
      order.value = ['c', 'b'];
      await t.pump();
      expect(a.timer.isActive, isFalse);
      expect(a.disposed, isTrue);
      order.value = [];
      await t.pump();
      expect(stream.hasListener, isFalse);
      for (final state in saved.values) {
        expect(state.timer.isActive, isFalse);
        expect(state.disposed, isTrue);
      }
      stream.add(1001);
      await t.pump();
      expect(t.screen.text, isEmpty);
    });
  });
}

class _TesterTableProbe {
  _TesterTableProbe(this.stream);
  final StreamController<int> stream;
  final states = <String, _TesterTableCellState>{};
}

class _TesterTableCell extends StatefulWidget {
  const _TesterTableCell(this.label, this.probe);
  final String label;
  final _TesterTableProbe probe;
  @override
  State<_TesterTableCell> createState() => _TesterTableCellState();
}

class _TesterTableCellState extends State<_TesterTableCell> {
  final editing = TextEditingController();
  final node = FocusNode();
  late final StreamSubscription<int> subscription;
  late final Timer timer;
  var value = 0;
  var disposed = false;
  @override
  void initState() {
    super.initState();
    widget.probe.states[widget.label] = this;
    subscription = widget.probe.stream.stream.listen(
      (n) => setState(() => value = n),
    );
    timer = Timer.periodic(const Duration(days: 1), (_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextInput(controller: editing, focusNode: node),
      Text('event $value'),
    ],
  );
  @override
  void dispose() {
    subscription.cancel();
    timer.cancel();
    editing.dispose();
    node.dispose();
    disposed = true;
    super.dispose();
  }
}
