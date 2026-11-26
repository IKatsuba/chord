import 'package:meta/meta.dart';

import '../input/keys.dart';
import '../terminal/style.dart';
import '../text/layout.dart';
import '../text/span.dart';
import 'basic.dart';
import 'focus.dart';
import 'framework.dart';
import 'focus_manager.dart';
import 'theme.dart';

/// The shortcuts that work right now, read from the bindings in scope.
///
/// The keys of one action are one entry, joined by `/`. While a chord is
/// half pressed, shows the keys so far and the chords that continue them.
class KeyHelp extends StatelessWidget {
  /// Help for the bindings in scope, styled by the given styles.
  const KeyHelp({
    super.key,
    this.separator = '  ',
    this.keyStyle,
    this.descriptionStyle,
  }) : _builder = null;

  /// Builds custom help from immutable snapshots of the current key scope.
  const KeyHelp.builder({
    super.key,
    required Widget Function(BuildContext, List<Binding>, List<KeyCombo>)
    builder,
  }) : _builder = builder,
       separator = '  ',
       keyStyle = null,
       descriptionStyle = null;

  final Widget Function(BuildContext, List<Binding>, List<KeyCombo>)? _builder;

  /// What goes between two shortcuts.
  final String separator;

  /// The keys and the pending chord; the theme's text, bold, if null.
  final Style? keyStyle;

  /// The descriptions; the theme's dim if null.
  final Style? descriptionStyle;

