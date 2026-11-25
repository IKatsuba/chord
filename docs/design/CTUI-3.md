# CTUI-3: Theme

Colour roles in an `InheritedWidget`, dark or light from the terminal. This
settles units 2–6 of the slice; unit 1 (`lib/src/terminal/background.dart`)
is the lead's, and where its names differ from the ones below, unit 1's win
and this file follows. It is read here as `Brightness { dark, light }`, `BrightnessSource { terminal, colorFgBg, fallback }` and `TerminalBackground(brightness, source)`.

The original is `../chord/src/ui/theme/theme.ts` (the `Palette`, `DARK`,
`LIGHT`, `PLAIN`, `background`, `colorFgBg`) and chord's decisions entry
"Themes: one palette module, `/theme` on `/model`'s list, is-term-dark asks
the terminal", with its notes on late and split OSC replies.

## The call site

```dart
// An app that does nothing gets the terminal's theme.
void main() => runApp(const App());

// Reading it.
final theme = Theme.of(context);
Text('saved', style: theme.success);
Text('3 files', style: theme.dim);
Box(border: Border.rounded, child: ...);          // border: theme.border
Box(border: Border.rounded.withStyle(theme.focus), child: ...);

// Overriding: a Theme below wins, as in Flutter.
Theme(
  data: ThemeData.dark().copyWith(accent: const Style(fg: Colors.magenta)),
  child: const Page(),
);

// Picking by the background, as the port's `auto` will.
final bg = Theme.backgroundOf(context);  // TerminalBackground
final data = bg.brightness == Brightness.light ? myLight : myDark;
```

## Roles are `Style`s

A role is a `Style`, not a `Color`: `dim` is the attribute, not a grey; the
cursor is `inverse`; the selection and the diff tint are backgrounds; and the
plain theme can still mark focus with `bold` where it paints no colour. A
widget merges a role into what it draws (`DefaultTextStyle.of(context)
.merge(role)`), so a role that is `Style.plain` leaves the terminal's own
colours, which is chord's rule: **plain and dim text are never painted**, so
the wrong theme can fade an accent but never the text.

```dart
enum Brightness { dark, light }

/// Every role a framework widget or an app paints with.
@immutable
class ThemeData {
  const ThemeData({required this.brightness, this.text = Style.plain, ...});
  factory ThemeData.dark();
  factory ThemeData.light();
  /// NO_COLOR: no colour at all, attributes only.
  factory ThemeData.plain({Brightness brightness = Brightness.dark});
  /// What `Theme.of` gives with no Theme above: [ThemeData.dark].
  factory ThemeData.fallback();

  final Brightness brightness;
  final Style text, dim, accent, link, inlineCode;
  final Style success, warning, error;
  final Style border, focus, selection, cursor;
  final DiffTheme diff;
  final CodeTones? code;   // null: code is not coloured

  ThemeData copyWith({...every field...});
  // == and hashCode over every field (Object.hashAll), so
  // Theme.updateShouldNotify is `data != oldWidget.data`.
}

/// A changed row: signs in [added]/[removed]; with [tint], the row's
/// background and the text on it; without, the row in added/removed.
@immutable
class DiffTheme {
  const DiffTheme({this.added = Style.plain, this.removed = Style.plain, this.tint});
  final Style added, removed;
  final DiffTint? tint;
  DiffTheme copyWith(...);   // ==, hashCode
}

@immutable
class DiffTint {
  const DiffTint({required this.added, required this.removed, required this.text});
  final Style added, removed;   // backgrounds
  final Style text;             // foreground on either
}

/// Code's tokens on the terminal's background, and on a diff's tint.
@immutable
class CodeTones {
  const CodeTones({required this.terminal, Tones? tint}) : tint = tint ?? terminal;
  final Tones terminal, tint;
}

/// A token's style per highlight class; Style.plain is the text's own.
@immutable
class Tones {
  const Tones({this.keyword = Style.plain, this.string = Style.plain,
      this.number = Style.plain, this.comment = Style.plain,
      this.title = Style.plain, this.type = Style.plain,
      this.name = Style.plain, this.meta = Style.plain});
  final Style keyword, string, number, comment, title, type, name, meta;
}
```

