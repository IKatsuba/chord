import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart';

import '../status/status.dart' show MarkTones;

/// Chord's app-specific mode colors and three-mark spinner palette.
final class ChordTheme extends ThemeExtension<ChordTheme> {
  const ChordTheme({
    this.plan = Style.plain,
    this.edits = Style.plain,
    this.auto = Style.plain,
    this.bash = Style.plain,
    this.mark = const MarkTones(),
    this.selection = const Style(inverse: true),
  });
  final Style plan, edits, auto, bash;
  final MarkTones mark;

  /// Selected glyphs use the original slate, or inverse under NO_COLOR.
  final Style selection;
}

/// The original dark mode roles and mark gradient.
const chordDark = ChordTheme(
  selection: Style(bg: IndexedColor(66)),
  plan: Style(fg: RgbColor(72, 150, 140)),
  edits: Style(fg: RgbColor(175, 135, 255)),
  auto: Style(fg: RgbColor(255, 215, 0)),
  bash: Style(fg: RgbColor(253, 93, 177)),
  mark: MarkTones(
    tone: 'greenBright',
    stops: ['#d2ffe4', '#3fdc9c', '#0a7470'],
  ),
);

/// The original light mode roles and mark gradient.
const chordLight = ChordTheme(
  selection: Style(bg: IndexedColor(152)),
  plan: Style(fg: RgbColor(0, 107, 102)),
  edits: Style(fg: RgbColor(122, 63, 214)),
  auto: Style(fg: RgbColor(138, 97, 0)),
  bash: Style(fg: RgbColor(209, 0, 111)),
  mark: MarkTones(tone: 'green', stops: ['#1e9a5e', '#147d55', '#0a5e57']),
);

/// Attributes and terminal foreground only, including under NO_COLOR.
const chordPlain = ChordTheme();

/// Adds the original app palette for the resolved framework theme.
class ChordThemeScope extends StatelessWidget {
  const ChordThemeScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    // A theme drawn from a named palette brings its own roles.
    if (base.extension<ChordTheme>() != null) return child;
    final palette = Theme.noColorOf(context)
        ? chordPlain
        : base.brightness == Brightness.light
        ? chordLight
        : chordDark;
    return Theme(
      data: base.copyWith(extensions: [palette]),
      child: child,
    );
  }
}

/// The app palette, leaving intentionally unwrapped consumers unpainted.
ChordTheme chordThemeOf(BuildContext context) =>
    Theme.of(context).extension<ChordTheme>() ?? chordPlain;

/// The mark's colors, which are hex values or its two named green tones.
Color? markColor(String? color) => switch (color) {
  null => null,
  'greenBright' => Colors.brightGreen,
  'green' => Colors.green,
  _ => RgbColor.hex(color),
};

// chord's themes, as the original's src/ui/theme/theme.ts: every colour it
// paints, by role, in each theme; which theme `auto` comes to on the
// terminal's background; and `/theme`'s choices. Colours are written as the
// original writes them, a hex, `ansi256(n)` or one of the terminal's
// sixteen by name, and made framework styles by [themeData].

/// The `theme` setting's values: Claude Code's ids for its own themes.
const themeSettingIds = [
  'auto',
  'dark',
  'light',
  'dark-daltonized',
  'light-daltonized',
  'dark-ansi',
  'light-ansi',
];

/// A token's colour in each class a highlight sheet tells apart.
typedef ToneMap = Map<String, String>;

/// Every colour a theme paints; a role left out is not painted.
final class Palette {
  const Palette({
    this.accent,
    this.permission,
    this.inlineCode,
    this.link,
    this.bash,
    this.plan,
    this.edits,
    this.auto,
    this.error,
    this.warning,
    this.success,
    this.agents,
    this.mark,
    required this.selection,
    this.code,
    this.codeOnTint,
    this.diffAdded,
    this.diffRemoved,
    this.tint,
  });

  final String? accent, permission, inlineCode, link, bash, plan, edits;
  final String? auto, error, warning, success;

  /// A session's long-lived agents' six colours, in the order they open.
  final List<String>? agents;

  /// The startup header's mark.
  final MarkTones? mark;

  /// The background of the cells a drag selects; every theme has one.
  final String selection;

