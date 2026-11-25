import 'package:meta/meta.dart';

import '../foundation/geometry.dart';
import '../foundation/selection.dart';
import '../foundation/selection_controller.dart';
import '../foundation/selection_diagnostics.dart';
import '../foundation/selection_geometry.dart';
import '../foundation/selection_source.dart';
import '../foundation/text_editing.dart';
import '../input/keys.dart';
import '../rendering/selection_area.dart';
import '../rendering/list_viewport.dart';
import '../rendering/box.dart';
import '../terminal/style.dart';
import '../text/selection_layout.dart';
import 'framework.dart';
import 'listener.dart';

/// Owns primary-drag text selection without taking focus or changing layout.
class SelectionArea extends StatefulWidget {
  /// Selects eligible descendant text through current semantic source maps.
  const SelectionArea({
    super.key,
    required this.controller,
    required this.selectionStyle,
    this.onSelectionChanged,
    this.onSelectionFinalized,
    required this.child,
  });

  /// One live area's logical range and synchronized queries.
  final SelectionController controller;

  /// Overrides selected glyph attributes while retaining other syntax styles.
  final Style selectionStyle;

  /// Called outside layout/paint after a logical range change.
  final void Function(SelectionValue)? onSelectionChanged;

  /// Called once after a matching release has let go of capture.
  final void Function(SelectionValue)? onSelectionFinalized;

  /// Existing content, including any disabled furniture and overlay host.
  final Widget child;

  @override
  State<SelectionArea> createState() => _SelectionAreaState();
}

/// Excludes furniture and request surfaces from an enclosing selection area.
class SelectionContainer extends SingleChildRenderObjectWidget {
  /// Omits all descendant sources while preserving their ordinary painting.
  const SelectionContainer.disabled({super.key, required super.child});

  @override
  RenderSelectionBoundary createRenderObject(BuildContext context) =>
      RenderSelectionBoundary(disabled: true);
}

/// Collects settled button geometry under its authoritative enclosing eligibility.
@internal
SelectionScene? collectCodeButtonScene(
  BuildContext context,
  RenderBox content,
) {
  var disabled = false;
  context.visitAncestorElements((element) {
    // Independent nested areas start their own authoritative document.
    if (element.widget is SelectionArea) return false;
    if (element.widget is SelectionContainer) {
      disabled = true;
      return false;
    }
    return true;
  });
  if (disabled) return null;
  final area = context.findAncestorStateOfType<_SelectionAreaState>();
  RenderBox? scope = area?._box;
  if (area != null && (area._detached || !area.mounted || scope == null)) {
    return null;
  }
  if (area == null) {
    // A delegate remains authoritative even without an enclosing range owner.
    context.visitAncestorElements((element) {
      if (element is RenderObjectElement &&
          element.renderObject is RenderListViewport) {
        final viewport = element.renderObject as RenderListViewport;
        if (viewport.selectionDelegate != null) {
          scope = viewport;
          return false;
        }
      }
      return true;
    });
  }
  final root = context.owner.inputRenderRoot?.call();
  if (root == null) return null;
  return SelectionScene.collect(root, scope ?? content);
}

/// Internal editor registration around its existing drawn rows and caret.
class SelectionEditor extends SingleChildRenderObjectWidget {
  /// Registers the live layout without creating another editor/caret model.
  const SelectionEditor({
    required this.controller,
    required this.layout,
    required super.child,
  });

  /// Existing editor controller, also its semantic identity.
  final TextAreaController controller;

  /// Exact controller layout used by the child rows.
  final TextAreaLayout layout;

  @override
  RenderSelectionEditor createRenderObject(BuildContext context) =>
      RenderSelectionEditor(controller, layout);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSelectionEditor renderObject,
  ) {
    renderObject
      ..controller = controller
      ..editorLayout = layout;
  }
}

class _AreaBox extends SingleChildRenderObjectWidget {
  const _AreaBox({required this.bind, required super.child});
  final void Function(RenderSelectionBoundary) bind;
  @override
  RenderSelectionBoundary createRenderObject(BuildContext context) {
    final box = RenderSelectionBoundary();
    bind(box);
    return box;
  }
}

