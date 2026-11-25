// The prompt box's named top while a child is in front, `╭─ docs ───╮`, as
// the original's `NamedTop` draws it (captures in
// docs/design/evidence/CTUI-35/agents-list/): the name bold in the agent's
// colour, the edges in the edge style, cut when narrow, nothing on a box
// too narrow for a border.
import 'package:chord/ui/prompt/named_top.dart';
import 'package:chord/ui/prompt/prompt_input.dart';
import 'package:chord/ui/theme/theme.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

final _docs = colorOf(palettes['dark']!.agents![1]);
final _bash = chordDark.bash;

Widget _prompt(
  TextAreaController controller, {
  PromptAgent? agent,
  bool bash = false,
  int? width,
}) {
  final input = PromptInput(
    controller: controller,
    windowRows: 24,
    onSubmit: (_) {},
    onOlder: () {},
    onNewer: () {},
    bash: bash,
    agent: agent,
  );
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [width == null ? input : SizedBox(width: width, child: input)],
  );
}

/// The text of a cell row, [from] for [count] cells.
String _cells(WidgetTester t, int row, int from, int count) =>
    [for (var x = from; x < from + count; x++) t.screen.charAt(x, row)].join();

void main() {
  _testerNamedEdges();
  group('namedTop', () {
    test("is the original's cells: the corner, the name, the fill to the "
        'end', () {
      const edge = (style: Style(dim: true), top: Style(dim: true), tone: null);
      String text(TextSpan span) =>
          span.children.map((child) => child.text).join();
      expect(text(namedTop('docs', 80, edge)), '╭─ docs ${'─' * 71}╮');
      expect(text(namedTop('parser', 120, edge)), '╭─ parser ${'─' * 109}╮');
      // At least one dash, however narrow.
      expect(text(namedTop('docs', 6, edge)), '╭─ docs ─╮');
    });

    test("a member's run follows its name dim, the fill counting it", () {
      const edge = (style: Style(dim: true), top: Style(dim: true), tone: null);
      final top = namedTop('tester', 40, edge, team: 'bugfix 2');
      expect(
        top.children.map((child) => child.text).join(),
        '╭─ tester · bugfix 2 ${'─' * 18}╮',
      );
      expect(top.children[2].text, ' · bugfix 2');
      expect(top.children[2].style, const Style(dim: true));
      expect(top.children[1].style, const Style(bold: true));
    });

    test('bash mode outranks the agent; with neither the edge is the '
        "theme's border", () {
      const border = Style(fg: IndexedColor(244));
      expect(
        promptEdge(bash: true, bashStyle: _bash, border: border, agent: _docs),
        (style: _bash, top: _bash, tone: _bash.fg),
      );
      expect(
        promptEdge(bash: false, bashStyle: _bash, border: border, agent: _docs),
        (style: Style(fg: _docs), top: Style(fg: _docs), tone: _docs),
      );
      expect(promptEdge(bash: false, bashStyle: _bash, border: border), (
        style: border,
        top: Style(dim: true),
        tone: null,
      ));
      // A theme with no bash colour: the agent's, else the terminal's own.
      expect(
        promptEdge(
          bash: true,
          bashStyle: Style.plain,
          border: border,
          agent: _docs,
        ),
        (style: Style(fg: _docs), top: Style(fg: _docs), tone: _docs),
      );
      expect(promptEdge(bash: true, bashStyle: Style.plain, border: border), (
        style: Style.plain,
        top: Style.plain,
        tone: null,
      ));
    });
  });

  for (final (size, name, fill) in const [
    (Size(120, 40), 'parser', 109),
    (Size(80, 24), 'docs', 71),
  ]) {
    testWidgets('the named top is the capture cell for cell, the name bold in '
        "the agent's colour, at $size", (t) async {
      final controller = TextAreaController();
      await t.pumpWidget(
        ChordThemeScope(
          child: _prompt(controller, agent: PromptAgent(name, colour: _docs)),
        ),
        size: size,
      );
      expect(t.screen.lines[1], '╭─ $name ${'─' * fill}╮');
      expect(t.screen.lines[2], startsWith('│ › '));
      expect(t.screen.lines[3], '╰${'─' * (size.width - 2)}╯');
      final edge = Style(fg: _docs), bold = Style(fg: _docs, bold: true);
      for (var x = 0; x < size.width; x++) {
        final inName = x >= 2 && x < 3 + name.length;
        expect(t.screen.styleAt(x, 1), inName ? bold : edge, reason: 'x $x');
      }
      // The whole border takes the edge style.
      expect(t.screen.styleAt(0, 2), edge);
      expect(t.screen.styleAt(size.width - 1, 3), edge);
    });
  }

  testWidgets('bash mode colours the edge and the name its own way', (t) async {
    await t.pumpWidget(
      ChordThemeScope(
        child: _prompt(
          TextAreaController(),
          agent: PromptAgent('docs', colour: _docs),
          bash: true,
        ),
      ),
      size: const Size(80, 24),
    );
    expect(t.screen.styleAt(0, 1), _bash);
    expect(t.screen.styleAt(3, 1), _bash.merge(const Style(bold: true)));
    expect(t.screen.styleAt(0, 3), _bash);
  });

  testWidgets("main's box with no colour is drawn in the theme's border, "
      "palette colour 244, as the original's DIM_BORDER", (t) async {
    await t.pumpWidget(
      ChordThemeScope(child: _prompt(TextAreaController())),
      size: const Size(80, 24),
    );
    const border = Style(fg: IndexedColor(244));
    expect(t.screen.lines[1], startsWith('╭'));
    expect(t.screen.styleAt(0, 1), border);
    expect(t.screen.styleAt(79, 1), border);
    expect(t.screen.styleAt(0, 2), border);
  });

  testWidgets('with no colour the box is the border, its named top dim and '
      'the name plain bold, as the original NamedTop', (t) async {
    await t.pumpWidget(
      _prompt(TextAreaController(), agent: const PromptAgent('docs')),
      size: const Size(80, 24),
    );
    expect(t.screen.lines[1], '╭─ docs ${'─' * 71}╮');
    // The top's edges are the original NamedTop's dim; the box's sides
    // are the theme's border.
    expect(t.screen.styleAt(0, 1), const Style(dim: true));
    expect(t.screen.styleAt(79, 1), const Style(dim: true));
    expect(t.screen.styleAt(0, 3), ThemeData.fallback().border);
    expect(t.screen.styleAt(3, 1), const Style(bold: true));
  });

  testWidgets('main is never named: the plain rounded top', (t) async {
    await t.pumpWidget(_prompt(TextAreaController()), size: const Size(80, 24));
    expect(t.screen.lines[1], '╭${'─' * 78}╮');
  });

  testWidgets('a name wider than the box is cut at its edge', (t) async {
    await t.pumpWidget(
      _prompt(
        TextAreaController(),
        agent: PromptAgent('a-very-long-agent-name', colour: _docs),
        width: 12,
      ),
      size: const Size(80, 24),
    );
    expect(_cells(t, 1, 0, 12), '╭─ a-very-lo');
    expect(_cells(t, 1, 12, 10).trim(), isEmpty);
    expect(t.screen.lines[2], startsWith('│'));
  });

  for (final width in const [0, 1]) {
    testWidgets('a box $width cells wide draws no top and does not throw', (
      t,
    ) async {
      await t.pumpWidget(
        _prompt(
          TextAreaController(),
          agent: PromptAgent('docs', colour: _docs),
          width: width,
        ),
        size: const Size(80, 24),
      );
      for (final line in t.screen.lines) {
        expect(line.trim(), isEmpty);
      }
    });
  }
}

