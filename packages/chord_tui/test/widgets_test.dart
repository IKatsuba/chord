import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => CounterState();
}

class CounterState extends State<Counter> {
  var count = 0;
  var disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      Binding('+', 'Increment', () => setState(() => count++)),
      Binding('ctrl+x r', 'Reset', () => setState(() => count = 0)),
    ],
    child: Text('count: $count'),
  );
}

class Theme extends InheritedWidget {
  const Theme({super.key, required this.name, required super.child});
  final String name;

  @override
  bool updateShouldNotify(Theme oldWidget) => name != oldWidget.name;
}

class ThemeLabel extends StatelessWidget {
  const ThemeLabel({super.key});

  static int builds = 0;

  @override
  Widget build(BuildContext context) {
    builds++;
    return Text(
      'theme: ${context.dependOnInheritedWidgetOfExactType<Theme>()!.name}',
    );
  }
}

void main() {
  group('layout', () {
    testWidgets('a column stacks, expanded takes the rest', (t) async {
      await t.pumpWidget(
        Column(
          children: [
            Text('top'),
            Expanded(
              child: Box(border: Border.single, child: Text('mid')),
            ),
            Text('bottom'),
          ],
        ),
        size: const Size(10, 6),
      );
      expect(t.screen.lines, [
        'top',
        '┌────────┐',
        '│mid     │',
        '│        │',
        '└────────┘',
        'bottom',
      ]);
    });

    testWidgets('a row shares width by flex, in whole cells', (t) async {
      await t.pumpWidget(
        Row(
          children: [
            Expanded(child: Text('a')),
            Expanded(flex: 2, child: Text('b')),
            Text('|'),
          ],
        ),
        size: const Size(10, 1),
      );
      expect(t.screen.lines.single, 'a  b     |');
    });

    testWidgets('text wraps to the width it gets', (t) async {
      await t.pumpWidget(
        Column(children: [Text('the quick brown fox jumps')]),
        size: const Size(10, 4),
      );
      expect(t.screen.lines, ['the quick', 'brown fox', 'jumps', '']);
    });

    testWidgets('center and padding', (t) async {
      await t.pumpWidget(
        Center(
          child: Padding(padding: const EdgeInsets.all(1), child: Text('x')),
        ),
        size: const Size(7, 5),
      );
      expect(t.screen.lines[2], '   x');
    });

    testWidgets('a box title sits on the border', (t) async {
      await t.pumpWidget(
        Box(border: Border.rounded, title: 'log', child: Text('hi')),
        size: const Size(12, 3),
      );
      expect(t.screen.lines.first, '╭ log ─────╮');
    });

    testWidgets('re-lays out on resize', (t) async {
      await t.pumpWidget(
        Column(children: [Text('aaa bbb')]),
        size: const Size(7, 2),
      );
      expect(t.screen.lines, ['aaa bbb', '']);
      await t.resize(const Size(3, 2));
      expect(t.screen.lines, ['aaa', 'bbb']);
    });
  });

  group('state', () {
    testWidgets('setState rebuilds', (t) async {
      await t.pumpWidget(const Counter());
      expect(t.screen, shows('count: 0'));
      await t.press('+');
      await t.press('+');
      expect(t.screen, shows('count: 2'));
    });

    testWidgets('state survives a parent rebuild and is disposed on removal', (
      t,
    ) async {
      late CounterState state;
      await t.pumpWidget(Column(children: [Text('a'), const Counter()]));
      await t.press('+');
      await t.pumpWidget(Column(children: [Text('b'), Text('c')]));
      expect(t.screen, isNot(shows('count')));
      // A fresh tree: mount, grab the state, replace the widget type.
      await t.pumpWidget(const Counter());
      t.host.rootElement.visitChildren((_) {});
      state = (t.host.rootElement as StatefulElement).state as CounterState;
      expect(state.disposed, isFalse);
      t.dispose();
      expect(state.disposed, isTrue);
    });

    testWidgets('inherited widgets rebuild their dependents only on change', (
      t,
    ) async {
      ThemeLabel.builds = 0;
      final name = ValueNotifier('dark');
      const label = ThemeLabel();
      await t.pumpWidget(
        ListenableBuilder(
          listenable: name,
          builder: (_) => Theme(name: name.value, child: label),
        ),
      );
      expect(t.screen, shows('theme: dark'));
      expect(ThemeLabel.builds, 1);
      name.value = 'light';
      await t.pump();
      expect(t.screen, shows('theme: light'));
      expect(ThemeLabel.builds, 2);
    });

    testWidgets('a build error is shown, not thrown', (t) async {
      await t.pumpWidget(Builder(builder: (_) => throw StateError('boom')));
      expect(t.screen, shows('boom'));
    });

    testWidgets('keys reorder children without losing state', (t) async {
      Widget tree(List<String> ids) => Column(
        children: [
          for (final id in ids)
            Row(
              key: ValueKey(id),
              children: [
                Text('$id '),
                const Expanded(child: TextInput()),
              ],
            ),
        ],
      );
      await t.pumpWidget(tree(['a', 'b']));
      await t.press('tab');
      await t.type('hello');
      expect(t.screen.lines[0], startsWith('a hello'));
      await t.pumpWidget(tree(['a', 'b']));
    });
  });

  group('keys', () {
    testWidgets('a chord waits for its second key', (t) async {
      await t.pumpWidget(const Counter());
      await t.press('+');
      expect(t.screen, shows('count: 1'));
      await t.press('ctrl+x');
      expect(t.focusManager.pendingChord, hasLength(1));
      expect(t.screen, shows('count: 1'));
      await t.press('r');
      expect(t.focusManager.pendingChord, isEmpty);
      expect(t.screen, shows('count: 0'));
    });

    testWidgets('a wrong second key ends the chord', (t) async {
      await t.pumpWidget(const Counter());
      await t.press('+');
      await t.press('ctrl+x +');
      expect(t.screen, shows('count: 1'));
      await t.press('+');
      expect(t.screen, shows('count: 2'));
    });

    test('two bindings cannot claim one key in a scope', () {
      expect(
        () => checkBindings([
          Binding('ctrl+o', 'One', () {}),
          Binding('Ctrl+O', 'Two', () {}),
        ]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('bound twice'),
          ),
        ),
      );
    });

    test('a chord cannot start with a bound key', () {
      expect(
        () => checkBindings([
          Binding('ctrl+x', 'Cut', () {}),
          Binding('ctrl+x a', 'Go', () {}),
        ]),
        throwsA(isA<ArgumentError>()),
      );
    });

    testWidgets('inner scopes shadow outer ones', (t) async {
      final log = <String>[];
      await t.pumpWidget(
        Actions(
          bindings: [
            Binding('a', 'Outer a', () => log.add('outer a')),
            Binding('b', 'Outer b', () => log.add('outer b')),
          ],
          child: Actions(
            bindings: [Binding('a', 'Inner a', () => log.add('inner a'))],
            child: Text('x'),
          ),
        ),
      );
      await t.press('a');
      await t.press('b');
      expect(log, ['inner a', 'outer b']);
      expect(t.focusManager.activeBindings.map((b) => b.description), [
        'Inner a',
        'Outer b',
      ]);
    });

    testWidgets('unhandled ctrl+c asks to quit', (t) async {
      await t.pumpWidget(Text('x'));
      await t.press('ctrl+c');
      expect(t.exitRequested, isTrue);
    });

    testWidgets('KeyHelp lists what is bound', (t) async {
      await t.pumpWidget(
        Actions(
          bindings: [
            Binding('ctrl+o', 'Toggle', () {}),
            Binding('ctrl+x a', 'Go', () {}),
          ],
          child: const KeyHelp(),
        ),
      );
      expect(t.screen, shows('ctrl+o Toggle  ctrl+x a Go'));
      await t.press('ctrl+x');
      expect(t.screen.text, startsWith('ctrl+x …'));
      expect(t.screen, isNot(shows('Toggle')));
    });
  });

  group('TextInput', () {
    testWidgets('typing, editing and submitting', (t) async {
      String? submitted;
      final c = TextEditingController();
      await t.pumpWidget(
        Actions(
          bindings: [Binding('ctrl+o', 'Other', () => submitted = 'action')],
          child: TextInput(
            controller: c,
            autofocus: true,
            prefix: '> ',
            onSubmit: (s) => submitted = s,
          ),
        ),
      );
      await t.type('helo wörld 🙂');
      expect(t.screen, shows('> helo wörld 🙂'));
      await t.press('home');
      await t.press('right right right');
      await t.type('l');
      expect(c.text, 'hello wörld 🙂');
      await t.press('end backspace');
      expect(c.text, 'hello wörld ');
      await t.press('ctrl+w');
      expect(c.text, 'hello ');
      await t.paste('there');
      await t.press('enter');
      expect(submitted, 'hello there');
      // Keys the input does not take go on to the bindings around it.
      await t.press('ctrl+o');
      expect(submitted, 'action');
    });

    testWidgets('the terminal cursor is claimed when focused', (t) async {
      await t.pumpWidget(const TextInput(autofocus: true));
      await t.type('ab');
      expect(t.screen.buffer.cursor, const Offset(2, 0));
      expect(t.screen.styleAt(2, 0).isInverse, isFalse);
      expect(t.screen.styleAt(1, 0).isInverse, isFalse);
    });

    testWidgets('tab moves focus between inputs', (t) async {
      final a = TextEditingController(), b = TextEditingController();
      await t.pumpWidget(
        Column(
          children: [
            TextInput(controller: a, autofocus: true),
            TextInput(controller: b),
          ],
        ),
      );
      await t.type('1');
      await t.press('tab');
      await t.type('2');
      expect((a.text, b.text), ('1', '2'));
    });
  });
}