Syntax tones are in now: Code and Diff will read them, and they are chord's
values already measured for contrast. Out, for the port to map on top: chord's
`bash`, `plan`, `edits`, `auto`, `agents`, `mark`, and the daltonized and
16-colour themes (the nullable `tint` and `code` are kept so those map
without a change here).

### Values

`fg(#x)` is `Style(fg: RgbColor.hex('#x'))`, `bg(n)` an `IndexedColor`
background. Dark and light are chord's `DARK` and `LIGHT`.

| role | dark | light | plain |
| --- | --- | --- | --- |
| text | plain | plain | plain |
| dim | `Style.dim` | `Style.dim` | `Style.dim` |
| accent | fg #47e7a5 | fg #147d55 | plain |
| link | fg #8cc8ff | fg #0b5cad | plain |
| inlineCode | fg #b1b9f9 | fg #4a5ae0 | plain |
| success | fg #4eba65 | fg #2c7a39 | plain |
| warning | fg #ffc107 | fg #8a5a00 | plain |
| error | fg #ff6b80 | fg #c4162a | plain |
| border | fg 244 | fg 244 | `Style.dim` |
| focus (chord's `permission`) | fg #b1b9f9 | fg #4a5ae0 | `Style.bold` |
| selection | bg 66 | bg 152 | `Style.inverse` |
| cursor | `Style.inverse` | `Style.inverse` | `Style.inverse` |
| diff.added | fg #86e08a | fg #17702f | plain |
| diff.removed | fg #ff8e8e | fg #c4162a | plain |
| diff.tint.added | bg #1f3b24 | bg #dcf5e0 | (no tint) |
| diff.tint.removed | bg #4a1f27 | bg #fde2e2 | (no tint) |
| diff.tint.text | fg #e4e4e4 | fg #1f2328 | (no tint) |
| code.terminal | `DARK_CODE` | `LIGHT_CODE` | (null) |
| code.tint | `DARK_CODE` | `LIGHT_ON_TINT` | (null) |

The code tones are theme.ts's `DARK_CODE`, `LIGHT_CODE`, `LIGHT_ON_TINT`,
each as `fg`. `border` is 244 as chord's `DIM_BORDER` and Claude Code's
prompt border: it reads on dark and on light, where colour 8 is the
background in some palettes. Differences from chord, decided here: the plain
theme's selection is `inverse`, not slate 66 (our renderer draws inverse
correctly, which OpenTUI did not, CHD-172, and NO_COLOR then means no colour),
and plain marks `focus` bold and `border` dim, attributes rather than colour.

## `Theme`

```dart
/// Hands [data] to everything below.
class Theme extends InheritedWidget {
  const Theme({super.key, required this.data, required super.child});
  final ThemeData data;

  /// The nearest Theme's data, or ThemeData.fallback() with none above.
  static ThemeData of(BuildContext context);

  /// What runApp found about the terminal's background; dark from
  /// `BrightnessSource.fallback` with no runApp above (the tester).
  static TerminalBackground backgroundOf(BuildContext context);

  /// Whether NO_COLOR was set; false with no runApp above.
  static bool noColorOf(BuildContext context);
}
```

`backgroundOf`/`noColorOf` read `TerminalEnvironment`, an `InheritedWidget`
runApp puts above the app's `Theme`, so an app that brings its own Theme (the
port, `/theme`) still knows what the terminal said and can label `Auto (dark,
from the terminal)`. It is public in `src/` (runApp is another library) and
hidden from `package:chorded_tui`'s export.

`ThemeData`'s own constructor defaults `dim` to `Style.dim` and `selection`
and `cursor` to `Style.inverse`, so a hand-built theme still shows a cursor
and a selection; every other role defaults to plain. As in Flutter, `copyWith`
cannot set `code` back to null.

