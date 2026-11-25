// Each child's colour, handed down to the transcript so a message's arrow
// and name are in the colour of the agent at its other end, as the
// original's `AgentColours` in src/ui/app/context.ts.
import 'package:chord_tui/chord_tui.dart';

/// The colour of each agent by name, for the `←` and `→` rows that name
/// it; `main`, `chord` and an agent with no colour are not in it.
class AgentColours extends InheritedWidget {
  /// [colours] for the transcript under it.
  const AgentColours({super.key, required this.colours, required super.child});

  /// Each coloured agent's colour by its name.
  final Map<String, Color> colours;

  /// The nearest map; none, and so no colour, without one.
  static Map<String, Color> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AgentColours>()?.colours ??
      const {};

  @override
  bool updateShouldNotify(AgentColours oldWidget) =>
      !sameColours(colours, oldWidget.colours);
}

/// Whether [a] and [b] colour the same agents alike.
bool sameColours(Map<String, Color> a, Map<String, Color> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

/// [colours] as a value equal for equal maps, so a selection source made
/// with them is reused only while they stay the same.
String coloursKey(Map<String, Color> colours) => [
  for (final MapEntry(:key, :value) in colours.entries)
    '$key\x00${value.fgCode}',
].join('\x01');
