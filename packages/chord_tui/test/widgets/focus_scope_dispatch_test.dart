import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// A page holding the focus beside a scope, off until [enter] turns it on;
/// under the scope, bindings with no focusable widget, and a focusable one
/// when [focusable].
class _Host extends StatefulWidget {
  const _Host({required this.focusable, required this.log});

  final bool focusable;
  final List<String> log;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final scope = FocusScopeNode(active: false);

  @override
  void dispose() {
    scope.dispose();
    super.dispose();
  }

  void enter() =>
      context.owner.focusManager.setScopeActive(scope, true, takeFocus: true);

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      Binding('tab', 'enter', enter),
      Binding('x', 'page x', () => widget.log.add('page x')),
    ],
    child: Focus(
      autofocus: true,
      child: Column(
        children: [
          Text('page'),
          FocusScope(
            node: scope,
            child: Actions(
              bindings: [
                Binding('x', 'scope x', () => widget.log.add('scope x')),
              ],
              child: Column(
                children: [
                  if (widget.focusable) Focus(child: Text('focusable')),
                  Text('bindings'),
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
    testWidgets('a scope holding the focus itself, with nothing focusable '
        'under it, starts keys at its deepest first node, at $size', (t) async {
      final log = <String>[];
      await t.pumpWidget(_Host(focusable: false, log: log), size: size);
      await t.press('x');
      expect(log, ['page x']);
      await t.press('tab');
      await t.press('x');
      expect(log, ['page x', 'scope x']);
    });

    testWidgets('a scope with a focusable node under it starts keys at '
        'itself, as before, at $size', (t) async {
      final log = <String>[];
      await t.pumpWidget(_Host(focusable: true, log: log), size: size);
      await t.press('tab');
      await t.press('x');
      // The scope holds the focus above the bindings under it: the page's.
      expect(log, ['page x']);
    });
  }
}
