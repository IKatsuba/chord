import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

final failure = StateError('child failed');
final trace = StackTrace.fromString('fixture stack');

class ThrowsBuild extends StatelessWidget {
  const ThrowsBuild({super.key});
  @override
  Widget build(BuildContext context) =>
      Error.throwWithStackTrace(failure, trace);
}

class ThrowsDrawing extends LeafRenderObjectWidget {
  const ThrowsDrawing(this.phase);
  final String phase;
  @override
  RenderBox createRenderObject(BuildContext context) => _ThrowsDrawing(phase);
}

class _ThrowsDrawing extends RenderBox {
  _ThrowsDrawing(this.phase);
  final String phase;
  @override
  void performLayout() {
    if (phase == 'layout') Error.throwWithStackTrace(failure, trace);
    size = constraints.smallest;
  }

  @override
  void paint(Canvas canvas, Offset origin) {
    if (phase == 'paint') Error.throwWithStackTrace(failure, trace);
  }
}

class Lifetime extends StatefulWidget {
  const Lifetime({required this.child, required this.disposeChild});
  final Widget child;
  final void Function() disposeChild;
  @override
  State<Lifetime> createState() => _LifetimeState();
}

class _LifetimeState extends State<Lifetime> {
  @override
  Widget build(BuildContext context) => widget.child;
  @override
  void dispose() {
    widget.disposeChild();
    super.dispose();
  }
}

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final phase in ['build', 'layout', 'lazy', 'list', 'paint']) {
      testWidgets('catches $phase with exact error and stack at $size', (
        t,
      ) async {
        var notified = 0;
        var disposed = 0;
        var inLayout = false;
        final child = switch (phase) {
          'build' => const ThrowsBuild(),
          'list' => ListView.builder(
            itemCount: 1,
            itemBuilder: (_, _) => Error.throwWithStackTrace(failure, trace),
          ),
          'lazy' => LayoutBuilder(
            builder: (_, _) {
              inLayout = true;
              try {
                Error.throwWithStackTrace(failure, trace);
              } finally {
                inLayout = false;
              }
            },
          ),
          _ => ThrowsDrawing(phase),
        };
        await t.pumpWidget(
          Theme(
            data: ThemeData.dark(),
            child: ErrorBoundary(
              onError: (error, stack) {
                expect(inLayout, isFalse);
                expect(error, same(failure));
                expect(stack, same(trace));
                expect(disposed, 1);
                notified++;
              },
              errorBuilder: (context, error, stack) {
                expect(error, same(failure));
                expect(stack, same(trace));
                return LayoutBuilder(
                  builder: (_, c) => Text('fallback ${c.maxWidth}'),
                );
              },
              child: Lifetime(disposeChild: () => disposed++, child: child),
            ),
          ),
          size: size,
        );
        expect(t.screen, shows('fallback ${size.width}'));
        await t.resize(const Size(30, 8));
        expect(t.screen, shows('fallback 30'));
        expect(notified, 1);
        expect(disposed, 1);
      });
    }
  }

  testWidgets(
    'later rebuild removes focus/actions and latches until key replacement',
    (t) async {
      final fail = ValueNotifier(false);
      addTearDown(fail.dispose);
      var oldAction = 0;
      var notified = 0;
      final boundaryKey = ValueNotifier(0);
      addTearDown(boundaryKey.dispose);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: boundaryKey,
          builder: (_) => ErrorBoundary(
            key: ValueKey(boundaryKey.value),
            onError: (_, _) => notified++,
            errorBuilder: (_, _, _) =>
                Focus(autofocus: true, child: Text('safe')),
            child: ListenableBuilder(
              listenable: fail,
              builder: (_) => Actions(
                bindings: [Binding('x', 'Old action', () => oldAction++)],
                child: Focus(
                  autofocus: true,
                  child: fail.value ? const ThrowsBuild() : Text('healthy'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.press('x');
      expect(oldAction, 1);
      fail.value = true;
      await t.pump();
      expect(t.screen, shows('safe'));
      expect(t.focusManager.activeBindings, isEmpty);
      await t.press('x');
      expect(oldAction, 1);
      fail.value = false;
      boundaryKey.notifyListeners();
      await t.pump();
      expect(t.screen, shows('safe'));
      expect(notified, 1);
      boundaryKey.value++;
      await t.pump();
      expect(t.screen, shows('healthy'));
    },
  );

  for (final source in [
    'fallback build',
    'fallback layout',
    'callback',
    'builder',
  ]) {
    testWidgets('$source errors escape to nearest outer boundary', (t) async {
      var outer = 0;
      await t.pumpWidget(
        ErrorBoundary(
          onError: (_, _) => outer++,
          errorBuilder: (_, _, _) => Text('outer'),
          child: ErrorBoundary(
            onError: (_, _) {
              if (source == 'callback') throw failure;
            },
            errorBuilder: (_, _, _) {
              if (source == 'builder') throw failure;
              if (source == 'fallback layout') {
                return const ThrowsDrawing('layout');
              }
              return const ThrowsBuild();
            },
            child: const ThrowsBuild(),
          ),
        ),
      );
      expect(t.screen, shows('outer'));
      expect(outer, 1);
    });
  }

  testWidgets('nearest nested boundary keeps outer subtree alive', (t) async {
    var outer = 0;
    await t.pumpWidget(
      ErrorBoundary(
        onError: (_, _) => outer++,
        errorBuilder: (_, _, _) => Text('outer'),
        child: ErrorBoundary(
          errorBuilder: (_, _, _) => Text('inner'),
          child: const ThrowsBuild(),
        ),
      ),
    );
    expect(t.screen, shows('inner'));
    expect(outer, 0);
  });

  test('boundary-owned callback failure retains root error path', () {
    expect(
      () => AppHost(
        ErrorBoundary(
          onError: (_, _) => throw failure,
          errorBuilder: (_, _, _) => Text('unused'),
          child: const ThrowsBuild(),
        ),
      ),
      throwsA(same(failure)),
    );
  });
  test('asynchronous errors remain on their existing zone path', () async {
    final caught = Completer<Object>();
    var notified = 0;
    AppHost? host;
    runZonedGuarded(() {
      host = AppHost(
        ErrorBoundary(
          onError: (_, _) => notified++,
          errorBuilder: (_, _, _) => Text('fallback'),
          child: Builder(
            builder: (_) {
              scheduleMicrotask(() => throw failure);
              return Text('healthy');
            },
          ),
        ),
      );
    }, (error, _) => caught.complete(error));
    expect(await caught.future, same(failure));
    expect(notified, 0);
    host!.dispose();
  });

  testWidgets(
    'a boundary mounted during lazy layout notifies after unwinding',
    (t) async {
      var building = false;
      var notified = 0;
      await t.pumpWidget(
        LayoutBuilder(
          builder: (_, _) {
            building = true;
            try {
              return ErrorBoundary(
                onError: (_, _) {
                  expect(building, isFalse);
                  notified++;
                },
                errorBuilder: (_, _, _) => Text('safe'),
                child: const ThrowsBuild(),
              );
            } finally {
              building = false;
            }
          },
        ),
      );
      expect(t.screen, shows('safe'));
      expect(notified, 1);
    },
  );

  group('tester: boundary recovery edges', () {
    for (final size in [const Size(0, 0), const Size(1, 1)]) {
      for (final phase in ['build', 'layout']) {
        testWidgets('$phase recovery survives $size and a later resize', (
          t,
        ) async {
          var reports = 0;
          await t.pumpWidget(
            ErrorBoundary(
              onError: (_, _) => reports++,
              errorBuilder: (_, _, _) => Text('recovered'),
              child: phase == 'build'
                  ? const ThrowsBuild()
                  : ThrowsDrawing(phase),
            ),
            size: size,
          );
          await t.resize(const Size(80, 24));
          expect(t.screen, shows('recovered'));
          expect(reports, 1);
        });
      }
    }

    testWidgets('fallback receives unbounded axes without changing them', (
      t,
    ) async {
      BoxConstraints? seen;
      await t.pumpWidget(
        Row(
          children: [
            Column(
              children: [
                ErrorBoundary(
                  errorBuilder: (_, _, _) => LayoutBuilder(
                    builder: (_, room) {
                      seen = room;
                      return Text('unbounded fallback');
                    },
                  ),
                  child: const ThrowsBuild(),
                ),
              ],
            ),
          ],
        ),
      );
      expect(seen!.maxWidth, unbounded);
      expect(seen!.maxHeight, unbounded);
      expect(t.screen, shows('unbounded fallback'));
    });

    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('fallback keeps outer theme and grapheme edges at $size', (
        t,
      ) async {
        final outer = ThemeData.dark();
        final inner = ThemeData.light();
        await t.pumpWidget(
          Theme(
            data: outer,
            child: ErrorBoundary(
              errorBuilder: (context, _, _) {
                expect(Theme.of(context), same(outer));
                return Column(
                  children: [
                    Text('界🙂e\u0301\x1b[31mR\x1b[0m'),
                    const Spacer(),
                    Row(children: [const Spacer(), Text('e\u0301🙂界')]),
                  ],
                );
              },
              child: Theme(data: inner, child: const ThrowsBuild()),
            ),
          ),
          size: size,
        );
        expect(t.screen.lines.first, '界🙂e\u0301R');
        expect(t.screen.charAt(size.width - 2, size.height - 1), '界');
        expect(t.screen.lines.last, endsWith('e\u0301🙂界'));
        await t.resize(const Size(1, 1));
        await t.resize(size);
        expect(t.screen.lines.first, '界🙂e\u0301R');
        expect(t.screen.lines.last, endsWith('e\u0301🙂界'));
      });
    }

    testWidgets('fallback actions follow focus away and back', (t) async {
      final fallback = FocusNode();
      final sibling = FocusNode();
      addTearDown(fallback.dispose);
      addTearDown(sibling.dispose);
      var actions = 0;
      await t.pumpWidget(
        Row(
          children: [
            Expanded(
              child: ErrorBoundary(
                errorBuilder: (_, _, _) => Actions(
                  bindings: [Binding('x', 'Fallback action', () => actions++)],
                  child: Focus(
                    focusNode: fallback,
                    autofocus: true,
                    child: Text('safe'),
                  ),
                ),
                child: const ThrowsBuild(),
              ),
            ),
            Focus(focusNode: sibling, child: Text('sibling')),
          ],
        ),
      );
      await t.press('x');
      expect(actions, 1);
      sibling.requestFocus();
      await t.press('x');
      expect(actions, 1);
      fallback.requestFocus();
      await t.press('x');
      expect(actions, 2);
    });

    testWidgets(
      'a thousand dirty updates dispose live resources once before fallback',
      (t) async {
        var cancellations = 0;
        final stream = StreamController<int>(
          sync: true,
          onCancel: () => cancellations++,
        );
        addTearDown(stream.close);
        final value = ValueNotifier(0);
        addTearDown(value.dispose);
        final probe = _TesterBoundaryProbe();
        var reports = 0;
        await t.pumpWidget(
          ErrorBoundary(
            onError: (_, _) {
              expect(probe.disposals, 1);
              expect(probe.timer!.isActive, isFalse);
              expect(stream.hasListener, isFalse);
              reports++;
            },
            errorBuilder: (_, _, _) => Text('safe'),
            child: _TesterBoundaryLive(probe, stream.stream, value),
          ),
        );
        for (var i = 1; i <= 1000; i++) {
          value.value = i;
          stream.add(i);
        }
        await t.pump();
        expect(t.screen, shows('safe'));
        expect(reports, 1);
        expect(cancellations, 1);
        expect(probe.builds, 2);
        stream.add(1001);
        value.value = 1001;
        await t.pump();
        expect(probe.disposals, 1);
        expect(reports, 1);
      },
    );

    testWidgets(
      'a fallback paint error recovers through the outer boundary once',
      (t) async {
        var outer = 0;
        await t.pumpWidget(
          ErrorBoundary(
            onError: (_, _) => outer++,
            errorBuilder: (_, _, _) => Text('outer paint recovery'),
            child: ErrorBoundary(
              errorBuilder: (_, _, _) => const ThrowsDrawing('paint'),
              child: const ThrowsBuild(),
            ),
          ),
        );
        expect(t.screen, shows('outer paint recovery'));
        await t.pump();
        expect(outer, 1);
      },
    );
  });
}

class _TesterBoundaryProbe {
  Timer? timer;
  int disposals = 0;
  int builds = 0;
}

class _TesterBoundaryLive extends StatefulWidget {
  const _TesterBoundaryLive(this.probe, this.stream, this.value);
  final _TesterBoundaryProbe probe;
  final Stream<int> stream;
  final ValueNotifier<int> value;
  @override
  State<_TesterBoundaryLive> createState() => _TesterBoundaryLiveState();
}

class _TesterBoundaryLiveState extends State<_TesterBoundaryLive> {
  late final StreamSubscription<int> subscription;
  @override
  void initState() {
    super.initState();
    subscription = widget.stream.listen((_) => setState(() {}));
    widget.value.addListener(changed);
    widget.probe.timer = Timer.periodic(
      const Duration(days: 1),
      (_) => changed(),
    );
  }

  void changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    widget.probe.builds++;
    if (widget.value.value >= 1000) throw failure;
    return Text('live');
  }

  @override
  void dispose() {
    subscription.cancel();
    widget.value.removeListener(changed);
    widget.probe.timer!.cancel();
    widget.probe.disposals++;
    super.dispose();
  }
}
