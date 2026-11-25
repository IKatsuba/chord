import 'package:meta/meta.dart';

import '../foundation/geometry.dart';
import '../foundation/selection.dart';
import '../foundation/selection_diagnostics.dart';
import '../foundation/selection_geometry.dart';
import '../foundation/selection_source.dart';
import '../foundation/text_editing.dart';
import '../text/selection_layout.dart';
import 'basic.dart';
import 'box.dart';
import 'list_viewport.dart';
import 'selection_content.dart';

/// A semantic boundary whose children retain their existing paint traversal.
@internal
class RenderSelectionBoundary extends RenderProxyBox {
  /// Areas form separate boundaries; disabled containers omit all descendants.
  RenderSelectionBoundary({this.disabled = false});

  /// Whether all descendant sources are excluded.
  final bool disabled;

  @override
  PaintCoverage describePaintCoverage(Rect localClip) =>
      const PaintCoverage.empty(RenderSelectionBoundary);
}

/// Registers an editor's existing controller and layout as one logical source.
@internal
class RenderSelectionEditor extends RenderProxyBox {
  /// Uses the editor's live layout, without changing its caret or text.
  RenderSelectionEditor(this.controller, this.editorLayout);

  /// Existing editable text and logical identity.
  TextAreaController controller;

  /// Exact layout already used to draw this editor.
  TextAreaLayout editorLayout;

  /// Current drawn paragraphs and their existing controller row indices.
  Iterable<(RenderParagraph, int)> get paragraphRows {
    final result = <(RenderParagraph, int)>[];
    var row = editorLayout.rowOffset;
    void visit(RenderBox box) {
      if (box is RenderParagraph) {
        result.add((box, row++));
      } else {
        box.visitChildren(visit);
      }
    }

    visitChildren(visit);
    return result;
  }

  @override
  PaintCoverage describePaintCoverage(Rect localClip) =>
      const PaintCoverage.empty(RenderSelectionEditor);
}

/// One logical source slot, potentially never mounted by a virtual provider.
@internal
class SelectionDocumentSlot {
  /// Resolves source/shaping lazily, at the provider's actual width.
  SelectionDocumentSlot({
    required this.id,
    required this.resolve,
    required this.separator,
    this.viewport,
    this.itemIndex,
  });

  /// Stable root identity used to survive virtual absence.
  final Object id;

  /// Resolves only this slot's current semantic map.
  final SelectionLayout Function() resolve;

  /// Current separator at this logical boundary.
  final String separator;

  /// Provider to reveal through, when this is a virtual item.
  final RenderListViewport? viewport;

  /// Logical index within that provider.
  final int? itemIndex;

  SelectionLayout? _layout;

  /// Current pure source projection, cached only within this scene.
  SelectionLayout get layout => _layout ??= resolve();
}

/// A current settled scene: logical slots, exposed endpoints and code geometry.
@internal
class SelectionScene {
  SelectionScene._(
    this.geometry,
    this.slots,
    this.surfaceSlots,
    this.codeBlocks,
    this.resolved,
    this.scrollEpochs,
  );

  /// Current endpoint geometry derived from pure coverage.
  final SelectionGeometry geometry;

  /// Document order, including lazy source slots.
  final List<SelectionDocumentSlot> slots;

  /// Logical slot index of each mounted source surface.
  final Map<SelectionSurface, int> surfaceSlots;

  /// Current exposed code containers in paint order.
  final List<CodeBlockGeometry> codeBlocks;

  /// False if any unknown paint coverage intersects the effective area clip.
  final bool resolved;

  /// Explicit scroll intent at each current area viewport, not layout motion.
  final Map<RenderListViewport, int> scrollEpochs;

  /// Collects current paint traversal and logical sources without paint/layout.
  static SelectionScene collect(RenderBox root, RenderBox area) {
    recordSelectionSceneCollection();
    return _Collector(root, area).collect();
  }

