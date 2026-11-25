import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

class _Terminal extends Terminal {
  final source = StreamController<String>();
  @override
  Size get size => const Size(80, 24);
  @override
  Stream<String> get input => source.stream;
  @override
  Stream<Size> get resizes => const Stream.empty();
  @override
  void enter() {}
  @override
  Future<void> leave() async {}
  @override
  void write(String data) {
    if (data == '\x1b]11;?\x07') source.add('\x1b]11;rgb:0000/0000/0000\x07');
  }
}

void main() {
  test('the default pending chord expires exactly at three seconds', () {
    fakeAsync((async) {
      final manager = FocusManager();
      final node = FocusNode()
        ..bindings = [Binding('ctrl+x a', 'Answer', () {})];
      node.attach(manager.root);
      node.requestFocus();
      manager.dispatchKey(KeyCombo.parse('ctrl+x').toEvent());
      async.elapse(const Duration(milliseconds: 2999));
      expect(manager.pendingChord, [KeyCombo.parse('ctrl+x')]);
      async.elapse(const Duration(milliseconds: 1));
      expect(manager.pendingChord, isEmpty);
      node.detach();
      node.dispose();
      manager.dispose();
      expect(async.pendingTimers, isEmpty);
    });
  });
  test(
    'each prefix renews the configurable wait; completion and rejection cancel it',
    () {
      fakeAsync((async) {
        var invoked = 0;
        final manager = FocusManager(
          chordTimeout: const Duration(milliseconds: 100),
        );
        final node = FocusNode()
          ..bindings = [Binding('ctrl+x b c', 'Long chord', () => invoked++)];
        node.attach(manager.root);
        node.requestFocus();
        manager.dispatchKey(KeyCombo.parse('ctrl+x').toEvent());
        async.elapse(const Duration(milliseconds: 99));
        manager.dispatchKey(KeyCombo.parse('b').toEvent());
        async.elapse(const Duration(milliseconds: 99));
        expect(manager.pendingChord, hasLength(2));
        manager.dispatchKey(KeyCombo.parse('c').toEvent());
        expect(invoked, 1);
        expect(manager.pendingChord, isEmpty);
        expect(async.pendingTimers, isEmpty);
        manager.dispatchKey(KeyCombo.parse('ctrl+x').toEvent());
        manager.dispatchKey(KeyCombo.parse('esc').toEvent());
        expect(async.pendingTimers, isEmpty);
        node.detach();
        node.dispose();
        manager.dispose();
      });
    },
  );
  test('scope changes and manager disposal cancel pending timers', () {
    fakeAsync((async) {
      final manager = FocusManager();
      final first = FocusNode()
        ..bindings = [Binding('ctrl+x a', 'Answer', () {})];
      final scope = FocusScopeNode()..attach(manager.root);
      final second = FocusNode()..attach(scope);
      first.attach(manager.root);
      first.requestFocus();
      manager.dispatchKey(KeyCombo.parse('ctrl+x').toEvent());
      second.requestFocus();
      expect(manager.pendingChord, isEmpty);
      expect(async.pendingTimers, isEmpty);
      first.requestFocus();
      manager.dispatchKey(KeyCombo.parse('ctrl+x').toEvent());
      manager.dispose();
      expect(async.pendingTimers, isEmpty);
      async.elapse(const Duration(seconds: 10));
      first.detach();
      second.detach();
      scope.detach();
      first.dispose();
      second.dispose();
      scope.dispose();
    });
  });
  test(
    'KeyHelp builder observes timeout and retains its previous immutable snapshot',
    () {
      fakeAsync((async) {
        List<KeyCombo> pending = [];
        final host = AppHost(
          Actions(
            bindings: [Binding('ctrl+x a', 'Answer', () {})],
            child: Focus(
              autofocus: true,
              child: KeyHelp.builder(
                builder: (_, _, keys) {
                  pending = keys;
                  return Text(keys.isEmpty ? 'idle' : keys.join(' '));
                },
              ),
            ),
          ),
          chordTimeout: const Duration(milliseconds: 100),
        );
        host.drawFrame(const Size(80, 24));
        host.handleKey(KeyCombo.parse('ctrl+x').toEvent());
        expect(Screen(host.drawFrame(const Size(80, 24))), shows('ctrl+x'));
        final retained = pending;
        async.elapse(const Duration(milliseconds: 100));
        expect(Screen(host.drawFrame(const Size(80, 24))), shows('idle'));
        expect(pending, isEmpty);
        expect(retained, [KeyCombo.parse('ctrl+x')]);
        expect(() => retained.clear(), throwsUnsupportedError);
        host.handleKey(KeyCombo.parse('ctrl+x').toEvent());
        host.dispose();
        expect(host.focusManager.isDisposed, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    },
  );
  test(
    'runApp forwards the configured timeout to its owned focus manager',
    () async {
      final terminal = _Terminal();
      Duration? seen;
      await runApp(
        Builder(
          builder: (context) {
            seen = context.owner.focusManager.chordTimeout;
            exitApp(context);
            return const SizedBox();
          },
        ),
        terminal: terminal,
        exitProcess: false,
        chordTimeout: const Duration(milliseconds: 17),
      );
      expect(seen, const Duration(milliseconds: 17));
      await terminal.source.close();
    },
  );

  group('tester: chord deadline boundaries', () {
    test(
      'a key after expiry dispatches normally instead of completing the old chord',
      () {
        fakeAsync((async) {
          var chord = 0;
          var ordinary = 0;
          final manager = FocusManager(
            chordTimeout: const Duration(milliseconds: 10),
          );
          final node = FocusNode()
            ..bindings = [
              Binding('ctrl+x a', 'Chord', () => chord++),
              Binding('a', 'Ordinary', () => ordinary++),
            ];
          node.attach(manager.root);
          node.requestFocus();
          manager.dispatchKey(KeyCombo.parse('ctrl+x').toEvent());
          async.elapse(const Duration(milliseconds: 10));
          manager.dispatchKey(KeyCombo.parse('a').toEvent());
          expect(chord, 0);
          expect(ordinary, 1);
          node.detach();
          node.dispose();
          manager.dispose();
          expect(async.pendingTimers, isEmpty);
        });
      },
    );

    test('independent managers retain separate deadlines', () {
      fakeAsync((async) {
        final managers = [
          FocusManager(chordTimeout: const Duration(milliseconds: 10)),
          FocusManager(chordTimeout: const Duration(milliseconds: 20)),
        ];
        final nodes = [
          for (final manager in managers)
            FocusNode()
              ..bindings = [Binding('ctrl+x a', 'Answer', () {})]
              ..attach(manager.root)
              ..requestFocus(),
        ];
        for (final manager in managers) {
          manager.dispatchKey(KeyCombo.parse('ctrl+x').toEvent());
        }
        async.elapse(const Duration(milliseconds: 10));
        expect(managers[0].pendingChord, isEmpty);
        expect(managers[1].pendingChord, hasLength(1));
        async.elapse(const Duration(milliseconds: 10));
        expect(managers[1].pendingChord, isEmpty);
        for (final node in nodes) {
          node.detach();
          node.dispose();
        }
        for (final manager in managers) {
          manager.dispose();
        }
        expect(async.pendingTimers, isEmpty);
      });
    });

    test(
      'a thousand rejected prefixes leave no pending timer or late notification',
      () {
        fakeAsync((async) {
          final manager = FocusManager();
          final node = FocusNode()
            ..bindings = [Binding('ctrl+x a', 'Answer', () {})];
          node.attach(manager.root);
          node.requestFocus();
          var notifications = 0;
          manager.addListener(() => notifications++);
          for (var i = 0; i < 1000; i++) {
            manager.dispatchKey(KeyCombo.parse('ctrl+x').toEvent());
            manager.dispatchKey(KeyCombo.parse('esc').toEvent());
          }
          expect(manager.pendingChord, isEmpty);
          expect(async.pendingTimers, isEmpty);
          final before = notifications;
          async.elapse(const Duration(seconds: 10));
          expect(notifications, before);
          node.detach();
          node.dispose();
          manager.dispose();
        });
      },
    );

    for (final size in [const Size(0, 0), const Size(1, 1)]) {
      test('help expiry survives $size and a later visible frame', () {
        fakeAsync((async) {
          final host = AppHost(
            Actions(
              bindings: [Binding('ctrl+x a', '界🙂e\u0301', () {})],
              child: Focus(
                autofocus: true,
                child: KeyHelp.builder(
                  builder: (_, _, pending) =>
                      Text(pending.isEmpty ? 'idle 界🙂e\u0301' : 'pending'),
                ),
              ),
            ),
            chordTimeout: const Duration(milliseconds: 10),
          );
          host.drawFrame(size);
          host.handleKey(KeyCombo.parse('ctrl+x').toEvent());
          host.drawFrame(size);
          async.elapse(const Duration(milliseconds: 10));
          expect(
            Screen(host.drawFrame(const Size(80, 24))),
            shows('idle 界🙂e\u0301'),
          );
          host.dispose();
          expect(async.pendingTimers, isEmpty);
        });
      });
    }
  });
}
