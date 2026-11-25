import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  group('tester: key capture capabilities and paste route snapshots', () {
    for (final change in ['focus round trip', 'registration round trip']) {
      test('$change invalidates a match despite equal final state', () {
        final manager = FocusManager();
        final other = FocusNode()..attach(manager.root);
        var actions = 0;
        final action = Binding('x', 'Action', () => actions++);
        final node = FocusNode()
          ..attach(manager.root)
          ..bindings = [action]
          ..requestFocus();
        node.onKeyCapture = (event) {
          final match = manager.matchKey(event);
          if (change == 'focus round trip') {
            other.requestFocus();
            node.requestFocus();
          } else {
            node.bindings = [Binding('x', 'Action', () => actions += 100)];
            node.bindings = [action];
          }
          expect(match.dispatch(), isFalse);
          return true;
        };
        manager.dispatchKey(const KeyEvent('x'));
        expect(actions, 0);
        node.dispose();
        other.dispose();
        manager.dispose();
      });
    }

    test('a rejected live filter result is still one-use', () {
      final manager = FocusManager();
      var eligible = true, actions = 0;
      final node = FocusNode()
        ..attach(manager.root)
        ..bindings = [Binding('x', 'Action', () => actions++)]
        ..requestFocus();
      node.onKeyCapture = (event) {
        final match = manager.matchKey(event, where: (_) => eligible);
        eligible = false;
        expect(match.dispatch(), isFalse);
        eligible = true;
        expect(match.dispatch(), isFalse);
        expect(
          manager.matchKey(event, where: (_) => eligible).dispatch(),
          isTrue,
        );
        return false;
      };
      manager.dispatchKey(const KeyEvent('x'));
      expect(actions, 1);
      node.dispose();
      manager.dispose();
    });

    test('one thousand previews never invoke or pend before one dispatch', () {
      final manager = FocusManager();
      var actions = 0, normals = 0;
      final node =
          FocusNode(
              onKey: (_) {
                normals++;
                return true;
              },
            )
            ..attach(manager.root)
            ..bindings = [Binding('x', 'Action', () => actions++)]
            ..requestFocus();
      node.onKeyCapture = (event) {
        final previews = [
          for (var i = 0; i < 1000; i++) manager.matchKey(event),
        ];
        expect(actions, 0);
        expect(manager.pendingChord, isEmpty);
        expect(previews.last.dispatch(), isTrue);
        for (final preview in previews.take(999)) {
          expect(preview.dispatch(), isFalse);
        }
        return false;
      };
      manager.dispatchKey(const KeyEvent('x'));
      expect((actions, normals), (1, 0));
      node.dispose();
      manager.dispose();
    });

    test(
      'previous identical input event cannot lend its match to the next input',
      () {
        final manager = FocusManager();
        KeyBindingMatch? old;
        var actions = 0;
        final node = FocusNode()
          ..attach(manager.root)
          ..bindings = [Binding('x', 'Action', () => actions++)]
          ..requestFocus();
        node.onKeyCapture = (event) {
          if (old == null) {
            old = manager.matchKey(event);
          } else {
            expect(old!.dispatch(), isFalse);
            expect(manager.matchKey(event).dispatch(), isTrue);
          }
          return true;
        };
        const event = KeyEvent('x');
        manager.dispatchKey(event);
        manager.dispatchKey(event);
        expect(actions, 1);
        node.dispose();
        manager.dispose();
      },
    );

    test(
      'paste callback replacement waits for the next paste including empty',
      () {
        final manager = FocusManager();
        final log = <String>[];
        final outer = FocusNode()..attach(manager.root);
        final inner =
            FocusNode(
                onPasteCapture: (text) {
                  log.add('old:$text');
                  return true;
                },
              )
              ..attach(outer)
              ..requestFocus();
        outer.onPasteCapture = (_) {
          inner.onPasteCapture = (text) {
            log.add('new:$text');
            return true;
          };
          return false;
        };
        manager.dispatchPaste('');
        manager.dispatchPaste('界👩‍💻e\u0301\x1b[31m');
        expect(log, ['old:', 'new:界👩‍💻e\u0301\x1b[31m']);
        inner.dispose();
        outer.dispose();
        manager.dispose();
      },
    );

    test(
      'capture disposal skips old receiver and never replays into new focus',
      () {
        final manager = FocusManager();
        final log = <String>[];
        final outer = FocusNode()..attach(manager.root);
        final next = FocusNode(
          onKey: (_) {
            log.add('next');
            return true;
          },
        )..attach(outer);
        final old =
            FocusNode(
                onKeyCapture: (_) {
                  log.add('old capture');
                  return false;
                },
                onKey: (_) {
                  log.add('old');
                  return true;
                },
              )
              ..attach(outer)
              ..requestFocus();
        outer.onKeyCapture = (_) {
          old.dispose();
          next.requestFocus();
          return false;
        };
        manager.dispatchKey(const KeyEvent('x'));
        expect(log, isEmpty);
        expect(next.hasPrimaryFocus, isTrue);
        next.dispose();
        outer.dispose();
        manager.dispose();
      },
    );
  });
}
