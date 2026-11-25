import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

class _Churn extends StatefulWidget {
  const _Churn({required this.child, required this.enabled});
  final Widget child;
  final bool Function() enabled;
  @override
  State<_Churn> createState() => _ChurnState();
}

class _ChurnState extends State<_Churn> {
  @override
  Widget build(BuildContext context) {
    if (widget.enabled()) {
      context.owner.afterLayout(() {
        if (mounted) setState(() {});
      });
    }
    return widget.child;
  }
}

class _LayoutFailure extends SingleChildRenderObjectWidget {
  const _LayoutFailure({required this.fail, required super.child});
  final bool Function() fail;
  @override
  RenderBox createRenderObject(BuildContext context) => _FailingBox(fail);
}

class _FailingBox extends RenderProxyBox {
  _FailingBox(this.fail);
  final bool Function() fail;
  @override
  void performLayout() {
    if (fail()) throw StateError('layout failure');
    super.performLayout();
  }
}

class _KeyTerminal extends Terminal {
  _KeyTerminal(this.size);
  @override
  final Size size;
  final source = StreamController<String>();
  final frame = Completer<void>();
  @override
  Stream<String> get input => source.stream;
  @override
  Stream<Size> get resizes => const Stream.empty();
  @override
  void enter() {}
  @override
  Future<void> leave() async {}
  @override
  void write(String bytes) {
    if (bytes == '\x1b]11;?\x07') {
      source.add('\x1b]11;#000000\x07');
    } else if (bytes == '\x1b[?u') {
      source.add('\x1b[?0u');
    } else if (!frame.isCompleted && bytes != '\x1b[>5u') {
      frame.complete();
    }
  }
}

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    test(
      'runApp delivers an exhausted same-chunk key batch once $size',
      () async {
        final terminal = _KeyTerminal(size);
        final keys = <String>[];
        final running = runApp(
          _Churn(
            enabled: () => true,
            child: Builder(
              builder: (context) => Focus(
                autofocus: true,
                onKey: (event) {
                  keys.add(event.key);
                  if (event.key == 'c') exitApp(context);
                  return true;
                },
                child: Text('keys'),
              ),
            ),
          ),
          terminal: terminal,
          exitProcess: false,
          handleSignals: false,
          environment: const {},
        );
        try {
          await terminal.frame.future.timeout(const Duration(seconds: 3));
          terminal.source.add('abc');
          await running.timeout(const Duration(seconds: 3));
          expect(keys, ['a', 'b', 'c']);
        } finally {
          await terminal.source.close();
          await running;
        }
      },
    );

    testWidgets('exhausted afterLayout delivers keys once in order $size', (
      t,
    ) async {
      final events = <String>[];
      var churn = true;
      await t.pumpWidget(
        _Churn(
          enabled: () => churn,
          child: Focus(
            autofocus: true,
            onKey: (event) {
              events.add(event.key);
              return true;
            },
            child: Text('keys'),
          ),
        ),
        size: size,
      );
      for (final key in ['a', 'b', 'c']) {
        final before = t.inputLayoutPasses;
        expect(t.host.handleKey(KeyEvent(key)), isTrue);
        expect(t.inputLayoutPasses - before, 2);
        expect(t.host.owner.hasDirtyElements, isTrue);
      }
      expect(events, ['a', 'b', 'c']);
      churn = false;
      await t.pump();
      expect(events, ['a', 'b', 'c']);
      expect(t.host.owner.hasDirtyElements, isFalse);
    });

    testWidgets(
      'exhausted keys retain bindings chords and default fallbacks $size',
      (t) async {
        final first = FocusNode(), second = FocusNode();
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        var actions = 0;
        await t.pumpWidget(
          _Churn(
            enabled: () => true,
            child: Actions(
              bindings: [Binding('ctrl+x a', 'Act', () => actions++)],
              child: Column(
                children: [
                  Focus(
                    focusNode: first,
                    autofocus: true,
                    child: Text('first'),
                  ),
                  Focus(focusNode: second, child: Text('second')),
                ],
              ),
            ),
          ),
          size: size,
        );
        for (final combo in Chord.parse('ctrl+x a').combos) {
          expect(t.host.handleKey(combo.toEvent()), isTrue);
        }
        expect(actions, 1);
        expect(t.host.handleKey(const KeyEvent('tab')), isTrue);
        expect(t.focusManager.primaryFocus, same(second));
        expect(t.host.handleKey(const KeyEvent('tab', shift: true)), isTrue);
        expect(t.focusManager.primaryFocus, same(first));
        expect(t.host.handleKey(const KeyEvent('c', ctrl: true)), isTrue);
        expect(t.exitRequested, isTrue);
      },
    );

    testWidgets(
      'exhausted key queries stay unresolved without extra passes $size',
      (t) async {
        final selection = SelectionController();
        addTearDown(selection.dispose);
        final source = SelectionSource.markdown(
          id: 'code',
          revision: 0,
          text: '```sh\necho hello\n```',
        );
        var keys = 0;
        await t.pumpWidget(
          _Churn(
            enabled: () => true,
            child: Focus(
              autofocus: true,
              onKey: (_) {
                keys++;
                final before = t.inputLayoutPasses;
                expect(t.host.owner.ensureCurrentInputGeometry(), isFalse);
                expect(selection.snapshot(), isNull);
                expect(selection.visibleCodeBlocks(), isEmpty);
                expect(
                  selection.revealCodeBlock(source.codeBlocks.single.id),
                  isFalse,
                );
                expect(t.inputLayoutPasses, before);
                return true;
              },
              child: SelectionArea(
                controller: selection,
                selectionStyle: const Style(inverse: true),
                child: Markdown.fromSelectionSource(source),
              ),
            ),
          ),
          size: size,
        );
        final before = t.inputLayoutPasses;
        expect(t.host.handleKey(const KeyEvent('a')), isTrue);
        expect(keys, 1);
        expect(t.inputLayoutPasses - before, 2);
        // Paste retains its existing fail-closed geometry policy.
        expect(t.host.handlePaste('paste'), isFalse);
      },
    );

    testWidgets('drawing recovery does not route old key to fallback $size', (
      t,
    ) async {
      var fail = false, keys = 0;
      await t.pumpWidget(
        ErrorBoundary(
          errorBuilder: (_, _, _) => Focus(
            autofocus: true,
            onKey: (_) {
              keys++;
              return true;
            },
            child: Text('fallback'),
          ),
          child: _LayoutFailure(
            fail: () => fail,
            child: Focus(
              autofocus: true,
              onKey: (_) {
                keys++;
                return true;
              },
              child: Text('original'),
            ),
          ),
        ),
        size: size,
      );
      fail = true;
      t.host.owner.requestFrame();
      expect(t.host.handleKey(const KeyEvent('c', ctrl: true)), isFalse);
      expect(keys, 0);
      expect(t.exitRequested, isFalse);
      await t.pump();
      expect(t.screen, shows('fallback'));
      expect(t.host.handleKey(const KeyEvent('a')), isTrue);
      expect(keys, 1);
    });

    testWidgets(
      'exhausted key handler disposal suppresses host fallback $size',
      (t) async {
        var keys = 0;
        await t.pumpWidget(
          _Churn(
            enabled: () => true,
            child: Focus(
              autofocus: true,
              onKey: (_) {
                keys++;
                t.host.dispose();
                return false;
              },
              child: Text('keys'),
            ),
          ),
          size: size,
        );
        expect(t.host.handleKey(const KeyEvent('c', ctrl: true)), isFalse);
        expect(keys, 1);
        expect(t.exitRequested, isFalse);
      },
    );

    for (final dispose in [false, true]) {
      testWidgets(
        'exhaustion callback ${dispose ? 'disposal' : 'nested input'} suppresses old key $size',
        (t) async {
          final events = <String>[];
          await t.pumpWidget(
            _Churn(
              enabled: () => true,
              child: Focus(
                autofocus: true,
                onKey: (event) {
                  events.add(event.key);
                  return true;
                },
                child: Text('keys'),
              ),
            ),
            size: size,
          );
          var called = false;
          t.host.owner.inputGeometryObservers.add((settled) {
            if (settled || called) return;
            called = true;
            if (dispose) {
              t.host.dispose();
            } else {
              t.host.handleKey(const KeyEvent('n'));
            }
          });
          expect(t.host.handleKey(const KeyEvent('c', ctrl: true)), isFalse);
          expect(events, dispose ? isEmpty : ['n']);
          expect(t.exitRequested, isFalse);
        },
      );
    }
  }

  test('key before known size stays suppressed', () {
    var keys = 0;
    final host = AppHost(
      Focus(
        autofocus: true,
        onKey: (_) {
          keys++;
          return true;
        },
        child: Text('keys'),
      ),
    );
    addTearDown(host.dispose);
    expect(host.handleKey(const KeyEvent('a')), isFalse);
    expect(keys, 0);
  });
}