  /// Code's tokens on the terminal's background, and on a diff's tint.
  final ToneMap? code, codeOnTint;

  /// A changed row's sign, or the whole row without [tint].
  final String? diffAdded, diffRemoved;

  /// A changed row's background and its text: added, removed, text.
  final ({String added, String removed, String text})? tint;

  /// This palette with its diff colours replaced.
  Palette withDiff({
    required String added,
    required String removed,
    ({String added, String removed, String text})? tint,
  }) => Palette(
    accent: accent,
    permission: permission,
    inlineCode: inlineCode,
    link: link,
    bash: bash,
    plan: plan,
    edits: edits,
    auto: auto,
    error: error,
    warning: warning,
    success: success,
    agents: agents,
    mark: mark,
    selection: selection,
    code: code,
    codeOnTint: codeOnTint,
    diffAdded: added,
    diffRemoved: removed,
    tint: tint,
  );
}

/// Tokens where the background is dark.
const _darkCode = {
  'keyword': '#d7a6ff',
  'string': '#f2d38a',
  'number': '#ffb07a',
  'comment': '#8f96a0',
  'title': '#8cc8ff',
  'type': '#7fe0e8',
  'name': '#f5a3c7',
  'meta': '#b4bcff',
};

/// The same hues darkened to 4.5:1 or more on white.
const _lightCode = {
  'keyword': '#8250df',
  'string': '#7d5200',
  'number': '#a94800',
  'comment': '#6e7781',
  'title': '#0b5cad',
  'type': '#00727a',
  'name': '#b0306f',
  'meta': '#4a50c4',
};

/// A step darker again, for 4.3:1 or more on every pale tint.
const _lightOnTint = {
  'keyword': '#7a45d0',
  'string': '#6e4900',
  'number': '#9a4200',
  'comment': '#626b75',
  'title': '#0a55a0',
  'type': '#00666d',
  'name': '#a32a66',
  'meta': '#4248b5',
};

/// The selection's background on a dark terminal, and where colour is off.
const _slate = 'ansi256(66)';

const _dark = Palette(
  accent: '#47e7a5',
  permission: '#b1b9f9',
  inlineCode: '#b1b9f9',
  link: '#8cc8ff',
  bash: '#fd5db1',
  plan: '#48968c',
  edits: '#af87ff',
  auto: '#ffd700',
  error: '#ff6b80',
  warning: '#ffc107',
  success: '#4eba65',
  // Lighter than the accent, so a name never sinks into the border.
  agents: ['#6cb6ff', '#c49cff', '#56d4dd', '#7ccf7f', '#e8c95a', '#f59ac6'],
  mark: MarkTones(
    stops: ['#d2ffe4', '#3fdc9c', '#0a7470'],
    tone: 'greenBright',
  ),
  // Claude Code's slate, `48;5;66`.
  selection: _slate,
  code: _darkCode,
  codeOnTint: _darkCode,
  diffAdded: '#86e08a',
  diffRemoved: '#ff8e8e',
  tint: (added: '#1f3b24', removed: '#4a1f27', text: '#e4e4e4'),
);

const _light = Palette(
  accent: '#147d55',
  permission: '#4a5ae0',
  inlineCode: '#4a5ae0',
  link: '#0b5cad',
  bash: '#d1006f',
  plan: '#006b66',
  edits: '#7a3fd6',
  auto: '#8a6100',
  error: '#c4162a',
  warning: '#8a5a00',
  success: '#2c7a39',
  agents: ['#0a5bc4', '#7a3fd6', '#00727a', '#2c7a39', '#8a6100', '#b0306f'],
  mark: MarkTones(stops: ['#1e9a5e', '#147d55', '#0a5e57'], tone: 'green'),
  selection: 'ansi256(152)',
  code: _lightCode,
  codeOnTint: _lightOnTint,
  // Pale washes, where the dark theme's tints are blocks on white.
  diffAdded: '#17702f',
  diffRemoved: '#c4162a',
  tint: (added: '#dcf5e0', removed: '#fde2e2', text: '#1f2328'),
);

