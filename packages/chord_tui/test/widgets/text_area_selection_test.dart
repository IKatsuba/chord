import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// The draft of the CTUI-164 captures; the cursor goes before ` zeta`.
const _draft = 'alpha beta gamma\ndelta epsilon zeta';

const _selected = Style(bg: IndexedColor(66));

const _sizes = [Size(120, 40), Size(80, 24)];

/// An area holding [text], the cursor at [cursor], every editing key its
/// own, beside a key help and above an ancestor that records what reaches
/// it.
Future<(TextAreaController, List<String>)> _pump(
  WidgetTester t, {
  String text = _draft,
  int cursor = 30,
  Size size = const Size(120, 40),
  TextSpan Function(BuildContext, String)? spans,
}) async {
  final c = TextAreaController(text: text)..cursor = cursor;
  final reached = <String>[];
  await t.pumpWidget(
    Focus(
      onKey: (event) {
        reached.add(event.combo.toString());
        return true;
      },
      child: TextArea(
        controller: c,
        autofocus: true,
        unhandledKeys: const {},
        selectionStyle: _selected,
        textSpanBuilder: spans,
      ),
    ),
    size: size,
  );
  return (c, reached);
}

void main() {
  _testerSelectionWidgetCases();
  group('the new moves and edits', () {
    // Key, then the text, base and extent it leaves.
    const cases = <(String, String, int, int)>[
      ('ctrl+f', _draft, 31, 31),
      ('ctrl+b', _draft, 29, 29),
      ('ctrl+right', _draft, 35, 35),
      ('ctrl+left', _draft, 23, 23),
      ('alt+a', _draft, 17, 17),
      ('alt+e', _draft, 35, 35),
      ('home', _draft, 0, 0),
      ('super+up', _draft, 0, 0),
      ('end', _draft, 35, 35),
      ('super+down', _draft, 35, 35),
      ('ctrl+d', 'alpha beta gamma\ndelta epsilonzeta', 30, 30),
      ('shift+delete', 'alpha beta gamma\ndelta epsilonzeta', 30, 30),
      ('ctrl+backspace', 'alpha beta gamma\ndelta  zeta', 23, 23),
      ('alt+d', 'alpha beta gamma\ndelta epsilon', 30, 30),
      ('alt+delete', 'alpha beta gamma\ndelta epsilon', 30, 30),
      ('ctrl+delete', 'alpha beta gamma\ndelta epsilon', 30, 30),
      ('ctrl+shift+d', 'alpha beta gamma', 16, 16),
      ('shift+left', _draft, 30, 29),
      ('shift+right', _draft, 30, 31),
      ('shift+up', _draft, 30, 13),
      ('alt+shift+left', _draft, 30, 23),
      ('alt+shift+b', _draft, 30, 23),
      ('alt+shift+right', _draft, 30, 35),
      ('alt+shift+f', _draft, 30, 35),
      ('ctrl+shift+a', _draft, 30, 17),
      ('ctrl+shift+e', _draft, 30, 35),
      ('alt+shift+a', _draft, 30, 17),
      ('shift+super+left', _draft, 30, 17),
      ('alt+shift+e', _draft, 30, 35),
      ('shift+super+right', _draft, 30, 35),
      ('shift+home', _draft, 30, 0),
      ('shift+super+up', _draft, 30, 0),
      ('shift+end', _draft, 30, 35),
      ('shift+super+down', _draft, 30, 35),
      ('super+a', _draft, 0, 35),
    ];
    for (final size in _sizes) {
      for (final (key, text, base, extent) in cases) {
        testWidgets('$key at $size', (t) async {
          final (c, reached) = await _pump(t, size: size);
          await t.press(key);
          expect(reached, isEmpty);
          expect(c.text, text);
          expect(
            c.selection,
            TextSelection(baseOffset: base, extentOffset: extent),
          );
          for (final line in text.split('\n')) {
            expect(t.screen, shows(line));
          }
        });
      }
    }

    testWidgets('the undo and redo aliases', (t) async {
      final (c, _) = await _pump(t);
      for (final (undo, redo) in [
        ('ctrl+-', 'ctrl+.'),
        ('super+z', 'shift+super+z'),
      ]) {
        await t.type('x');
        expect(c.text, 'alpha beta gamma\ndelta epsilonx zeta');
        await t.press(undo);
        expect(c.text, _draft);
        await t.press(redo);
        expect(c.text, 'alpha beta gamma\ndelta epsilonx zeta');
        await t.press('backspace');
      }
    });

    testWidgets('shift+down on the last row goes on, untouched', (t) async {
      final (c, reached) = await _pump(t);
      await t.press('shift+down');
      expect(reached, ['shift+down']);
      expect(c.selection, const TextSelection.collapsed(offset: 30));
    });

    testWidgets('shift+up on the first row goes on, without onEdge', (t) async {
      final c = TextAreaController(text: 'abc')..cursor = 1;
      final edges = <TextAreaDirection>[];
      final reached = <String>[];
      await t.pumpWidget(
        Focus(
          onKey: (event) {
            reached.add(event.combo.toString());
            return true;
          },
          child: TextArea(controller: c, autofocus: true, onEdge: edges.add),
        ),
      );
      await t.press('shift+up');
      expect(reached, ['shift+up']);
      expect(edges, isEmpty);
      expect(c.hasSelection, isFalse);
    });

    testWidgets('home and end are left out by default; shift+home selects', (
      t,
    ) async {
      final c = TextAreaController(text: _draft)..cursor = 30;
      final reached = <String>[];
      await t.pumpWidget(
        Focus(
          onKey: (event) {
            reached.add(event.combo.toString());
            return true;
          },
          child: TextArea(controller: c, autofocus: true),
        ),
      );
      await t.press('home end shift+home');
      expect(reached, ['home', 'end']);
      expect(c.selection, const TextSelection(baseOffset: 30, extentOffset: 0));
    });

    testWidgets('editingKeys names every binding, with its description', (
      t,
    ) async {
      await t.pumpWidget(
        const Column(
          children: [
            // A middle row, so up and down and their selects can act.
            _MiddleRow(),
            KeyHelp(),
          ],
        ),
        size: const Size(4000, 4),
      );
      final byDescription = <String, List<String>>{};
      for (final MapEntry(:key, :value) in TextArea.editingKeys.entries) {
        expect(KeyCombo.parse(key).toString(), key);
        (byDescription[value] ??= []).add(key);
      }
      for (final MapEntry(:key, :value) in byDescription.entries) {
        expect(t.screen, shows('${value.join('/')} $key'));
      }
    });
  });

  group('after selecting all', () {
    testWidgets('typing replaces it', (t) async {
      final (c, _) = await _pump(t);
      await t.press('super+a');
      await t.type('|');
      expect(c.text, '|');
    });

    testWidgets('a paste replaces it', (t) async {
      final (c, _) = await _pump(t);
      await t.press('super+a');
      await t.paste('PASTED');
      expect((c.text, c.cursor), ('PASTED', 6));
    });

    testWidgets('down on the last row collapses and reaches onEdge', (t) async {
      final c = TextAreaController(text: _draft);
      final edges = <TextAreaDirection>[];
      await t.pumpWidget(
        TextArea(controller: c, autofocus: true, onEdge: edges.add),
      );
      await t.press('super+a down');
      expect(edges, [TextAreaDirection.down]);
      expect(c.hasSelection, isFalse);
    });

    testWidgets('left collapses to its start', (t) async {
      final (c, _) = await _pump(t);
      await t.press('super+a left');
      await t.type('L');
      expect(c.text, 'L$_draft');
    });
  });

  group('drawing', () {
    for (final size in _sizes) {
      testWidgets('paints the selected graphemes and no more at $size', (
        t,
      ) async {
        final (c, _) = await _pump(t, size: size);
        await t.press('super+a');
        for (var x = 0; x < 18; x++) {
          expect(t.screen.styleAt(x, 1).bg, x < 18 ? _selected.bg : null);
        }
        // Each line to its end; the break and what follows are bare.
        expect(t.screen.styleAt(15, 0).bg, _selected.bg);
        expect(t.screen.styleAt(16, 0).bg, isNull);
        expect(t.screen.styleAt(17, 1).bg, _selected.bg);
        expect(t.screen.styleAt(18, 1).bg, isNull);
        expect(c.selectedText, _draft);
      });

      testWidgets('a part selection at $size', (t) async {
        await _pump(t, size: size);
        await t.press('alt+shift+left');
        for (var x = 0; x < 20; x++) {
          final inside = x >= 6 && x < 13;
          expect(t.screen.styleAt(x, 1).bg, inside ? _selected.bg : null);
        }
        expect(t.screen.styleAt(0, 0).bg, isNull);
      });

      testWidgets('a selection across a wrapped line at $size', (t) async {
        final text = List.filled(30, 'word').join(' ');
        await _pump(t, text: text, cursor: 0, size: size);
        await t.press('shift+end');
        final width = size.width;
        final rest = text.length - width;
        expect(t.screen.styleAt(0, 0).bg, _selected.bg);
        expect(t.screen.styleAt(width - 1, 0).bg, _selected.bg);
        expect(t.screen.styleAt(0, 1).bg, _selected.bg);
        expect(t.screen.styleAt(rest - 1, 1).bg, _selected.bg);
        expect(t.screen.styleAt(rest, 1).bg, isNull);
      });

      testWidgets('a tab and a wide grapheme paint all their cells at $size', (
        t,
      ) async {
        await _pump(t, text: 'a\t界b', cursor: 0, size: size);
        await t.press('shift+right shift+right shift+right');
        for (var x = 0; x < 7; x++) {
          expect(t.screen.styleAt(x, 0).bg, _selected.bg);
        }
        expect(t.screen.styleAt(7, 0).bg, isNull);
      });

      testWidgets('spans of textSpanBuilder are kept under it at $size', (
        t,
      ) async {
        await _pump(
          t,
          text: 'ab cd',
          cursor: 0,
          size: size,
          spans: (context, text) => TextSpan(
            '',
            children: [
              TextSpan(text.substring(0, 2), style: Style.bold),
              TextSpan(text.substring(2)),
            ],
          ),
        );
        await t.press('shift+right');
        expect(t.screen.styleAt(0, 0).bg, _selected.bg);
        expect(t.screen.styleAt(0, 0).isBold, isTrue);
        expect(t.screen.styleAt(1, 0).bg, isNull);
        expect(t.screen.styleAt(1, 0).isBold, isTrue);
      });
    }

    testWidgets('kept unfocused; the theme\'s selection by default', (t) async {
      final c = TextAreaController(text: 'abc');
      final node = FocusNode();
      await t.pumpWidget(
        Theme(
          data: ThemeData.dark(),
          child: TextArea(controller: c, focusNode: node, autofocus: true),
        ),
      );
      await t.press('super+a');
      node.unfocus();
      await t.pump();
      expect(t.screen.styleAt(0, 0).bg, const IndexedColor(66));
      expect(t.screen.styleAt(3, 0).bg, isNull);
      node.dispose();
    });

    testWidgets('without room nothing is drawn and the model stays', (t) async {
      final c = TextAreaController(text: 'abc');
      await t.pumpWidget(
        Row(
          children: [
            SizedBox(width: 0, child: TextArea(controller: c, autofocus: true)),
          ],
        ),
      );
      await t.press('super+a');
      expect(c.selection, const TextSelection(baseOffset: 0, extentOffset: 3));
      expect(t.screen.styleAt(0, 0).bg, isNull);
    });
  });
}

