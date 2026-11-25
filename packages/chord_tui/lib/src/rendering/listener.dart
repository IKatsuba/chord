import 'package:meta/meta.dart';

import '../foundation/geometry.dart';
import '../input/keys.dart';
import 'box.dart';

/// How a Listener joins a pointer route and affects siblings behind it.
enum HitTestBehavior {
  /// Joins only a child's hit path.
  deferToChild,

  /// Also covers its own bounds and stops siblings behind it.
  opaque,

  /// Also covers its own bounds while allowing siblings behind it.
  translucent,
}

/// Owns one Listener's primary-button capture without taking keyboard focus.
class PointerCaptureController {
  /// Creates a controller to attach to one Listener.
  PointerCaptureController();

  RenderPointerListener? _listener;
  bool _disposed = false;

  /// Whether this controller currently owns a captured primary gesture.
  bool get isCaptured => _listener?.router?.isCapturedBy(_listener!) ?? false;

  /// Captures only from this listener's current primary-down callback.
  void capture() {
    if (_disposed) throw StateError('The capture controller is disposed.');
    final listener = _listener;
    if (listener == null || listener.router == null) {
      throw StateError('The capture controller is not attached.');
    }
    listener.router!.capture(listener);
  }

  /// Cancels an unfinished capture, releasing ownership before callbacks.
  void release() {
    if (_disposed) throw StateError('The capture controller is disposed.');
    final listener = _listener;
    if (listener != null && isCaptured) listener.router!.cancel();
  }

  /// Cancels any capture and detaches this controller permanently.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final listener = _listener;
    _listener = null;
    if (listener != null && listener.router?.isCapturedBy(listener) == true) {
      listener.router!.cancel();
    }
  }
}

/// A passive pointer observer with its child's layout and paint.
class RenderPointerListener extends RenderProxyBox {
  @override
  PaintCoverage describePaintCoverage(Rect localClip) =>
      const PaintCoverage.empty(RenderPointerListener);

  /// A listener that does not change layout or focus.
  RenderPointerListener({
    this.onPointerDown,
    this.onPointerUp,
    this.onPointerMove,
    this.onPointerCancel,
    this.onPointerSignal,
    this.absorbPointerSignal = false,
    this.behavior = HitTestBehavior.deferToChild,
    this.router,
    this.isMounted,
    PointerCaptureController? captureController,
  }) {
    this.captureController = captureController;
  }

  /// Called on a button press along this listener's hit route.
  void Function(MouseEvent)? onPointerDown;

  /// Called on a button release along this listener's hit route.
  void Function(MouseEvent)? onPointerUp;

  /// Called on a held-button motion along this listener's hit route.
  void Function(MouseEvent)? onPointerMove;

  /// Called when an unfinished captured gesture is cancelled.
  void Function(MouseEvent)? onPointerCancel;

  /// Called on a wheel step along this listener's hit route.
  void Function(MouseEvent)? onPointerSignal;

  /// Stops ancestor wheel callbacks on this branch after its own callback.
  bool absorbPointerSignal;

  /// Whether blank bounds hit and whether siblings behind can participate.
  HitTestBehavior behavior;

  /// The host-local pointer dispatcher; render objects do not own it.
  @internal
  final PointerRouter? router;

  /// Whether the widget that owns this listener remains mounted.
  @internal
  final bool Function()? isMounted;

  bool _detached = false;
  PointerCaptureController? _controller;

  /// Whether this receiver can still take a snapshotted callback.
  @internal
  bool get attached => !_detached && (isMounted?.call() ?? true);

  /// The optional capture handle attached to this listener.
  PointerCaptureController? get captureController => _controller;
  set captureController(PointerCaptureController? value) {
    if (identical(_controller, value)) return;
    if (value != null &&
        (value._disposed ||
            (value._listener != null && value._listener!.attached))) {
      throw StateError('A capture controller needs one live Listener.');
    }
    final old = _controller;
    _controller = null;
    if (old != null) {
      old._listener = null;
      if (router?.isCapturedBy(this) == true) router!.cancel();
    }
    _controller = value;
    if (value != null) value._listener = this;
  }

