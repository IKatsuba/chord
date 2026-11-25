# CTUI-17: prompt and TextArea viewport notification

The original is `../chord/src/ui/prompt/Prompt.tsx`, `prompt.ts`,
`history.ts` and `queue.ts`. CTUI-7 defines editing and row geometry;
CTUI-15 defines queue withdrawal and cancellation; CTUI-16 defines the
transcript and middle overflow. Those contracts continue to apply.

## U1: let a sibling follow the actual viewport

Add one optional parameter to TextArea. Keep its border and gutter outside,
as CTUI-7 specifies. The immutable TextAreaLayout and TextAreaRow are
already public; add no second row model, gutter widget or controller.

```dart
TextAreaLayout? viewport;

// Inside the prompt State's build; the surrounding Row reserves the gutter.
TextArea(
  controller: draft,
  autofocus: true,
  maxHeight: promptRows(windowRows),
  onLayoutChanged: (layout) => setState(() => viewport = layout),
  onSubmit: send,
  onEdge: walkHistory,
  onKey: walkUntouchedRecall,
)

// New TextArea parameter, default null:
final void Function(TextAreaLayout layout)? onLayoutChanged;
```

The call site illustrates the callback, not a standalone prompt widget.
The prompt's Row contains a fixed two-cell gutter and Expanded TextArea.
The gutter reads viewport.shownRows; before the initial callback it may
reserve one blank row. One pump/frame must settle the initial gutter.
Do not call controller.layout from the prompt to guess the viewport.
Ancestor height constraints can give the area fewer rows than maxHeight.

The callback follows the existing onChanged naming and receives the actual
layout snapshot. It runs in the existing post-layout notification phase,
never inside layout or paint, so a parent may setState to rebuild a sibling.
The existing bounded second layout settles that sibling before paint.
No polling, timer or new frame scheduler is introduced.

Notify once after the first layout of a mounted area, then only when the
snapshot's public values change: width, height, rowOffset, cursorRow,
cursorColumn and the complete row data (text, line, piece, last, start,
end). Compare contents, not snapshot/list identity. An identical relayout,
a callback's setState and focus-only styling must not cause another call.
Changes to offscreen row metadata still count; consumers may read rows.

The callback observes a settled snapshot and may read controller.lastLayout,
which must describe that same viewport at delivery. It does not imply a text
edit: geometry/cursor changes must not call onChanged. Keep existing
controller listeners and lastLayout semantics working without the callback.
A missing callback changes nothing. Each area still accepts one controller.

A replacement controller gets an initial notification for its own layout,
even when it has identical geometry. A newly installed/replaced non-null
callback gets the current settled snapshot once after layout. A pending
notification for an old controller/callback must not reach it after
replacement, callback removal or unmount. Mutating the controller in a
callback must not recurse; subsequent geometry is published through the
normal bounded frame mechanism. Snapshots already delivered remain stable.

Zero width/height reports the actual zero-size layout and empty shownRows,
with no invented visible row. Restoring space publishes the restored view.
Unbounded width retains TextArea's existing error. maxHeight retains its
positive constraint and default 10. No new focus or key behavior belongs to U1.
This is terminal layout; no package trial is needed.

### Port mapping

Use TextAreaLayout.rowOffset as the original textarea.scrollY. Every
shownRows entry already has zero-based logical line, wrapped piece and
last (last row of the entire buffer). Empty text with room has one empty
row, line 0, piece 0, last true. A wrapped continuation retains its logical
line and increments piece. Preserve CTUI-7's full-width cursor row and
Unicode behavior; do not rewrap in the gutter.

Port gutterMark exactly: line 0/piece 0 gets `›`; otherwise the earliest
shown row gets `↑`; otherwise the latest shown row gets `↓` if not last;
otherwise blank. This priority matters when only one row fits: `›`, then
`↑`, wins over `↓`. `›` uses normal text and the arrows use dim text.
The gutter always occupies two cells, including blank and continuation rows.

### Required focused tests

Use the existing TextArea widget test file and name cases for the behavior:

