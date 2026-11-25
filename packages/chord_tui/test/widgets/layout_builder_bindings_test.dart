import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

class _AfterLayout extends SingleChildRenderObjectWidget {
  const _AfterLayout({
    required this.trigger,
    required this.changed,
    required super.child,
  });
  final bool trigger;
  final void Function() changed;
  @override
  RenderBox createRenderObject(BuildContext context) =>
      _RenderAfterLayout(context.owner, trigger, changed);
  @override
  void updateRenderObject(BuildContext context, _RenderAfterLayout box) =>
      box.trigger = trigger;
}

class _RenderAfterLayout extends RenderProxyBox {
  _RenderAfterLayout(this.owner, this.trigger, this.changed);
  final BuildOwner owner;
  bool trigger, sent = false;
  final void Function() changed;
  @override
  void performLayout() {
    super.performLayout();
    if (trigger && !sent) {
      sent = true;
      owner.afterLayout(changed);
    }
  }
}

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'layout-built sibling key help settles before second child layout $size',
      (t) async {
        final trigger = ValueNotifier(false),
            label = ValueNotifier('old label');
        final text = TextAreaController();
        final app = ListenableBuilder(
          listenable: trigger,
          builder: (_) {
            return ListenableBuilder(
              listenable: label,
              builder: (_) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    return _AfterLayout(
                      trigger: trigger.value,
                      changed: () => label.value = 'current label',
                      child: Column(
                        children: [
                          KeyHelp.builder(
                            builder: (_, bindings, pending) => Text(
                              bindings
                                      .where(
                                        (b) => b.chord.toString() == 'alt+y',
                                      )
                                      .singleOrNull
                                      ?.description ??
                                  'waiting',
                            ),
                          ),
                          Actions(
                            bindings: [Binding('alt+y', label.value, () {})],
                            child: TextArea(controller: text, autofocus: true),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
        await t.pumpWidget(app, size: size);
        trigger.value = true;
        final before = t.host.owner.inputLayoutPasses;
        expect(t.host.handleKey(const KeyEvent('x')), isTrue);
        expect(t.host.owner.inputLayoutPasses - before, 2);
        expect(text.text, 'x');
        await t.pump();
        expect(t.screen, shows('current label'));
        trigger.dispose();
        label.dispose();
        text.dispose();
      },
    );
  }
}
