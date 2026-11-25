/// Names offered by `@@` must fit its literal, single-line quoted syntax.
/// From the original's `agent_name.ts`.
library;

/// The same refusal before starting a child and when reading a saved team;
/// null when [name] may be used.
String? agentNameProblem(String name) {
  for (final rune in name.runes) {
    if (rune == 0x22) return 'must not contain the character "';
    if (rune < 32 || rune == 127) {
      final hex = rune.toRadixString(16).toUpperCase().padLeft(4, '0');
      return 'must not contain the control character U+$hex';
    }
  }
  return null;
}