- `onLayoutChanged publishes the initial viewport in one pump`
- `a sibling gutter settles with wrapping scrolling and resize`
- `onLayoutChanged reports actual constrained height and zero space`
- `onLayoutChanged reports source line piece last and rowOffset`
- `identical relayout and focus changes do not repeat the callback`
- `offscreen row edits publish without geometry changes`
- `layout notifications do not call onChanged`
- `replacing controller or callback publishes only the current viewport`
- `removed callbacks and disposed areas receive no pending notification`
- `a callback edit does not recurse and old snapshots stay unchanged`

At 120x40 and 80x24, a runnable framework fixture must show a sibling
marker column through empty, wrapped, scrolled and resized states. Developer
hands its command and commit to designer before reviewer. The fixture may
extend example/text_area.dart; it must demonstrate the new callback rather
than introducing port data into the framework.

## U2: undo and redo

The original PROMPT_KEYS binds ctrl+z to undo and ctrl+y to redo. Add those
edits to the TextArea/controller unit, through Actions with descriptions
`Undo` and `Redo`, visible to KeyHelp alongside the other editing actions.
The lead settled one undo step per text-changing edit: a typed grapheme,
a paste, a newline, or each delete/cut. Undo and redo restore the cursor
with the text. A new edit clears redo; there are no branches. Cursor moves
and no-op edits add no step and keep redo. Replacing the whole text through
the controller clears both stacks. Keep the last 100 steps.

History recall and submit replace the text, so they clear undo, as the
original's setText does. Cover individual typing steps, newline, paste,
delete/cut, empty stacks, cursor restoration, redo clearing after a new edit,
redo preservation after moves/no-ops, whole-text replacement and the 100-step
limit. Keep TextInput unchanged. No vim or reverse history search enters
this slice.

## Prompt box: copy the original

PromptInput without a child-agent name draws a full-width rounded dim border
(`╭─╮`, `│`, `╰─╯`), one blank row above it, one cell of horizontal
padding inside each edge, and the fixed two-cell gutter before TextArea.
There is no vertical padding. Content width is window width minus six:
114 cells at 120 columns and 74 at 80. Editable rows grow from one to
promptRows = min(10, max(3, floor(windowRows / 3))): ten at 120x40 and
eight at 80x24, additionally clamped by actual available space. Cursor is a
steady block; unfocused input has identical geometry without cursor styling.
No scrollbar is drawn. The border does not become bright on focus.

The following source-derived mocks show the original's prompt region and
the intended port identically; they are not observed runtime captures.
Rows above/below this region belong to the window and are omitted.
`▉` denotes a styled blank cursor cell, not a literal glyph. Runtime pairs
at both full pane sizes are required when the screen unit is handed over.

### 120x40: original / intended port

Original (source mock)

```text

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ › Build a keyboard-first prompt.▉                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

Port (target mock)

```text

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ › Build a keyboard-first prompt.▉                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

### 80x24: original / intended port

Original (source mock)

```text

╭──────────────────────────────────────────────────────────────────────────────╮
│ › Build a keyboard-first prompt.▉                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
```

Port (target mock)

```text

╭──────────────────────────────────────────────────────────────────────────────╮
│ › Build a keyboard-first prompt.▉                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
```

### States and keys

Empty/focused: the gutter shows `›` and a blank cursor occupies the first
editable cell. Do not invent placeholder wording. Multiline/wrapped: only
the first visual row shows `›`, continuation gutters stay blank until a
scroll edge needs an arrow. Overflowing: show `↑` on the first visible
row if earlier rows are hidden, `↓` on the final visible row if later rows
are hidden, and blank interior gutters. Narrow: rewrap at the available
editable width, preserve graphemes and logical cursor, then derive arrows
from the newly settled viewport. Zero space draws no gutter rows.

