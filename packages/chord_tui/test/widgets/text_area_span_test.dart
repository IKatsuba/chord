import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'selection_test.dart' show drag;

List<Object> facts(TextAreaLayout layout) => [
  layout.width,
  layout.height,
  layout.rowOffset,
  layout.cursorRow,
  layout.cursorColumn,
  for (final row in layout.rows)
    (row.text, row.start, row.end, row.line, row.piece, row.last),
];

List<(String, Style)> cells(WidgetTester t) => [
  for (var y = 0; y < t.size.height; y++)
    for (var x = 0; x < t.size.width; x++)
      (t.screen.charAt(x, y), t.screen.styleAt(x, y)),
];

TextSpan inverseHits(String text, String query) {
  final parts = <TextSpan>[];
  var at = 0;
  while (query.isNotEmpty) {
    final next = text.indexOf(query, at);
    if (next < 0) break;
    parts.add(TextSpan(text.substring(at, next)));
    parts.add(TextSpan(query, style: Style.inverse));
    at = next + query.length;
  }
  parts.add(TextSpan(text.substring(at)));
  return TextSpan('', children: parts);
}

void main() {
  _testerSpanWidgetBoundaries();
  for (final size in const [
    Size(120, 40),
    Size(80, 24),
    Size(12, 7),
    Size(0, 0),
  ]) {
    testWidgets(
      'span styles leave actual rows cursor and notifications unchanged $size',
      (t) async {
        final c = TextAreaController(
          text: 'abcneedleXYZ\n界😀é\t\x1b[31mred\x1b[0m\u0001',
        );
        final mode = ValueNotifier(0);
        final changes = <String>[];
        final layouts = <TextAreaLayout>[];
        final onLayout = layouts.add;
        final onChange = changes.add;
        var calls = 0;
        TextSpan noOp(BuildContext _, String text) {
          calls++;
          return TextSpan(text);
        }

        await t.pumpWidget(
          ListenableBuilder(
            listenable: mode,
            builder: (_) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 4,
                  height: 3,
                  child: TextArea(
                    controller: c,
                    autofocus: true,
                    maxHeight: 3,
                    onChanged: onChange,
                    onLayoutChanged: onLayout,
                    textSpanBuilder: mode.value == 0
                        ? null
                        : mode.value == 1
                        ? noOp
                        : (_, text) => inverseHits(text, 'needle'),
                  ),
                ),
              ],
            ),
          ),
          size: size,
        );
        final original = facts(c.lastLayout!);
        final originalCells = cells(t);
        final cursor = t.screen.buffer.cursor;
        final notifications = layouts.length;
        final editing = (c.text, c.cursor);
        expect(calls, 0);
        mode.value = 1;
        await t.pump();
        expect(calls, greaterThan(0));
        expect(cells(t), originalCells);
        expect(facts(c.lastLayout!), original);
        mode.value = 2;
        await t.pump();
        expect(facts(c.lastLayout!), original);
        expect(t.screen.buffer.cursor, cursor);
        expect((c.text, c.cursor), editing);
        expect(changes, isEmpty);
        expect(layouts, hasLength(notifications));
        t.dispose();
        c.dispose();
        mode.dispose();
      },
    );
  }

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets(
      'captured query and callback replacement update without text edits $size',
      (t) async {
        final c = TextAreaController(text: 'needle needle');
        final rebuild = ValueNotifier(0);
        var query = 'needle', calls = 0;
        TextSpan builder(BuildContext _, String text) {
          calls++;
          return inverseHits(text, query);
        }

        final stableBuilder = builder;
        await t.pumpWidget(
          ListenableBuilder(
            listenable: rebuild,
            builder: (_) => TextArea(
              controller: c,
              textSpanBuilder: rebuild.value == 3
                  ? null
                  : rebuild.value == 2
                  ? (_, text) => TextSpan(text, style: Style.bold)
                  : stableBuilder,
            ),
          ),
          size: size,
        );
        expect(t.screen.styleAt(0, 0).isInverse, isTrue);
        expect(t.screen.styleAt(7, 0).isInverse, isTrue);
        final before = calls;
        query = 'missing';
        rebuild.value = 1;
        await t.pump();
        expect(calls, greaterThan(before));
        expect(t.screen.styleAt(0, 0).isInverse, isFalse);
        rebuild.value = 2;
        await t.pump();
        expect(t.screen.styleAt(0, 0).isBold, isTrue);
        rebuild.value = 3;
        await t.pump();
        expect(t.screen.styleAt(0, 0).isBold, isFalse);
        expect(c.text, 'needle needle');
        t.dispose();
        c.dispose();
        rebuild.dispose();
      },
    );

    testWidgets(
      'inherited root and nested span styles keep normal merge precedence $size',
      (t) async {
        final c = TextAreaController(text: 'abc');
        await t.pumpWidget(
          DefaultTextStyle(
            style: const Style(fg: Colors.green, dim: true),
            child: TextArea(
              controller: c,
              style: Style.bold,
              textSpanBuilder: (_, text) => const TextSpan(
                'a',
                style: Style.italic,
                children: [
                  TextSpan('b', style: Style(fg: Colors.blue)),
                  TextSpan('c'),
                ],
              ),
            ),
          ),
          size: size,
        );
        expect(t.screen.styleAt(0, 0).fg, Colors.green);
        expect(t.screen.styleAt(1, 0).fg, Colors.blue);
        expect(t.screen.styleAt(2, 0).fg, Colors.green);
        for (var x = 0; x < 3; x++) {
          final style = t.screen.styleAt(x, 0);
          expect(style.isBold && style.isDim && style.isItalic, isTrue);
        }
        t.dispose();
        c.dispose();
      },
    );

    testWidgets(
      'whole-text cross-wrap hits and LF keep row style provenance $size',
      (t) async {
        final c = TextAreaController(text: 'abcneedleXYZ\nneedle');
        c.cursor = 0;
        await t.pumpWidget(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 4,
                child: TextArea(
                  controller: c,
                  maxHeight: 8,
                  textSpanBuilder: (_, text) => inverseHits(text, 'needle'),
                ),
              ),
            ],
          ),
          size: size,
        );
        expect(t.screen.lines.take(6), [
          'abcn',
          'eedl',
          'eXYZ',
          '',
          'need',
          'le',
        ]);
        expect(t.screen.styleAt(3, 0).isInverse, isTrue);
        expect(t.screen.styleAt(0, 1).isInverse, isTrue);
        expect(t.screen.styleAt(0, 2).isInverse, isTrue);
        expect(t.screen.styleAt(1, 2).isInverse, isFalse);
        expect(t.screen.styleAt(0, 4).isInverse, isTrue);
        t.dispose();
        c.dispose();
      },
    );

    for (final excluded in [false, true]) {
      testWidgets(
        'decoration preserves existing editor selection eligibility $excluded $size',
        (t) async {
          final c = TextAreaController(text: 'first\nsecond');
          final selection = SelectionController();
          final decorate = ValueNotifier(false);
          await t.pumpWidget(
            SelectionArea(
              selectionStyle: Style.inverse,
              controller: selection,
              child: ListenableBuilder(
                listenable: decorate,
                builder: (_) {
                  final area = TextArea(
                    controller: c,
                    autofocus: true,
                    textSpanBuilder: decorate.value
                        ? (_, text) => TextSpan(text, style: Style.bold)
                        : null,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      excluded
                          ? SelectionContainer.disabled(child: area)
                          : area,
                    ],
                  );
                },
              ),
            ),
            size: size,
          );
          await drag(t, const Offset(0, 0), const Offset(5, 1));
          final selected = selection.snapshot()?.text;
          if (excluded) {
            expect(selection.value.hasText, isFalse);
          } else {
            expect(selected, 'first\nsecond');
          }
          final cursor = t.screen.buffer.cursor;
          decorate.value = true;
          await t.pump();
          expect(selection.snapshot()?.text, selected);
          expect(c.text, 'first\nsecond');
          expect(t.screen.buffer.cursor, cursor);
          await t.paste('!');
          final typed = c.text;
          await t.press('ctrl+z');
          expect(c.text, 'first\nsecond');
          await t.press('ctrl+y');
          expect(c.text, typed);
          t.dispose();
          c.dispose();
          selection.dispose();
          decorate.dispose();
        },
      );
    }
  }

  testWidgets(
    'visible placeholder bypasses callback while empty text without it validates',
    (t) async {
      final c = TextAreaController();
      final placeholder = ValueNotifier(true);
      var calls = 0;
      await t.pumpWidget(
        ListenableBuilder(
          listenable: placeholder,
          builder: (_) => TextArea(
            controller: c,
            autofocus: true,
            placeholder: placeholder.value ? 'Write' : null,
            textSpanBuilder: (_, text) {
              calls++;
              return TextSpan(text);
            },
          ),
        ),
      );
      expect(calls, 0);
      expect(t.screen, shows('Write'));
      placeholder.value = false;
      await t.pump();
      expect(calls, greaterThan(0));
      expect(c.lastLayout!.shownRows.single.text, '');
      c.insert('actual');
      await t.pump();
      placeholder.value = true;
      await t.pump();
      expect(t.screen, shows('actual'));
      t.dispose();
      c.dispose();
      placeholder.dispose();
    },
  );
}

