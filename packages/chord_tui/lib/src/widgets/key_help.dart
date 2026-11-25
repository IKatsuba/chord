import 'package:meta/meta.dart';

import '../input/keys.dart';
import '../terminal/style.dart';
import '../text/layout.dart';
import '../text/span.dart';
import 'basic.dart';
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
    final theme = Theme.of(context);
    final keyStyle = this.keyStyle ?? theme.text.merge(Style.bold);
    final descriptionStyle = this.descriptionStyle ?? theme.dim;
    return ListenableBuilder(
      listenable: fm,
      builder: (context) {
        final pending = fm.pendingChord;
        final builder = _builder;
        if (builder != null) {
          return builder(
            context,
            List<Binding>.unmodifiable(fm.activeBindings),
            List<KeyCombo>.unmodifiable(pending),
          );
        }
        final spans = <TextSpan>[];
        for (final group in groupBindings(fm.activeBindings)) {
          final chords = [
            for (final chord in group.chords)
              if (pending.isEmpty || chord.startsWith(pending)) chord,
          ];
          if (chords.isEmpty) continue;
          if (spans.isNotEmpty) spans.add(TextSpan(separator));
          spans.add(TextSpan(chords.join('/'), style: keyStyle));
          spans.add(TextSpan(' ${group.description}', style: descriptionStyle));
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
