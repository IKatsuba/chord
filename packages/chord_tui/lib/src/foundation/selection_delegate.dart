import 'selection_source.dart';

/// Immutable logical identities and lazy immutable sources for a virtual list.
class SelectionChildDelegate {
  /// Validates identity/lookup agreement without asking for offscreen sources.
  SelectionChildDelegate({
    required this.itemCount,
    required Object Function(int) idAt,
    required int? Function(Object) indexOfId,
    required SelectionSource Function(int) sourceAt,
    String Function(int)? separatorBefore,
  }) : _sourceAt = sourceAt,
       _separatorBefore = separatorBefore {
    if (itemCount < 0) throw ArgumentError.value(itemCount, 'itemCount');
    final ids = <Object>[];
    final indices = <Object, int>{};
    for (var i = 0; i < itemCount; i++) {
      final id = idAt(i);
      if (indices.containsKey(id) || indexOfId(id) != i) {
        throw ArgumentError(
          'Selection delegate identities and lookup disagree.',
        );
      }
      ids.add(id);
      indices[id] = i;
    }
    _ids = List.unmodifiable(ids);
    _indices = Map.unmodifiable(indices);
  }

  /// Number of logical sources, matching the viewport item count.
  final int itemCount;
  late final List<Object> _ids;
  late final Map<Object, int> _indices;
  final SelectionSource Function(int) _sourceAt;
  final String Function(int)? _separatorBefore;

  /// Frozen logical identity at [index].
  Object idAt(int index) => _ids[index];

  /// Current logical index of an identity, or null when absent.
  int? indexOfId(Object id) => _indices[id];

  /// Resolves only the requested source and validates its logical identity.
  SelectionSource sourceAt(int index) {
    final source = _sourceAt(index);
    if (source.id != idAt(index)) {
      throw StateError(
        'Selection delegate source identity does not match its item.',
      );
    }
    return source;
  }

  /// Explicit logical separator, independent of terminal layout gaps.
  String separatorBefore(int index) =>
      index == 0 ? '' : _separatorBefore?.call(index) ?? '\n';
}
