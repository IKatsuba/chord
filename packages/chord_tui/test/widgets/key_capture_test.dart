import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'capture visits ancestors before focused normal key and empty paste',
    () {
      final manager = FocusManager();
      final calls = <String>[];
      final outer = FocusNode(
        onKeyCapture: (_) {
          calls.add('outer capture');
          return false;
        },
        onPasteCapture: (text) {
          calls.add('outer paste:$text');
          return false;
        },
      )..attach(manager.root);
      final inner =
          FocusNode(
              onKeyCapture: (_) {
                calls.add('inner capture');
                return false;
              },
              onKey: (_) {
                calls.add('normal');
                return true;
              },
              onPasteCapture: (text) {
                calls.add('inner paste:$text');
                return false;
              },
              onPaste: (text) {
                calls.add('paste:$text');
                return true;
              },
            )
            ..attach(outer)
            ..requestFocus();
      manager.dispatchKey(const KeyEvent('x'));
      expect(calls, ['outer capture', 'inner capture', 'normal']);
      calls.clear();
      manager.dispatchPaste('');
      expect(calls, ['outer paste:', 'inner paste:', 'paste:']);
      inner.dispose();
      outer.dispose();
      manager.dispose();
    },
  );

  test('filtered capture owns exact and prefix before a typing handler', () {
    final manager = FocusManager();
    final typed = <String>[];
    var copies = 0;
    final copy = Binding('x c', 'Priority action', () => copies++);
    final outer = FocusNode()
      ..attach(manager.root)
      ..bindings = [copy];
    outer.onKeyCapture = (event) {
      final match = manager.matchKey(event, where: (b) => identical(b, copy));
      if (match.kind == KeyBindingMatchKind.dropped) {
        final pending = manager.pendingChord;
        expect(match.dispatch(), isFalse);
        expect(manager.pendingChord, pending);
        return false;
      }
      return match.dispatch();
    };
    final inner =
        FocusNode(
            onKey: (event) {
              typed.add(event.key);
              return true;
            },
          )
          ..attach(outer)
          ..requestFocus();
    manager.dispatchKey(const KeyEvent('x'));
    expect(manager.pendingChord, [KeyCombo.parse('x')]);
    manager.dispatchKey(const KeyEvent('z'));
    expect(manager.pendingChord, isEmpty);
    expect(typed, isEmpty);
    manager.dispatchKey(const KeyEvent('x'));
    manager.dispatchKey(const KeyEvent('c'));
    expect(copies, 1);
    expect(typed, isEmpty);
    manager.dispatchKey(const KeyEvent('y'));
    expect(typed, ['y']);
    inner.dispose();
    outer.dispose();
    manager.dispose();
  });

  test(
    'match fields are immutable and accepted dispatch is exclusive and one-use',
    () {
      final manager = FocusManager();
      var invoked = 0, typed = 0;
      late KeyBindingMatch saved;
      final binding = Binding('x', 'Action', () => invoked++);
      final node =
          FocusNode(
              onKey: (_) {
                typed++;
                return true;
              },
            )
            ..attach(manager.root)
            ..bindings = [binding]
            ..requestFocus();
      node.onKeyCapture = (event) {
        saved = manager.matchKey(event);
        expect(saved.kind, KeyBindingMatchKind.exact);
        expect(saved.binding, same(binding));
        expect(saved.sequence, [event.combo]);
        expect(() => saved.sequence.clear(), throwsUnsupportedError);
        expect(saved.dispatch(), isTrue);
        expect(saved.dispatch(), isFalse);
        return false;
      };
      manager.dispatchKey(const KeyEvent('x'));
      expect((invoked, typed), (1, 0));
      expect(saved.dispatch(), isFalse);
      node.dispose();
      manager.dispose();
    },
  );

  test(
    'pending cancellation permits a fresh match without replaying the prefix',
    () {
      final manager = FocusManager();
      var ordinary = 0;
      final raw = Binding('ctrl+c', 'Ordinary action', () => ordinary++);
      final node = FocusNode()
        ..attach(manager.root)
        ..bindings = [Binding('ctrl+x a', 'Chord', () {}), raw]
        ..requestFocus();
      node.onKeyCapture = (event) {
        if (event.combo != KeyCombo.parse('ctrl+c')) return false;
        final old = manager.matchKey(event, where: (b) => identical(b, raw));
        expect(old.kind, KeyBindingMatchKind.dropped);
        expect(old.dispatch(), isFalse);
        expect(manager.pendingChord, [KeyCombo.parse('ctrl+x')]);
        manager.cancelPendingChord();
        expect(old.dispatch(), isFalse);
        return manager
            .matchKey(event, where: (b) => identical(b, raw))
            .dispatch();
      };
      manager.dispatchKey(KeyCombo.parse('ctrl+x').toEvent());
      manager.dispatchKey(KeyCombo.parse('ctrl+c').toEvent());
      expect(ordinary, 1);
      node.dispose();
      manager.dispose();
    },
  );

  for (final stale in [
    'focus',
    'binding',
    'pending',
    'dispose',
    'reentrant input',
  ]) {
    test('stale match dispatch has no effect after $stale', () {
      final manager = FocusManager();
      var invoked = 0;
      final typed = <String>[];
      final other = FocusNode(
        onKey: (_) {
          typed.add('other');
          return true;
        },
      )..attach(manager.root);
      final node =
          FocusNode(
              onKey: (event) {
                typed.add(event.key);
                return true;
              },
            )
            ..attach(manager.root)
            ..bindings = [Binding('x', 'Action', () => invoked++)]
            ..requestFocus();
      node.onKeyCapture = (event) {
        if (event.key != 'x') return false;
        final match = manager.matchKey(event);
        switch (stale) {
          case 'focus':
            other.requestFocus();
          case 'binding':
            node.bindings = [Binding('x', 'Replacement', () => invoked++)];
          case 'pending':
            manager.cancelPendingChord();
          case 'dispose':
            node.dispose();
          case 'reentrant input':
            manager.dispatchKey(const KeyEvent('z'));
        }
        expect(match.dispatch(), isFalse);
        return stale == 'pending';
      };
      manager.dispatchKey(const KeyEvent('x'));
      expect(invoked, 0);
      expect(typed, stale == 'reentrant input' ? ['z'] : isEmpty);
      if (!node.isDisposed) node.dispose();
      other.dispose();
      manager.dispose();
    });
  }

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'public capture precedes editor input and sees empty paste $size',
      (t) async {
        final text = TextAreaController();
        var actions = 0, pastes = 0;
        late Binding binding;
        binding = Binding('v', 'Capture printable action', () => actions++);
        await t.pumpWidget(
          Actions(
            bindings: [binding],
            child: Focus(
              canRequestFocus: false,
              onKeyCapture: (event) => t.focusManager
                  .matchKey(event, where: (b) => identical(b, binding))
                  .dispatch(),
              onPasteCapture: (_) {
                pastes++;
                return false;
              },
              child: TextArea(controller: text, autofocus: true),
            ),
          ),
          size: size,
        );
        await t.type('v');
        expect(actions, 1);
        expect(text.text, '');
        await t.type('x');
        expect(text.text, 'x');
        await t.paste('');
        expect(pastes, 1);
        text.dispose();
      },
    );
  }
  test(
    'filtered binding preview bypasses modal chord shadowing only when dispatched',
    () {
      final manager = FocusManager();
      final calls = <String>[];
      final selected = Binding(
        'v',
        'Selected action',
        () => calls.add('selected'),
      );
      final outer = FocusNode()
        ..attach(manager.root)
        ..bindings = [selected];
      final modal =
          FocusNode(
              onKey: (_) {
                calls.add('form');
                return true;
              },
            )
            ..attach(outer)
            ..bindings = [
              Binding('v', 'Modal action', () => calls.add('modal')),
            ]
            ..requestFocus();
      outer.onKeyCapture = (event) => manager
          .matchKey(event, where: (binding) => identical(binding, selected))
          .dispatch();
      manager.dispatchKey(const KeyEvent('v'));
      expect(calls, ['selected']);
      outer.onKeyCapture = (event) {
        expect(manager.matchKey(event).kind, KeyBindingMatchKind.exact);
        return false;
      };
      manager.dispatchKey(const KeyEvent('v'));
      expect(calls, ['selected', 'form']);
      modal.dispose();
      outer.dispose();
      manager.dispose();
    },
  );

  test('normal inner prefix and pending binding order are unchanged', () {
    final manager = FocusManager();
    final calls = <String>[];
    final outer =
        FocusNode(
            onKey: (_) {
              calls.add('outer');
              return false;
            },
          )
          ..attach(manager.root)
          ..bindings = [
            Binding('x', 'Outer', () => calls.add('outer binding')),
          ];
    final inner =
        FocusNode(
            onKey: (_) {
              calls.add('inner');
              return false;
            },
          )
          ..attach(outer)
          ..bindings = [
            Binding('x c', 'Inner prefix', () => calls.add('inner binding')),
          ]
          ..requestFocus();
    manager.dispatchKey(const KeyEvent('x'));
    expect(calls, ['inner']);
    manager.dispatchKey(const KeyEvent('c'));
    expect(calls, ['inner', 'inner binding']);
    inner.dispose();
    outer.dispose();
    manager.dispose();
  });

  test(
    'capture callback snapshot waits until next input to see replacement',
    () {
      final manager = FocusManager();
      final calls = <String>[];
      final outer = FocusNode()..attach(manager.root);
      final inner =
          FocusNode(
              onKeyCapture: (_) {
                calls.add('old');
                return true;
              },
            )
            ..attach(outer)
            ..requestFocus();
      outer.onKeyCapture = (_) {
        inner.onKeyCapture = (_) {
          calls.add('new');
          return true;
        };
        return false;
      };
      manager.dispatchKey(const KeyEvent('x'));
      manager.dispatchKey(const KeyEvent('y'));
      expect(calls, ['old', 'new']);
      inner.dispose();
      outer.dispose();
      manager.dispose();
    },
  );

  test(
    'empty paste capture may consume without invoking the normal paste handler',
    () {
      final manager = FocusManager();
      var normal = 0;
      final node =
          FocusNode(
              onPasteCapture: (text) {
                expect(text, '');
                return true;
              },
              onPaste: (_) {
                normal++;
                return true;
              },
            )
            ..attach(manager.root)
            ..requestFocus();
      expect(manager.dispatchPaste(''), isTrue);
      expect(normal, 0);
      node.dispose();
      manager.dispose();
    },
  );

  test('reentrant paste invalidates old key continuation and capability', () {
    final manager = FocusManager();
    final calls = <String>[];
    final node =
        FocusNode(
            onKey: (_) {
              calls.add('key');
              return true;
            },
            onPaste: (text) {
              calls.add(text);
              return true;
            },
          )
          ..attach(manager.root)
          ..bindings = [Binding('x', 'Old action', () => calls.add('binding'))]
          ..requestFocus();
    node.onKeyCapture = (event) {
      final saved = manager.matchKey(event);
      manager.dispatchPaste('paste');
      expect(saved.dispatch(), isFalse);
      return false;
    };
    manager.dispatchKey(const KeyEvent('x'));
    expect(calls, ['paste']);
    node.dispose();
    manager.dispose();
  });

  test(
    'pending-clear observer disposal prevents the snapshotted action callback',
    () {
      final manager = FocusManager();
      var calls = 0, remove = false;
      final node = FocusNode()
        ..attach(manager.root)
        ..bindings = [Binding('x c', 'Action', () => calls++)]
        ..requestFocus();
      manager.addListener(() {
        if (remove && manager.pendingChord.isEmpty && !node.isDisposed) {
          node.dispose();
        }
      });
      manager.dispatchKey(const KeyEvent('x'));
      remove = true;
      manager.dispatchKey(const KeyEvent('c'));
      expect(calls, 0);
      manager.dispose();
    },
  );

  test(
    'binding registrations freeze caller mutations and reject getter mutation',
    () {
      final manager = FocusManager();
      var old = 0, replacement = 0;
      final registrations = [Binding('x', 'Action', () => old++)];
      final node = FocusNode()
        ..attach(manager.root)
        ..bindings = registrations
        ..requestFocus();
      node.onKeyCapture = (event) {
        final match = manager.matchKey(event);
        registrations.clear();
        registrations.add(Binding('x', 'Action', () => replacement++));
        expect(() => node.bindings.clear(), throwsUnsupportedError);
        expect(match.dispatch(), isTrue);
        registrations.clear();
        return true;
      };
      manager.dispatchKey(const KeyEvent('x'));
      expect((old, replacement), (1, 0));
      expect(node.bindings, hasLength(1));
      node.dispose();
      manager.dispose();
    },
  );

  test(
    'setter replacement invalidates capability even when visible binding is unchanged',
    () {
      final manager = FocusManager();
      var old = 0, replacement = 0, notices = 0;
      final node = FocusNode()
        ..attach(manager.root)
        ..bindings = [Binding('x', 'Action', () => old++)]
        ..requestFocus();
      manager.addListener(() => notices++);
      node.onKeyCapture = (event) {
        final match = manager.matchKey(event);
        node.bindings = [Binding('x', 'Action', () => replacement++)];
        expect(notices, 0);
        expect(match.dispatch(), isFalse);
        return false;
      };
      manager.dispatchKey(const KeyEvent('x'));
      expect((old, replacement), (0, 0));
      node.dispose();
      manager.dispose();
    },
  );

  for (final kind in ['exact', 'prefix', 'pending exact']) {
    test(
      'live eligibility invalidates $kind without registration mutation',
      () {
        final manager = FocusManager();
        var eligible = true, calls = 0;
        final node = FocusNode()
          ..attach(manager.root)
          ..bindings = [
            Binding(kind == 'exact' ? 'v' : 'x c', 'Action', () => calls++),
          ]
          ..requestFocus();
        if (kind == 'pending exact') manager.dispatchKey(const KeyEvent('x'));
        node.onKeyCapture = (event) {
          final before = manager.pendingChord;
          final match = manager.matchKey(event, where: (_) => eligible);
          expect(
            match.kind,
            kind == 'prefix'
                ? KeyBindingMatchKind.prefix
                : KeyBindingMatchKind.exact,
          );
          eligible = false;
          expect(match.dispatch(), isFalse);
          expect(manager.pendingChord, before);
          return true;
        };
        manager.dispatchKey(
          KeyEvent(
            kind == 'exact'
                ? 'v'
                : kind == 'prefix'
                ? 'x'
                : 'c',
          ),
        );
        expect(calls, 0);
        node.dispose();
        manager.dispose();
      },
    );
  }
}