/// The 16-colour themes: the terminal's own palette decides each colour,
/// with no tint, which taken from 16 is a loud block.
Palette _sixteen(bool bright) {
  String tone(String name) => bright ? '${name}Bright' : name;
  return Palette(
    accent: tone('yellow'),
    permission: tone('blue'),
    inlineCode: tone('blue'),
    link: tone('blue'),
    bash: tone('magenta'),
    plan: tone('cyan'),
    edits: tone('magenta'),
    auto: tone('yellow'),
    error: tone('red'),
    warning: tone('yellow'),
    success: tone('green'),
    agents: [
      for (final name in ['blue', 'magenta', 'cyan', 'green', 'yellow', 'red'])
        tone(name),
    ],
    mark: MarkTones(tone: tone('green')),
    // A slate still, where the sixteen have none that reads under text.
    selection: bright ? _slate : 'ansi256(152)',
    code: {
      'keyword': tone('magenta'),
      'string': tone('yellow'),
      'number': tone('yellow'),
      'comment': 'gray',
      'title': tone('blue'),
      'type': tone('cyan'),
      'meta': tone('blue'),
    },
    diffAdded: tone('green'),
    diffRemoved: tone('red'),
  );
}

/// The palette of each theme there is.
final Map<String, Palette> palettes = {
  'dark': _dark,
  'light': _light,
  // For red–green colour blindness only the diff changes: blue and orange,
  // the pair that stays apart, and the signs still say which is which.
  'dark-daltonized': _dark.withDiff(
    added: '#6cb6ff',
    removed: '#ffb15c',
    tint: (added: '#16304f', removed: '#4a2a12', text: '#e4e4e4'),
  ),
  'light-daltonized': _light.withDiff(
    added: '#0a5bc4',
    removed: '#a34a00',
    tint: (added: '#dbeeff', removed: '#fde8d4', text: '#1f2328'),
  ),
  'dark-ansi': _sixteen(true),
  'light-ansi': _sixteen(false),
};

/// What NO_COLOR, or a terminal that takes no colour, leaves: nothing but
/// the selection, which would not show at all without one.
const plainPalette = Palette(selection: _slate);

/// The palette [name] is drawn in, or none at all where colour is off.
Palette paletteOf(String name, bool colour) =>
    colour ? palettes[name]! : plainPalette;

/// A child's colour, by its place among the session's children.
String? agentColour(Palette palette, int? colour) {
  final all = palette.agents;
  return colour == null || all == null || all.isEmpty
      ? null
      : all[colour % all.length];
}

/// The theme drawn for [setting]: `auto` is the background's.
String resolveTheme(String setting, TerminalBackground found) =>
    setting == 'auto' ? found.brightness.name : setting;

const _labels = {
  'dark': 'Dark',
  'light': 'Light',
  'dark-daltonized': 'Dark, colour-blind friendly',
  'light-daltonized': 'Light, colour-blind friendly',
  'dark-ansi': "Dark, the terminal's 16 colours",
  'light-ansi': "Light, the terminal's 16 colours",
};

/// A theme as `/theme` lists it; Auto says what it found and where.
String themeLabel(String setting, TerminalBackground found) {
  if (setting != 'auto') return _labels[setting]!;
  final tone = found.brightness.name;
  return switch (found.source) {
    BrightnessSource.terminal => 'Auto ($tone, from the terminal)',
    BrightnessSource.colorFgBg => 'Auto ($tone, from COLORFGBG)',
    BrightnessSource.fallback => 'Auto (dark: the terminal did not say)',
  };
}

/// A theme as a sentence names it: `Auto`, `Light`.
String themeName(String setting) =>
    setting == 'auto' ? 'Auto' : _labels[setting]!;

/// `/theme`'s rows, the setting in use marked as `/model` marks its model.
List<({String value, String label, bool current})> themeChoices(
  String current,
  TerminalBackground found,
) => [
  for (final setting in themeSettingIds)
    (
      value: setting,
      label: '${themeLabel(setting, found)}${setting == current ? ' ✔' : ''}',
      current: setting == current,
    ),
];

/// Whether [value] is one of the setting's ids.
bool isThemeSetting(String value) => themeSettingIds.contains(value);

/// The sample `/theme` draws under its choices, in the theme highlighted.
const themeSample = (
  path: 'greet.js',
  old: 'function greet(name) {\n  return "hello " + name;\n}\n',
  now: 'function greet(name) {\n  return `hello, \${name}`;\n}\n',
);