class _SelectionAreaState extends State<SelectionArea>
    implements SelectionClient {
  final _model = SelectionRangeModel();
  final _capture = PointerCaptureController();
  RenderSelectionBoundary? _box;
  SelectionScene? _scene;
  ({
    int epoch,
    RenderBox root,
    RenderSelectionBoundary boundary,
    SelectionController controller,
  })?
  _sceneStamp;

  void _forgetScene() {
    _scene = null;
    _sceneStamp = null;
  }

  SelectionPosition? _focus;
  Offset? _lastMotion;
  Object? _anchorSlot;
  Set<Object> _retainedSlots = {};
  var _refreshing = false, _detached = false;
  var _releaseAfterProjection = false;
  int _gesture = 0;
  int _published = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.attachSelection(this);
    context.owner.inputGeometryObservers.add(_geometryChanged);
    context.owner.afterLayout(() {
      if (mounted && !_detached) widget.controller.validateAttachment();
    });
  }

  @override
  void didUpdateWidget(SelectionArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.detachSelection(this);
      clearSelection();
      _detached = false;
      widget.controller.attachSelection(this);
      context.owner.afterLayout(() {
        if (mounted && !_detached) widget.controller.validateAttachment();
      });
    }
  }

  @override
  void dispose() {
    context.owner.inputGeometryObservers.remove(_geometryChanged);
    _detached = true;
    _capture.dispose();
    // A disposed host may retain its element tree; release selection resources
    // without relying on that tree or the render paint bridges being collected.
    _clearHighlights();
    _model.clear();
    _retainedSlots = {};
    _anchorSlot = null;
    _lastMotion = null;
    _forgetScene();
    _focus = null;
    widget.controller.detachSelection(this);
    super.dispose();
  }

  @override
  SelectionValue get selectionValue => _model.value;

  @override
  SelectionDiagnostics get selectionDiagnostics {
    final scene = _scene?.diagnostics ?? const SelectionDiagnostics();
    return SelectionDiagnostics(
      logicalSlots: scene.logicalSlots,
      visibleRoots: scene.visibleRoots,
      resolvedRoots: scene.resolvedRoots,
      offscreenResolvedRoots: scene.offscreenResolvedRoots,
      cachedFragments: scene.cachedFragments,
      selectedRoots: _retainedSlots.length,
      selectedRanges: _model.leases.length,
    );
  }

  bool _sync({int maxPasses = 2}) {
    if (_detached || !mounted) return false;
    final gesture = _gesture;
    if (!context.owner.ensureCurrentInputGeometry(maxPasses: maxPasses)) {
      if (gesture == _gesture) _unresolved();
      return false;
    }
    final epoch = context.owner.inputGeometryEpoch;
    _refresh();
    if (epoch != context.owner.inputGeometryEpoch ||
        context.owner.hasDirtyElements ||
        context.owner.structureChanged) {
      if (gesture == _gesture) _unresolved();
      return false;
    }
    return (gesture == _gesture || _model.value.phase == SelectionPhase.none) &&
        (_scene?.resolved ?? false);
  }

  void _geometryChanged(bool settled) {
    if (!mounted || _detached) return;
    if (settled) {
      _refresh();
    } else {
      _unresolved();
    }
  }

  void _clearHighlights() {
    for (final surface in _scene?.geometry.surfaces ?? <SelectionSurface>[]) {
      final owner = surface.owner;
      if (owner is RenderBox) owner.selectionGlyphStyle = null;
      if (owner is RenderSelectionEditor) {
        for (final (paragraph, _) in owner.paragraphRows) {
          paragraph.selectionGlyphStyle = null;
        }
      }
    }
  }

  void _unresolved() {
    _clearHighlights();
    _forgetScene();
    if (_model.value.phase == SelectionPhase.changing) clearSelection();
  }

  void _refresh() {
    if (_refreshing || _detached || !mounted) return;
    final box = _box, root = context.owner.inputRenderRoot?.call();
    if (box == null || root == null) {
      _unresolved();
      return;
    }
    final stamp = _sceneStamp, cached = _scene;
    final epoch = context.owner.inputGeometryEpoch;
    if (cached != null &&
        stamp != null &&
        stamp.epoch == epoch &&
        identical(stamp.root, root) &&
        identical(stamp.boundary, box) &&
        identical(stamp.controller, widget.controller) &&
        cached.scrollEpochs.entries.every(
          (entry) => entry.key.controller.explicitScrollEpoch == entry.value,
        )) {
      return;
    }
    _refreshing = true;
    try {
      _clearHighlights();
      final previousScene = _scene;
      final scene = SelectionScene.collect(root, box);
      _scene = scene;
      if (!scene.resolved) {
        _unresolved();
        return;
      }
      if (_model.value.phase != SelectionPhase.none) {
        final changing = _model.value.phase == SelectionPhase.changing;
        final allowed = <Object>{
          for (final lease in _model.leases) lease.fragment.id,
          if (_model.value.anchor != null) _model.value.anchor!.sourceId,
          if (_model.value.extent != null) _model.value.extent!.sourceId,
        };
        final current = <SelectionFragmentProjection>[];
        final fragmentSlots = <Object, int>{};
        for (var i = 0; i < scene.slots.length; i++) {
          if (!_retainedSlots.contains(scene.slots[i].id)) continue;
          for (final fragment in scene.interval(i, i)) {
            current.add(fragment);
            fragmentSlots[fragment.id] = i;
          }
        }
        _model.reconcile(current);
        if (changing && _model.value.phase == SelectionPhase.none) {
          clearSelection();
        } else if (_model.value.phase == SelectionPhase.changing) {
          _anchorSlot =
              scene.slots[fragmentSlots[_model.value.anchor!.sourceId]!].id;
          _focus = _model.value.extent;
          final explicitlyScrolled =
              previousScene != null &&
              scene.scrollEpochs.entries.any(
                (entry) =>
                    previousScene.scrollEpochs.containsKey(entry.key) &&
                    previousScene.scrollEpochs[entry.key] != entry.value,
              );
          if (_lastMotion != null) {
            _projectMotion(
              _lastMotion!,
              scene,
              allowed: explicitlyScrolled ? null : allowed,
            );
          }
        }
      }
      _highlight(scene);
      // Publish the cache before callbacks. A reentrant clear/new owner may
      // invalidate it; the old refresh never reinstates it afterwards.
      if (identical(_scene, scene)) {
        _sceneStamp = (
          epoch: epoch,
          root: root,
          boundary: box,
          controller: widget.controller,
        );
      }
    } finally {
      _refreshing = false;
      if (_releaseAfterProjection) {
        _releaseAfterProjection = false;
        _capture.release();
      }
      _notify();
    }
  }

  void _highlight(SelectionScene scene) {
    final selected = {
      for (final lease in _model.leases) lease.fragment.id: lease,
    };
    for (final surface in scene.geometry.surfaces) {
      // Surface owners are current render boxes; no logical range retains them.
      final owner = surface.owner;
      if (owner is! RenderBox) continue;
      Style highlight(int x, int y, int width, Style base) {
        if (y < 0 || y >= surface.layout.rows.length) return base;
        final glyph = surface.layout.rows[y].glyphs
            .where(
              (cell) =>
                  cell.x == x &&
                  cell.glyph.width == width &&
                  cell.sourceId != null,
            )
            .lastOrNull;
        final lease = selected[glyph?.sourceId];
        if (glyph?.offset == null ||
            lease == null ||
            glyph!.offset! < lease.start ||
            glyph.offset! >= lease.end ||
            !scene.geometry.exposed(
              surface,
              surface.origin.x + x,
              surface.origin.y + y,
              width,
            )) {
          return base;
        }
        return base.merge(widget.selectionStyle);
      }

      if (owner is RenderSelectionEditor) {
        for (final (paragraph, row) in owner.paragraphRows) {
          paragraph.selectionGlyphStyle = (x, y, width, base) =>
              highlight(x, row, width, base);
        }
      } else {
        owner.selectionGlyphStyle = highlight;
      }
    }
  }

  void _notify() {
    final value = _model.value;
    if (_refreshing ||
        _published == value.generation ||
        _detached ||
        !mounted) {
      return;
    }
    _published = value.generation;
    context.owner.requestPaint();
    widget.controller.notifyListeners();
    if (mounted && !_detached && identical(_model.value, value)) {
      widget.onSelectionChanged?.call(value);
    }
  }

  void _down(MouseEvent event) {
    if (_detached ||
        event.button != MouseButton.primary ||
        event.shift ||
        event.alt ||
        event.ctrl ||
        !_sync()) {
      return;
    }
    final scene = _scene!;
    final hit = scene.geometry.hit(event.position);
    if (hit == null) return;
    final slot = scene.surfaceSlots[hit.surface]!;
    final fragment = scene.slots[slot].layout.fragments
        .where((f) => f.id == hit.position.sourceId)
        .firstOrNull;
    if (fragment == null) return;
    _capture.capture();
    final gesture = ++_gesture;
    _focus = hit.position;
    _lastMotion = null;
    _anchorSlot = scene.slots[slot].id;
    _retainedSlots = {scene.slots[slot].id};
    _model.begin(fragment, hit.position.offset);
    _highlight(scene);
    _notify();
    if (gesture != _gesture) return;
  }

  void _projectMotion(
    Offset point,
    SelectionScene scene, {
    Set<Object>? allowed,
  }) {
    if (_model.value.phase != SelectionPhase.changing) return;
    final hit = scene.geometry.resolve(point, _focus);
    if (hit == null ||
        (allowed != null && !allowed.contains(hit.position.sourceId))) {
      return;
    }
    final slot = scene.surfaceSlots[hit.surface];
    final a = scene.slots.indexWhere((slot) => slot.id == _anchorSlot);
    if (slot == null || a < 0) return;
    _focus = hit.position;
    if (allowed == null) {
      _retainedSlots = {
        for (var i = a < slot ? a : slot; i <= (a > slot ? a : slot); i++)
          scene.slots[i].id,
      };
    }
    final interval = scene.interval(a, slot);
    _model.extend(
      allowed == null
          ? interval
          : interval
                .where((fragment) => allowed.contains(fragment.id))
                .toList(),
      hit.position,
    );
  }

  void _move(MouseEvent event) {
    if (_model.value.phase != SelectionPhase.changing) return;
    if (!_sync()) return;
    _lastMotion = event.position;
    _projectMotion(event.position, _scene!);
    _highlight(_scene!);
    _notify();
  }

  void _up(MouseEvent event) {
    if (_model.value.phase != SelectionPhase.changing) return;
    final gesture = _gesture;
    if (!_sync() ||
        gesture != _gesture ||
        _model.value.phase != SelectionPhase.changing) {
      return;
    }
    _model.finalize();
    _focus = null;
    _lastMotion = null;
    _highlight(_scene!);
    final value = _model.value;
    final finalized = widget.onSelectionFinalized;
    _notify();
    // The immutable completion belongs to this matching release. A live
    // receiver still gets it if notification starts another gesture first.
    if (mounted && !_detached) finalized?.call(value);
  }

  void _cancel() {
    _clearHighlights();
    // Cancellation must release crossed projections before a new drag can start.
    _forgetScene();
    _gesture++;
    _focus = null;
    _lastMotion = null;
    if (_model.value.phase == SelectionPhase.changing) {
      _model.clear();
      _anchorSlot = null;
      _retainedSlots = {};
      _notify();
    }
    context.owner.requestPaint();
  }

  @override
  SelectionValue? selectionSnapshot() => _sync() ? _model.value : null;

  @override
  void clearSelection() {
    if (_detached || !mounted) return;
    if (context.owner.doingLayoutOrPaint) {
      throw StateError('Cannot clear selection during layout or paint.');
    }
    _clearHighlights();
    // A crossed scene owns lazy projections beyond the visible baseline.
    _forgetScene();
    _gesture++;
    _focus = null;
    _lastMotion = null;
    _model.clear();
    _anchorSlot = null;
    _retainedSlots = {};
    context.owner.requestPaint();
    // Old logical cleanup is complete before release callbacks or a none
    // observer can start another drag. Never resume cleanup after either.
    if (_refreshing) {
      _releaseAfterProjection = true;
    } else {
      _capture.release();
    }
    _notify();
  }

  @override
  List<CodeBlockGeometry> selectionCodeBlocks() =>
      _sync() ? _scene!.codeBlocks : const [];

  @override
  bool revealSelectionCodeBlock(CodeBlockId id) {
    final firstPass = context.owner.inputLayoutPasses;
    if (!_sync()) return false;
    final scene = _scene!;
    final direct = scene.slots.where((slot) => slot.id == id.sourceId).toList();
    for (final slot in direct.isNotEmpty ? direct : scene.slots) {
      final bounds = slot.layout.codeBounds[selectionCodeFragment(id)];
      if (bounds == null) continue;
      final viewport = slot.viewport;
      if (viewport == null) {
        return scene.codeBlocks.any((geometry) => geometry.block.id == id);
      }
      final top = viewport.itemTop(slot.itemIndex!) + bounds.top;
      final bottom = top + bounds.height;
      final controller = viewport.controller;
      if (top < controller.offset ||
          bottom > controller.offset + viewport.size.height) {
        controller.jumpTo(top);
      }
      final remaining = (2 - (context.owner.inputLayoutPasses - firstPass))
          .clamp(0, 2);
      if (!_sync(maxPasses: remaining)) return false;
      return _scene!.codeBlocks.any((geometry) => geometry.block.id == id);
    }
    return false;
  }

  @override
  void detachSelection() {
    if (_detached) return;
    _detached = true;
    context.owner.inputGeometryObservers.remove(_geometryChanged);
    _clearHighlights();
    _model.clear();
    _focus = null;
    _lastMotion = null;
    _anchorSlot = null;
    _retainedSlots = {};
    _capture.release();
    _forgetScene();
    context.owner.requestPaint();
  }

  @override
  Widget build(BuildContext context) => Listener(
    captureController: _capture,
    behavior: HitTestBehavior.translucent,
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: (_) => _cancel(),
    child: _AreaBox(bind: (box) => _box = box, child: widget.child),
  );
}
