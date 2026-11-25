import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// [rows] numbered lines.
Widget body(int rows) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [for (var i = 1; i <= rows; i++) Text('line $i')],
);

/// [child] in the top [rows] rows of the screen, with a marker under it.
Widget inRows(int rows, Widget child) => Column(
  children: [
    SizedBox(height: rows, child: child),
    Text('under'),
  ],
);

void main() {
  testerEdges();
  focusCases();
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('closed shows the header, open the body, at $size', (t) async {
      final open = ValueNotifier(false);
      await t.pumpWidget(
        Column(
          children: [
            ListenableBuilder(
              listenable: open,
              builder: (_) =>
                  Fold(title: 'Read file', open: open.value, child: body(3)),
            ),
            Text('after'),
          ],
        ),
        size: size,
      );
      expect(t.screen.lines.take(2), ['▸ Read file', 'after']);
      final dark = ThemeData.dark();
      expect(t.screen.styleAt(0, 0), dark.dim);
      expect(t.screen.styleAt(2, 0), dark.text);
      open.value = true;
      await t.pump();
      expect(t.screen.lines.take(5), [
        '▾ Read file',
        'line 1',
        'line 2',
        'line 3',
        'after',
      ]);
    });
  }

  testWidgets('a body taller than the room folds under a count', (t) async {
    await t.pumpWidget(
      inRows(5, Fold(title: 'Output', open: true, child: body(10))),
    );
    expect(t.screen.lines.take(6), [
      '▾ Output',
      'line 1',
      'line 2',
      'line 3',
      '  … 7 more lines',
      'under',
    ]);
    expect(t.screen.styleAt(4, 4), ThemeData.dark().dim);
  });

  testWidgets('one hidden line is counted in the singular', (t) async {
    await t.pumpWidget(
      inRows(4, Fold(title: 'Output', open: true, child: body(4))),
    );
    expect(t.screen.lines.take(5), [
      '▾ Output',
      'line 1',
      'line 2',
      '  … 2 more lines',
      'under',
    ]);
    await t.pumpWidget(
      inRows(5, Fold(title: 'Output', open: true, child: body(5))),
    );
    expect(t.screen.lines[4], '  … 2 more lines');
    await t.pumpWidget(
      inRows(3, Fold(title: 'Output', open: true, child: body(2))),
    );
    expect(t.screen.lines.take(3), ['▾ Output', 'line 1', 'line 2']);
  });

  testWidgets('one body row shows only the count, none shows nothing', (
    t,
  ) async {
    await t.pumpWidget(
      inRows(2, Fold(title: 'Output', open: true, child: body(10))),
    );
    expect(t.screen.lines.take(3), ['▾ Output', '  … 10 more lines', 'under']);
    await t.pumpWidget(
      inRows(1, Fold(title: 'Output', open: true, child: body(10))),
    );
    expect(t.screen.lines.take(2), ['▾ Output', 'under']);
    await t.pumpWidget(
      inRows(0, Fold(title: 'Output', open: true, child: body(10))),
    );
    expect(t.screen.lines.first, 'under');
  });

  testWidgets('an empty body adds no row', (t) async {
    await t.pumpWidget(
      Column(
        children: [
          Fold(title: 'Nothing', open: true, child: body(0)),
          Text('after'),
        ],
      ),
    );
    expect(t.screen.lines.take(2), ['▾ Nothing', 'after']);
  });

  testWidgets('wrapped rows are counted at the width it gets', (t) async {
    final width = ValueNotifier(40);
    await t.pumpWidget(
      ListenableBuilder(
        listenable: width,
        builder: (_) => Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width.value,
            height: 3,
            child: Fold(
              title: 'Wrapped',
              open: true,
              child: Text('word ' * 20),
            ),
          ),
        ),
      ),
    );
    // 100 cells: three rows at 40, so one shown and two counted.
    expect(t.screen.lines[2], '  … 2 more lines');
    width.value = 20;
    await t.pump();
    expect(t.screen.lines[2], '  … 4 more lines');
  });

  testWidgets('a long title and count are cut at the right edge', (t) async {
    await t.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 12,
          height: 2,
          child: Fold(title: 'A very long title', open: true, child: body(9)),
        ),
      ),
    );
    expect(t.screen.lines.take(2), ['▾ A very lo…', '  … 9 more …']);
  });

  testWidgets('a wide grapheme at the edge is not split', (t) async {
    await t.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 5,
          height: 2,
          child: Fold(
            title: 'x',
            open: true,
            child: Text('ab漢字', softWrap: false),
          ),
        ),
      ),
    );
    expect(t.screen.lines[1], 'ab漢');
    expect(t.screen.charAt(4, 1), ' ');
  });

  testWidgets('a closed body keeps its state and is not laid out', (t) async {
    final open = ValueNotifier(true);
    final controller = TextEditingController(text: 'kept');
    await t.pumpWidget(
      ListenableBuilder(
        listenable: open,
        builder: (_) => Fold(
          title: 'Input',
          open: open.value,
          child: TextInput(controller: controller),
        ),
      ),
    );
    expect(t.screen.lines[1], 'kept');
    open.value = false;
    await t.pump();
    expect(t.screen.lines.take(2), ['▸ Input', '']);
    open.value = true;
    await t.pump();
    expect(t.screen.lines[1], 'kept');
  });
}