  /// Reads only existing cache fields; never calls a lazy source resolver.
  SelectionDiagnostics get diagnostics {
    final mounted = <int, SelectionLayout>{
      for (final entry in surfaceSlots.entries) entry.value: entry.key.layout,
    };
    var resolved = 0, offscreen = 0, fragments = 0;
    for (final (index, slot) in slots.indexed) {
      final cached = slot._layout ?? mounted[index];
      if (cached == null) continue;
      resolved++;
      if (!mounted.containsKey(index)) offscreen++;
      fragments += cached.fragments.length;
    }
    return SelectionDiagnostics(
      logicalSlots: slots.length,
      visibleRoots: mounted.length,
      resolvedRoots: resolved,
      offscreenResolvedRoots: offscreen,
      cachedFragments: fragments,
    );
  }

  /// Resolves only the logical slots crossed by the current endpoints.
  List<SelectionFragmentProjection> interval(int a, int b) {
    final low = a < b ? a : b, high = a > b ? a : b;
    return [
      for (var i = low; i <= high; i++)
        for (final (j, fragment) in slots[i].layout.fragments.indexed)
          j == 0 ? fragment.separated(slots[i].separator) : fragment,
    ];
  }
}

class _Placement {
  _Placement(this.origin, this.clip, this.order);
  final Offset origin;
  final Rect clip;
  final int order;
}

class _Collector {
  _Collector(this.root, this.area);
  final RenderBox root;
  final RenderBox area;
  final placements = <RenderBox, _Placement>{};
  final cells = <Offset, SelectionCellOwner>{};
  final unknown = <Rect>[];
  final slots = <SelectionDocumentSlot>[];
  final surfaces = <SelectionSurface>[];
  final surfaceSlots = <SelectionSurface, int>{};
  final codeBlocks = <CodeBlockGeometry>[];
  final slotIds = <Object>{};
  final scrollEpochs = <RenderListViewport, int>{};
  final providerOrigins = <int, Offset>{};
  final providerSources = <int, SelectionSource>{};
  final paintOwners = <RenderBox, Object>{};
  var order = 0;
  int? lastRow;

  SelectionScene collect() {
    final rootClip = Rect.fromOffsetSize(Offset.zero, root.size);
    _paint(root, Offset.zero, rootClip);
    final at = placements[area];
    final areaClip = at == null
        ? Rect.zero
        : at.clip.intersect(Rect.fromOffsetSize(at.origin, area.size));
    final resolved =
        at != null &&
        !areaClip.isEmpty &&
        !unknown.any((r) => !r.intersect(areaClip).isEmpty);
    if (at != null) {
      _logical(
        area is RenderSelectionBoundary
            ? (area as RenderSelectionBoundary).child
            : area,
        null,
      );
    }
    surfaces.sort((a, b) => a.order.compareTo(b.order));
    final geometry = SelectionGeometry(surfaces, cells);
    if (resolved) {
      for (final surface in surfaces) {
        final source = switch (surface.owner) {
          RenderSelectionContent(:final source) => source,
          _ => null,
        };
        if (source == null) continue;
        for (final block in source.codeBlocks) {
          final rect =
              surface.layout.codeBounds[selectionCodeFragment(block.id)];
          if (rect == null) continue;
          final bounds = Rect(
            rect.left + surface.origin.x,
            rect.top + surface.origin.y,
            rect.width,
            rect.height,
          );
          final clip = bounds.intersect(surface.clip).intersect(areaClip);
          final visible = <Rect>[];
          for (var y = clip.top; y < clip.bottom; y++) {
            int? start;
            for (var x = clip.left; x <= clip.right; x++) {
              final painted =
                  x < clip.right && cells[Offset(x, y)]?.owner == surface.owner;
              if (painted) {
                start ??= x;
              } else if (start != null) {
                visible.add(Rect(start, y, x - start, 1));
                start = null;
              }
            }
          }
          if (visible.isNotEmpty) {
            codeBlocks.add(
              CodeBlockGeometry(
                block: block,
                bounds: bounds,
                visibleRects: visible,
              ),
            );
          }
        }
      }
    }
    codeBlocks.sort((a, b) {
      final ai = surfaces.indexWhere(
        (s) =>
            s.layout.codeBounds.containsKey(selectionCodeFragment(a.block.id)),
      );
      final bi = surfaces.indexWhere(
        (s) =>
            s.layout.codeBounds.containsKey(selectionCodeFragment(b.block.id)),
      );
      return surfaces[ai].order.compareTo(surfaces[bi].order);
    });
    return SelectionScene._(
      geometry,
      List.unmodifiable(slots),
      surfaceSlots,
      List.unmodifiable(codeBlocks),
      resolved,
      Map.unmodifiable(scrollEpochs),
    );
  }

