import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const allow = [
  PickerItem(value: 'once', label: 'Allow once'),
  PickerItem(value: 'reject', label: 'Reject'),
];

/// A dialog at the bottom of [height] rows, with what it gave in [log].
Widget at(
  int height,
  List<String> log, {
  List<PickerItem<String>> choices = allow,
  String body = 'Run the requested command in this session.',
  Widget? hint,
}) => Column(
  children: [
    SizedBox(
      height: height,
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Dialog<String>(
          title: Text('Allow command?'),
          choices: choices,
          onSelected: log.add,
          onCanceled: () => log.add('close'),
          hint: hint,
          child: Text(body),
        ),
      ),
    ),
    Text('under'),
  ],
);

List<String> keys(WidgetTester t) => [
  for (final b in t.focusManager.activeBindings) '${b.chord} ${b.description}',
];

/// [rows] without the frame's sides.
List<String> inside(List<String> rows) => [
  for (final r in rows)
    r.startsWith('│') ? r.substring(2, r.length - 1).trimRight() : r,
];

void main() {
  testerEdges();
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('title, body, choices and hint at $size', (t) async {
      final log = <String>[];
      await t.pumpWidget(at(9, log), size: size);
      final rows = t.screen.lines.take(10).toList();
      expect(rows.first, '╭${'─' * (size.width - 2)}╮');
      expect(inside(rows.sublist(1, 8)), [
        'Allow command?',
        'Run the requested command in this session.',
        '',
        '❯ 1. Allow once',
        '  2. Reject',
        '',
        '↑↓ or j/k to move · Enter or 1–9 to select · Esc to close',
      ]);
      expect(rows[8], '╰${'─' * (size.width - 2)}╯');
      expect(rows[9], 'under');
      final dark = ThemeData.dark();
      expect(t.screen.styleAt(0, 0), dark.focus);
      expect(t.screen.styleAt(2, 1), dark.focus.merge(Style.bold));
      expect(t.screen.styleAt(2, 7), dark.dim);
    });
  }

  testWidgets('up and down go round, Enter and numbers choose', (t) async {
    final log = <String>[];
    await t.pumpWidget(at(9, log));
    await t.press('up');
    expect(t.screen.lines[5], '│ ❯ 2. Reject${' ' * 66}│');
    await t.press('j');
    expect(t.screen.lines[4], startsWith('│ ❯ 1. Allow once'));
    await t.press('k');
    await t.press('enter');
    await t.press('1');
    await t.press('esc');
    expect(log, ['reject', 'once', 'close']);
    expect(keys(t), [
      'up Previous choice',
      'k Previous choice',
      'down Next choice',
      'j Next choice',
      'enter Choose highlighted item',
      '1 Choose item 1',
      '2 Choose item 2',
      'escape Close dialog',
    ]);
  });

  testWidgets('a long body folds under a count', (t) async {
    final log = <String>[];
    await t.pumpWidget(at(10, log, body: 'a\nb\nc\nd'));
    expect(inside(t.screen.lines.sublist(1, 9)), [
      'Allow command?',
      'a',
      '  … 3 more lines',
      '',
      '❯ 1. Allow once',
      '  2. Reject',
      '',
      '↑↓ or j/k to move · Enter or 1–9 to select · Esc to close',
    ]);
    expect(t.screen.styleAt(4, 3), ThemeData.dark().dim);
  });

  testWidgets('short room drops the body, then the hint, keeping choices', (
    t,
  ) async {
    final log = <String>[];
    await t.pumpWidget(at(7, log));
    expect(inside(t.screen.lines.sublist(1, 6)), [
      'Allow command?',
      '❯ 1. Allow once',
      '  2. Reject',
      '',
      '↑↓ or j/k to move · Enter or 1–9 to select · Esc to close',
    ]);
    await t.pumpWidget(at(5, log));
    expect(inside(t.screen.lines.sublist(1, 4)), [
      'Allow command?',
      '❯ 1. Allow once',
      '  2. Reject',
    ]);
  });

  testWidgets('clipped choices take no numbers, none take no keys', (t) async {
    final log = <String>[];
    await t.pumpWidget(at(4, log));
    expect(inside(t.screen.lines.sublist(1, 2)), ['Allow command?']);
    expect(t.screen.lines[2], startsWith('│ ❯ 1. Allow once'));
    await t.press('2');
    expect(log, isEmpty);
    expect(keys(t), isNot(contains('2 Choose item 2')));
    await t.pumpWidget(at(3, log));
    await t.press('enter');
    await t.press('1');
    expect(log, isEmpty);
    expect(keys(t), ['escape Close dialog']);
  });

  testWidgets('with no rows nothing paints and only Esc acts', (t) async {
    final log = <String>[];
    await t.pumpWidget(at(2, log));
    expect(t.screen.lines.take(3), ['', '', 'under']);
    await t.press('enter');
    await t.press('esc');
    expect(log, ['close']);
  });

  testWidgets('without choices it is a notice that Esc closes', (t) async {
    final log = <String>[];
    await t.pumpWidget(at(6, log, choices: const []));
    expect(inside(t.screen.lines.sublist(1, 5)), [
      'Allow command?',
      'Run the requested command in this session.',
      '',
      'Esc to close',
    ]);
    await t.press('enter');
    await t.press('1');
    expect(log, isEmpty);
    expect(keys(t), ['escape Close dialog']);
  });

  testWidgets('a hint replaces the words, not the keys', (t) async {
    final log = <String>[];
    await t.pumpWidget(at(9, log, hint: Text('Enter to choose')));
    expect(t.screen.lines[7], startsWith('│ Enter to choose '));
    await t.press('2');
    expect(log, ['reject']);
  });

  testWidgets('without focus the frame is the border and no row is lit', (
    t,
  ) async {
    final log = <String>[];
    final other = FocusNode(debugLabel: 'other');
    await t.pumpWidget(
      Column(
        children: [
          Focus(focusNode: other, child: Text('elsewhere')),
          Expanded(child: at(9, log)),
        ],
      ),
    );
    expect(t.screen.styleAt(0, 1), ThemeData.dark().focus);
    other.requestFocus();
    await t.pump();
    expect(t.screen.styleAt(0, 1), ThemeData.dark().border);
    expect(t.screen, isNot(shows('❯')));
    other.dispose();
  });

  testWidgets('a long title ends in an ellipsis on one row', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 16,
          height: 9,
          child: Dialog<String>(
            title: Text('Allow 日本語 command?'),
            choices: allow,
            onSelected: log.add,
            onCanceled: () {},
            child: Text('body'),
          ),
        ),
      ),
    );
    // Twelve cells inside: 'Allow 日本…' is eleven; 語 would not fit.
    expect(t.screen.lines[1], '│ Allow 日本…  │');
    expect(t.screen.lines[2], startsWith('│ body'));
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('in a layer with one or two rows it hides and lets go, $size', (
      t,
    ) async {
      final log = <String>[];
      final link = LayerLink();
      final above = ValueNotifier(2);
      await t.pumpWidget(
        Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => ListenableBuilder(
                listenable: above,
                builder: (_) => Column(
                  children: [
                    SizedBox(height: above.value),
                    CompositedTransformTarget(
                      link: link,
                      child: const SizedBox(height: 0),
                    ),
                    Focus(
                      autofocus: true,
                      debugLabel: 'prompt',
                      child: Text('> prompt'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        size: size,
      );
      final overlay = (() {
        OverlayState? found;
        void walk(Element e) {
          if (e is StatefulElement && e.state is OverlayState) {
            found = e.state as OverlayState;
          }
          e.visitChildren(walk);
        }

        walk(t.host.rootElement);
        return found!;
      })();
      overlay.insert(
        OverlayEntry(
          builder: (_) => CompositedTransformFollower(
            link: link,
            followerAnchor: Alignment.bottomLeft,
            child: Dialog<String>(
              title: Text('Allow command?'),
              choices: allow,
              onSelected: log.add,
              onCanceled: () => log.add('close'),
              child: Text('body'),
            ),
          ),
        ),
      );
      await t.pump();
      for (final rows in [2, 1]) {
        above.value = rows;
        await t.pump();
        expect(t.screen, isNot(shows('╭')), reason: '$rows rows');
        expect(t.focusManager.primaryFocus?.debugLabel, 'prompt');
        expect(keys(t), isNot(contains('escape Close dialog')));
        await t.press('esc');
        await t.press('1');
        expect(log, isEmpty);
      }
      above.value = 9;
      await t.pump();
      expect(t.screen, shows('│ Allow command?'));
      expect(t.focusManager.primaryFocus?.debugLabel, 'dialog');
      await t.press('2');
      expect(log, ['reject']);
    });
  }

  testWidgets('moves go round only the choices with rows', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      at(
        5,
        log,
        choices: const [
          PickerItem(value: 'a', label: 'A'),
          PickerItem(value: 'b', label: 'B'),
          PickerItem(value: 'c', label: 'C'),
        ],
      ),
    );
    // Three rows inside: the title and two choices; C has none.
    await t.press('up');
    expect(t.screen.lines[3], startsWith('│ ❯ 2. B'));
    await t.press('down');
    expect(t.screen.lines[2], startsWith('│ ❯ 1. A'));
    await t.press('3');
    expect(log, isEmpty);
  });
}

void testerEdges() {
  group('tester: Dialog dynamic choices and resize boundaries', () {
    testWidgets('unmount disposes a body with a live stream and timer', (
      t,
    ) async {
      final stream = StreamController<int>.broadcast(sync: true);
      final probe = _TesterDialogResourceProbe(stream);
      addTearDown(stream.close);
      await t.pumpWidget(
        Dialog(
          title: Text('live'),
          onCanceled: () {},
          child: _TesterDialogLive(probe),
        ),
      );
      expect(stream.hasListener, isTrue);
      expect(probe.timer!.isActive, isTrue);
      for (var i = 1; i <= 1000; i++) {
        stream.add(i);
      }
      await t.pump();
      expect(t.screen, shows('event 1000'));
      await t.pumpWidget(Text('removed'));
      expect(stream.hasListener, isFalse);
      expect(probe.timer!.isActive, isFalse);
      stream.add(1001);
      await t.pump();
      expect(t.screen.text, 'removed');
    });

    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'choice shrink resets hidden selection and rejects stale numbers at $size',
        (t) async {
          final log = <String>[];
          final height = ValueNotifier(9);
          addTearDown(height.dispose);
          await t.pumpWidget(
            ListenableBuilder(
              listenable: height,
              builder: (_) => at(height.value, log),
            ),
            size: size,
          );
          await t.press('down');
          height.value = 4;
          await t.pump();
          await t.press('2');
          expect(log, isEmpty);
          await t.press('up');
          await t.press('enter');
          expect(log, ['once']);
          height.value = 3;
          await t.pump();
          await t.press('1');
          await t.press('enter');
          await t.press('j');
          expect(log, ['once']);
          height.value = 9;
          await t.pump();
          expect(log, ['once']);
          await t.press('down');
          await t.press('enter');
          expect(log, ['once', 'reject']);
        },
      );
      testWidgets(
        'a thousand choice replacements accept only current values at $size',
        (t) async {
          final log = <String>[];
          final choices = ValueNotifier(allow);
          addTearDown(choices.dispose);
          await t.pumpWidget(
            ListenableBuilder(
              listenable: choices,
              builder: (_) => at(9, log, choices: choices.value),
            ),
            size: size,
          );
          await t.press('down');
          for (var i = 0; i < 1000; i++) {
            choices.value = [
              PickerItem(value: 'new$i', label: '界🙂e\u0301 $i'),
            ];
          }
          await t.pump();
          await t.press('2');
          expect(log, isEmpty);
          await t.press('enter');
          expect(log, ['new999']);
          expect(t.screen, shows('界🙂e\u0301 999'));
          choices.value = [];
          await t.pump();
          await t.press('enter');
          expect(log, ['new999']);
          await t.press('esc');
          expect(log, ['new999', 'close']);
        },
      );
      testWidgets(
        'focus loss and return preserves highlighted choice at $size',
        (t) async {
          final log = <String>[];
          final outside = FocusNode();
          addTearDown(outside.dispose);
          await t.pumpWidget(
            Column(
              children: [
                Focus(focusNode: outside, child: Text('outside')),
                Expanded(child: at(9, log)),
              ],
            ),
            size: size,
          );
          await t.press('down');
          outside.requestFocus();
          await t.pump();
          expect(t.screen, isNot(shows('❯')));
          await t.press('enter');
          expect(log, isEmpty);
          await t.press('tab');
          await t.press('enter');
          expect(log, ['reject']);
        },
      );
      testWidgets(
        'removing the focused dialog drops callbacks and keys at $size',
        (t) async {
          final log = <String>[];
          final present = ValueNotifier(true);
          addTearDown(present.dispose);
          await t.pumpWidget(
            ListenableBuilder(
              listenable: present,
              builder: (_) => present.value ? at(9, log) : Text('removed'),
            ),
            size: size,
          );
          present.value = false;
          await t.pump();
          for (final key in [
            'enter',
            '1',
            '2',
            'esc',
            'tab',
            'shift+tab',
            'up',
            'down',
            'j',
            'k',
          ]) {
            await t.press(key);
          }
          await t.paste('late input');
          expect(log, isEmpty);
          expect(t.screen.text, 'removed');
        },
      );
    }
    testWidgets('unbounded height uses a finite dialog surface', (t) async {
      final log = <String>[];
      await t.pumpWidget(
        Column(
          children: [
            Dialog(
              title: Text('Title'),
              child: Text('Body'),
              choices: allow,
              onSelected: log.add,
              onCanceled: () {},
            ),
            Text('after'),
          ],
        ),
      );
      expect(t.screen, shows('Title'));
      expect(t.screen, shows('Body'));
      expect(t.screen, shows('after'));
      await t.press('2');
      expect(log, ['reject']);
    });
  });
}

class _TesterDialogResourceProbe {
  _TesterDialogResourceProbe(this.stream);
  final StreamController<int> stream;
  Timer? timer;
}

class _TesterDialogLive extends StatefulWidget {
  const _TesterDialogLive(this.probe);
  final _TesterDialogResourceProbe probe;
  @override
  State<_TesterDialogLive> createState() => _TesterDialogLiveState();
}

class _TesterDialogLiveState extends State<_TesterDialogLive> {
  late final StreamSubscription<int> subscription;
  var value = 0;
  @override
  void initState() {
    super.initState();
    subscription = widget.probe.stream.stream.listen(
      (n) => setState(() => value = n),
    );
    widget.probe.timer = Timer.periodic(
      const Duration(days: 1),
      (_) => setState(() {}),
    );
  }

  @override
  Widget build(BuildContext context) => Text('event $value');
  @override
  void dispose() {
    subscription.cancel();
    widget.probe.timer!.cancel();
    super.dispose();
  }
}
