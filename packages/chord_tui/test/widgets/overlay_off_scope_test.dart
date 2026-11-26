import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// A page holding the focus beside a scope ([off] at first, else on) that
/// holds an overlay; [open] layers go over it once it is laid out, each a
/// focused field whose `x` logs its name.
class _Host extends StatefulWidget {
  const _Host({required this.off, required this.open, required this.log});

  final bool off;
  final List<String> open;
  final List<String> log;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late final scope = FocusScopeNode(active: !widget.off);
  late OverlayState overlay;
  var opened = false;

  @override
  void dispose() {
    scope.dispose();
    super.dispose();
  }

  void enter() =>
      context.owner.focusManager.setScopeActive(scope, true, takeFocus: true);

  OverlayEntry layer(String name) => OverlayEntry(
    builder: (_) => Actions(
      bindings: [Binding('x', name, () => widget.log.add(name))],
      child: Focus(autofocus: true, child: Text('layer $name')),
    ),
  );

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      Binding('tab', 'enter', enter),
      Binding('p', 'page', () => widget.log.add('page')),
    ],
    child: Focus(
      autofocus: true,
      child: Column(
        children: [
          Text('page'),
          Expanded(
            child: FocusScope(
              node: scope,
              child: Overlay(
                initialEntries: [
                  OverlayEntry(
                    builder: (context) {
                      overlay = Overlay.of(context);
                      if (!opened) {
                        opened = true;
                        context.owner.afterLayout(() {
                          for (final name in widget.open) {
                            overlay.insert(layer(name));
                          }
                        });
                      }
                      return Text('base');
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('a layer opened under a scope that is off leaves the page '
        'its focus, and takes it when the scope is entered, at $size', (
      t,
    ) async {
      final log = <String>[];
      await t.pumpWidget(
        _Host(off: true, open: ['dialog'], log: log),
        size: size,
      );
      await t.pump();
      expect(t.screen, shows('layer dialog'));
      await t.press('p');
      await t.press('x');
      expect(log, ['page'], reason: 'the page still has the keys');
      await t.press('tab');
      await t.press('x');
      expect(log, ['page', 'dialog']);
    });
  }

  testWidgets('with no scope off above it, a layer takes the focus when it '
      'opens, as before', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      _Host(off: false, open: ['dialog'], log: log),
      size: const Size(80, 24),
    );
    await t.pump();
    await t.press('x');
    expect(log, ['dialog']);
  });

  testWidgets('a later layer\'s request replaces a pending one', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      _Host(off: true, open: ['first', 'second'], log: log),
      size: const Size(80, 24),
    );
    await t.pump();
    await t.press('tab');
    await t.press('x');
    expect(log, ['second']);
  });

  group('a scope turned on under one that is off', () {
    late FocusManager manager;
    late FocusScopeNode outer, inner;
    late FocusNode asked;

    setUp(() {
      manager = FocusManager();
      outer = FocusScopeNode(active: false)..attach(manager.root);
      inner = FocusScopeNode(active: false)..attach(outer);
      asked = FocusNode()..attach(inner);
      asked.requestFocus();
    });

    for (final (label, takeFocus, autofocus, expected) in [
      ('with neither flag passes no request up', false, false, false),
      ('with autofocus passes the asked node up', false, true, true),
      ('with takeFocus passes the asked node up', true, false, true),
    ]) {
      test(label, () {
        manager.setScopeActive(
          inner,
          true,
          takeFocus: takeFocus,
          autofocus: autofocus,
        );
        expect(manager.primaryFocus, isNull, reason: 'nothing moves yet');
        manager.setScopeActive(outer, true, autofocus: true);
        expect(asked.hasPrimaryFocus, expected);
      });
    }
  });
}
