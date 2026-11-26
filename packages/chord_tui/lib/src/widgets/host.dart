import '../foundation/geometry.dart';
import '../input/keys.dart';
import '../rendering/box.dart';
import '../rendering/listener.dart';
import '../terminal/buffer.dart';
import '../terminal/terminal.dart';
import 'focus_manager.dart';
import 'framework.dart';

/// Owns a widget tree and turns it into frames; knows nothing of terminals.
///
/// [runApp] drives one with a real terminal, the tester with a fake one.
class AppHost {
  /// An app host whose pending chord wait is [chordTimeout], reading a
  /// press that does nothing through [layoutFallback], in [terminal],
  /// which `TerminalScope.of` gives its widgets.
  AppHost(
    Widget app, {
    void Function()? onNeedsFrame,
    void Function()? onExit,
    Duration chordTimeout = defaultChordTimeout,
    KeyLayoutFallback? layoutFallback,
    Terminal? terminal,
  }) : owner = BuildOwner(
         onNeedsFrame: onNeedsFrame,
         onExit: onExit,
         chordTimeout: chordTimeout,
         layoutFallback: layoutFallback,
       ) {
    owner.terminal = terminal;
    owner.synchronizeInputGeometry = (maxPasses) =>
        _ensureCurrentGeometry(maxPasses: maxPasses);
    owner.inputRenderRoot = () =>
        _disposed ? null : RenderObjectElement.firstRenderObject(_root);
    _root = app.createElement()..attachRootOwner(owner);
    _root.mount(null);
  }

  /// The owner that builds, lays out and dispatches for this app.
  final BuildOwner owner;
  late final Element _root;
  bool _disposed = false;
  Size? _lastSize;
  int _geometryEpoch = -1;
  int _inputDispatchEpoch = 0;
  _GeometryBudget? _geometryBudget;

  /// Where focus and key bindings are kept.
  FocusManager get focusManager => owner.focusManager;

  /// The root of the element tree.
  Element get rootElement => _root;

  /// Builds what is dirty, lays the tree out at [size] and paints it.
  ///
  /// What layout changes is told to listeners after it; when that dirties
  /// anything, the tree is built and laid out once more, so one frame shows
  /// a settled screen. What the second layout changes is drawn next frame.
  Buffer drawFrame(Size size) {
    while (true) {
      try {
        return _drawFrame(size);
      } catch (error, stack) {
        owner.pointerRouter.cancel();
        if (!owner.recoverDrawingError(error, stack)) rethrow;
      }
    }
  }

  Buffer _drawFrame(Size size) {
    updateSize(size);
    final pointerEpoch = owner.pointerRouter.epoch;
    if (!_settleGeometry(size) || !_geometryIsCurrent) {
      owner.pointerRouter.cancel(expectedEpoch: pointerEpoch);
    }
    final buffer = Buffer(size.width, size.height);
    final ro = RenderObjectElement.firstRenderObject(_root);
    owner.doingLayoutOrPaint = true;
    try {
      ro?.paint(Canvas(buffer), Offset.zero);
    } finally {
      owner.doingLayoutOrPaint = false;
      owner.flushInputGeometryNotifications();
    }
    return buffer;
  }

  /// Records a terminal resize before the next input batch or frame is routed.
  void updateSize(Size size) {
    if (_lastSize == size) return;
    _lastSize = size;
    owner.requestFrame();
  }

  bool _settleGeometry(Size size, {int maxPasses = 2}) {
    if (owner.settlingInputGeometry || owner.doingLayoutOrPaint) {
      throw StateError('Cannot settle geometry recursively.');
    }
    final previousBudget = _geometryBudget;
    final budget = previousBudget?.inputEpoch == _inputDispatchEpoch
        ? previousBudget!
        : _GeometryBudget(_inputDispatchEpoch, maxPasses);
    _geometryBudget = budget;
    bool current() => !_disposed && budget.inputEpoch == _inputDispatchEpoch;
    void notify(bool settled) {
      if (!current()) return;
      if (!settled) {
        if (budget.unresolvedNotified) return;
        budget.unresolvedNotified = true;
      }
      for (final observer in List.of(owner.inputGeometryObservers)) {
        if (!current()) break;
        if (owner.inputGeometryObservers.contains(observer)) observer(settled);
      }
      owner.flushInputGeometryNotifications();
    }

    try {
      for (var pass = 0; pass < maxPasses && budget.remaining > 0; pass++) {
        budget.remaining--;
        owner.settlingInputGeometry = true;
        try {
          _buildAndLayout(size);
          final epoch = owner.inputGeometryEpoch;
          owner.flushAfterLayout();
          _geometryEpoch =
              !owner.hasDirtyElements && epoch == owner.inputGeometryEpoch
              ? epoch
              : -1;
        } finally {
          owner.settlingInputGeometry = false;
        }
        // Ordinary notifications can rebuild the parent. They settle within
        // this same budget, after layout and its recursion guard have unwound.
        if (_geometryIsCurrent) notify(true);
        if (!current()) return false;
        if (_geometryIsCurrent) return true;
      }
      _geometryEpoch = -1;
      budget.exhausted = true;
      owner.requestFrame();
      notify(false);
      return false;
    } catch (_) {
      budget.exhausted = false;
      _geometryEpoch = -1;
      notify(false);
      rethrow;
    } finally {
      owner.settlingInputGeometry = false;
      try {
        owner.flushInputGeometryNotifications();
      } finally {
        _geometryBudget = previousBudget;
      }
    }
  }

