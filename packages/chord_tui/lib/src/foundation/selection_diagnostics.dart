import 'package:meta/meta.dart';

/// Numeric observations only; reading never resolves sources or geometry.
@internal
@immutable
class SelectionDiagnostics {
  /// Captures current counts without retaining any selected content.
  const SelectionDiagnostics({
    this.logicalSlots = 0,
    this.visibleRoots = 0,
    this.resolvedRoots = 0,
    this.offscreenResolvedRoots = 0,
    this.cachedFragments = 0,
    this.selectedRoots = 0,
    this.selectedRanges = 0,
  });

  /// Current document identity slots, including unresolved lazy items.
  final int logicalSlots;

  /// Mounted semantic roots contributing visible geometry.
  final int visibleRoots;

  /// Slots whose semantic layouts have already been resolved.
  final int resolvedRoots;

  /// Resolved slots without a currently mounted surface.
  final int offscreenResolvedRoots;

  /// Fragments held by already resolved scene layouts.
  final int cachedFragments;

  /// Logical roots retained by the current selection.
  final int selectedRoots;

  /// Current source-local range leases.
  final int selectedRanges;
}

int _sceneCollections = 0, _rangeCompositions = 0;

/// Actual scene collection and range serialization calls in this isolate.
@internal
({int sceneCollections, int rangeCompositions}) get selectionWorkDiagnostics =>
    (
      sceneCollections: _sceneCollections,
      rangeCompositions: _rangeCompositions,
    );

/// Resets only numeric work counters, preserving all live selection state.
@internal
void resetSelectionWorkDiagnostics() {
  _sceneCollections = 0;
  _rangeCompositions = 0;
}

/// Records entry into the real scene collector, without retaining its objects.
@internal
void recordSelectionSceneCollection() => _sceneCollections++;

/// Records entry into real range serialization, including unchanged results.
@internal
void recordSelectionRangeComposition() => _rangeCompositions++;
