import 'package:meta/meta.dart';

import '../terminal/background.dart';
import '../terminal/style.dart';

Style _fg(String hex) => Style(fg: RgbColor.hex(hex));
Style _bg(String hex) => Style(bg: RgbColor.hex(hex));

/// A token's style in each class a highlighter tells apart; [Style.plain]
/// leaves the text's own.
@immutable
class Tones {
  /// Tones with each class given, the rest plain.
  const Tones({
    this.keyword = Style.plain,
    this.string = Style.plain,
    this.number = Style.plain,
    this.comment = Style.plain,
    this.title = Style.plain,
    this.type = Style.plain,
    this.name = Style.plain,
    this.meta = Style.plain,
  });

  /// Keywords: `if`, `return`, `class`.
  final Style keyword;

  /// String literals.
  final Style string;

  /// Number literals.
  final Style number;

  /// Comments.
  final Style comment;

  /// Names being defined: functions, classes, headings.
  final Style title;

  /// Types and built-ins.
  final Style type;

  /// Other names: attributes, variables, tags.
  final Style name;

  /// Preprocessor lines, annotations, punctuation of note.
  final Style meta;

  @override
  bool operator ==(Object other) =>
      other is Tones &&
      other.keyword == keyword &&
      other.string == string &&
      other.number == number &&
      other.comment == comment &&
      other.title == title &&
      other.type == type &&
      other.name == name &&
      other.meta == meta;

  @override
  int get hashCode =>
      Object.hash(keyword, string, number, comment, title, type, name, meta);
}

/// Code's tokens on the terminal's background, and on a diff's tint.
@immutable
class CodeTones {
  /// [terminal] on the background; [tint] on a diff's tint, [terminal] if
  /// not given.
  const CodeTones({required this.terminal, Tones? tint})
    : tint = tint ?? terminal;

  /// Tones on the terminal's background.
  final Tones terminal;

  /// Tones on a changed row's tint.
  final Tones tint;

  @override
  bool operator ==(Object other) =>
      other is CodeTones && other.terminal == terminal && other.tint == tint;

  @override
  int get hashCode => Object.hash(terminal, tint);
}

/// A changed row's background, and the text drawn on it, which is set rather
/// than left to the terminal, since its own may not read on the tint.
@immutable
class DiffTint {
  /// A tint of [added] and [removed] backgrounds with [text] on either.
  const DiffTint({
    required this.added,
    required this.removed,
    required this.text,
  });

  /// An added row's background.
  final Style added;

  /// A removed row's background.
  final Style removed;

  /// The foreground on either.
  final Style text;

  @override
  bool operator ==(Object other) =>
      other is DiffTint &&
      other.added == added &&
      other.removed == removed &&
      other.text == text;

  @override
  int get hashCode => Object.hash(added, removed, text);
}

/// A changed row: with [tint], on its background with [added] and [removed]
/// for the signs; without, the whole row in [added] or [removed], as
/// `git diff` draws it.
@immutable
class DiffTheme {
  /// A diff theme; plain with no tint by default.
  const DiffTheme({
    this.added = Style.plain,
    this.removed = Style.plain,
    this.tint,
  });

  /// An added line's sign, or the whole line without a tint.
  final Style added;

  /// A removed line's sign, or the whole line without a tint.
  final Style removed;

  /// The rows' backgrounds; null draws no background.
  final DiffTint? tint;

  /// This diff theme with the parts given replaced.
  DiffTheme copyWith({Style? added, Style? removed, DiffTint? tint}) =>
      DiffTheme(
        added: added ?? this.added,
        removed: removed ?? this.removed,
        tint: tint ?? this.tint,
      );

  @override
  bool operator ==(Object other) =>
      other is DiffTheme &&
      other.added == added &&
      other.removed == removed &&
      other.tint == tint;

  @override
  int get hashCode => Object.hash(added, removed, tint);
}

