import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const BoundaryExample());

/// A drawing failure, its latched fallback, and replacement by a new key.
class BoundaryExample extends StatefulWidget {
  const BoundaryExample({super.key});

  @override
  State<BoundaryExample> createState() => _BoundaryExampleState();
}

class _BoundaryExampleState extends State<BoundaryExample> {
  final fail = ValueNotifier(false);
  int generation = 0;

  @override
  void dispose() {
    fail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      Binding('x', 'Fail child', () => fail.value = true),
      Binding(
        'r',
        'Replace boundary',
        () => setState(() {
          fail.value = false;
          generation++;
        }),
      ),
      Binding('q', 'Quit', () => exitApp(context)),
    ],
    child: Focus(
      autofocus: true,
      child: Column(
        children: [
          Expanded(
            child: ErrorBoundary(
              key: ValueKey(generation),
              errorBuilder: (context, error, stack) => LayoutBuilder(
                builder: (_, constraints) => Text(
                  'Fallback at ${constraints.maxWidth} columns\n$error\nResize, or press r to replace the boundary.',
                  style: Theme.of(context).error,
                ),
              ),
              child: ListenableBuilder(
                listenable: fail,
                builder: (_) {
                  if (fail.value) throw StateError('The example child failed');
                  return Text('Healthy child. Press x to fail its build.');
                },
              ),
            ),
          ),
          const KeyHelp(),
        ],
      ),
    ),
  );
}