/// An outer binding over a fold whose body is the only thing that could
/// take keys: its own binding and a Focus that takes keys and pastes.
Widget soleBody(ValueNotifier<bool> open, List<String> log) => Actions(
  bindings: [Binding('ctrl+q', 'Outer', () => log.add('outer'))],
  child: ListenableBuilder(
    listenable: open,
    builder: (_) => Fold(
      title: 'Body',
      open: open.value,
      child: Actions(
        bindings: [Binding('x', 'Inner', () => log.add('inner'))],
        child: Focus(
          autofocus: true,
          onKey: (e) {
            log.add('key ${e.combo}');
            return true;
          },
          onPaste: (text) {
            log.add('paste');
            return true;
          },
          child: Text('body'),
        ),
      ),
    ),
  ),
);

void focusCases() {
  testWidgets('a closed sole body takes no keys, pastes or bindings', (
    t,
  ) async {
    final log = <String>[];
    await t.pumpWidget(soleBody(ValueNotifier(false), log));
    await t.press('x');
    await t.type('a');
    await t.paste('p');
    await t.press('ctrl+q');
    expect(log, ['outer']);
    expect(t.focusManager.activeBindings.map((b) => b.description), ['Outer']);
  });

  testWidgets('a sole body collapsed while focused lets go of keys', (t) async {
    final log = <String>[];
    final open = ValueNotifier(true);
    await t.pumpWidget(soleBody(open, log));
    await t.type('a');
    expect(log, ['key a']);
    open.value = false;
    await t.pump();
    log.clear();
    await t.press('x');
    await t.type('a');
    await t.paste('p');
    await t.press('ctrl+q');
    expect(log, ['outer']);
  });

  testWidgets('a closed body gives up focus, an open one can take it', (
    t,
  ) async {
    final open = ValueNotifier(true);
    final outside = FocusNode(debugLabel: 'outside');
    final inside = FocusNode(debugLabel: 'inside');
    await t.pumpWidget(
      Column(
        children: [
          Focus(focusNode: outside, child: Text('outside')),
          ListenableBuilder(
            listenable: open,
            builder: (_) => Fold(
              title: 'Body',
              open: open.value,
              child: Focus(focusNode: inside, child: Text('inside')),
            ),
          ),
        ],
      ),
    );
    outside.requestFocus();
    await t.pump();
    inside.requestFocus();
    await t.pump();
    expect(t.focusManager.primaryFocus, inside);
    open.value = false;
    await t.pump();
    expect(t.focusManager.primaryFocus, outside, reason: 'the most recent');
    inside.requestFocus();
    await t.press('tab');
    expect(t.focusManager.primaryFocus, outside, reason: 'Tab skips it');
    open.value = true;
    await t.pump();
    await t.press('tab');
    expect(t.focusManager.primaryFocus, inside);
    outside.dispose();
    inside.dispose();
  });

  testWidgets('with nothing else to take it, focus is cleared', (t) async {
    final open = ValueNotifier(true);
    final inside = FocusNode(debugLabel: 'inside');
    await t.pumpWidget(
      ListenableBuilder(
        listenable: open,
        builder: (_) => Fold(
          title: 'Body',
          open: open.value,
          child: Focus(focusNode: inside, autofocus: true, child: Text('in')),
        ),
      ),
    );
    expect(t.focusManager.primaryFocus, inside);
    open.value = false;
    await t.pump();
    expect(t.focusManager.primaryFocus, isNull);
    inside.dispose();
  });

  testWidgets('an autofocus in a closed body does not take focus', (t) async {
    await t.pumpWidget(
      Fold(
        title: 'Body',
        open: false,
        child: Focus(autofocus: true, debugLabel: 'in', child: Text('in')),
      ),
    );
    expect(t.focusManager.primaryFocus, isNull);
  });
}

