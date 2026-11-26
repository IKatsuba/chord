import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// Calls exitApp from its own context on ctrl+x.
class _Quits extends StatelessWidget {
  const _Quits(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Actions(
    bindings: [Binding('ctrl+x', 'quit', () => exitApp(context))],
    child: Focus(autofocus: true, child: Text(label)),
  );
}

class _Terminal extends Terminal {
  final input$ = StreamController<String>();
  @override
  Size get size => const Size(80, 24);
  @override
  Stream<String> get input => input$.stream;
  @override
  Stream<Size> get resizes => const Stream.empty();
  @override
  void write(String data) {}
  @override
  void enter() {}
  @override
  Future<void> leave() async {}
}

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('at $size', () {
      testWidgets('without a scope, exitApp quits as before', (t) async {
        await t.pumpWidget(const _Quits('app'), size: size);
        await t.press('ctrl+x');
        expect(t.exitRequested, isTrue);
      });

      testWidgets('under a scope, exitApp runs onExit and does not quit', (
        t,
      ) async {
        var taken = 0;
        await t.pumpWidget(
          ExitScope(onExit: () => taken++, child: const _Quits('embedded')),
          size: size,
        );
        await t.press('ctrl+x');
        expect(taken, 1);
        expect(t.exitRequested, isFalse);
      });

      testWidgets('the nearest scope takes it, with no bubbling', (t) async {
        var outer = 0, inner = 0;
        await t.pumpWidget(
          ExitScope(
            onExit: () => outer++,
            child: ExitScope(
              onExit: () => inner++,
              child: const _Quits('nested'),
            ),
          ),
          size: size,
        );
        await t.press('ctrl+x');
        expect((outer, inner), (0, 1));
        expect(t.exitRequested, isFalse);
      });

      testWidgets('exitApp from above the scope still quits', (t) async {
        var taken = 0;
        await t.pumpWidget(
          Builder(
            builder: (outside) => Actions(
              bindings: [
                Binding('ctrl+y', 'quit the app', () => exitApp(outside)),
              ],
              child: ExitScope(
                onExit: () => taken++,
                child: const _Quits('embedded'),
              ),
            ),
          ),
          size: size,
        );
        await t.press('ctrl+y');
        expect(taken, 0);
        expect(t.exitRequested, isTrue);
      });
    });
  }

  test(
    'runApp: an exit under a scope keeps it running; one above ends it',
    () async {
      final term = _Terminal();
      var taken = 0;
      var returned = false;
      final running = runApp(
        Builder(
          builder: (outside) => Actions(
            bindings: [Binding('ctrl+y', 'quit', () => exitApp(outside))],
            child: ExitScope(onExit: () => taken++, child: const _Quits('app')),
          ),
        ),
        terminal: term,
        exitProcess: false,
        handleSignals: false,
        environment: const {},
      ).then((_) => returned = true);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      term.input$.add('\x18'); // ctrl+x, inside the scope
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(taken, 1);
      expect(returned, isFalse);
      term.input$.add('\x19'); // ctrl+y, above it
      await running.timeout(const Duration(seconds: 5));
      expect(returned, isTrue);
      await term.input$.close();
    },
  );
}