void _testerNamedEdges() {
  group('CTUI-35 tester: named top grapheme edges', () {
    for (final name in [
      '界界',
      '👩‍💻e\u0301',
      'e\u0301界🙂',
      'left\x1b[31mred\x1b[0m',
    ]) {
      testWidgets('clipped names stay inside every narrow box: $name', (
        t,
      ) async {
        final controller = TextAreaController(text: 'kept draft');
        for (var width = 0; width <= 18; width++) {
          await t.pumpWidget(
            _prompt(
              controller,
              agent: PromptAgent(name, colour: _docs),
              width: width,
            ),
            size: const Size(80, 24),
          );
          await t.pump();
          for (var x = width; x < 80; x++) {
            expect(
              t.screen.charAt(x, 1).trim(),
              isEmpty,
              reason: 'width=$width x=$x',
            );
          }
          expect(t.screen.text, isNot(contains('\x1b')));
          expect(controller.text, 'kept draft');
          if (width > 1) expect(t.screen.charAt(0, 1), '╭');
        }
        await t.pumpWidget(
          _prompt(controller, agent: PromptAgent(name, colour: _docs)),
          size: const Size(120, 40),
        );
        expect(t.screen.charAt(119, 1), '╮');
        expect(t.screen.lines[2], contains('kept draft'));
      });
    }
  });
}