  void _write(RenderBox box, Iterable<Rect> rects, Offset origin, Rect clip) {
    final phase = order++;
    for (final rect in rects) {
      final r = Rect(
        origin.x + rect.left,
        origin.y + rect.top,
        rect.width,
        rect.height,
      ).intersect(clip);
      for (var y = r.top; y < r.bottom; y++) {
        for (var x = r.left; x < r.right; x++) {
          cells[Offset(x, y)] = SelectionCellOwner(
            paintOwners[box] ?? box,
            phase,
          );
        }
      }
    }
  }

  void _paint(
    RenderBox box,
    Offset origin,
    Rect clip, [
    RenderSelectionEditor? editor,
  ]) {
    if (box.layoutPass != root.layoutPass || clip.isEmpty) return;
    if (box is RenderSelectionEditor) editor = box;
    if (editor != null && box is RenderParagraph) paintOwners[box] = editor;
    final localClip = Rect(
      clip.left - origin.x,
      clip.top - origin.y,
      clip.width,
      clip.height,
    );
    placements[box] = _Placement(origin, clip, order);
    final coverage = box.describePaintCoverage(localClip);
    if (coverage == null || coverage.declaredFor != box.runtimeType) {
      final bounds = Rect.fromOffsetSize(origin, box.size).intersect(clip);
      if (!bounds.isEmpty) unknown.add(bounds);
    } else {
      _write(box, coverage.beforeChildren, origin, clip);
    }
    box.visitPaintChildren(origin, clip, (child, at, effectiveClip) {
      _paint(child, at, effectiveClip, editor);
    });
    if (coverage != null && coverage.declaredFor == box.runtimeType) {
      _write(box, coverage.afterChildren, origin, clip);
    }
  }

  int _slot(
    Object id,
    SelectionLayout Function() resolve,
    String separator, {
    RenderListViewport? viewport,
    int? index,
  }) {
    if (!slotIds.add(id)) {
      throw StateError('Selection source IDs must be unique within an area.');
    }
    slots.add(
      SelectionDocumentSlot(
        id: id,
        resolve: resolve,
        separator: slots.isEmpty ? '' : separator,
        viewport: viewport,
        itemIndex: index,
      ),
    );
    return slots.length - 1;
  }

  String _automatic(_Placement at, int height) {
    final separator = lastRow == at.origin.y ? '' : '\n';
    lastRow = at.origin.y + height - 1;
    return separator;
  }

  void _surface(RenderBox box, SelectionLayout layout, int slot) {
    final at = placements[box];
    if (at == null) return;
    final surface = SelectionSurface(
      owner: box,
      layout: layout,
      origin: at.origin,
      bounds: Rect.fromOffsetSize(at.origin, box.size),
      clip: at.clip.intersect(Rect.fromOffsetSize(at.origin, box.size)),
      order: at.order,
    );
    surfaces.add(surface);
    surfaceSlots[surface] = slot;
  }

