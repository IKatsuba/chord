import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'selection_test.dart' show pointer;

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final nested in [false, true]) {
      testWidgets(
        'observer ${nested ? 'nested query' : 'notification'} uses remaining pass before fresh hit $size',
        (t) async {
          final shift = ValueNotifier(0);
          var hits = 0, stable = 0;
          await t.pumpWidget(
            ListenableBuilder(
              listenable: shift,
              builder: (_) => Padding(
                padding: EdgeInsets.only(left: shift.value),
                child: Listener(
                  onPointerDown: (_) => hits++,
                  child: Text('glyph'),
                ),
              ),
            ),
            size: size,
          );
          void observer(bool settled) {
            expect(t.host.owner.doingLayoutOrPaint, isFalse);
            expect(t.host.owner.settlingInputGeometry, isFalse);
            expect(settled, isTrue);
            if (stable++ == 0) {
              shift.value = 5;
              if (nested) {
                expect(t.host.owner.ensureCurrentInputGeometry(), isTrue);
              }
            }
          }

          t.host.owner.inputGeometryObservers.add(observer);
          shift.value = 1;
          final before = t.inputLayoutPasses;
          t.host.handleMouse(pointer(MouseEventKind.press, 5, 0));
          expect(t.inputLayoutPasses - before, 2);
          expect(stable, 2);
          expect(hits, 1);
          t.host.owner.inputGeometryObservers.remove(observer);
          shift.dispose();
        },
      );
    }

    testWidgets(
      'observer exhaustion is notified once, cancels old capture and queues no input $size',
      (t) async {
        final shift = ValueNotifier(0), capture = PointerCaptureController();
        var settled = 0, unresolved = 0, cancels = 0, moves = 0;
        await t.pumpWidget(
          ListenableBuilder(
            listenable: shift,
            builder: (_) => Padding(
              padding: EdgeInsets.only(left: shift.value),
              child: Listener(
                captureController: capture,
                onPointerDown: (_) => capture.capture(),
                onPointerMove: (_) => moves++,
                onPointerCancel: (_) {
                  expect(t.host.owner.doingLayoutOrPaint, isFalse);
                  expect(t.host.owner.settlingInputGeometry, isFalse);
                  cancels++;
                },
                child: Text('glyph'),
              ),
            ),
          ),
          size: size,
        );
        t.host.handleMouse(pointer(MouseEventKind.press, 0, 0));
        void observer(bool current) {
          expect(t.host.owner.doingLayoutOrPaint, isFalse);
          expect(t.host.owner.settlingInputGeometry, isFalse);
          if (!current) {
            unresolved++;
            return;
          }
          settled++;
          shift.value++;
          expect(t.host.owner.ensureCurrentInputGeometry(), isFalse);
        }

        t.host.owner.inputGeometryObservers.add(observer);
        shift.value = 1;
        final before = t.inputLayoutPasses;
        expect(t.host.handleMouse(pointer(MouseEventKind.move, 0, 0)), isFalse);
        expect(t.inputLayoutPasses - before, 2);
        expect((settled, unresolved, cancels, moves), (2, 1, 1, 0));
        expect(capture.isCaptured, isFalse);
        t.host.owner.inputGeometryObservers.remove(observer);
        shift.value = 0;
        await t.pump();
        expect((cancels, moves), (1, 0));
        t.host.handleMouse(pointer(MouseEventKind.press, 0, 0));
        t.host.handleMouse(pointer(MouseEventKind.move, 1, 0));
        expect(capture.isCaptured, isTrue);
        expect(moves, 1);
        capture.dispose();
        shift.dispose();
      },
    );

    for (final outer in ['key', 'paste']) {
      for (final inner in ['key', 'paste']) {
        testWidgets(
          'pre-route $inner supersedes old $outer without fallback $size',
          (t) async {
            final label = ValueNotifier('initial');
            final events = <String>[];
            await t.pumpWidget(
              ListenableBuilder(
                listenable: label,
                builder: (_) => Focus(
                  autofocus: true,
                  onKey: (event) {
                    events.add('key:${event.key}');
                    return true;
                  },
                  onPaste: (text) {
                    events.add('paste:$text');
                    return true;
                  },
                  child: Text(label.value),
                ),
              ),
              size: size,
            );
            var nested = false;
            void observer(bool settled) {
              expect(t.host.owner.doingLayoutOrPaint, isFalse);
              expect(t.host.owner.settlingInputGeometry, isFalse);
              if (!settled || nested) return;
              nested = true;
              if (inner == 'key') {
                t.host.handleKey(const KeyEvent('n'));
              } else {
                t.host.handlePaste('new');
              }
            }

            t.host.owner.inputGeometryObservers.add(observer);
            label.value = 'dirty';
            final handled = outer == 'key'
                ? t.host.handleKey(const KeyEvent('c', ctrl: true))
                : t.host.handlePaste('old');
            expect(handled, isFalse);
            expect(events, [inner == 'key' ? 'key:n' : 'paste:new']);
            expect(t.exitRequested, isFalse);
            t.host.owner.inputGeometryObservers.remove(observer);
            label.dispose();
          },
        );
      }
    }

    testWidgets(
      'observer disposal suppresses old input and cancels capture outside layout $size',
      (t) async {
        final label = ValueNotifier('initial'),
            capture = PointerCaptureController();
        var keys = 0, cancels = 0;
        await t.pumpWidget(
          ListenableBuilder(
            listenable: label,
            builder: (_) => Focus(
              autofocus: true,
              onKey: (_) {
                keys++;
                return true;
              },
              child: Listener(
                captureController: capture,
                onPointerDown: (_) => capture.capture(),
                onPointerCancel: (_) {
                  expect(t.host.owner.doingLayoutOrPaint, isFalse);
                  expect(t.host.owner.settlingInputGeometry, isFalse);
                  cancels++;
                },
                child: Text(label.value),
              ),
            ),
          ),
          size: size,
        );
        t.host.handleMouse(pointer(MouseEventKind.press, 0, 0));
        t.host.owner.inputGeometryObservers.add((settled) {
          if (settled) t.host.dispose();
        });
        label.value = 'dirty';
        expect(t.host.handleKey(const KeyEvent('c', ctrl: true)), isFalse);
        expect(keys, 0);
        expect(cancels, 1);
        expect(capture.isCaptured, isFalse);
        expect(t.exitRequested, isFalse);
        capture.dispose();
        label.dispose();
      },
    );
  }
}
