import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('CHD-638 tester: scope-self dispatch barriers', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('inactive and excluded descendants cannot suppress fallback '
          'at $size', (t) async {
        final scope = FocusScopeNode(active: false);
        final inactive = FocusScopeNode(active: false);
        final excluding = ValueNotifier(true);
        final log = <String>[];
        addTearDown(scope.dispose);
        addTearDown(inactive.dispose);
        addTearDown(excluding.dispose);
        await t.pumpWidget(
          Actions(
            bindings: [Binding('x', 'outer', () => log.add('outer'))],
            child: Focus(
              autofocus: true,
              child: FocusScope(
                node: scope,
                child: Actions(
                  bindings: [Binding('x', 'inside', () => log.add('inside'))],
                  child: Column(
                    children: [
                      FocusScope(
                        node: inactive,
                        child: Focus(
                          child: Actions(
                            bindings: [
                              Binding(
                                'x',
                                'inactive',
                                () => log.add('inactive'),
                              ),
                            ],
                            child: Text('inactive'),
                          ),
                        ),
                      ),
                      ListenableBuilder(
                        listenable: excluding,
                        builder: (_) => ExcludeFocus(
                          excluding: excluding.value,
                          child: Focus(
                            child: Actions(
                              bindings: [
                                Binding(
                                  'x',
                                  'excluded',
                                  () => log.add('excluded'),
                                ),
                              ],
                              child: Text('excluded'),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          size: size,
        );
        t.focusManager.setScopeActive(scope, true, takeFocus: true);
        await t.press('x');
        expect(t.focusManager.primaryFocus, same(scope));
        expect(log, ['inside']);
        excluding.value = false;
        await t.pump();
        await t.press('x');
        expect(t.focusManager.effectiveFocus, same(scope));
        expect(log, ['inside', 'outer']);
        excluding.value = true;
        await t.pump();
        await t.press('x');
        expect(log, ['inside', 'outer', 'inside']);
      });

      testWidgets('a non-scope primary never enters descendant Actions at '
          '$size', (t) async {
        final log = <String>[];
        await t.pumpWidget(
          Actions(
            bindings: [Binding('x', 'outer', () => log.add('outer'))],
            child: Focus(
              autofocus: true,
              child: Actions(
                bindings: [Binding('x', 'inner', () => log.add('inner'))],
                child: Text('界🙂e\u0301\x1b[31m'),
              ),
            ),
          ),
          size: size,
        );
        await t.press('x');
        expect(log, ['outer']);
        expect(
          t.focusManager.effectiveFocus,
          same(t.focusManager.primaryFocus),
        );
      });
    }
  });

  group('CHD-638 tester: scope-self dispatch lifecycle', () {
    for (final size in const [
      Size.zero,
      Size(1, 1),
      Size(80, 24),
      Size(120, 40),
    ]) {
      testWidgets('keys survive tiny and unbounded rooms, resize and a scope '
          'round trip at $size', (t) async {
        final scope = FocusScopeNode(active: false);
        addTearDown(scope.dispose);
        final received = <String>[];
        const keys = [
          'enter',
          'space',
          'escape',
          'tab',
          'shift+tab',
          'up',
          'down',
          'left',
          'right',
          'home',
          'end',
          'pageup',
          'pagedown',
          'backspace',
          'delete',
          'insert',
          'f1',
          'f2',
          'f3',
          'f4',
          'f5',
          'f6',
          'f7',
          'f8',
          'f9',
          'f10',
          'f11',
          'f12',
          'ctrl+c',
          'ctrl+q',
          'alt+x',
          'x',
        ];
        await t.pumpWidget(
          SingleChildScrollView(
            child: Focus(
              autofocus: true,
              child: FocusScope(
                node: scope,
                child: Actions(
                  bindings: [
                    for (final key in keys)
                      Binding(key, key, () => received.add(key)),
                    Binding('ctrl+k c', 'chord', () => received.add('chord')),
                  ],
                  child: Text('界🙂e\u0301\x1b[31m\n🙂界e\u0301'),
                ),
              ),
            ),
          ),
          size: size,
        );
        t.focusManager.setScopeActive(scope, true, takeFocus: true);
        for (final key in keys) {
          await t.press(key);
        }
        expect(received, keys);
        await t.resize(const Size(120, 40));
        for (var i = 0; i < 1000; i++) {
          t.host.handleKey(const KeyEvent('x'));
        }
        await t.pump();
        expect(received.length, keys.length + 1000);
        await t.press('ctrl+k');
        expect(t.focusManager.pendingChord, isNotEmpty);
        t.focusManager.setScopeActive(scope, false);
        expect(t.focusManager.pendingChord, isEmpty);
        t.focusManager.setScopeActive(scope, true, takeFocus: true);
        await t.press('c');
        expect(received, isNot(contains('chord')));
        await t.press('x');
        expect(received.length, keys.length + 1001);
        await t.press('ctrl+k');
        await t.pumpWidget(Text('removed'));
        await t.press('c');
        expect(received, isNot(contains('chord')));
        expect(t.screen.text, 'removed');
        expect(t.exitRequested, isFalse);
      });
    }
  });
}