  void _logical(RenderBox? box, int? providerSlot) {
    if (box == null || box.layoutPass != root.layoutPass) return;
    if (box is RenderSelectionBoundary && box != area) return;
    final at = placements[box];
    if (box is RenderListViewport) {
      scrollEpochs[box] = box.controller.explicitScrollEpoch;
    }
    if (box is RenderListViewport && box.selectionDelegate != null) {
      final delegate = box.selectionDelegate!;
      final first = slots.length;
      final separator = at == null ? '\n' : _automatic(at, box.size.height);
      for (var i = 0; i < delegate.itemCount; i++) {
        _slot(
          delegate.idAt(i),
          () {
            final source = delegate.sourceAt(i);
            providerSources[first + i] = source;
            return shapeSelectionSource(source, width: box.size.width);
          },
          i == 0 ? separator : delegate.separatorBefore(i),
          viewport: box,
          index: i,
        );
      }
      for (final (i, child) in box.placedItems) {
        final origin = placements[child]?.origin;
        if (origin != null) providerOrigins[first + i] = origin;
        _logical(child, first + i);
      }
      return;
    }
    if (box is RenderSelectionEditor && at != null) {
      final layout = shapeTextAreaSelection(
        id: box.controller,
        text: box.controller.text,
        layout: box.editorLayout,
      );
      final slot = _slot(
        box.controller,
        () => layout,
        _automatic(at, box.size.height),
      );
      final origin = at.origin - Offset(0, box.editorLayout.rowOffset);
      final surface = SelectionSurface(
        owner: box,
        layout: layout,
        origin: origin,
        bounds: Rect(origin.x, origin.y, box.editorLayout.width, layout.height),
        clip: at.clip.intersect(Rect.fromOffsetSize(at.origin, box.size)),
        order: at.order,
      );
      surfaces.add(surface);
      surfaceSlots[surface] = slot;
      return;
    }
    final SelectionSource? source;
    final SelectionLayout? layout;
    if (box is RenderParagraph) {
      source = box.effectiveSelectionSource;
      layout = box.selectionLayout;
    } else if (box is RenderSelectionContent) {
      source = box.source;
      layout = box.projection;
    } else {
      source = null;
      layout = null;
    }
    if (source != null && layout != null && at != null) {
      final slot =
          providerSlot ??
          _slot(source.id, () => layout!, _automatic(at, layout.height));
      if (providerSlot != null) {
        final canonical = slots[slot].layout;
        final rootSource = providerSources[slot]!;
        final bound = rootSource.id == source.id
            ? rootSource
            : rootSource.child(source.id);
        if (bound.revision != source.revision) {
          throw StateError(
            'Mounted selection content must use its current source revision.',
          );
        }
        // A bound leaf is also constrained by its authoritative provider path.
        // Its standalone projection must not re-add an excluded descendant.
        bool eligible(SelectionSource current) =>
            current.id == source!.id ||
            selectionSourceSlots(
              current,
            ).any((slot) => slot.selectable && eligible(slot.source));
        if (!eligible(rootSource)) return;
        final fragments = {
          for (final fragment in canonical.fragments) fragment.id: fragment,
        };
        if (layout.fragments.any(
          (fragment) => fragments[fragment.id]?.text != fragment.text,
        )) {
          throw StateError(
            'Mounted selection content must bind its current delegate source.',
          );
        }
        final itemOrigin = providerOrigins[slot]!;
        final relative = at.origin - itemOrigin;
        final expected = {
          for (final (y, row) in canonical.rows.indexed)
            for (final glyph in row.glyphs)
              if (glyph.sourceId != null && glyph.offset != null)
                (
                  glyph.sourceId,
                  glyph.offset,
                  glyph.x,
                  y,
                  glyph.glyph.text,
                  glyph.glyph.width,
                ),
        };
        for (final (y, row) in layout.rows.indexed) {
          for (final glyph in row.glyphs) {
            if (glyph.sourceId != null &&
                glyph.offset != null &&
                !expected.contains((
                  glyph.sourceId,
                  glyph.offset,
                  relative.x + glyph.x,
                  relative.y + y,
                  glyph.glyph.text,
                  glyph.glyph.width,
                ))) {
              throw StateError(
                'Mounted selection geometry must agree with its delegate source.',
              );
            }
          }
        }
      }
      _surface(box, layout, slot);
      return;
    }
    box.visitChildren((child) => _logical(child, providerSlot));
  }
}
