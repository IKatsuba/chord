import '../input/keys.dart';
import '../rendering/listener.dart';
import 'framework.dart';

export '../rendering/listener.dart'
    show HitTestBehavior, PointerCaptureController;

/// Observes typed mouse events under its child without taking focus.
class Listener extends SingleChildRenderObjectWidget {
  /// A passive pointer listener; opaque behavior also covers blank bounds.
  const Listener({
    super.key,
    required super.child,
    this.onPointerDown,
    this.onPointerUp,
    this.onPointerMove,
    this.onPointerCancel,
    this.captureController,
    this.onPointerSignal,
    this.absorbPointerSignal = false,
    this.behavior = HitTestBehavior.deferToChild,
  });

  /// Called for a press on the listener's hit path.
  final void Function(MouseEvent)? onPointerDown;

  /// Called for a release, following this listener's capture when held.
  final void Function(MouseEvent)? onPointerUp;

  /// Called for held-button motion, including outside captured bounds.
  final void Function(MouseEvent)? onPointerMove;

  /// Called once when an unfinished captured gesture is cancelled.
  final void Function(MouseEvent)? onPointerCancel;

  /// Allows this listener to capture from its primary-down callback.
  final PointerCaptureController? captureController;

  /// Called for a wheel step, independently of keyboard focus.
  final void Function(MouseEvent)? onPointerSignal;

  /// Stops ancestor wheel callbacks on this branch, retaining its own callback.
  final bool absorbPointerSignal;

  /// How this listener participates alongside painted descendants and siblings.
  final HitTestBehavior behavior;

  @override
  Element createElement() => _ListenerElement(this);

  @override
  RenderPointerListener createRenderObject(BuildContext context) =>
      RenderPointerListener(
        onPointerDown: onPointerDown,
        onPointerUp: onPointerUp,
        onPointerMove: onPointerMove,
        onPointerCancel: onPointerCancel,
        captureController: captureController,
        router: context.owner.pointerRouter,
        isMounted: () => context.mounted,
        onPointerSignal: onPointerSignal,
        absorbPointerSignal: absorbPointerSignal,
        behavior: behavior,
      );
  @override
  void updateRenderObject(
    BuildContext context,
    RenderPointerListener renderObject,
  ) {
    renderObject
      ..onPointerDown = onPointerDown
      ..onPointerUp = onPointerUp
      ..onPointerMove = onPointerMove
      ..onPointerCancel = onPointerCancel
      ..captureController = captureController
      ..onPointerSignal = onPointerSignal
      ..absorbPointerSignal = absorbPointerSignal
      ..behavior = behavior;
  }
}

class _ListenerElement extends SingleChildRenderObjectElement {
  _ListenerElement(Listener super.widget);

  @override
  void unmount() {
    (renderObject as RenderPointerListener).detach();
    super.unmount();
  }
}