**The tester** wraps nothing: `Theme.of` falls back to `ThemeData.dark()`,
the theme an app gets on a terminal that does not answer, so tests see what
the default app sees. A test of light or plain wraps its widget in
`Theme(data: ThemeData.light(), ...)`. Tests that read a border's style see
fg 244 now instead of plain; that is the expected change.

## Unit 2: the parser's OSC event

```dart
/// A terminal's reply to an Operating System Command: `ESC ] code ; data`
/// ended by BEL or `ESC \`. Never a key.
final class OscEvent extends InputEvent {
  const OscEvent(this.code, this.data);
  final int code;       // 11
  final String data;    // 'rgb:ffff/ffff/ffff'
}
```

As chord's `replies.ts`:

- A reply is `ESC ]`, a code of one to nine digits, `;`, the data, then BEL
  or `ESC \`. It may arrive split across any number of `feed`s; the parser
  holds it. Real codes have four digits at most, and the cap bounds the
  parse.
- `ESC ]` followed by anything but a digit is alt+] at once, and the rest is
  parsed as usual (alt+] pressed alone).
- A reply broken off (a control character other than BEL/ESC inside it,
  `ESC` followed by anything but `\`, digits followed by anything but `;` or
  more digits, a code longer than nine digits, or more than 1024 characters
  of data) gives the keys back:
  alt+], then everything after `ESC ]` re-parsed as typed text, from the
  breaking character on parsed as usual.
- `flush()` with a reply pending gives the keys back the same way.
- Inside a bracketed paste, `ESC ]` is pasted text, as now.
- `hasPendingOsc` tells runApp a reply is half read (see below).

## Unit 5: `runApp`

```dart
Future<void> runApp(
  Widget app, {
  Terminal? terminal,
  bool exitProcess = true,
  ThemeData? theme,          // used as given, whatever the background
  Map<String, String>? environment,  // NO_COLOR, COLORFGBG; for tests and embedding
});
```

1. `NO_COLOR` set and not empty: the Theme is `ThemeData.plain(brightness:
   ...)`, whatever `theme` says. The ask still runs, so `backgroundOf` is
   true.
2. After `term.enter()`, and before the first frame, runApp writes
   `ESC ] 11 ; ? BEL` and waits up to **100 ms**. Input is read meanwhile:
   an `OscEvent(11, …)` ends the wait; keys and pastes are held. With no
   answer, `COLORFGBG`, else dark (unit 1's function). Then the app is
   mounted once, with the resolved Theme, so `initState` sees the true
   background; the held keys and pastes are delivered in order, and the
   first frame is drawn.
3. An `OscEvent` that comes later, or any other code, is dropped silently.
   It never reaches the app as keys: that is the parser's job (unit 2).
4. The pending-input timer is 30 ms for a lone `ESC`, as now, and 100 ms
   while `hasPendingOsc`, so a slow link's split reply is not flushed as
   text.
5. The tree is `TerminalEnvironment(background, noColor, child: Theme(data:
   resolved, child: app))`; `resolved` is plain under NO_COLOR, else `theme`,
   else `ThemeData.dark()` / `.light()` by the background.

No asking or waiting is added to a `Terminal` fake: it receives the query in
`write` and may answer through `input`, which is how unit 5 is tested. `environment` defaults to
`Platform.environment`; a test passes its own map, so the interface every
fake implements stays as it is.

## Unit 4: what the framework's widgets read

An explicit style always wins; a role fills only what is not given.

| widget | part | style |
| --- | --- | --- |
| `Box`, `DecoratedBox` | border; title as now, the border's style bold | `border.style ?? theme.border` |
| `KeyHelp` | the keys, and the pending chord | `keyStyle ?? theme.text.merge(Style.bold)` |
| `KeyHelp` | the descriptions | `descriptionStyle ?? theme.dim` |
| `TextInput` | the cursor cell | `cursorStyle ?? theme.cursor` |
| `TextInput` | the placeholder | `placeholderStyle ?? theme.dim` |
| `TextInput` | the prefix | `prefixStyle ?? theme.dim` |
| `TextInput` | the typed text | `style`, else the default text style (unpainted) |

API changes this needs:

- `Border.style` becomes `Style?`, default `null` (= the theme's); the
  constants (`Border.single`, `.rounded`, …) carry `null`. `withStyle` is
  unchanged. `DecoratedBox` resolves it from `Theme.of(context)` when it
  creates and updates its render object, so `RenderDecoratedBox` always gets
  a concrete style.
- `KeyHelp.keyStyle` becomes `Style?` (default null); `descriptionStyle` is
  new.
- `TextInput` gains `cursorStyle`, `placeholderStyle`, `prefixStyle`, all
  `Style?` (Flutter's `cursorColor`, `hintStyle`, `prefixStyle`).
- No widget focuses its border by itself in this slice; `theme.focus` is for
  the app (the demo uses it on the prompt).

## Unit 6: the demo

The demo shows the theme and lets you switch it with a key.

- The header is ` chorded-tui demo ` in `accent` bold, and at the right edge
  what the terminal said: `dark, from the terminal`, `light, from COLORFGBG`,
  `dark: the terminal did not say` (chord's `/theme` wording), and `, no
  colour` under NO_COLOR.
- The log box's border is the theme's (no style given); the prompt box's is
  `theme.focus`. The cell counts under ctrl+o are `warning`; the spinner is
  `accent`.
- ctrl+o (Toggle details) also shows a row of swatches, one word per role in
  its own style: `accent link code success warning error  + added  - removed`,
  the last two on the diff tint.
- **ctrl+t, `Theme`**: cycles auto → dark → light → plain → auto, by wrapping
  the demo in its own `Theme`, which is the override path. KeyHelp lists it;
  the header then reads e.g. `light (ctrl+t)`.
  Under NO_COLOR every choice draws plain, since NO_COLOR wins over
  everything, and every label keeps `, no colour`: `light (ctrl+t), no
  colour`. The header's right label sits in an `Expanded`, right-aligned,
  and ends in `…` when it does not fit; the title keeps its place. Dropping
  it whole needs an overflow that hides, a `LayoutBuilder` or a
  `MediaQuery`, none of which the framework has yet: a candidate for a
  later task, out of this slice.

At 120x40, dark terminal, after typing two lines and ctrl+o (colours in
brackets, shown here only):

```text
[accent,bold] chorded-tui demo                                                                         dark, from the terminal
╭ log ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮ [244]
│ accent link code success warning error  + added  - removed                                                           │
│ 1 hello                                                                                                     5 cells  │
│ 2 日本語 🙂                                                                                                  9 cells  │
│                                                                                                                      │
…
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮ [focus]
│> █ay something                                                                                                       │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
 [bold]ctrl+o[dim] Toggle details  ctrl+t Theme  ctrl+x b Toggle busy  ctrl+x c Clear  ctrl+q Quit
```

At 80x24 the same (every label fits beside the title there; a narrower
screen ends the label in `…`, title first), and KeyHelp ending in `…` as
now:

```text
 chorded-tui demo                                        dark, from the terminal
╭ log ─────────────────────────────────────────────────────────────────────────╮
│ accent link code success warning error  + added  - removed                   │
…
 ctrl+o Toggle details  ctrl+t Theme  ctrl+x b Toggle busy  ctrl+x c Clear  c…
```

States to check in tmux: a dark pane, a light pane (`window-style bg=white`,
which tmux 3.6 answers OSC 11 with), a pane with no style (no answer: dark,
`the terminal did not say`, first frame after 100 ms), `COLORFGBG='0;15'` on a
silent pane (light, from COLORFGBG), and `NO_COLOR=1` (no colour anywhere,
cursor and selection inverse, border dim). Typing during start-up must leave
no `11;rgb:` in the prompt.
