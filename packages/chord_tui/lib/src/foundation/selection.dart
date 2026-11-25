import 'package:meta/meta.dart';

import '../text/selection_layout.dart';
import 'geometry.dart';
import 'selection_diagnostics.dart';
import 'selection_source.dart';

/// The lifecycle of a framework-owned text range.
enum SelectionPhase {
  /// No gesture or retained range exists.
  none,

  /// A primary drag is changing its source-local endpoints.
  changing,

  /// A matching release finalized the current range.
  finalized,
}

/// A grapheme insertion boundary in an opaque semantic fragment.
@immutable
class SelectionPosition {
  /// Addresses a fragment independently of its mounted rows.
  const SelectionPosition(this.sourceId, this.offset);

  /// Framework-issued semantic fragment identity.
  final Object sourceId;

  /// Grapheme offset, including genuine source line breaks.
  final int offset;
  @override
  bool operator ==(Object other) =>
      other is SelectionPosition &&
      sourceId == other.sourceId &&
      offset == other.offset;
  @override
  int get hashCode => Object.hash(sourceId, offset);
}

/// An immutable notification or synchronized snapshot of a selected range.
@immutable
class SelectionValue {
  /// Carries current source-local endpoints and already-projected text.
  const SelectionValue({
    required this.phase,
    this.anchor,
    this.extent,
    this.text = '',
    this.generation = 0,
  });

  /// Whether this range is absent, changing or finalized.
  final SelectionPhase phase;

  /// The original directional endpoint, independent of wrap geometry.
  final SelectionPosition? anchor;

  /// The last-motion directional endpoint.
  final SelectionPosition? extent;

  /// Copy text projected through allowed current source intervals.
  final String text;

  /// Monotonic logical-change generation, including clear and a new gesture.
  final int generation;

  /// Whether this snapshot contains text, including source spaces or newlines.
  bool get hasText => text.isNotEmpty;
}

/// A current code container and its exposed cells in terminal coordinates.
@immutable
class CodeBlockGeometry {
  /// Defensively freezes nonoverlapping exposed rectangles.
  CodeBlockGeometry({
    required this.block,
    required this.bounds,
    required List<Rect> visibleRects,
  }) : visibleRects = List.unmodifiable(visibleRects);

  /// Current immutable code text and parser metadata.
  final MarkdownCodeBlock block;

  /// Full container bounds, including an enclosing quote where applicable.
  final Rect bounds;

  /// Actual exposed paint cells, excluding clips and overlay holes.
  final List<Rect> visibleRects;
}

/// One currently selected source-local interval; no widget or old source lease.
@internal
@immutable
class SelectionRangeLease {
  /// Retains only this current fragment projection and its selected bounds.
  const SelectionRangeLease(this.fragment, this.start, this.end);

  /// The current immutable fragment map.
  final SelectionFragmentProjection fragment;

  /// Inclusive lower endpoint converted to a half-open interval.
  final int start;

  /// Exclusive upper endpoint, including the greater endpoint's whole glyph.
  final int end;
}

/// Plain range/reconciliation logic shared by the area and terminal-free tests.
@internal
class SelectionRangeModel {
  /// A model with nothing selected.
  SelectionRangeModel();

  SelectionValue _value = const SelectionValue(phase: SelectionPhase.none);
  List<SelectionRangeLease> _leases = const [];
  List<Object> _anchorLineage = const [], _extentLineage = const [];

  /// Latest immutable logical value, without geometry synchronization.
  SelectionValue get value => _value;

  /// Current selected projections only; clearing drops every lease.
  List<SelectionRangeLease> get leases => _leases;

  /// Starts a new empty gesture at a real exposed glyph or blank-line boundary.
  void begin(SelectionFragmentProjection fragment, int offset) {
    final at = SelectionPosition(fragment.id, offset.clamp(0, fragment.length));
    _leases = const [];
    _anchorLineage = fragment.lineage;
    _extentLineage = fragment.lineage;
    _value = SelectionValue(
      phase: SelectionPhase.changing,
      anchor: at,
      extent: at,
      generation: _value.generation + 1,
    );
  }

