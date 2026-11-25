import 'package:meta/meta.dart';

import '../input/keys.dart';
import 'focus_manager.dart';
import 'framework.dart';

/// Moves the keys of identified bindings for every [Actions] under it.
///
/// An inner keymap replaces an outer one whole.
class Keymap extends InheritedWidget {
  /// Applies [data] to the bindings under [child].
  const Keymap({super.key, required this.data, required super.child});

  /// The keys by binding id.
  final KeymapData data;

  /// The nearest keymap's data; an empty one when there is none.
  static KeymapData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Keymap>()?.data ??
      const KeymapData();

  @override
  bool updateShouldNotify(Keymap oldWidget) => data != oldWidget.data;
}

/// Keys by binding id: what a keymap makes of the bindings it covers.
///
/// An id it names gets exactly those keys, an empty list none; an id absent
/// keeps the keys it was bound with.
@immutable
class KeymapData {
  /// The final keys of each id this keymap changes.
  const KeymapData([this._keys = const {}]);

  final Map<String, List<Chord>> _keys;

  /// The keys of [id], or null when the keymap leaves it as bound.
  /// An empty list unbinds it.
  List<Chord>? keysFor(String id) => _keys[id];

  /// [bindings] with this keymap applied, and the keys it could not bind.
  ///
  /// The keys of an id take the place of its first binding, made from it
  /// in the keymap's order. A key that clashes with another binding (the
  /// same chord, or one chord the start of the other) is left out and
  /// reported; the other keeps it, and of two keys this keymap gave, the
  /// later one gives way. Bindings the app wrote are not checked here.
  ({List<Binding> bindings, List<KeymapConflict> conflicts}) apply(
    List<Binding> bindings,
  ) {
    if (_keys.isEmpty) return (bindings: bindings, conflicts: const []);
    final out = <Binding>[];
    final made = <Binding>{};
    final placed = <String>{};
    for (final binding in bindings) {
      final id = binding.id;
      final keys = id == null ? null : _keys[id];
      if (keys == null) {
        out.add(binding);
      } else if (placed.add(id!)) {
        for (final chord in keys) {
          final moved = binding.copyWith(chord: chord);
          made.add(moved);
          out.add(moved);
        }
      }
    }
    if (made.isEmpty) return (bindings: out, conflicts: const []);
    final conflicts = <KeymapConflict>[];
    final dropped = <Binding>{};
    // App-written bindings hold their keys first, then the keymap's in order.
    final holders = [
      for (final b in out)
        if (!made.contains(b)) b,
    ];
    for (final b in out) {
      if (!made.contains(b)) continue;
      final other = holders
          .where((h) => _clashes(h.chord, b.chord))
          .firstOrNull;
      if (other == null) {
        holders.add(b);
        continue;
      }
      dropped.add(b);
      conflicts.add(
        KeymapConflict(
          id: b.id!,
          chord: b.chord,
          other: other,
          prefix: other.chord != b.chord,
        ),
      );
    }
    return (
      bindings: [
        for (final b in out)
          if (!dropped.contains(b)) b,
      ],
      conflicts: conflicts,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! KeymapData || other._keys.length != _keys.length) {
      return false;
    }
    for (final MapEntry(:key, :value) in _keys.entries) {
      final theirs = other._keys[key];
      if (theirs == null || theirs.length != value.length) return false;
      for (var i = 0; i < value.length; i++) {
        if (theirs[i] != value[i]) return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered([
    for (final MapEntry(:key, :value) in _keys.entries)
      Object.hash(key, Object.hashAll(value)),
  ]);
}

bool _clashes(Chord a, Chord b) =>
    a == b || a.startsWith(b.combos) || b.startsWith(a.combos);

/// A key the keymap gave [id] that clashes with another binding of the
/// same scope, and was left out.
@immutable
class KeymapConflict {
  /// What was not bound, and what holds the key.
  const KeymapConflict({
    required this.id,
    required this.chord,
    required this.other,
    required this.prefix,
  });

  /// The id the keymap gave the key to.
  final String id;

  /// The key that was left out.
  final Chord chord;

  /// The binding that keeps the key.
  final Binding other;

  /// Whether one chord is the start of the other, not the same chord.
  final bool prefix;

  @override
  String toString() =>
      '$chord for $id: ${prefix ? 'overlaps' : 'held by'} $other';
}
