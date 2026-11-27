import 'package:chord_site/live_plate.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// A page that holds the focus, with Tab entering [plate]'s example: a
/// field that shows what it was typed, and binds Esc when [ownsEscape].
class _Page extends StatefulWidget {
  const _Page({this.ownsEscape = false, required this.live});

  final bool ownsEscape;
  final ValueNotifier<bool> live;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  final controller = LivePlateController();
  var typed = '';
  var pageKeys = 0;
  var homes = 0;
  var escapes = 0;

  @override
  Widget build(BuildContext context) => LiveScope(
    entered: widget.live,
    child: Actions(
      bindings: [
        Binding('tab', 'enter example', controller.enter),
        Binding('x', 'page key', () => setState(() => pageKeys++)),
        Binding('y', 'page key', () => setState(() => pageKeys++)),
      ],
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('page keys $pageKeys  homes $homes  escapes $escapes'),
            LivePlate(
              controller: controller,
              figure: 2,
              title: 'example/field.dart',
              rows: 3,
              ownsEscape: widget.ownsEscape,
              home: () => setState(() => homes++),
              child: (_) => Actions(
                bindings: [
                  Binding('x', 'type x', () => setState(() => typed += 'x')),
                  if (widget.ownsEscape)
                    Binding('esc', 'close', () => setState(() => escapes++)),
                ],
                child: Focus(autofocus: true, child: Text('typed "$typed"')),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('the example draws but gets no key until Tab enters it; Esc '
        'leaves, at $size', (t) async {
      final live = ValueNotifier(false);
      await t.pumpWidget(_Page(live: live), size: size);
      expect(t.screen, shows('FIG. 2 EXAMPLE/FIELD.DART · TAB TO ENTER'));
      await t.press('x');
      expect(t.screen, shows('page keys 1'));
      expect(t.screen, shows('typed ""'));
      expect(live.value, isFalse);
      await t.press('tab');
      expect(live.value, isTrue);
      // The tag sits at the caption row's right end.
      final caption = t.screen.lines.firstWhere((l) => l.contains('FIG. 2'));
      expect(caption, contains('FIG. 2 EXAMPLE/FIELD.DART '));
      expect(caption.trimRight(), endsWith('ESC LEAVES'));
      await t.press('x');
      expect(t.screen, shows('typed "x"'));
      expect(t.screen, shows('page keys 1'));
      // A key the example leaves stops at the plate.
      await t.press('y');
      expect(t.screen, shows('page keys 1'));
      await t.press('esc');
      expect(live.value, isFalse);
      expect(t.screen, shows('TAB TO ENTER'));
      await t.press('x');
      expect(t.screen, shows('page keys 2'));
      expect(t.screen, shows('typed "x"'), reason: 'kept while left');
      // Entering again goes back to the example's own focus.
      await t.press('tab');
      await t.press('x');
      expect(t.screen, shows('typed "xx"'));
    });
  }

  testWidgets('where the example binds Esc, Esc is its own and Ctrl+Q '
      'leaves', (t) async {
    final live = ValueNotifier(false);
    await t.pumpWidget(
      _Page(live: live, ownsEscape: true),
      size: const Size(80, 24),
    );
    await t.press('tab');
    expect(t.screen, shows('CTRL+Q LEAVES'));
    await t.press('esc');
    expect(t.screen, shows('escapes 1'));
    expect(live.value, isTrue);
    await t.press('ctrl+q');
    expect(live.value, isFalse);
    expect(t.screen, shows('homes 0'));
  });

  for (final quit in ['ctrl+q', 'ctrl+c']) {
    testWidgets('$quit inside an example that leaves Esc to the plate leaves '
        'and goes home', (t) async {
      final live = ValueNotifier(false);
      await t.pumpWidget(_Page(live: live), size: const Size(80, 24));
      await t.press('tab');
      await t.press(quit);
      expect(live.value, isFalse);
      expect(t.screen, shows('homes 1'));
    });
  }

  testWidgets('the caption sits on the cream, FIG. n in green', (t) async {
    await t.pumpWidget(
      _Page(live: ValueNotifier(false)),
      size: const Size(80, 24),
    );
    final y = t.screen.lines.indexWhere((l) => l.contains('FIG. 2'));
    final x = t.screen.lines[y].indexOf('FIG. 2');
    final fig = t.screen.styleAt(x, y);
    expect(fig.isInverse, isTrue);
    expect(fig.bg, ThemeData.dark().accent.fg);
    final title = t.screen.lines[y].indexOf('EXAMPLE');
    expect(t.screen.styleAt(title, y).isInverse, isTrue);
    expect(t.screen.styleAt(0, y).isInverse, isTrue, reason: 'the plate');
  });
}
