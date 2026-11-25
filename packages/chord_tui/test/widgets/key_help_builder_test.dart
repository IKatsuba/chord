import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'builder snapshots follow scopes, bindings and chords at $size',
      (t) async {
        final enabled = ValueNotifier(true);
        addTearDown(enabled.dispose);
        final first = FocusNode();
        final second = FocusNode();
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        var invoked = 0;
        List<Binding> bindings = [];
        List<KeyCombo> pending = [];
        await t.pumpWidget(
          Actions(
            bindings: [
              Binding('x', 'Outer x', () {}),
              Binding('q', 'Quit', () {}),
            ],
            child: Column(
              children: [
                ListenableBuilder(
                  listenable: enabled,
                  builder: (_) => Actions(
                    bindings: [
                      Binding(
                        'x',
                        'Inner x',
                        () => invoked++,
                        enabled: enabled.value,
                      ),
                      Binding('ctrl+x a', 'Chord A', () {}),
                      Binding('z', 'Disabled', () {}, enabled: false),
                    ],
                    child: Focus(
                      focusNode: first,
                      autofocus: true,
                      child: Text('first'),
                    ),
                  ),
                ),
                Focus(focusNode: second, child: Text('second')),
                KeyHelp.builder(
                  builder: (_, current, chord) {
                    bindings = current;
                    pending = chord;
                    return Text(current.map((b) => b.description).join(', '));
                  },
                ),
              ],
            ),
          ),
          size: size,
        );
        expect(bindings.map((b) => b.description), [
          'Inner x',
          'Chord A',
          'Quit',
        ]);
        final oldBindings = bindings;
        expect(() => bindings.clear(), throwsUnsupportedError);
        expect(
          () => bindings.first.chord.combos.clear(),
          throwsUnsupportedError,
        );
        await t.press('x');
        expect(invoked, 1);
        expect(oldBindings.first.chord.toString(), 'x');
        expect(() => pending.add(KeyCombo.parse('q')), throwsUnsupportedError);
        await t.press('ctrl+x');
        expect(pending, [KeyCombo.parse('ctrl+x')]);
        final oldPending = pending;
        expect(
          bindings.length,
          3,
          reason: 'All active bindings survive pending prefix',
        );
        await t.press('a');
        expect(pending, isEmpty);
        expect(oldPending, [KeyCombo.parse('ctrl+x')]);
        await t.press('ctrl+x');
        await t.press('esc');
        expect(pending, isEmpty);
        enabled.value = false;
        await t.pump();
        expect(bindings.map((b) => b.description), [
          'Chord A',
          'Outer x',
          'Quit',
        ]);
        expect(oldBindings.first.description, 'Inner x');
        second.requestFocus();
        await t.pump();
        expect(bindings.map((b) => b.description), ['Outer x', 'Quit']);
        expect(t.screen, shows('Outer x, Quit'));
        t.dispose();
        enabled.value = true;
      },
    );
  }

  testWidgets('default help retains pending-prefix filtering and drawing', (
    t,
  ) async {
    await t.pumpWidget(
      Actions(
        bindings: [
          Binding('ctrl+x a', 'Answer', () {}),
          Binding('q', 'Quit', () {}),
        ],
        child: Focus(autofocus: true, child: const KeyHelp()),
      ),
    );
    expect(t.screen, shows('ctrl+x a Answer  q Quit'));
    await t.press('ctrl+x');
    expect(t.screen, shows('ctrl+x …  ctrl+x a Answer'));
    expect(t.screen.text, isNot(contains('Quit')));
  });

  group('tester: custom key help edges', () {
    for (final size in [const Size(0, 0), const Size(1, 1)]) {
      testWidgets('empty snapshots survive $size and resize', (t) async {
        List<Binding>? bindings;
        List<KeyCombo>? pending;
        await t.pumpWidget(
          KeyHelp.builder(
            builder: (_, active, prefix) {
              bindings = active;
              pending = prefix;
              return Text('empty help');
            },
          ),
          size: size,
        );
        expect(bindings, isEmpty);
        expect(pending, isEmpty);
        expect(
          () => bindings!.add(Binding('x', 'x', () {})),
          throwsUnsupportedError,
        );
        await t.resize(const Size(80, 24));
        expect(t.screen, shows('empty help'));
      });
    }

    testWidgets('custom content receives unbounded constraints', (t) async {
      BoxConstraints? seen;
      await t.pumpWidget(
        Row(
          children: [
            Column(
              children: [
                KeyHelp.builder(
                  builder: (_, _, _) => LayoutBuilder(
                    builder: (_, constraints) {
                      seen = constraints;
                      return Text('custom unbounded help');
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      expect(seen!.maxWidth, unbounded);
      expect(seen!.maxHeight, unbounded);
      expect(t.screen, shows('custom unbounded help'));
    });

    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('caller content preserves Unicode edges at $size', (t) async {
        await t.pumpWidget(
          KeyHelp.builder(
            builder: (_, _, _) => Column(
              children: [
                Text('界🙂e\u0301\x1b[31mR\x1b[0m'),
                const Spacer(),
                Row(children: [const Spacer(), Text('e\u0301🙂界')]),
              ],
            ),
          ),
          size: size,
        );
        expect(t.screen.lines.first, '界🙂e\u0301R');
        expect(t.screen.lines.last, endsWith('e\u0301🙂界'));
        expect(t.screen.charAt(size.width - 2, size.height - 1), '界');
        await t.resize(const Size(1, 1));
        await t.resize(size);
        expect(t.screen.lines.last, endsWith('e\u0301🙂界'));
      });
    }

    testWidgets(
      'burst binding updates retain old snapshots and detach the builder',
      (t) async {
        final revision = ValueNotifier(0);
        final visible = ValueNotifier(true);
        addTearDown(revision.dispose);
        addTearDown(visible.dispose);
        var builds = 0;
        var invoked = 0;
        List<Binding>? snapshot;
        await t.pumpWidget(
          ListenableBuilder(
            listenable: revision,
            builder: (_) => Actions(
              bindings: [
                Binding(
                  'ctrl+x a',
                  'Action ${revision.value}',
                  () => invoked++,
                ),
              ],
              child: Focus(
                autofocus: true,
                child: ListenableBuilder(
                  listenable: visible,
                  builder: (_) => visible.value
                      ? KeyHelp.builder(
                          builder: (_, bindings, _) {
                            builds++;
                            snapshot = bindings;
                            return Text(bindings.single.description);
                          },
                        )
                      : Text('removed'),
                ),
              ),
            ),
          ),
        );
        final first = snapshot!;
        for (var i = 1; i <= 1000; i++) {
          revision.value = i;
        }
        await t.pump();
        expect(t.screen, shows('Action 1000'));
        expect(first.single.description, 'Action 0');
        expect(first.single.chord.toString(), 'ctrl+x a');
        await t.press('ctrl+x');
        visible.value = false;
        await t.pump();
        final atRemoval = builds;
        await t.press('a');
        expect(invoked, 1);
        expect(builds, atRemoval);
        expect(t.screen, shows('removed'));
        visible.value = true;
        await t.pump();
        expect(t.screen, shows('Action 1000'));
        expect(snapshot!.single.description, 'Action 1000');
      },
    );
  });
}