void _testerSpanWidgetBoundaries() {
  group('tester: U27F style lifetime and prepaint rejection', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'a thousand captured styles preserve layout undo and focus at $size',
        (t) async {
          final controller = TextAreaController(text: 'needle')..insert('!');
          final version = ValueNotifier(0),
              editor = FocusNode(),
              other = FocusNode();
          final changes = <String>[];
          var calls = 0, layouts = 0;
          void rememberLayout(TextAreaLayout _) {
            layouts++;
          }

          TextSpan decorate(BuildContext _, String text) {
            calls++;
            return TextSpan(
              text,
              style: version.value > 0 && version.value.isEven
                  ? Style.inverse
                  : Style.plain,
            );
          }

          final stable = decorate;
          await t.pumpWidget(
            ListenableBuilder(
              listenable: version,
              builder: (_) => Column(
                children: [
                  TextArea(
                    controller: controller,
                    focusNode: editor,
                    autofocus: true,
                    maxHeight: 3,
                    textSpanBuilder: stable,
                    onChanged: changes.add,
                    onLayoutChanged: rememberLayout,
                  ),
                  Focus(focusNode: other, child: Text('Other focus')),
                ],
              ),
            ),
            size: size,
          );
          final original = facts(controller.lastLayout!);
          final beforeLayouts = layouts;
          for (var i = 1; i <= 1000; i++) {
            version.value = i;
          }
          await t.pump();
          expect(facts(controller.lastLayout!), original);
          expect(layouts, beforeLayouts);
          expect(changes, isEmpty);
          expect(t.screen.styleAt(0, 0).isInverse, isTrue);
          other.requestFocus();
          await t.pump();
          expect(other.hasFocus, isTrue);
          editor.requestFocus();
          await t.pump();
          await t.press('ctrl+z');
          expect(controller.text, 'needle');
          await t.press('ctrl+y');
          expect(controller.text, 'needle!');
          await t.pumpWidget(const SizedBox());
          final beforeCalls = calls;
          version.value++;
          await t.pump();
          expect(calls, beforeCalls);
          t.dispose();
          controller.dispose();
          version.dispose();
          editor.dispose();
          other.dispose();
        },
      );

      testWidgets(
        'invalid parent rebuild rejects paste and Enter before paint at $size',
        (t) async {
          final controller = TextAreaController(text: 'draft');
          final invalid = ValueNotifier(false);
          final changes = <String>[], submitted = <String>[];
          await t.pumpWidget(
            ListenableBuilder(
              listenable: invalid,
              builder: (_) => TextArea(
                controller: controller,
                autofocus: true,
                onChanged: changes.add,
                onSubmit: submitted.add,
                textSpanBuilder: (_, text) =>
                    TextSpan(invalid.value ? '$text invalid' : text),
              ),
            ),
            size: size,
          );
          invalid.value = true;
          t.host.handlePaste('hidden');
          t.host.handleKey(const KeyEvent('enter'));
          expect(controller.text, 'draft');
          expect(changes, isEmpty);
          expect(submitted, isEmpty);
          expect(
            t.focusManager.activeBindings.where(
              (binding) => binding.description == 'Undo',
            ),
            isEmpty,
          );
          invalid.value = false;
          await t.pump();
          expect(controller.text, 'draft');
          await t.paste('visible');
          expect(controller.text, 'draftvisible');
          t.dispose();
          controller.dispose();
          invalid.dispose();
        },
      );
    }
  });
}