  bool get _geometryIsCurrent =>
      _geometryEpoch == owner.inputGeometryEpoch &&
      !owner.hasDirtyElements &&
      !owner.structureChanged;

  bool _ensureCurrentGeometry({int maxPasses = 2}) {
    if (owner.doingLayoutOrPaint || owner.settlingInputGeometry) {
      throw StateError('Cannot synchronize geometry during layout or paint.');
    }
    final size = _lastSize;
    if (_disposed || size == null) return false;
    if (_geometryIsCurrent) return true;
    final pointerEpoch = owner.pointerRouter.epoch;
    try {
      if (_settleGeometry(size, maxPasses: maxPasses) && _geometryIsCurrent) {
        return true;
      }
    } catch (error, stack) {
      _geometryBudget?.exhausted = false;
      owner.pointerRouter.cancel(expectedEpoch: pointerEpoch);
      if (!owner.recoverDrawingError(error, stack)) rethrow;
      // Recovery is routed by a later explicit operation or ordinary frame.
      return false;
    }
    owner.pointerRouter.cancel(expectedEpoch: pointerEpoch);
    return false;
  }

  void _buildAndLayout(Size size) {
    owner.buildScope();
    if (owner.structureChanged) {
      syncRenderTree(_root);
      owner.structureChanged = false;
    }
    final ro = RenderObjectElement.firstRenderObject(_root);
    if (ro != null) {
      owner.inputLayoutPasses++;
      RenderBox.beginLayoutPass();
      owner.doingLayoutOrPaint = true;
      try {
        ro.layout(BoxConstraints.tight(size));
        ro.offset = Offset.zero;
      } finally {
        owner.doingLayoutOrPaint = false;
      }
    }
  }

  bool _inputOperation(bool Function(int epoch) route) {
    final previousBudget = _geometryBudget;
    final epoch = ++_inputDispatchEpoch;
    _geometryBudget = _GeometryBudget(epoch, 2);
    try {
      return route(epoch);
    } finally {
      _geometryBudget = previousBudget;
    }
  }

  /// Routes a key press. Unhandled tab moves focus; unhandled ctrl+c quits.
  bool handleKey(KeyEvent event) => _inputOperation((dispatchEpoch) {
    final current = _ensureCurrentGeometry();
    if (_disposed ||
        dispatchEpoch != _inputDispatchEpoch ||
        (!current && !_geometryBudget!.exhausted)) {
      return false;
    }
    // Exhaustion leaves a completed mounted focus tree and schedules a frame.
    // Keys can use that tree; geometry-dependent queries still fail closed.
    final handled = focusManager.dispatchKey(event);
    if (_disposed || dispatchEpoch != _inputDispatchEpoch) return false;
    if (handled) return true;
    final c = event.combo;
    if (c == KeyCombo.parse('tab')) {
      focusManager.focusNext();
      owner.requestFrame();
      return true;
    }
    if (c == KeyCombo.parse('shift+tab')) {
      focusManager.focusPrevious();
      owner.requestFrame();
      return true;
    }
    if (c == KeyCombo.parse('ctrl+c')) {
      owner.requestExit();
      return true;
    }
    return false;
  });

  /// Delivers a typed mouse report along a fixed current paint hit path.
  bool handleMouse(MouseEvent event) => _inputOperation((dispatchEpoch) {
    if (!_ensureCurrentGeometry() || dispatchEpoch != _inputDispatchEpoch) {
      return false;
    }
    return owner.pointerRouter.dispatch(event, () {
      if (!_ensureCurrentGeometry() || dispatchEpoch != _inputDispatchEpoch) {
        return null;
      }
      final root = RenderObjectElement.firstRenderObject(_root);
      if (root == null) return const [];
      return hitTestMouse(
        root,
        event,
        Rect.fromOffsetSize(Offset.zero, _lastSize!),
      );
    });
  });

  /// Cancels unfinished pointer ownership before terminal handoff or teardown.
  void cancelPointerCapture() => owner.pointerRouter.cancel();

  /// Routes pasted text to the focused handlers; true when one took it.
  bool handlePaste(String text) => _inputOperation((dispatchEpoch) {
    return _ensureCurrentGeometry() &&
        dispatchEpoch == _inputDispatchEpoch &&
        focusManager.dispatchPaste(text);
  });

  /// Releases pointer capture, unmounts the app and disposes its focus; later calls do nothing.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      cancelPointerCapture();
    } finally {
      try {
        Element.unmountTree(_root);
      } finally {
        owner.synchronizeInputGeometry = null;
        owner.inputRenderRoot = null;
        owner.inputGeometryObservers.clear();
        focusManager.dispose();
      }
    }
  }
}

/// Asks the app that [context] belongs to to quit.
void exitApp(BuildContext context) => context.owner.requestExit();

// Reentrant geometry queries share the remaining work of their input operation.
// A real nested input supersedes the old operation and has its own epoch.
class _GeometryBudget {
  _GeometryBudget(this.inputEpoch, this.remaining);
  final int inputEpoch;
  int remaining;
  bool unresolvedNotified = false;
  bool exhausted = false;
}
