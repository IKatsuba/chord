import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

final _taken = {KeyCombo.parse('ctrl+q'), KeyCombo.parse('ctrl+c')};

/// A host with its own keys and a help row outside, around an embedded
/// tree with its own keys and help row inside, on [inner] bindings.
Widget _host({
  required List<Binding> inner,
  List<Binding> outer = const [],
  Set<KeyCombo>? taken,
  Widget Function(Widget child)? wrapInner,
}) {
  Widget embedded = Actions(
    bindings: inner,
    child: Focus(
      autofocus: true,
      child: Column(children: [Text('inside:'), const KeyHelp()]),
    ),
  );
  if (wrapInner != null) embedded = wrapInner(embedded);
  return Actions(
    bindings: [
      Binding('escape', 'up', () {}),
      Binding('?', 'keys', () {}),
      ...outer,
    ],
    child: Column(
      children: [
        Expanded(
          child: KeyHelpBoundary(taken: taken ?? _taken, child: embedded),
        ),
        Text('outside:'),
        const KeyHelp(),
      ],
    ),
  );
}

/// The help row under [label]; an empty row takes no height, so none may
/// follow the label at the bottom.
String _row(WidgetTester t, String label) {
  final lines = t.screen.lines;
  final at = lines.indexOf(label) + 1;
  return at < lines.length ? lines[at] : '';
}

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('inside lists its own keys, outside both, less taken, $size', (
      t,
    ) async {
      await t.pumpWidget(
        _host(
          inner: [
            Binding('ctrl+o', 'Toggle', () {}),
            Binding('ctrl+q', 'Quit', () {}),
          ],
        ),
        size: size,
      );
      expect(_row(t, 'inside:'), 'ctrl+o Toggle');
      expect(_row(t, 'outside:'), 'ctrl+o Toggle  escape up  ? keys');
    });
  }

  testWidgets('a taken key hides any chord starting with it', (t) async {
    await t.pumpWidget(
      _host(
        inner: [
          Binding('ctrl+x a', 'Anchor', () {}),
          Binding('ctrl+x b', 'Bottom', () {}),
          Binding('x', 'Ex', () {}),
        ],
        taken: {KeyCombo.parse('ctrl+x')},
      ),
      size: const Size(120, 40),
    );
    expect(_row(t, 'inside:'), 'x Ex');
    expect(_row(t, 'outside:'), 'x Ex  escape up  ? keys');
  });

  testWidgets('a pending chord inside offers its listed endings', (t) async {
    await t.pumpWidget(
      _host(
        inner: [
          Binding('ctrl+x a', 'Anchor', () {}),
          Binding('ctrl+x b', 'Bottom', () {}),
        ],
        outer: [Binding('ctrl+x z', 'Outer', () {})],
      ),
      size: const Size(120, 40),
    );
    await t.press('ctrl+x');
    expect(_row(t, 'inside:'), 'ctrl+x …  ctrl+x a Anchor  ctrl+x b Bottom');
    expect(
      _row(t, 'outside:'),
      'ctrl+x …  ctrl+x a Anchor  ctrl+x b Bottom  ctrl+x z Outer',
    );
  });

  testWidgets('a chord only outer keys finish is not shown inside', (t) async {
    await t.pumpWidget(
      _host(inner: const [], outer: [Binding('ctrl+x z', 'Outer', () {})]),
      size: const Size(120, 40),
    );
    await t.press('ctrl+x');
    expect(_row(t, 'inside:'), '');
    expect(_row(t, 'outside:'), 'ctrl+x …  ctrl+x z Outer');
  });

  testWidgets('a builder inside gets nothing while an outer chord waits', (
    t,
  ) async {
    final heard = <String>[];
    await t.pumpWidget(
      Actions(
        bindings: [Binding('ctrl+x z', 'Outer', () {})],
        child: KeyHelpBoundary(
          child: Actions(
            bindings: [Binding('ctrl+o', 'Toggle', () {})],
            child: Focus(
              autofocus: true,
              child: KeyHelp.builder(
                builder: (_, bindings, pending) {
                  heard.add(
                    '${[for (final b in bindings) b.description]} '
                    '${[for (final k in pending) k.toString()]}',
                  );
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      ),
      size: const Size(120, 40),
    );
    expect(heard.last, '[Toggle] []');
    await t.press('ctrl+x');
    expect(heard.last, '[] []');
  });

  testWidgets('a builder gets nothing while a taken chord waits', (t) async {
    final heard = <List<String>>[];
    await t.pumpWidget(
      KeyHelpBoundary(
        taken: {KeyCombo.parse('ctrl+x')},
        child: Actions(
          bindings: [
            Binding('ctrl+x a', 'Anchor', () {}),
            Binding('ctrl+o', 'Toggle', () {}),
          ],
          child: Focus(
            autofocus: true,
            child: KeyHelp.builder(
              builder: (_, bindings, pending) {
                heard.add([for (final b in bindings) b.description]);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
      size: const Size(120, 40),
    );
    expect(heard.last, ['Toggle']);
    await t.press('ctrl+x');
    expect(heard.last, isEmpty);
  });

  testWidgets('a chord only taken keys finish is shown nowhere', (t) async {
    await t.pumpWidget(
      _host(
        inner: [Binding('ctrl+x a', 'Anchor', () {})],
        taken: {KeyCombo.parse('ctrl+x')},
      ),
      size: const Size(120, 40),
    );
    await t.press('ctrl+x');
    expect(_row(t, 'inside:'), '');
    expect(_row(t, 'outside:'), '');
  });

  testWidgets('changing only taken updates both rows at once', (t) async {
    final taken = ValueNotifier<Set<KeyCombo>>(const {});
    // The same widget instance every build: nothing below changes.
    final embedded = Actions(
      bindings: [
        Binding('ctrl+o', 'Toggle', () {}),
        Binding('ctrl+q', 'Quit', () {}),
      ],
      child: Focus(
        autofocus: true,
        child: Column(children: [Text('inside:'), const KeyHelp()]),
      ),
    );
    await t.pumpWidget(
      Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: taken,
              builder: (_) =>
                  KeyHelpBoundary(taken: taken.value, child: embedded),
            ),
          ),
          Text('outside:'),
          const KeyHelp(),
        ],
      ),
      size: const Size(120, 40),
    );
    expect(_row(t, 'inside:'), 'ctrl+o Toggle  ctrl+q Quit');
    expect(_row(t, 'outside:'), 'ctrl+o Toggle  ctrl+q Quit');
    taken.value = {KeyCombo.parse('ctrl+q')};
    await t.pump();
    expect(_row(t, 'inside:'), 'ctrl+o Toggle');
    expect(_row(t, 'outside:'), 'ctrl+o Toggle');
  });

  testWidgets('an inside with no bindings of its own lists nothing', (t) async {
    await t.pumpWidget(_host(inner: const []), size: const Size(80, 24));
    expect(_row(t, 'inside:'), '');
    expect(_row(t, 'outside:'), 'escape up  ? keys');
  });

  testWidgets('nested boundaries: the nearest decides, taken keys add up', (
    t,
  ) async {
    await t.pumpWidget(
      _host(
        inner: [
          Binding('ctrl+q', 'Quit', () {}),
          Binding('ctrl+t', 'Theme', () {}),
          Binding('ctrl+o', 'Open', () {}),
        ],
        taken: {KeyCombo.parse('ctrl+q')},
        // A middle layer with keys of its own and a boundary of its own.
        wrapInner: (child) => Actions(
          bindings: [Binding('ctrl+m', 'Middle', () {})],
          child: Column(
            children: [
              Expanded(
                child: KeyHelpBoundary(
                  taken: {KeyCombo.parse('ctrl+t')},
                  child: child,
                ),
              ),
              Text('middle:'),
              const KeyHelp(),
            ],
          ),
        ),
      ),
      size: const Size(120, 40),
    );
    expect(_row(t, 'inside:'), 'ctrl+o Open');
    expect(_row(t, 'middle:'), 'ctrl+o Open  ctrl+m Middle');
    expect(
      _row(t, 'outside:'),
      'ctrl+o Open  ctrl+m Middle  escape up  ? keys',
    );
  });

  testWidgets('dispatch is unchanged by the boundary', (t) async {
    final fired = <String>[];
    await t.pumpWidget(
      _host(
        inner: [Binding('ctrl+q', 'Quit', () => fired.add('inner quit'))],
        outer: [Binding('ctrl+g', 'Go', () => fired.add('outer go'))],
      ),
      size: const Size(120, 40),
    );
    // An outer key with focus inside still fires; a taken key's inner
    // binding still fires when nothing captures it.
    await t.press('ctrl+g');
    await t.press('ctrl+q');
    expect(fired, ['outer go', 'inner quit']);
  });

  testWidgets('the builder gets the listed bindings', (t) async {
    late List<String> listed;
    await t.pumpWidget(
      Actions(
        bindings: [Binding('escape', 'up', () {})],
        child: KeyHelpBoundary(
          taken: _taken,
          child: Actions(
            bindings: [
              Binding('ctrl+o', 'Toggle', () {}),
              Binding('ctrl+c', 'Quit', () {}),
            ],
            child: Focus(
              autofocus: true,
              child: KeyHelp.builder(
                builder: (_, bindings, _) {
                  listed = [for (final b in bindings) b.description];
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      ),
    );
    expect(listed, ['Toggle']);
  });
}