  /// Removes host references before the owning element is unmounted.
  @internal
  void detach() {
    _detached = true;
    if (router?.isCapturedBy(this) == true) router!.cancel();
    if (identical(_controller?._listener, this)) _controller?._listener = null;
    _controller = null;
  }

  /// Snapshots the callback for one event kind before any callback runs.
  void Function(MouseEvent)? callbackFor(MouseEventKind kind) => switch (kind) {
    MouseEventKind.press => onPointerDown,
    MouseEventKind.release => onPointerUp,
    MouseEventKind.move => onPointerMove,
    MouseEventKind.cancel => onPointerCancel,
    MouseEventKind.wheel => onPointerSignal,
  };
}

/// A receiver and its ancestors, captured before dispatch starts.
@internal
class PointerRouteEntry {
  /// Snapshots this event's callback and its logical listener ancestors.
  PointerRouteEntry(this.receiver, MouseEventKind kind, this.ancestors)
    : callback = receiver.callbackFor(kind);

  /// The receiver is checked for disposal immediately before delivery.
  final RenderPointerListener receiver;

  /// The immutable callback for this event.
  final void Function(MouseEvent)? callback;

  /// Closest ancestor first, without translucent siblings.
  final List<RenderPointerListener> ancestors;
}

/// Host-local captured routes and epochs, independent of pointer geometry.
@internal
class PointerRouter {
  /// Defers cancellation notification until a layout/paint phase has unwound.
  PointerRouter({this.deferCancellation});

  /// The host may queue notification, after ownership is already released.
  final void Function(void Function())? deferCancellation;

  List<RenderPointerListener>? _captured;
  PointerRouteEntry? _candidate;
  int _epoch = 0;
  int? _downEpoch;
  MouseEvent? _last;

  /// Identifies pointer ownership across callbacks that start another drag.
  int get epoch => _epoch;

  /// Whether [listener] owns the current captured gesture.
  bool isCapturedBy(RenderPointerListener listener) =>
      _captured?.first == listener;

  /// Claims the current primary down; a deeper claim cannot be stolen.
  void capture(RenderPointerListener listener) {
    if (_downEpoch != _epoch ||
        _candidate?.receiver != listener ||
        !listener.attached) {
      throw StateError('Capture requires this Listener primary-down callback.');
    }
    if (_captured != null) return;
    _captured = List.unmodifiable([listener, ..._candidate!.ancestors]);
  }

  /// Cancels once, clearing ownership before any callback can reenter.
  void cancel({int? expectedEpoch}) {
    if (expectedEpoch != null && expectedEpoch != _epoch) return;
    final path = _captured;
    if (path == null) return;
    _captured = null;
    final epoch = ++_epoch;
    final last = _last!;
    final event = MouseEvent(
      MouseEventKind.cancel,
      position: last.position,
      button: MouseButton.primary,
      shift: last.shift,
      alt: last.alt,
      ctrl: last.ctrl,
    );
    final route = _snapshot(path, event.kind);
    void notify() => _deliver(route, event, epoch);
    final defer = deferCancellation;
    if (defer == null) {
      notify();
    } else {
      defer(notify);
    }
  }

  List<PointerRouteEntry> _snapshot(
    List<RenderPointerListener> path,
    MouseEventKind kind,
  ) => [
    for (final receiver in path) PointerRouteEntry(receiver, kind, const []),
  ];

