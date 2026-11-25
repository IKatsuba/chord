import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

MouseEvent _wheel(int x, int y) => MouseEvent(
  MouseEventKind.wheel,
  position: Offset(x, y),
  scrollDelta: const Offset(0, -1),
);
Widget _listen(
  String name,
  List<String> log,
  Widget child, {
  HitTestBehavior behavior = HitTestBehavior.opaque,
}) => Listener(
  behavior: behavior,
  onPointerSignal: (_) => log.add(name),
  child: child,
);

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'root blank bounds, event kinds and focus remain independent at $size',
      (t) async {
        final events = <MouseEvent>[];
        final draft = TextAreaController(text: 'draft');
        await t.pumpWidget(
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: events.add,
            onPointerUp: events.add,
            onPointerSignal: events.add,
            child: Column(
              children: [
                TextArea(controller: draft, autofocus: true),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
          size: size,
        );
        final focus = t.focusManager.primaryFocus;
        await t.mouse(_wheel(size.width - 1, size.height - 1));
        await t.mouse(
          const MouseEvent(
            MouseEventKind.press,
            position: Offset(1, 1),
            button: MouseButton.primary,
          ),
        );
        await t.mouse(
          const MouseEvent(
            MouseEventKind.release,
            position: Offset(3, 2),
            button: MouseButton.primary,
          ),
        );
        expect(events.map((e) => e.kind), [
          MouseEventKind.wheel,
          MouseEventKind.press,
          MouseEventKind.release,
        ]);
        expect(events.last.position, const Offset(3, 2));
        await t.mouse(_wheel(-1, 0));
        await t.mouse(_wheel(size.width, 0));
        expect(events, hasLength(3));
        expect(t.focusManager.primaryFocus, same(focus));
        expect(draft.text, 'draft');
        t.dispose();
        draft.dispose();
      },
    );
  }
  testWidgets(
    'defer joins painted descendants, empty layout is not a surface',
    (t) async {
      final log = <String>[];
      await t.pumpWidget(
        _listen(
          'defer',
          log,
          const SizedBox(),
          behavior: HitTestBehavior.deferToChild,
        ),
      );
      await t.mouse(_wheel(1, 1));
      expect(log, isEmpty);
      await t.pumpWidget(
        _listen(
          'defer',
          log,
          Box(border: Border.single, child: const SizedBox()),
          behavior: HitTestBehavior.deferToChild,
        ),
      );
      await t.mouse(_wheel(5, 5));
      expect(log, ['defer']);
      log.clear();
      for (final child in <Widget>[
        Text('paint'),
        const Code('paint'),
        const Markdown('> paint'),
        const Markdown('|a|\n|---|\n|b|'),
        const Diff('a', 'b'),
      ]) {
        await t.pumpWidget(
          _listen('leaf', log, child, behavior: HitTestBehavior.deferToChild),
        );
        await t.mouse(_wheel(0, 0));
        expect(log.last, 'leaf');
      }
    },
  );
  testWidgets(
    'reverse painting, translucent siblings and deepest ancestor order',
    (t) async {
      final log = <String>[];
      for (final behavior in HitTestBehavior.values) {
        await t.pumpWidget(
          _listen(
            'root',
            log,
            Stack(
              children: [
                Positioned(
                  left: 1,
                  top: 1,
                  width: 8,
                  height: 3,
                  child: _listen('lower', log, Text('lower')),
                ),
                Positioned(
                  left: 1,
                  top: 1,
                  width: 8,
                  height: 3,
                  child: _listen(
                    'upper',
                    log,
                    Text('upper'),
                    behavior: behavior,
                  ),
                ),
              ],
            ),
          ),
        );
        log.clear();
        await t.mouse(_wheel(2, 2));
        expect(
          log,
          behavior == HitTestBehavior.translucent
              ? ['upper', 'lower', 'root']
              : ['upper', 'root'],
        );
        log.clear();
        await t.mouse(_wheel(0, 0));
        expect(log, ['root']);
      }
    },
  );
  testWidgets(
    'clipped translated children and visible overflow use paint geometry',
    (t) async {
      final log = <String>[];
      await t.pumpWidget(
        Row(
          children: [
            SizedBox(
              width: 6,
              height: 3,
              child: Stack(
                children: [
                  Positioned(
                    left: -2,
                    top: -1,
                    width: 8,
                    height: 4,
                    child: _listen('clipped', log, Text('visible')),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      await t.mouse(_wheel(0, 0));
      expect(log, ['clipped']);
      log.clear();
      await t.mouse(_wheel(6, 0));
      expect(log, isEmpty);
      await t.pumpWidget(
        Row(
          children: [
            Align(
              alignment: Alignment.topLeft,
              widthFactor: .5,
              child: SizedBox(
                width: 10,
                height: 2,
                child: _listen('overflow', log, Text('0123456789')),
              ),
            ),
          ],
        ),
      );
      await t.mouse(_wheel(8, 0));
      expect(log, ['overflow']);
    },
  );
  testWidgets(
    'fold body clips counts and closed or zero children never receive',
    (t) async {
      final log = <String>[];
      Widget page(bool open) => Column(
        children: [
          SizedBox(
            width: 12,
            height: 4,
            child: Fold(
              title: 'fold',
              open: open,
              child: _listen(
                'body',
                log,
                const SizedBox(width: 12, height: 10),
              ),
            ),
          ),
          SizedBox(
            width: 0,
            height: 0,
            child: _listen('zero', log, Text('hidden')),
          ),
        ],
      );
      await t.pumpWidget(page(true));
      await t.mouse(_wheel(2, 1));
      expect(log, ['body']);
      log.clear();
      await t.mouse(_wheel(2, 3));
      expect(log, isEmpty);
      await t.pumpWidget(page(false));
      await t.mouse(_wheel(2, 1));
      expect(log, isEmpty);
      await t.mouse(_wheel(0, 4));
      expect(log, isEmpty);
    },
  );
  testWidgets('virtualised positions follow current offset and viewport clip', (
    t,
  ) async {
    final log = <String>[];
    final scroll = ScrollController();
    await t.pumpWidget(
      Column(
        children: [
          SizedBox(
            height: 4,
            child: ListView.builder(
              controller: scroll,
              itemCount: 20,
              itemVersion: (i) => i,
              itemBuilder: (_, i) => _listen(
                'item$i',
                log,
                SizedBox(height: 2, child: Text('item$i')),
              ),
            ),
          ),
          Text('below'),
        ],
      ),
    );
    await t.mouse(_wheel(0, 0));
    expect(log, ['item0']);
    log.clear();
    scroll.jumpTo(3);
    await t.pump();
    await t.mouse(_wheel(0, 0));
    expect(log, ['item1']);
    log.clear();
    await t.mouse(_wheel(0, 1));
    expect(log, ['item2']);
    log.clear();
    await t.mouse(_wheel(0, 4));
    expect(log, isEmpty);
    t.dispose();
    scroll.dispose();
  });
  testWidgets(
    'follower routes only its clipped painted area and moves or hides',
    (t) async {
      final log = <String>[];
      final link = LayerLink();
      final left = ValueNotifier<int?>(4);
      final page = OverlayEntry(
        builder: (_) => _listen(
          'page',
          log,
          ListenableBuilder(
            listenable: left,
            builder: (_) => Stack(
              children: [
                if (left.value case final x?)
                  Positioned(
                    left: x,
                    top: 2,
                    child: CompositedTransformTarget(
                      link: link,
                      child: Text('anchor'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      final front = OverlayEntry(
        builder: (_) => CompositedTransformFollower(
          link: link,
          targetAnchor: Alignment.bottomLeft,
          child: _listen('front', log, const SizedBox(width: 8, height: 3)),
        ),
      );
      await t.pumpWidget(
        _listen('root', log, Overlay(initialEntries: [page, front])),
      );
      await t.mouse(_wheel(4, 3));
      expect(log, ['front', 'root']);
      log.clear();
      await t.mouse(_wheel(0, 0));
      expect(log, ['page', 'root']);
      log.clear();
      left.value = 10;
      await t.pump();
      await t.mouse(_wheel(4, 3));
      expect(log, ['page', 'root']);
      log.clear();
      await t.mouse(_wheel(10, 3));
      expect(log, ['front', 'root']);
      log.clear();
      left.value = null;
      await t.pump();
      await t.mouse(_wheel(10, 3));
      expect(log, ['page', 'root']);
      log.clear();
      front.remove();
      await t.pump();
      await t.mouse(_wheel(10, 3));
      expect(log, ['page', 'root']);
      t.dispose();
      left.dispose();
    },
  );
  testWidgets(
    'one event snapshots callbacks despite a rebuild during delivery',
    (t) async {
      final log = <String>[];
      final version = ValueNotifier(0);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: version,
          builder: (_) {
            final value = version.value;
            return _listen(
              'root$value',
              log,
              Stack(
                children: [
                  _listen('lower$value', log, Text('lower')),
                  Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerSignal: (_) {
                      log.add('upper$value');
                      if (value == 0) {
                        version.value = 1;
                        t.host.drawFrame(const Size(80, 24));
                      }
                    },
                    child: Text('upper'),
                  ),
                ],
              ),
            );
          },
        ),
        size: const Size(80, 24),
      );
      await t.mouse(_wheel(0, 0));
      expect(log, ['upper0', 'lower0', 'root0']);
      log.clear();
      await t.mouse(_wheel(0, 0));
      expect(log, ['upper1', 'lower1', 'root1']);
      t.dispose();
      version.dispose();
    },
  );
  testWidgets(
    'signal absorption is branch-local and leaves buttons unchanged',
    (t) async {
      final log = <String>[];
      for (final lowerAbsorbs in [false, true]) {
        Widget branch(String name, bool absorbs, HitTestBehavior behavior) =>
            Listener(
              behavior: behavior,
              absorbPointerSignal: absorbs,
              onPointerSignal: (_) => log.add(name),
              onPointerDown: (_) => log.add('$name down'),
              onPointerUp: (_) => log.add('$name up'),
              child: Text(name),
            );
        await t.pumpWidget(
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: (_) => log.add('root'),
            onPointerDown: (_) => log.add('root down'),
            onPointerUp: (_) => log.add('root up'),
            child: Stack(
              children: [
                branch('lower', lowerAbsorbs, HitTestBehavior.opaque),
                Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerSignal: (_) => log.add('upper ancestor'),
                  child: branch('upper', true, HitTestBehavior.translucent),
                ),
              ],
            ),
          ),
        );
        log.clear();
        await t.mouse(_wheel(0, 0));
        expect(
          log,
          lowerAbsorbs ? ['upper', 'lower'] : ['upper', 'lower', 'root'],
        );
        log.clear();
        for (final kind in [MouseEventKind.press, MouseEventKind.release]) {
          await t.mouse(
            MouseEvent(
              kind,
              position: Offset.zero,
              button: MouseButton.primary,
            ),
          );
        }
        expect(log, [
          'upper down',
          'lower down',
          'root down',
          'upper up',
          'lower up',
          'root up',
        ]);
      }
    },
  );
  testWidgets(
    'absorption and callbacks are snapshotted across synchronous rebuild',
    (t) async {
      final log = <String>[];
      final absorbs = ValueNotifier(true);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: absorbs,
          builder: (_) {
            final value = absorbs.value;
            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerSignal: (_) => log.add('root $value'),
              child: Listener(
                behavior: HitTestBehavior.opaque,
                absorbPointerSignal: value,
                onPointerSignal: (_) {
                  log.add('child $value');
                  absorbs.value = !value;
                  t.host.drawFrame(const Size(80, 24));
                },
                child: const SizedBox(),
              ),
            );
          },
        ),
        size: const Size(80, 24),
      );
      await t.mouse(_wheel(0, 0));
      expect(log, ['child true']);
      log.clear();
      await t.mouse(_wheel(0, 0));
      expect(log, ['child false', 'root false']);
      log.clear();
      await t.mouse(_wheel(0, 0));
      expect(log, ['child true']);
      t.dispose();
      absorbs.dispose();
    },
  );
  test(
    'separate hosts do not invalidate one another through global layout stamps',
    () {
      final log = <String>[];
      final a = AppHost(_listen('a', log, Text('a'))),
          b = AppHost(_listen('b', log, Text('b')));
      a.drawFrame(const Size(20, 6));
      b.drawFrame(const Size(20, 6));
      a.handleMouse(_wheel(0, 0));
      b.handleMouse(_wheel(0, 0));
      expect(log, ['a', 'b']);
      a.dispose();
      b.dispose();
      expect(a.handleMouse(_wheel(0, 0)), isFalse);
    },
  );
}
