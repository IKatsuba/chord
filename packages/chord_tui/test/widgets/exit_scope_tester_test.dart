import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

class _ExitProbe extends StatelessWidget {
  const _ExitProbe({this.node, this.autofocus = true});
  final FocusNode? node;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [Binding('ctrl+x', 'Request exit', () => exitApp(context))],
    child: Focus(
      focusNode: node,
      autofocus: autofocus,
      child: Text('界👩‍💻e\u0301'),
    ),
  );
}

void main() {
  group('CHD-638 tester: exit scope live ownership', () {
    for (final size in [
      Size.zero,
      const Size(1, 1),
      const Size(80, 24),
      const Size(120, 40),
    ]) {
      testWidgets('a retained child uses the latest callback at $size', (
        t,
      ) async {
        final revision = ValueNotifier(0);
        addTearDown(revision.dispose);
        final taken = <int>[];
        await t.pumpWidget(
          ListenableBuilder(
            listenable: revision,
            builder: (_) {
              final value = revision.value;
              return ExitScope(
                onExit: () => taken.add(value),
                child: const _ExitProbe(),
              );
            },
          ),
          size: size,
        );
        await t.press('ctrl+x');
        for (var i = 0; i < 1000; i++) {
          revision.value = i;
        }
        await t.pump();
        await t.press('ctrl+x');
        expect(taken, [0, 999]);
        expect(t.exitRequested, isFalse);
      });
    }

    testWidgets('scope removal restores the host exit route', (t) async {
      final scoped = ValueNotifier(true);
      addTearDown(scoped.dispose);
      var taken = 0;
      await t.pumpWidget(
        ListenableBuilder(
          listenable: scoped,
          builder: (_) => scoped.value
              ? ExitScope(
                  onExit: () {
                    taken++;
                    scoped.value = false;
                  },
                  child: const _ExitProbe(),
                )
              : const _ExitProbe(),
        ),
      );
      await t.press('ctrl+x');
      expect(taken, 1);
      expect(t.exitRequested, isFalse);
      await t.press('ctrl+x');
      expect(taken, 1);
      expect(t.exitRequested, isTrue);
    });

    testWidgets('a callback error does not bubble to an outer scope or host', (
      t,
    ) async {
      final failure = StateError('scope callback failure');
      var outer = 0;
      await t.pumpWidget(
        ExitScope(
          onExit: () => outer++,
          child: ExitScope(
            onExit: () => throw failure,
            child: const _ExitProbe(),
          ),
        ),
      );
      await expectLater(t.press('ctrl+x'), throwsA(same(failure)));
      expect(outer, 0);
      expect(t.exitRequested, isFalse);
    });

    testWidgets('an unbounded parent does not change exit interception', (
      t,
    ) async {
      var taken = 0;
      await t.pumpWidget(
        ExitScope(
          onExit: () => taken++,
          child: Row(children: [const _ExitProbe()]),
        ),
      );
      await t.press('ctrl+x');
      expect(taken, 1);
      expect(t.exitRequested, isFalse);
    });

    testWidgets(
      'focus moving between siblings uses each scope without leaking',
      (t) async {
        final first = FocusNode(), second = FocusNode();
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        var a = 0, b = 0;
        await t.pumpWidget(
          Column(
            children: [
              ExitScope(
                onExit: () => a++,
                child: _ExitProbe(node: first),
              ),
              ExitScope(
                onExit: () => b++,
                child: _ExitProbe(node: second, autofocus: false),
              ),
            ],
          ),
        );
        await t.press('ctrl+x');
        second.requestFocus();
        await t.pump();
        await t.press('ctrl+x');
        first.requestFocus();
        await t.resize(const Size(120, 40));
        await t.press('ctrl+x');
        expect((a, b), (2, 1));
        expect(t.exitRequested, isFalse);
      },
    );
  });
}
