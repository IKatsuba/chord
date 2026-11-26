import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

Widget host(
  FocusScopeNode outer,
  FocusNode page,
  void Function(OverlayState) ready,
) => Column(
  children: [
    Focus(focusNode: page, autofocus: true, child: Text('page')),
    Expanded(
      child: FocusScope(
        node: outer,
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) {
                ready(Overlay.of(context));
                return Text('base');
              },
            ),
          ],
        ),
      ),
    ),
  ],
);

OverlayEntry layer(
  FocusNode node,
  List<String> log,
  String name, {
  bool requestFocus = true,
}) => OverlayEntry(
  requestFocus: requestFocus,
  builder: (_) => Actions(
    bindings: [Binding('x', name, () => log.add(name))],
    child: Focus(
      focusNode: node,
      autofocus: true,
      child: Text('界🙂e\u0301 $name\x1b[31m'),
    ),
  ),
);

void main() {
  group('CHD-638 tester: deferred overlay request ownership', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('a passive later layer cannot replace a pending takeover '
          'at $size', (t) async {
        final outer = FocusScopeNode(active: false);
        final page = FocusNode();
        final wanted = FocusNode();
        final passive = FocusNode();
        for (final node in [outer, page, wanted, passive]) {
          addTearDown(node.dispose);
        }
        late OverlayState overlay;
        final log = <String>[];
        await t.pumpWidget(host(outer, page, (o) => overlay = o), size: size);
        overlay.insert(layer(wanted, log, 'wanted'));
        await t.pump();
        overlay.insert(layer(passive, log, 'passive', requestFocus: false));
        await t.pump();
        expect(t.focusManager.primaryFocus, same(page));
        await t.press('x');
        expect(log, isEmpty);
        t.focusManager.setScopeActive(outer, true, takeFocus: true);
        await t.press('x');
        expect(t.focusManager.primaryFocus, same(wanted));
        expect(log, ['wanted']);
        t.focusManager.setScopeActive(outer, false);
        expect(t.focusManager.primaryFocus, same(page));
      });

      testWidgets('removing the queued layer cannot focus its detached node '
          'at $size', (t) async {
        final outer = FocusScopeNode(active: false);
        final page = FocusNode();
        final removed = FocusNode();
        for (final node in [outer, page, removed]) {
          addTearDown(node.dispose);
        }
        late OverlayState overlay;
        final log = <String>[];
        await t.pumpWidget(host(outer, page, (o) => overlay = o), size: size);
        final entry = layer(removed, log, 'removed');
        overlay.insert(entry);
        await t.pump();
        entry.remove();
        await t.pump();
        expect(removed.attached, isFalse);
        expect(t.focusManager.primaryFocus, same(page));
        t.focusManager.setScopeActive(outer, true, takeFocus: true);
        await t.press('x');
        expect(t.focusManager.primaryFocus, isNot(same(removed)));
        expect(log, isEmpty);
        await t.pumpWidget(Text('disposed'));
        await t.press('x');
        expect(log, isEmpty);
      });
    }
  });

  group('CHD-638 tester: nearest inactive scope handoff', () {
    for (final size in const [
      Size.zero,
      Size(1, 1),
      Size(120, 40),
      Size(80, 24),
    ]) {
      testWidgets('three inactive ancestors pass the request one level at a '
          'time without stealing page keys at $size', (t) async {
        final page = FocusNode();
        final outer = FocusScopeNode(active: false);
        final middle = FocusScopeNode(active: false);
        final inner = FocusScopeNode(active: false);
        final field = FocusNode();
        for (final node in [page, outer, middle, inner, field]) {
          addTearDown(node.dispose);
        }
        final log = <String>[];
        await t.pumpWidget(
          SingleChildScrollView(
            child: Focus(
              focusNode: page,
              autofocus: true,
              child: FocusScope(
                node: outer,
                child: FocusScope(
                  node: middle,
                  child: FocusScope(
                    node: inner,
                    child: Actions(
                      bindings: [Binding('x', 'field', () => log.add('field'))],
                      child: Focus(
                        focusNode: field,
                        autofocus: true,
                        child: Text('界🙂e\u0301\x1b[31m'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          size: size,
        );
        t.focusManager.setScopeActive(inner, true, takeFocus: true);
        await t.press('x');
        expect(t.focusManager.primaryFocus, same(page));
        t.focusManager.setScopeActive(middle, true, autofocus: true);
        await t.press('x');
        expect(t.focusManager.primaryFocus, same(page));
        expect(log, isEmpty);
        await t.resize(const Size(120, 40));
        t.focusManager.setScopeActive(outer, true, takeFocus: true);
        for (var i = 0; i < 1000; i++) {
          t.host.handleKey(const KeyEvent('x'));
        }
        await t.pump();
        expect(t.focusManager.primaryFocus, same(field));
        expect(log, hasLength(1000));
        t.focusManager.setScopeActive(outer, false);
        expect(t.focusManager.primaryFocus, same(page));
        t.focusManager.setScopeActive(outer, true, takeFocus: true);
        await t.press('x');
        expect(t.focusManager.primaryFocus, same(field));
        expect(log, hasLength(1001));
        await t.pumpWidget(Text('removed'));
        await t.press('x');
        expect(log, hasLength(1001));
        expect(t.exitRequested, isFalse);
      });
    }
  });
}