/// How `/theme` fits the layer it floats in, [room] rows above the prompt:
/// every choice and the diff sample while they fit around its frame, title
/// and hint; else the choices alone, as many as fit, with the row that
/// counts the hidden ones; none where not one fits.
({int choices, bool sample}) themePickerLayout(int room) {
  // Border, title, the line under it and the gap before the choices, the
  // gap before the hint and the hint itself.
  const frame = 7;
  final count = themeSettingIds.length;
  // The sample's three rows and the gap above them.
  const sample = 4;
  if (room >= frame + count + sample) return (choices: count, sample: true);
  final fits = room - frame;
  return (
    choices: math.max(0, fits >= count ? count : fits - 1),
    sample: false,
  );
}

/// [colour] as the framework draws it: a hex, `ansi256(n)` or one of the
/// terminal's sixteen by name.
Color colorOf(String colour) {
  if (colour.startsWith('#')) return RgbColor.hex(colour);
  final indexed = RegExp(r'^ansi256\((\d+)\)$').firstMatch(colour);
  if (indexed != null) return IndexedColor(int.parse(indexed[1]!));
  return switch (colour) {
    'black' => Colors.black,
    'red' => Colors.red,
    'green' => Colors.green,
    'yellow' => Colors.yellow,
    'blue' => Colors.blue,
    'magenta' => Colors.magenta,
    'cyan' => Colors.cyan,
    'white' => Colors.white,
    'gray' => Colors.gray,
    'redBright' => Colors.brightRed,
    'greenBright' => Colors.brightGreen,
    'yellowBright' => Colors.brightYellow,
    'blueBright' => Colors.brightBlue,
    'magentaBright' => Colors.brightMagenta,
    'cyanBright' => Colors.brightCyan,
    'whiteBright' => Colors.brightWhite,
    _ => throw ArgumentError.value(colour, 'colour', 'no colour'),
  };
}

Style _fg(String? colour) =>
    colour == null ? Style.plain : Style(fg: colorOf(colour));

Tones _tones(ToneMap tones) => Tones(
  keyword: _fg(tones['keyword']),
  string: _fg(tones['string']),
  number: _fg(tones['number']),
  comment: _fg(tones['comment']),
  title: _fg(tones['title']),
  type: _fg(tones['type']),
  name: _fg(tones['name']),
  meta: _fg(tones['meta']),
);

/// The framework theme [name] is drawn in, chord's own roles with it; the
/// plain one where colour is off.
ThemeData themeData(String name, {bool colour = true}) {
  final brightness = name.startsWith('light')
      ? Brightness.light
      : Brightness.dark;
  if (!colour) {
    return ThemeData.plain(
      brightness: brightness,
    ).copyWith(extensions: [chordPlain]);
  }
  final palette = palettes[name]!;
  final tint = palette.tint;
  return ThemeData(
    brightness: brightness,
    accent: _fg(palette.accent),
    link: _fg(palette.link),
    inlineCode: _fg(palette.inlineCode),
    success: _fg(palette.success),
    warning: _fg(palette.warning),
    error: _fg(palette.error),
    border: const Style(fg: IndexedColor(244)),
    focus: _fg(palette.permission),
    selection: Style(bg: colorOf(palette.selection)),
    diff: DiffTheme(
      added: _fg(palette.diffAdded),
      removed: _fg(palette.diffRemoved),
      tint: tint == null
          ? null
          : DiffTint(
              added: Style(bg: colorOf(tint.added)),
              removed: Style(bg: colorOf(tint.removed)),
              text: _fg(tint.text),
            ),
    ),
    code: palette.code == null
        ? null
        : CodeTones(
            terminal: _tones(palette.code!),
            tint: palette.codeOnTint == null
                ? null
                : _tones(palette.codeOnTint!),
          ),
    extensions: [
      ChordTheme(
        plan: _fg(palette.plan),
        edits: _fg(palette.edits),
        auto: _fg(palette.auto),
        bash: _fg(palette.bash),
        mark: palette.mark ?? const MarkTones(),
        selection: Style(bg: colorOf(palette.selection)),
      ),
    ],
  );
}