  /// Creates one current route, then delivers without layout or rehit testing.
  bool dispatch(
    MouseEvent event,
    List<PointerRouteEntry>? Function() freshRoute,
  ) {
    if (event.kind == MouseEventKind.cancel) {
      final hadCapture = _captured != null;
      cancel();
      return hadCapture;
    }
    final primaryDown =
        event.kind == MouseEventKind.press &&
        event.button == MouseButton.primary;
    if (primaryDown) {
      final before = _epoch;
      cancel();
      // A cancel callback may have started a new gesture of its own.
      if (_epoch > before + 1) return false;
      _epoch++;
    }
    final epoch = _epoch;
    final captured = _captured;
    final matching =
        captured != null &&
        event.button == MouseButton.primary &&
        (event.kind == MouseEventKind.move ||
            event.kind == MouseEventKind.release);
    final route = matching ? _snapshot(captured, event.kind) : freshRoute();
    if (route == null || epoch != _epoch) return false;
    _last = event;
    if (matching && event.kind == MouseEventKind.release) {
      // Old-up cleanup cannot release a new down made by an up callback.
      _captured = null;
    }
    final previousDown = _downEpoch;
    final previousCandidate = _candidate;
    _downEpoch = primaryDown ? epoch : null;
    try {
      return _deliver(route, event, epoch);
    } finally {
      _candidate = previousCandidate;
      _downEpoch = previousDown;
    }
  }

  bool _deliver(List<PointerRouteEntry> route, MouseEvent event, int epoch) {
    var delivered = false;
    for (final entry in route) {
      if (epoch != _epoch) break;
      if (!entry.receiver.attached || entry.callback == null) continue;
      _candidate = entry;
      entry.callback!(event);
      delivered = true;
    }
    return delivered;
  }
}

/// Snapshots a deepest-first mouse route using current paint geometry.
List<PointerRouteEntry> hitTestMouse(
  RenderBox root,
  MouseEvent event,
  Rect clip,
) {
  if (root.layoutPass < 0 ||
      !clip.contains(event.position.x, event.position.y)) {
    return const [];
  }
  final callbacks = <PointerRouteEntry>[];
  final ancestors = <RenderPointerListener>[];
  (bool, bool, bool) visit(RenderBox box, Offset origin, Rect clip) {
    if (box.layoutPass != root.layoutPass ||
        box.size.isEmpty ||
        !clip.contains(event.position.x, event.position.y)) {
      return (false, false, false);
    }
    final children = <(RenderBox, Offset, Rect)>[];
    box.visitPaintChildren(origin, clip, (child, at, clip) {
      children.add((child, at, clip));
    });
    var hit = false, blocks = false, bubbles = false;
    if (box is RenderPointerListener) ancestors.add(box);
    for (final (child, at, childClip) in children.reversed) {
      final (childHit, childBlocks, childBubbles) = visit(child, at, childClip);
      hit |= childHit;
      bubbles |= childBubbles;
      blocks |= childBlocks;
      if (childBlocks) break;
    }
    if (box is RenderPointerListener) ancestors.removeLast();
    final local = event.position - origin;
    final inside = Rect.fromOffsetSize(
      Offset.zero,
      box.size,
    ).contains(local.x, local.y);
    if (box is RenderPointerListener) {
      final own = inside && box.behavior != HitTestBehavior.deferToChild;
      final reaches = bubbles || (!hit && own);
      if (reaches) {
        callbacks.add(
          PointerRouteEntry(
            box,
            event.kind,
            List.unmodifiable(ancestors.reversed),
          ),
        );
      }
      return (
        hit || own,
        switch (box.behavior) {
          HitTestBehavior.opaque => blocks || own,
          HitTestBehavior.translucent => own ? false : blocks,
          HitTestBehavior.deferToChild => blocks,
        },
        reaches &&
            !(event.kind == MouseEventKind.wheel && box.absorbPointerSignal),
      );
    }
    final self = inside && box.hitTestSelf(local);
    return (hit || self, blocks || self, bubbles || (!hit && self));
  }

  visit(root, Offset.zero, clip);
  return List.unmodifiable(callbacks);
}
