import 'package:chord_tui/chord_tui.dart';

/// What the keys panel shows of its entries in the rows it has: its rule
/// only while there is room above the page for it, then the title, then a
/// scrolled window of entries between `↑ +N more` and `↓ +N more`.
class PanelWindow {
  /// A window of [count] entries from [first], with [above] and [below]
  /// hidden, under a rule when [rule].
  const PanelWindow({
    required this.rule,
    required this.first,
    required this.count,
    required this.above,
    required this.below,
    required this.overflows,
  });

  /// Whether the panel draws its own rule: not where it reaches the top of
  /// the page, under the header's rule.
  final bool rule;

  /// The first entry shown.
  final int first;

  /// How many entries are shown.
  final int count;

  /// How many entries are hidden above.
  final int above;

  /// How many entries are hidden below.
  final int below;

  /// Whether there are more entries than rows, so the panel scrolls.
  final bool overflows;
}

/// The window of [entries] at scroll [offset] in [rows] rows; [offset] is
/// clamped to what scrolling can reach.
PanelWindow panelWindow({
  required int entries,
  required int rows,
  required int offset,
}) {
  final rule = entries + 2 <= rows;
  // The rows under the title.
  final room = rows - (rule ? 2 : 1);
  if (entries <= room) {
    return PanelWindow(
      rule: rule,
      first: 0,
      count: entries,
      above: 0,
      below: 0,
      overflows: false,
    );
  }
  final first = offset.clamp(0, panelMaxOffset(entries: entries, rows: rows));
  final top = first > 0 ? 1 : 0;
  final left = room - top;
  final count = first + left >= entries
      ? entries - first
      : (left - 1).clamp(0, entries);
  return PanelWindow(
    rule: false,
    first: first,
    count: count,
    above: first,
    below: entries - first - count,
    overflows: true,
  );
}

/// The furthest scroll offset: the last entries under a `↑` row.
int panelMaxOffset({required int entries, required int rows}) {
  final room = rows - 1;
  if (entries <= room) return 0;
  return (entries - (room - 1)).clamp(0, entries);
}

/// The panel's entries in the order it lists them: the site's own keys
/// first, those whose id starts with one of [ownPrefixes], then the page's.
List<BindingGroup> panelEntries(
  List<Binding> bindings,
  List<String> ownPrefixes,
) {
  bool own(BindingGroup g) =>
      ownPrefixes.any((prefix) => (g.id ?? '').startsWith(prefix));
  final grouped = groupBindings(bindings);
  return [...grouped.where(own), ...grouped.where((g) => !own(g))];
}
