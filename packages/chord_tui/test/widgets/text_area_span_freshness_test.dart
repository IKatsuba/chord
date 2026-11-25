import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:chord_tui/src/rendering/selection_area.dart'
    show RenderSelectionEditor;
import 'package:test/test.dart';

class _Probe extends SingleChildRenderObjectWidget {
  const _Probe({
    required this.before,
    required this.after,
    required super.child,
  });
  final void Function() before;
  final void Function(RenderBox) after;
  @override
  RenderBox createRenderObject(BuildContext context) =>
      _ProbeBox(before, after);
  @override
  void updateRenderObject(BuildContext context, _ProbeBox box) {
    box
      ..before = before
      ..after = after;
  }
}

class _ProbeBox extends RenderProxyBox {
  _ProbeBox(this.before, this.after);
  void Function() before;
  void Function(RenderBox) after;
  @override
  void performLayout() {
    before();
    super.performLayout();
    after(this);
  }
}

List<(String, Style)> paragraphs(RenderBox root) {
  final out = <(String, Style)>[];
  void visit(RenderBox box) {
    if (box is RenderParagraph) {
      final runs = box.text.flatten(box.style);
      out.add((
        box.text.toPlainText(),
        runs.isEmpty ? box.style : runs.first.$2,
      ));
    }
    box.visitChildren(visit);
  }

  visit(root);
  return out;
}

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets(
      'sibling layout text change draws current plain rows before fresh spans $size',
      (t) async {
        final c = TextAreaController(text: 'old');
        var armed = true, layouts = 0, calls = 0;
        final seen = <(String, Style)>[];
        await t.pumpWidget(
          _Probe(
            before: () {
              layouts++;
              if (armed) {
                armed = false;
                c.text = 'current';
              }
            },
            after: (root) => seen.addAll(paragraphs(root)),
            child: TextArea(
              controller: c,
              textSpanBuilder: (_, text) {
                calls++;
                return TextSpan(text, style: Style.inverse);
              },
            ),
          ),
          size: size,
        );
        expect(
          seen.any((row) => row.$1 == 'current' && !row.$2.isInverse),
          isTrue,
        );
        expect(layouts, lessThanOrEqualTo(2));
        expect(calls, lessThanOrEqualTo(2));
        await t.pump();
        expect(t.screen, shows('current'));
        expect(t.screen.styleAt(0, 0).isInverse, isTrue);
        expect(c.lastLayout!.rows.single.text, 'current');
        t.dispose();
        c.dispose();
      },
    );

    testWidgets(
      'afterLayout changes respect the normal pass budget and next frame $size',
      (t) async {
        final c = TextAreaController(text: 'old');
        var layouts = 0, changes = 0, calls = 0;
        final seen = <(String, Style)>[];
        await t.pumpWidget(
          _Probe(
            before: () => layouts++,
            after: (root) => seen.addAll(paragraphs(root)),
            child: TextArea(
              controller: c,
              onLayoutChanged: (_) {
                if (changes < 2) c.insert('${++changes}');
              },
              textSpanBuilder: (_, text) {
                calls++;
                return TextSpan(
                  text,
                  style: text.endsWith('2') ? Style.inverse : Style.bold,
                );
              },
            ),
          ),
          size: size,
        );
        expect(layouts, lessThanOrEqualTo(2));
        expect(calls, lessThanOrEqualTo(2));
        expect(c.text, 'old12');
        expect(
          seen.where((row) => row.$1 == 'old12' && row.$2.isBold),
          isEmpty,
        );
        layouts = 0;
        calls = 0;
        await t.pump();
        expect(layouts, lessThanOrEqualTo(2));
        expect(calls, lessThanOrEqualTo(2));
        expect(t.screen, shows('old12'));
        expect(t.screen.styleAt(0, 0).isInverse, isTrue);
        expect(c.lastLayout!.cursorColumn, 5);
        t.dispose();
        c.dispose();
      },
    );

    testWidgets(
      'controller and theme replacement retain current identity and styles $size',
      (t) async {
        final old = TextAreaController(text: 'old')..insert('!');
        final current = TextAreaController(text: 'current')..cursor = 0;
        final replacement = ValueNotifier(false);
        var armed = true;
        final seen = <(String, Style)>[];
        final green = ThemeData.dark().copyWith(
          text: const Style(fg: Colors.green),
        );
        final blue = ThemeData.light().copyWith(
          text: const Style(fg: Colors.blue),
        );
        TextSpan builder(BuildContext context, String text) => TextSpan(
          text,
          style: Style(fg: Theme.of(context).text.fg, inverse: true),
        );
        final stableBuilder = builder;
        await t.pumpWidget(
          ListenableBuilder(
            listenable: replacement,
            builder: (_) => Theme(
              data: replacement.value ? blue : green,
              child: _Probe(
                before: () {
                  if (armed) {
                    armed = false;
                    replacement.value = true;
                  }
                },
                after: (root) => seen.addAll(paragraphs(root)),
                child: TextArea(
                  controller: replacement.value ? current : old,
                  textSpanBuilder: stableBuilder,
                ),
              ),
            ),
          ),
          size: size,
        );
        await t.pump();
        expect(t.screen, shows('current'));
        expect(t.screen.styleAt(0, 0).fg, Colors.blue);
        expect(
          seen.where((row) => row.$1 == 'current' && row.$2.fg != Colors.blue),
          isEmpty,
        );
        expect(current.cursor, 0);
        expect(current.lastLayout!.cursorColumn, 0);
        final editors = <RenderSelectionEditor>[];
        void visit(Element element) {
          if (element is RenderObjectElement &&
              element.renderObject is RenderSelectionEditor) {
            editors.add(element.renderObject as RenderSelectionEditor);
          }
          element.visitChildren(visit);
        }

        visit(t.host.rootElement);
        expect(editors.single.controller, same(current));
        expect(editors.single.editorLayout, same(current.lastLayout));
        old.undo();
        expect(old.text, 'old');
        current.insert('!');
        current.undo();
        expect(current.text, 'current');
        t.dispose();
        old.dispose();
        current.dispose();
        replacement.dispose();
      },
    );
  }
}