void testerEdges() {
  group('tester: Fold constraints and retained lifecycle', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('zero and one cell recover without losing draft at $size', (
        t,
      ) async {
        final editing = TextEditingController(text: '界🙂e\u0301');
        addTearDown(editing.dispose);
        await t.pumpWidget(
          Fold(
            title: '界🙂e\u0301',
            open: true,
            child: TextInput(controller: editing, autofocus: true),
          ),
          size: size,
        );
        for (final next in [Size.zero, const Size(1, 1), size]) {
          await t.resize(next);
          expect(t.screen.buffer.size, next);
        }
        expect(t.screen.lines.first, '▾ 界🙂e\u0301');
        expect(t.screen.lines[1], '界🙂e\u0301');
        expect(editing.text, '界🙂e\u0301');
      });

      testWidgets('ANSI and graphemes remain inside folded body at $size', (
        t,
      ) async {
        await t.pumpWidget(
          Column(
            children: [
              SizedBox(
                height: 4,
                child: Fold(
                  title: '界🙂e\u0301',
                  open: true,
                  child: Column(
                    children: [
                      Text('界🙂e\u0301\x1b[31mR\x1b[0m'),
                      Row(children: [const Spacer(), Text('e\u0301🙂界')]),
                      Text('hidden 1'),
                      Text('hidden 2'),
                    ],
                  ),
                ),
              ),
              Text('protected'),
            ],
          ),
          size: size,
        );
        expect(t.screen.lines[1], '界🙂e\u0301R');
        expect(t.screen.charAt(size.width - 2, 2), '界');
        expect(t.screen.lines[3], '  … 2 more lines');
        expect(t.screen.lines[4], 'protected');
        expect(t.screen.text, isNot(contains('hidden')));
      });

      testWidgets(
        'nested exclusions keep hidden fields out of traversal at $size',
        (t) async {
          final outer = ValueNotifier(true), inner = ValueNotifier(false);
          final inside = FocusNode(debugLabel: 'inside');
          final outside = FocusNode(debugLabel: 'outside');
          addTearDown(outer.dispose);
          addTearDown(inner.dispose);
          addTearDown(inside.dispose);
          addTearDown(outside.dispose);
          await t.pumpWidget(
            Column(
              children: [
                Focus(
                  focusNode: outside,
                  autofocus: true,
                  child: Text('outside'),
                ),
                ListenableBuilder(
                  listenable: outer,
                  builder: (_) => Fold(
                    title: 'outer',
                    open: outer.value,
                    child: ListenableBuilder(
                      listenable: inner,
                      builder: (_) => Fold(
                        title: 'inner',
                        open: inner.value,
                        child: Focus(focusNode: inside, child: Text('inside')),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            size: size,
          );
          inside.requestFocus();
          await t.pump();
          expect(t.focusManager.primaryFocus, outside);
          outer.value = false;
          inner.value = true;
          await t.pump();
          inside.requestFocus();
          await t.pump();
          expect(t.focusManager.primaryFocus, outside);
          outer.value = true;
          await t.pump();
          expect(
            t.focusManager.primaryFocus,
            outside,
            reason: 'hidden requests are not deferred',
          );
          await t.press('tab');
          expect(t.focusManager.primaryFocus, inside);
          inner.value = false;
          await t.pump();
          expect(t.focusManager.primaryFocus, outside);
          await t.press('shift+tab');
          expect(t.focusManager.primaryFocus, outside);
        },
      );
    }

    testWidgets('unbounded axes use finite natural child and header sizes', (
      t,
    ) async {
      await t.pumpWidget(
        Row(
          children: [
            Column(
              children: [
                Fold(title: 'x', open: true, child: Text('longer child')),
                Text('after'),
              ],
            ),
          ],
        ),
      );
      expect(t.screen.lines.take(3), ['▾ x', 'longer child', 'after']);
    });

    testWidgets(
      'closed retained stream coalesces updates and cancels on removal',
      (t) async {
        final stream = StreamController<int>.broadcast(sync: true);
        final open = ValueNotifier(true), present = ValueNotifier(true);
        final probe = _TesterFoldProbe(stream);
        addTearDown(stream.close);
        addTearDown(open.dispose);
        addTearDown(present.dispose);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: present,
            builder: (_) => present.value
                ? ListenableBuilder(
                    listenable: open,
                    builder: (_) => Fold(
                      title: 'Stream',
                      open: open.value,
                      child: _TesterFoldStream(probe),
                    ),
                  )
                : Text('removed'),
          ),
        );
        expect(probe.mounts, 1);
        open.value = false;
        await t.pump();
        for (var i = 1; i <= 1000; i++) {
          stream.add(i);
        }
        await t.pump();
        expect(t.screen.lines.first, '▸ Stream');
        expect(t.screen.text, isNot(contains('value')));
        expect(stream.hasListener, isTrue);
        expect(probe.timer!.isActive, isTrue);
        open.value = true;
        await t.pump();
        expect(t.screen.lines[1], 'value 1000');
        expect(probe.mounts, 1);
        open.value = false;
        await t.pump();
        present.value = false;
        await t.pump();
        expect(stream.hasListener, isFalse);
        expect(probe.timer!.isActive, isFalse);
        stream.add(1001);
        await t.pump();
        expect(t.screen.lines.first, 'removed');
      },
    );
  });
}

class _TesterFoldProbe {
  _TesterFoldProbe(this.stream);
  final StreamController<int> stream;
  Timer? timer;
  var mounts = 0;
}

class _TesterFoldStream extends StatefulWidget {
  const _TesterFoldStream(this.probe);
  final _TesterFoldProbe probe;
  @override
  State<_TesterFoldStream> createState() => _TesterFoldStreamState();
}

class _TesterFoldStreamState extends State<_TesterFoldStream> {
  late final StreamSubscription<int> subscription;
  var value = 0;
  @override
  void initState() {
    super.initState();
    widget.probe.mounts++;
    subscription = widget.probe.stream.stream.listen(
      (n) => setState(() => value = n),
    );
    widget.probe.timer = Timer.periodic(
      const Duration(days: 1),
      (_) => setState(() {}),
    );
  }

  @override
  Widget build(BuildContext context) => Text('value $value');
  @override
  void dispose() {
    subscription.cancel();
    widget.probe.timer!.cancel();
    super.dispose();
  }
}