Enter submits; Shift+Enter, Alt+Enter, Ctrl+Enter and Ctrl+J insert a line;
a backslash before Enter continues a line. Up/Down move through visual
rows, handing edges to history; untouched recalled text walks history from
any row. Ctrl+C clears a nonempty draft. Esc interrupts the running turn
and restores queued prompts oldest first before the draft, separated by LF.
Ctrl+Z/Y undo/redo. All named actions have Actions descriptions and appear
in the shortcuts panel; editing aliases retain CTUI-7 behavior.

The queue is dim below the working line and plan, above the prompt's top
margin, with one-cell outer padding and the same two-cell gutter. It uses
queueRowLimit and queueRows from the original: first logical line with ` …`
for multiline text, oldest entries first, `… +N more` when capped; long
text uses TextOverflow.middle. Preserve a header whole before truncating
its text, as Prompt.tsx does. CTUI-19 adds the plan and status/working lines;
its spinner is the original's three `›`, not the board's older `✻`.

No visual difference from the original is authorized here. Slash commands,
mentions, bash, steering, ctrl+r, vim, images, the `?` hint and children's
named top border stay outside this slice. Any newly observed mismatch or
undo policy not settled by the original goes to the lead.

## Runtime evidence handover

Save U1 and prompt captures under docs/design/evidence/CTUI-17/ and optional
CTUI-19 captures under its own evidence directory. For each handed-over
screen unit, capture its named command and the original fake/QA state at
120x40 and 80x24, with color captures when styling is in question. Record
commit, command, state and any deliberate differences; omit private paths.
Designer hands a passing unit with evidence to reviewer, never tester, and
kills all owned tmux sessions and fake processes after each check.

## U11a: app theme extensions

CTUI-19 needs the original's mode colors and spinner mark palette. They are
chord data, so no framework role is named plan, edits, auto, bash or mark.
Add a small typed extension collection to ThemeData. Existing Theme,
Theme.backgroundOf and Theme.noColorOf supply the resolved environment;
there is no second background probe or theme-selection setting.

### Framework API

```dart
/// Immutable theme values declared by an app, looked up by their type.
abstract class ThemeExtension<T extends ThemeExtension<T>> {
  const ThemeExtension();
  Type get type => T;
}

// Additional ThemeData constructor parameter:
Iterable<ThemeExtension<dynamic>> extensions = const []

// Additional ThemeData public members:
Map<Type, ThemeExtension<dynamic>> get extensions;
T? extension<T extends ThemeExtension<T>>();

// Additional copyWith parameter:
Iterable<ThemeExtension<dynamic>>? extensions
```

Export ThemeExtension through chorded_tui.dart. Store a defensive,
unmodifiable map built once at construction, keyed by extension.type, not
runtimeType. An app type extends ThemeExtension<AppTheme>; a specialized
subclass can replace the same AppTheme slot. Duplicate keys in one supplied
collection throw ArgumentError, including in release mode. This catches
an ambiguous app palette at its declaration. Missing type returns null.
Different extension types coexist without casts at the call site.

The ThemeData constructor becomes non-const to snapshot caller collections;
all existing named arguments/defaults retain their meaning. This explicitly
supersedes only CTUI-3's const ThemeData constructor shape. No current call
site constructs const ThemeData; const Theme and the other theme value
classes remain usable. Preserve dark/light/plain/fallback factory defaults;
no factory needs another parameter because copyWith supplies extensions.

copyWith without extensions preserves the map's entries. A supplied iterable
replaces the entire collection, including an empty iterable clearing it.
Do not merge implicitly or inherit missing types from an ancestor Theme.
The nearest Theme owns a complete ThemeData as before.

ThemeData equality/hash include extension keys and values, independent of
insertion order. Values use their own ==/hashCode; identity equality is the
default. An extension-only change must notify Theme dependents, while an
equal replacement must not. Extension authors keep fields and nested lists
immutable and may implement value equality. Framework copies the registry,
not arbitrary app objects.

No abstract copyWith or lerp is required on ThemeExtension: this framework
swaps whole immutable themes and has no AnimatedTheme or interpolation
consumer. App value classes may add copyWith if they need it. Avoid making
every app write unused interpolation or identity-copy methods. A later
animation feature can add an optional contract when it has a consumer.

