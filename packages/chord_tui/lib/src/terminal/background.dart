/// Whether a terminal's background is dark or light.
enum Brightness {
  /// A dark background: light text on it.
  dark,

  /// A light background: dark text on it.
  light,
}

/// What said how bright the terminal's background is.
enum BrightnessSource {
  /// The terminal's own answer to OSC 11.
  terminal,

  /// The `COLORFGBG` variable, which rxvt and Konsole set.
  colorFgBg,

  /// Neither: dark, by default.
  fallback,
}

/// The terminal's background as an app reads it at start, and what said so.
class TerminalBackground {
  /// A background of [brightness], as [source] said.
  const TerminalBackground(this.brightness, this.source);

  /// Dark or light.
  final Brightness brightness;

  /// What said so.
  final BrightnessSource source;

  @override
  bool operator ==(Object other) =>
      other is TerminalBackground &&
      other.brightness == brightness &&
      other.source == source;

  @override
  int get hashCode => Object.hash(brightness, source);

  @override
  String toString() => 'TerminalBackground(${brightness.name}, ${source.name})';
}

final _osc11 = RegExp(
  r'^(?:\x1b\]11;)?'
  r'(?:rgb:([0-9a-fA-F]{1,4})/([0-9a-fA-F]{1,4})/([0-9a-fA-F]{1,4})'
  r'|#([0-9a-fA-F]{6}))'
  r'(?:\x07|\x1b\\)?$',
);

/// The brightness of the background a terminal reports in its answer to
/// OSC 11 (`ESC ]11;rgb:RRRR/GGGG/BBBB` ended by BEL or `ESC \`, or the
/// colour alone, as `rgb:R/G/B` with one to four hex digits a channel or
/// `#rrggbb`); null when [reply] is not such an answer.
Brightness? brightnessFromOsc11(String reply) {
  final match = _osc11.firstMatch(reply);
  if (match == null) return null;
  final List<int> rgb;
  if (match.group(4) case final hex?) {
    rgb = [
      for (var i = 0; i < 6; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
  } else {
    rgb = [for (var i = 1; i <= 3; i++) _scale(match.group(i)!)];
  }
  // The original decides through OpenTUI's inferThemeModeFromBackgroundColor:
  // perceived brightness over 128 of 255 is light. It is matched as written so
  // the port picks the same palette on the same terminal.
  final brightness = (rgb[0] * 299 + rgb[1] * 587 + rgb[2] * 114) / 1000;
  return brightness > 128 ? Brightness.light : Brightness.dark;
}

/// A channel of one to four hex digits, scaled to 0..255 and rounded.
int _scale(String digits) {
  final max = (1 << (4 * digits.length)) - 1;
  return (int.parse(digits, radix: 16) / max * 255).round();
}

/// The background `COLORFGBG` names: `7` or `15` in its last field is
/// light, any other number dark; null when [value] is unset or its last field
/// is not a number.
Brightness? brightnessFromColorFgBg(String? value) {
  final last = (value ?? '').split(';').last.trim();
  if (!RegExp(r'^\d+$').hasMatch(last)) return null;
  return last == '7' || last == '15' ? Brightness.light : Brightness.dark;
}

/// The background from the terminal's answer to OSC 11 ([fromTerminal]),
/// else from `COLORFGBG` ([colorFgBg]), else dark.
TerminalBackground resolveBackground(
  Brightness? fromTerminal,
  String? colorFgBg,
) {
  if (fromTerminal != null) {
    return TerminalBackground(fromTerminal, BrightnessSource.terminal);
  }
  final fromVariable = brightnessFromColorFgBg(colorFgBg);
  return fromVariable == null
      ? const TerminalBackground(Brightness.dark, BrightnessSource.fallback)
      : TerminalBackground(fromVariable, BrightnessSource.colorFgBg);
}
