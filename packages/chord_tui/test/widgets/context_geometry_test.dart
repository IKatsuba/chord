import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

class _Churn extends StatefulWidget {
  const _Churn({required this.enabled, required this.child});
  final bool Function() enabled;
  final Widget child;
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

class _Probe extends SingleChildRenderObjectWidget {
  const _Probe({this.layout, this.paint, required super.child});
  final void Function()? layout, paint;
  @override
  RenderBox createRenderObject(BuildContext context) => _ProbeBox(this);
  @override
  void updateRenderObject(BuildContext context, _ProbeBox r) => r.widget = this;
}

class _ProbeBox extends RenderProxyBox {
  _ProbeBox(this.widget);
  _Probe widget;
  @override
  void performLayout() {
    super.performLayout();
    widget.layout?.call();
  }

  @override
  void paint(Canvas canvas, Offset origin) {
    widget.paint?.call();
    super.paint(canvas, origin);
  }
}

class _Unknown extends SingleChildRenderObjectWidget {
  const _Unknown({required super.child});
  @override
  RenderBox createRenderObject(BuildContext context) => _UnknownBox();
}

class _UnknownBox extends RenderProxyBox {}

void main() {
  test('context before first usable host size and after disposal is false', () {
    late BuildContext context;
    final host = AppHost(
      Builder(
        builder: (c) {
          context = c;
          return Text('before size');
        },
      ),
    );
    expect(context.ensureCurrentInputGeometry(), isFalse);
    host.drawFrame(const Size(80, 24));
    expect(context.ensureCurrentInputGeometry(), isTrue);
    host.dispose();
    expect(context.ensureCurrentInputGeometry(), isFalse);
  });
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'stable/dirty/recorded resize geometry synchronizes without paint $size',
      (t) async {
        late BuildContext context;
        var paints = 0;
        final width = ValueNotifier(1);
        addTearDown(width.dispose);
        final layer = LayerLink();
        final entry = OverlayEntry(
          requestFocus: false,
          builder: (_) => CompositedTransformFollower(
            link: layer,
            followerAnchor: Alignment.bottomLeft,
            child: Text('choice'),
          ),
        );
        await t.pumpWidget(
          Builder(
            builder: (c) {
              context = c;
              return _Probe(
                paint: () => paints++,
                child: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => ListenableBuilder(
                        listenable: width,
                        builder: (_) => Column(
                          children: [
                            Expanded(child: Text('width ${width.value}')),
                            CompositedTransformTarget(
                              link: layer,
                              child: const SizedBox(height: 0),
                            ),
                            const SizedBox(height: 5),
                          ],
                        ),
                      ),
                    ),
                    entry,
                  ],
                ),
              );
            },
          ),
          size: size,
        );
        final initial = paints, passes = t.inputLayoutPasses;
        expect(context.ensureCurrentInputGeometry(), isTrue);
        expect(t.inputLayoutPasses, passes);
        expect(entry.visible, isTrue);
        width.value = 2;
        expect(context.ensureCurrentInputGeometry(), isTrue);
        expect(paints, initial);
        expect(t.inputLayoutPasses - passes, lessThanOrEqualTo(2));
        t.host.updateSize(Size(size.width, 5));
        expect(context.ensureCurrentInputGeometry(), isTrue);
        expect(entry.visible, isFalse);
        expect(paints, initial);
        t.host.updateSize(size);
        expect(context.ensureCurrentInputGeometry(), isTrue);
        expect(entry.visible, isTrue);
        expect(paints, initial);
        t.host.updateSize(Size(0, size.height));
        expect(context.ensureCurrentInputGeometry(), isTrue);
        expect(entry.visible, isFalse);
        expect(paints, initial);
      },
    );
    testWidgets('detached context cannot use a surviving owner $size', (
      t,
    ) async {
      late BuildContext captured;
      final show = ValueNotifier(true);
      addTearDown(show.dispose);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: show,
          builder: (_) => show.value
              ? Builder(
                  builder: (c) {
                    captured = c;
                    return Text('old');
                  },
                )
              : Text('replacement'),
        ),
        size: size,
      );
      show.value = false;
      expect(captured.ensureCurrentInputGeometry(), isFalse);
      expect(captured.mounted, isFalse);
      final passes = t.inputLayoutPasses;
      expect(captured.ensureCurrentInputGeometry(), isFalse);
      expect(t.inputLayoutPasses, passes);
    });
    testWidgets(
      'same context rejects an owner replaced during delegation $size',
      (t) async {
        late BuildContext context;
        await t.pumpWidget(
          Builder(
            builder: (c) {
              context = c;
              return Text('owner');
            },
          ),
          size: size,
        );
        final owner = context.owner,
            alternate = BuildOwner(),
            element = context as Element;
        final delegate = owner.synchronizeInputGeometry;
        owner.synchronizeInputGeometry = (passes) {
          final settled = delegate!(passes);
          element.attachRootOwner(alternate);
          return settled;
        };
        try {
          expect(context.ensureCurrentInputGeometry(), isFalse);
        } finally {
          element.attachRootOwner(owner);
          owner.synchronizeInputGeometry = delegate;
          alternate.focusManager.dispose();
        }
        expect(context.ensureCurrentInputGeometry(), isTrue);
      },
    );
    testWidgets('queries share exhausted input budget without retry $size', (
      t,
    ) async {
      late BuildContext context;
      await t.pumpWidget(
        _Churn(
          enabled: () => true,
          child: Builder(
            builder: (c) {
              context = c;
              return Focus(
                autofocus: true,
                onKey: (_) {
                  final before = t.inputLayoutPasses;
                  expect(context.ensureCurrentInputGeometry(), isFalse);
                  expect(context.ensureCurrentInputGeometry(), isFalse);
                  expect(t.inputLayoutPasses, before);
                  return true;
                },
                child: Text('keys'),
              );
            },
          ),
        ),
        size: size,
      );
      final before = t.inputLayoutPasses;
      expect(t.host.handleKey(const KeyEvent('a')), isTrue);
      expect(t.inputLayoutPasses - before, 2);
    });
    for (final dispose in [false, true]) {
      testWidgets(
        'synchronization reentrant ${dispose ? 'disposal' : 'input'} supersedes old query $size',
        (t) async {
          late BuildContext context;
          final keys = <String>[];
          await t.pumpWidget(
            Builder(
              builder: (c) {
                context = c;
                return Focus(
                  autofocus: true,
                  onKey: (e) {
                    keys.add(e.key);
                    return true;
                  },
                  child: Text('keys'),
                );
              },
            ),
            size: size,
          );
          var ran = false;
          t.host.owner.inputGeometryObservers.add((settled) {
            if (!settled || ran) return;
            ran = true;
            if (dispose) {
              t.host.dispose();
            } else {
              t.host.handleKey(const KeyEvent('n'));
            }
          });
          t.host.owner.requestFrame();
          final before = t.inputLayoutPasses;
          expect(context.ensureCurrentInputGeometry(), isFalse);
          expect(ran, isTrue);
          expect(keys, dispose ? isEmpty : ['n']);
          expect(t.inputLayoutPasses - before, lessThanOrEqualTo(2));
        },
      );
    }
    testWidgets(
      'unresolved selection exposure does not make stable geometry fail $size',
      (t) async {
        late BuildContext context;
        final selection = SelectionController();
        addTearDown(selection.dispose);
        await t.pumpWidget(
          Builder(
            builder: (c) {
              context = c;
              return SelectionArea(
                controller: selection,
                selectionStyle: const Style(inverse: true),
                child: const _Unknown(child: SizedBox(width: 10, height: 1)),
              );
            },
          ),
          size: size,
        );
        final before = t.inputLayoutPasses;
        expect(context.ensureCurrentInputGeometry(), isTrue);
        expect(selection.snapshot(), isNull);
        expect(context.ensureCurrentInputGeometry(), isTrue);
        expect(t.inputLayoutPasses, before);
      },
    );
    testWidgets(
      'layout paint and active settlement guards remain errors $size',
      (t) async {
        late BuildContext context;
        var inLayout = 0, inPaint = 0;
        await t.pumpWidget(
          Builder(
            builder: (c) {
              context = c;
              return _Probe(
                layout: () {
                  expect(
                    () => context.ensureCurrentInputGeometry(),
                    throwsStateError,
                  );
                  inLayout++;
                },
                paint: () {
                  expect(
                    () => context.ensureCurrentInputGeometry(),
                    throwsStateError,
                  );
                  inPaint++;
                },
                child: Text('guards'),
              );
            },
          ),
          size: size,
        );
        expect(inLayout, greaterThan(0));
        expect(inPaint, greaterThan(0));
        final owner = context.owner;
        owner.settlingInputGeometry = true;
        try {
          expect(() => context.ensureCurrentInputGeometry(), throwsStateError);
        } finally {
          owner.settlingInputGeometry = false;
        }
      },
    );
    testWidgets(
      'drawing exception recovery is unresolved and ordinary exceptions propagate $size',
      (t) async {
        late BuildContext context;
        var fail = false;
        await t.pumpWidget(
          Builder(
            builder: (c) {
              context = c;
              return ErrorBoundary(
                errorBuilder: (_, _, _) => Text('fallback'),
                child: _Probe(
                  layout: () {
                    if (fail) throw StateError('probe');
                  },
                  child: Text('original'),
                ),
              );
            },
          ),
          size: size,
        );
        fail = true;
        t.host.owner.requestFrame();
        expect(context.ensureCurrentInputGeometry(), isFalse);
        await t.pump();
        expect(t.screen, shows('fallback'));
        expect(context.ensureCurrentInputGeometry(), isTrue);
        fail = false;
        await t.pumpWidget(
          Builder(
            builder: (c) {
              context = c;
              return _Probe(
                layout: () {
                  if (fail) throw StateError('ordinary');
                },
                child: Text('plain'),
              );
            },
          ),
          size: size,
        );
        fail = true;
        t.host.owner.requestFrame();
        expect(
          () => context.ensureCurrentInputGeometry(),
          throwsA(
            isA<StateError>().having((e) => e.message, 'message', 'ordinary'),
          ),
        );
        fail = false;
      },
    );
  }
}