class _MiddleRow extends StatefulWidget {
  const _MiddleRow();

  @override
  State<_MiddleRow> createState() => _MiddleRowState();
}

class _MiddleRowState extends State<_MiddleRow> {
  final _c = TextAreaController(text: 'a\nb\nc')..cursor = 2;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      TextArea(controller: _c, autofocus: true, unhandledKeys: const {});
}

void _testerSelectionWidgetCases() {
  group('tester CTUI-164: selection widget boundaries', () {
    for (final size in _sizes) {
      testWidgets('wide clusters at a wrap edge select whole cells at $size', (
        t,
      ) async {
        final text = '${'x' * (size.width - 1)}界👩‍💻e\u0301';
        final c = TextAreaController(text: text);
        try {
          await t.pumpWidget(
            TextArea(controller: c, autofocus: true, selectionStyle: _selected),
            size: size,
          );
          await t.press('super+a');
          expect(c.selectedText, text);
          expect(t.screen.styleAt(size.width - 2, 0).bg, _selected.bg);
          expect(t.screen.styleAt(size.width - 1, 0).bg, isNull);
          for (var x = 0; x < 5; x++) {
            expect(t.screen.styleAt(x, 1).bg, _selected.bg);
          }
          expect(t.screen.styleAt(5, 1).bg, isNull);
          await t.resize(const Size(3, 3));
          expect(c.selectedText, text);
          await t.resize(size);
          expect(t.screen.styleAt(4, 1).bg, _selected.bg);
          await t.press('shift+left');
          expect(c.selectedText, text.substring(0, text.length - 2));
        } finally {
          t.dispose();
          c.dispose();
        }
      });
    }

    for (final size in [Size.zero, const Size(1, 1), ..._sizes]) {
      testWidgets('selection survives focus and tiny resize at $size', (
        t,
      ) async {
        const text = '界👩‍💻e\u0301\n\x1b[31mZ\x1b[0m';
        final c = TextAreaController(text: text);
        final focus = FocusNode();
        try {
          await t.pumpWidget(
            Column(
              children: [
                TextArea(
                  controller: c,
                  focusNode: focus,
                  autofocus: true,
                  selectionStyle: _selected,
                ),
              ],
            ),
            size: size,
          );
          await t.press('super+a');
          final selection = c.selection;
          focus.unfocus();
          await t.pump();
          expect(c.selection, selection);
          expect(t.screen.buffer.cursor, isNull);
          await t.resize(const Size(80, 24));
          expect(c.selectedText, text);
          expect(t.screen.styleAt(0, 0).bg, _selected.bg);
          focus.requestFocus();
          await t.pump();
          expect(c.selection, selection);
          await t.paste('done');
          expect((c.text, c.cursor, c.hasSelection), ('done', 4, false));
          expect(t.screen.styleAt(0, 0).bg, isNull);
        } finally {
          t.dispose();
          focus.dispose();
          c.dispose();
        }
      });
    }

    testWidgets('an empty selected editor never paints its placeholder', (
      t,
    ) async {
      final c = TextAreaController(text: '界e\u0301');
      try {
        await t.pumpWidget(
          TextArea(
            controller: c,
            autofocus: true,
            placeholder: 'hint',
            selectionStyle: _selected,
          ),
        );
        await t.press('super+a delete super+a');
        expect(c.selectedText, isEmpty);
        expect(t.screen, shows('hint'));
        for (var x = 0; x < 5; x++) {
          expect(t.screen.styleAt(x, 0).bg, isNull);
        }
      } finally {
        t.dispose();
        c.dispose();
      }
    });

    testWidgets(
      'every editing key can be delegated without changing selection',
      (t) async {
        final c = TextAreaController(text: 'a\nb\nc');
        c.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
        final reached = <String>[];
        final keys = TextArea.editingKeys.keys.toSet();
        try {
          await t.pumpWidget(
            Focus(
              onKey: (event) {
                reached.add(event.combo.toString());
                return true;
              },
              child: TextArea(
                controller: c,
                autofocus: true,
                unhandledKeys: keys,
              ),
            ),
          );
          for (final key in keys) {
            await t.press(key);
          }
          expect(reached, keys.toList());
          expect(c.text, 'a\nb\nc');
          expect(
            c.selection,
            const TextSelection(baseOffset: 0, extentOffset: 2),
          );
        } finally {
          t.dispose();
          c.dispose();
        }
      },
    );

    testWidgets('stream selection bursts detach when the editor is removed', (
      t,
    ) async {
      final c = TextAreaController();
      final events = StreamController<String>(sync: true);
      final changed = <String>[];
      final subscription = events.stream.listen((text) {
        c.text = text;
        c.selectAll();
      });
      try {
        await t.pumpWidget(
          TextArea(
            controller: c,
            autofocus: true,
            selectionStyle: _selected,
            onChanged: changed.add,
          ),
        );
        for (var i = 0; i < 1000; i++) {
          events.add('界👩‍💻e\u0301 $i');
        }
        await t.pump();
        expect(c.selectedText, '界👩‍💻e\u0301 999');
        expect(changed, hasLength(1000));
        expect(t.screen.styleAt(0, 0).bg, _selected.bg);
        await t.pumpWidget(Text('removed'));
        events.add('late selection');
        await t.pump();
        expect(changed, hasLength(1000));
        expect(t.screen.text, 'removed');
        expect(c.selectedText, 'late selection');
      } finally {
        t.dispose();
        await subscription.cancel();
        await events.close();
        c.dispose();
      }
    });
  });
}