### Port call site and brightness

The following shape belongs to example/chord, not lib/:

```dart
final class ChordTheme extends ThemeExtension<ChordTheme> {
  const ChordTheme({
    required this.plan,
    required this.edits,
    required this.auto,
    required this.bash,
    required this.markTone,
    this.markStops,
  });

  final Style plan, edits, auto, bash;
  final Color? markTone;
  final (Color, Color, Color)? markStops;

  // dark/light/plain are immutable app palette values.
}

// In an app theme wrapper below runApp's resolved Theme:
final base = Theme.of(context);
final palette = Theme.noColorOf(context)
    ? chordPlain
    : base.brightness == Brightness.light ? chordLight : chordDark;
return Theme(
  data: base.copyWith(extensions: [palette]),
  child: child,
);

// A descendant:
final palette = Theme.of(context).extension<ChordTheme>();
```

ChordTheme is an illustrative app name; developer may keep an existing
port naming convention. The palette values are declared once in the port.
The wrapper uses the currently resolved base ThemeData brightness, so an
explicit light theme and an auto-selected light theme take the same light
extension. NO_COLOR wins over that selection through Theme.noColorOf.
A plain extension has Style.plain mode roles, null markTone and null stops.
The framework cannot remove colors from arbitrary app fields; applications
must provide the plain extension just as they provide their custom roles.
The port must not silently fall back to a dark colored palette when its
extension is missing: supply the wrapper to every window/fixture consumer,
and use a plain fallback if an intentionally unwrapped consumer needs one.

Keep original dark/light values from ../chord/src/ui/theme/theme.ts:

| Role | Dark | Light |
| --- | --- | --- |
| plan | #48968c | #006b66 |
| edits | #af87ff | #7a3fd6 |
| auto | #ffd700 | #8a6100 |
| bash | #fd5db1 | #d1006f |
| mark stops | #d2ffe4, #3fdc9c, #0a7470 | #1e9a5e, #147d55, #0a5e57 |
| mark tone | greenBright | green |

Use existing framework colors for the named tones. statusColour keeps
plain unpainted; bypass/error/ended use existing error, low/failed/waits
existing warning. Only the four missing modes use the extension. Working
text still uses base accent. spinnerMarks remains port logic: three `›`,
four steps; with stops, the lit mark takes stop 0 and others stop 2 without
dim; with one tone, non-lit marks are dim; with no tone, the same dim rhythm
uses terminal foreground. The middle stop remains available for other app
mark consumers but is not used by this spinner. No gradient interpolation,
spinner timer or chord-specific mark count enters lib/.

### States, screen and actions

U11a is data and inheritance only; it draws nothing, binds no keys and adds
no shortcuts. Existing empty, focused, narrow and overflowing geometry is
unchanged. At 120x40 and 80x24 the future U11 working/status fixtures must
keep identical text/positions while switching dark/light/plain values.
Observe dark/light status modes and lit/dim spinner styles in ANSI captures;
plain/NO_COLOR captures must contain no explicit foreground/background
colors from the extension and must preserve the spinner's dim rhythm.
No additional theme selection action is introduced by this unit.

### Required focused tests

Framework theme tests, with two small app-declared extension types:

- `theme extensions are looked up by declared type`
- `a missing theme extension returns null`
- `duplicate extension types are rejected`
- `theme extensions snapshot input and expose an unmodifiable map`
- `copyWith preserves replaces and clears extensions`
- `theme equality and hash include extensions independent of order`
- `an extension-only theme change rebuilds dependent widgets`
- `equal extension collections do not notify dependents`
- `the nearest theme does not merge ancestor extensions`
- `dark light plain and fallback factories keep empty extensions by default`

Port tests in U11 verify app selection from resolved dark/light brightness,
explicit theme choice, NO_COLOR plain selection and missing-extension plain
fallback; exact original mode values and spinner stops/rhythm; a mounted
palette change; no foreground/background color in plain status/spinner cells.
No package is needed for immutable typed theme data or inheritance.