  @override
  Widget build(BuildContext context) {
    final fm = context.owner.focusManager;
    final boundary = context
        .dependOnInheritedWidgetOfExactType<_BoundaryScope>()
        ?.node;
    final theme = Theme.of(context);
    final keyStyle = this.keyStyle ?? theme.text.merge(Style.bold);
    final descriptionStyle = this.descriptionStyle ?? theme.dim;
    return ListenableBuilder(
      listenable: fm,
      builder: (context) {
        final listed = listedBindings(fm, boundary);
        // A pending chord is this row's to show only where a listed binding
        // finishes it: one only outer or taken keys finish is not.
        final waiting = fm.pendingChord;
        final pending = listed.any((b) => b.chord.startsWith(waiting))
            ? waiting
            : const <KeyCombo>[];
        final builder = _builder;
        if (builder != null) {
          return builder(
            context,
            List<Binding>.unmodifiable(listed),
            List<KeyCombo>.unmodifiable(pending),
          );
        }
        final spans = <TextSpan>[];
        for (final group in groupBindings(listed)) {
          final chords = [
            for (final chord in group.chords)
              if (pending.isEmpty || chord.startsWith(pending)) chord,
          ];
          if (chords.isEmpty) continue;
          if (spans.isNotEmpty) spans.add(TextSpan(separator));
          spans.add(TextSpan(chords.join('/'), style: keyStyle));
          spans.add(TextSpan(' ${group.description}', style: descriptionStyle));
        }
        if (waiting.isNotEmpty && pending.isEmpty) {
          return const SizedBox();
        }
        if (pending.isNotEmpty) {
          spans.insert(
            0,
            TextSpan('${pending.join(' ')} …  ', style: keyStyle),
          );
        }
        return Text.rich(
          TextSpan('', children: spans),
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

/// The keys of one action, as one entry of key help.
@immutable
class BindingGroup {
  /// Groups [bindings], which share an id, or a description and no id.
  BindingGroup(List<Binding> bindings)
    : assert(bindings.isNotEmpty),
      bindings = List.unmodifiable(bindings);

  /// The bindings, in order; never empty.
  final List<Binding> bindings;

  /// What the action does: the first binding's description.
  String get description => bindings.first.description;

  /// The action's id, if its bindings carry one.
  String? get id => bindings.first.id;

  /// The keys, in order.
  List<Chord> get chords => [for (final b in bindings) b.chord];
}

/// [bindings] grouped by id, else by description, in first-seen order.
List<BindingGroup> groupBindings(List<Binding> bindings) {
  final groups = <Object, List<Binding>>{};
  for (final b in bindings) {
    final key = b.id == null ? (description: b.description) : (id: b.id!);
    (groups[key] ??= []).add(b);
  }
  return [for (final group in groups.values) BindingGroup(group)];
}

/// The keys a host takes before an embedded tree sees them, by the
/// boundary's node.
final _taken = Expando<Set<KeyCombo>>();

/// Marks where an embedded tree's key help begins: help built inside lists
/// only the bindings inside, and no help lists the bindings inside on the
/// keys [taken] by the host.
///
/// It changes what [KeyHelp] and [KeyHelp.builder] list, nothing else: every
/// binding fires as without it. A binding is inside when its node is below
/// the boundary on the focus path. Help inside lists the bindings inside the
/// nearest boundary; help outside lists every binding. A binding whose
/// chord starts with a key one of its enclosing boundaries takes is listed
/// by none; taking the key is the host's own capture handler's work.
class KeyHelpBoundary extends StatefulWidget {
  /// A boundary around [child], whose bindings on [taken] keys go unlisted.
  const KeyHelpBoundary({
    super.key,
    this.taken = const {},
    required this.child,
  });

  /// The keys the host takes first, so no help lists them from inside.
  final Set<KeyCombo> taken;

  /// The embedded tree.
  final Widget child;

  @override
  State<KeyHelpBoundary> createState() => _KeyHelpBoundaryState();
}

class _KeyHelpBoundaryState extends State<KeyHelpBoundary> {
  // A node that never takes focus marks the boundary on the focus path, as
  // an Actions node does, so keys and traversal pass it by.
  final _node = FocusNode(canRequestFocus: false, debugLabel: 'key help');

  @override
  void initState() {
    super.initState();
    _taken[_node] = widget.taken;
  }

  @override
  void didUpdateWidget(KeyHelpBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sameKeys(oldWidget.taken, widget.taken)) return;
    _taken[_node] = widget.taken;
    // Every help row reads taken keys, inside and outside alike, and all of
    // them listen to the manager.
    context.owner.focusManager.notifyListeners();
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      canRequestFocus: false,
      child: _BoundaryScope(node: _node, child: widget.child),
    );
  }
}

bool _sameKeys(Set<KeyCombo> a, Set<KeyCombo> b) =>
    a.length == b.length && a.containsAll(b);

class _BoundaryScope extends InheritedWidget {
  const _BoundaryScope({required this.node, required super.child});

  final FocusNode node;

  @override
  bool updateShouldNotify(_BoundaryScope oldWidget) => node != oldWidget.node;
}

/// What help built under [boundary] lists of [fm]'s active bindings: those
/// inside [boundary], or all when it is null, less those on keys a boundary
/// around them takes. Inner bindings shadow outer ones first, as for keys.
@visibleForTesting
List<Binding> listedBindings(FocusManager fm, FocusNode? boundary) {
  final path = fm.focusPath;
  final inside = boundary == null ? path.length : path.indexOf(boundary);
  if (inside < 0) return const [];
  // The keys taken above each node: every boundary further out adds its own.
  final takenAbove = List<Set<KeyCombo>>.filled(path.length, const {});
  var taken = <KeyCombo>{};
  for (var i = path.length - 1; i >= 0; i--) {
    takenAbove[i] = taken;
    if (_taken[path[i]] case final more?) taken = {...taken, ...more};
  }
  final seen = <Chord>{};
  final out = <Binding>[];
  for (var i = 0; i < path.length; i++) {
    for (final b in path[i].bindings) {
      if (!b.enabled || !seen.add(b.chord)) continue;
      if (i >= inside) continue;
      if (takenAbove[i].contains(b.chord.combos.first)) continue;
      out.add(b);
    }
  }
  return out;
}