  /// Resolves one ordered interval immediately, including never-mounted sources.
  void extend(
    List<SelectionFragmentProjection> ordered,
    SelectionPosition extent,
  ) {
    final anchor = _value.anchor;
    if (_value.phase != SelectionPhase.changing || anchor == null) return;
    final a = ordered.indexWhere((fragment) => fragment.id == anchor.sourceId);
    final b = ordered.indexWhere((fragment) => fragment.id == extent.sourceId);
    if (a < 0 || b < 0) return;
    _extentLineage = ordered[b].lineage;
    final clampedAnchor = SelectionPosition(
      anchor.sourceId,
      anchor.offset.clamp(0, ordered[a].length),
    );
    final clampedExtent = SelectionPosition(
      extent.sourceId,
      extent.offset.clamp(0, ordered[b].length),
    );
    if (clampedAnchor == clampedExtent) {
      _publish(const [], clampedAnchor, clampedExtent, SelectionPhase.changing);
      return;
    }
    final forward =
        a < b || (a == b && clampedAnchor.offset < clampedExtent.offset);
    final first = forward ? a : b, last = forward ? b : a;
    final low = forward ? clampedAnchor.offset : clampedExtent.offset;
    final high = forward ? clampedExtent.offset : clampedAnchor.offset;
    final leases = <SelectionRangeLease>[];
    for (var i = first; i <= last; i++) {
      final fragment = ordered[i];
      final start = i == first ? low : 0;
      final end = i == last
          ? (high + 1).clamp(0, fragment.length)
          : fragment.length;
      if (start < end) leases.add(SelectionRangeLease(fragment, start, end));
    }
    _publish(leases, clampedAnchor, clampedExtent, SelectionPhase.changing);
  }

  /// Replaces leases with current compatible fragments, never selecting inserts.
  void reconcile(List<SelectionFragmentProjection> current) {
    if (_value.phase == SelectionPhase.none) return;
    final previous = {for (final lease in _leases) lease.fragment.id: lease};
    final updated = <SelectionRangeLease>[];
    for (final fragment in current) {
      final old = previous[fragment.id];
      if (old == null ||
          !_sameLineage(old.fragment.lineage, fragment.lineage)) {
        continue;
      }
      final start = old.start.clamp(0, fragment.length),
          end = old.end.clamp(0, fragment.length);
      if (start < end && fragment.extract(start, end).isNotEmpty) {
        updated.add(SelectionRangeLease(fragment, start, end));
      }
    }
    if (previous.isNotEmpty && updated.isEmpty) {
      clear();
      return;
    }
    SelectionPosition? clamp(
      SelectionPosition? position,
      List<Object> lineage,
    ) {
      if (position == null) return null;
      for (final fragment in current) {
        if (fragment.id == position.sourceId &&
            _sameLineage(fragment.lineage, lineage)) {
          return SelectionPosition(
            position.sourceId,
            position.offset.clamp(0, fragment.length),
          );
        }
      }
      return null;
    }

    var anchor = clamp(_value.anchor, _anchorLineage),
        extent = clamp(_value.extent, _extentLineage);
    if (updated.isEmpty && (anchor == null || extent == null)) {
      clear();
      return;
    }
    if (updated.isNotEmpty && (anchor == null || extent == null)) {
      final forward =
          _value.anchor == null ||
          _leases.isEmpty ||
          _value.anchor!.sourceId == _leases.first.fragment.id;
      final first = updated.first, last = updated.last;
      anchor ??= forward
          ? SelectionPosition(first.fragment.id, first.start)
          : SelectionPosition(last.fragment.id, last.end - 1);
      extent ??= forward
          ? SelectionPosition(last.fragment.id, last.end - 1)
          : SelectionPosition(first.fragment.id, first.start);
    }
    _publish(updated, anchor, extent, _value.phase);
  }

  /// Finalizes once; a release never independently changes the last motion.
  void finalize() {
    if (_value.phase != SelectionPhase.changing) return;
    _publish(_leases, _value.anchor, _value.extent, SelectionPhase.finalized);
  }

  /// Drops endpoints and all current source leases immediately.
  void clear() {
    if (_value.phase == SelectionPhase.none && _leases.isEmpty) return;
    _leases = const [];
    _anchorLineage = const [];
    _extentLineage = const [];
    _value = SelectionValue(
      phase: SelectionPhase.none,
      generation: _value.generation + 1,
    );
  }

  void _publish(
    List<SelectionRangeLease> leases,
    SelectionPosition? anchor,
    SelectionPosition? extent,
    SelectionPhase phase,
  ) {
    recordSelectionRangeComposition();
    final out = StringBuffer();
    var first = true;
    for (final lease in leases) {
      final text = lease.fragment.extract(lease.start, lease.end);
      if (text.isEmpty) continue;
      if (!first) out.write(lease.fragment.separatorBefore);
      out.write(text);
      first = false;
    }
    final text = out.toString();
    _leases = List.unmodifiable(leases);
    for (final lease in leases) {
      if (lease.fragment.id == anchor?.sourceId) {
        _anchorLineage = lease.fragment.lineage;
      }
      if (lease.fragment.id == extent?.sourceId) {
        _extentLineage = lease.fragment.lineage;
      }
    }
    if (_value.phase == phase &&
        _value.anchor == anchor &&
        _value.extent == extent &&
        _value.text == text) {
      return;
    }
    _value = SelectionValue(
      phase: phase,
      anchor: anchor,
      extent: extent,
      text: text,
      generation: _value.generation + 1,
    );
  }
}

bool _sameLineage(List<Object> a, List<Object> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