final _darkCode = Tones(
  keyword: _fg('#d7a6ff'),
  string: _fg('#f2d38a'),
  number: _fg('#ffb07a'),
  comment: _fg('#8f96a0'),
  title: _fg('#8cc8ff'),
  type: _fg('#7fe0e8'),
  name: _fg('#f5a3c7'),
  meta: _fg('#b4bcff'),
);

final _lightCode = Tones(
  keyword: _fg('#8250df'),
  string: _fg('#7d5200'),
  number: _fg('#a94800'),
  comment: _fg('#6e7781'),
  title: _fg('#0b5cad'),
  type: _fg('#00727a'),
  name: _fg('#b0306f'),
  meta: _fg('#4a50c4'),
);

// A step darker again than _lightCode, to read on every pale tint.
final _lightOnTint = Tones(
  keyword: _fg('#7a45d0'),
  string: _fg('#6e4900'),
  number: _fg('#9a4200'),
  comment: _fg('#626b75'),
  title: _fg('#0a55a0'),
  type: _fg('#00666d'),
  name: _fg('#a32a66'),
  meta: _fg('#4248b5'),
);

// Colour 244 reads on dark and on light, where 8 is the background in some
// palettes.
const _border = Style(fg: IndexedColor(244));

/// Immutable app-defined theme values looked up by their declared type.
abstract class ThemeExtension<T extends ThemeExtension<T>> {
  /// An app's extension, whose fields and nested values stay immutable.
  const ThemeExtension();

  /// The registry slot, including for specialized subclasses of an app type.
  Type get type => T;
}

/// Every role a framework widget or an app paints with.
///
/// A role is a [Style], not a colour, merged into what a widget draws: a
/// role that is [Style.plain] leaves the terminal's own colours. Plain and
/// dim text are never painted, so the wrong theme can fade an accent but
/// never the text.
@immutable
class ThemeData {
  /// A theme of the roles given, the rest plain.
  ThemeData({
    required this.brightness,
    this.text = Style.plain,
    this.dim = Style.dim,
    this.accent = Style.plain,
    this.link = Style.plain,
    this.inlineCode = Style.plain,
    this.success = Style.plain,
    this.warning = Style.plain,
    this.error = Style.plain,
    this.border = Style.plain,
    this.focus = Style.plain,
    this.selection = Style.inverse,
    this.cursor = Style.inverse,
    this.diff = const DiffTheme(),
    this.code,
    Iterable<ThemeExtension<dynamic>> extensions = const [],
  }) : extensions = _extensionsOf(extensions);

  /// The theme for a dark background.
  factory ThemeData.dark() => ThemeData(
    brightness: Brightness.dark,
    accent: _fg('#47e7a5'),
    link: _fg('#8cc8ff'),
    inlineCode: _fg('#b1b9f9'),
    success: _fg('#4eba65'),
    warning: _fg('#ffc107'),
    error: _fg('#ff6b80'),
    border: _border,
    focus: _fg('#b1b9f9'),
    selection: const Style(bg: IndexedColor(66)),
    diff: DiffTheme(
      added: _fg('#86e08a'),
      removed: _fg('#ff8e8e'),
      tint: DiffTint(
        added: _bg('#1f3b24'),
        removed: _bg('#4a1f27'),
        text: _fg('#e4e4e4'),
      ),
    ),
    code: CodeTones(terminal: _darkCode),
  );

  /// The theme for a light background.
  factory ThemeData.light() => ThemeData(
    brightness: Brightness.light,
    accent: _fg('#147d55'),
    link: _fg('#0b5cad'),
    inlineCode: _fg('#4a5ae0'),
    success: _fg('#2c7a39'),
    warning: _fg('#8a5a00'),
    error: _fg('#c4162a'),
    border: _border,
    focus: _fg('#4a5ae0'),
    selection: const Style(bg: IndexedColor(152)),
    diff: DiffTheme(
      added: _fg('#17702f'),
      removed: _fg('#c4162a'),
      tint: DiffTint(
        added: _bg('#dcf5e0'),
        removed: _bg('#fde2e2'),
        text: _fg('#1f2328'),
      ),
    ),
    code: CodeTones(terminal: _lightCode, tint: _lightOnTint),
  );

  /// No colour at all, attributes only: what NO_COLOR asks for.
  factory ThemeData.plain({Brightness brightness = Brightness.dark}) =>
      ThemeData(brightness: brightness, border: Style.dim, focus: Style.bold);

  /// What `Theme.of` gives with no Theme above: [ThemeData.dark].
  factory ThemeData.fallback() => ThemeData.dark();

  /// The background this theme is drawn for.
  final Brightness brightness;

  /// Plain text; unpainted in the framework's themes.
  final Style text;

  /// Text that steps back: hints, descriptions, placeholders.
  final Style dim;

  /// What is going on now: a working line, a spinner, a title.
  final Style accent;

  /// Links.
  final Style link;

  /// Code inside prose.
  final Style inlineCode;

  /// Something that went well.
  final Style success;

  /// Something to look at.
  final Style warning;

  /// Something that failed.
  final Style error;

  /// Box borders that are not focused.
  final Style border;

  /// What holds attention: a focused border, a prompt that asks.
  final Style focus;

  /// The background of selected cells.
  final Style selection;

  /// The cursor cell in a text input.
  final Style cursor;

  /// Changed rows in a diff.
  final DiffTheme diff;

  /// Code's tokens; null where code is not coloured.
  final CodeTones? code;

  /// App-defined values, snapshotted and indexed by their declared type.
  final Map<Type, ThemeExtension<dynamic>> extensions;

  /// Values of app type [T], or null when this theme has none.
  T? extension<T extends ThemeExtension<T>>() => extensions[T] as T?;

  /// This theme with the roles given replaced.
  ThemeData copyWith({
    Brightness? brightness,
    Style? text,
    Style? dim,
    Style? accent,
    Style? link,
    Style? inlineCode,
    Style? success,
    Style? warning,
    Style? error,
    Style? border,
    Style? focus,
    Style? selection,
    Style? cursor,
    DiffTheme? diff,
    CodeTones? code,
    Iterable<ThemeExtension<dynamic>>? extensions,
  }) => ThemeData(
    brightness: brightness ?? this.brightness,
    text: text ?? this.text,
    dim: dim ?? this.dim,
    accent: accent ?? this.accent,
    link: link ?? this.link,
    inlineCode: inlineCode ?? this.inlineCode,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    error: error ?? this.error,
    border: border ?? this.border,
    focus: focus ?? this.focus,
    selection: selection ?? this.selection,
    cursor: cursor ?? this.cursor,
    diff: diff ?? this.diff,
    code: code ?? this.code,
    extensions: extensions ?? this.extensions.values,
  );

  @override
  bool operator ==(Object other) =>
      other is ThemeData &&
      other.brightness == brightness &&
      other.text == text &&
      other.dim == dim &&
      other.accent == accent &&
      other.link == link &&
      other.inlineCode == inlineCode &&
      other.success == success &&
      other.warning == warning &&
      other.error == error &&
      other.border == border &&
      other.focus == focus &&
      other.selection == selection &&
      other.cursor == cursor &&
      other.diff == diff &&
      other.code == code &&
      other.extensions.length == extensions.length &&
      extensions.entries.every(
        (entry) => other.extensions[entry.key] == entry.value,
      );

  @override
  int get hashCode => Object.hashAll([
    brightness,
    text,
    dim,
    accent,
    link,
    inlineCode,
    success,
    warning,
    error,
    border,
    focus,
    selection,
    cursor,
    diff,
    code,
    Object.hashAllUnordered(
      extensions.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  ]);
}

Map<Type, ThemeExtension<dynamic>> _extensionsOf(
  Iterable<ThemeExtension<dynamic>> values,
) {
  final Map<Type, ThemeExtension<dynamic>> extensions =
      <Type, ThemeExtension<dynamic>>{};
  for (final ThemeExtension<dynamic> value in values) {
    if (extensions.containsKey(value.type)) {
      throw ArgumentError('Duplicate theme extension type: ${value.type}');
    }
    extensions[value.type] = value;
  }
  return Map.unmodifiable(extensions);
}
