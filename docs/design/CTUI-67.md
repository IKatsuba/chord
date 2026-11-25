# CTUI-67: keys on a non-Latin layout

The behaviour is the original's (`../chord/docs/guide.md`, the paragraph on
the Russian layout and kitty's protocol; `src/ui/shortcuts/press.ts`,
`baseOf`; `src/ui/shortcuts/bindings.ts`, `layoutKeys`;
`src/ui/app/state.ts`, `keyAnswer`): a press that does nothing as typed is
read again as the key in the same place on the US layout, first as the
terminal names it, then by an app's table; a reading never types text, and
an editing widget never hears one. This file holds the framework's half.
The Russian table and where chord asks for readings are the port's.

Nothing here draws; there are no captures.

## What the terminal says: `KeyEvent.baseKey`

kitty's protocol with flag 4 ("report alternate keys") writes a key as
`CSI code:shifted:base ; mods u`, where `base` is the key in the press's
place on the PC-101 US layout, whatever layout is active. `ctrl+ч` on a
Russian layout arrives as `CSI 1095::120;5u`.

- `runApp` pushes `CSI > 5 u` (disambiguate | alternate keys) instead of
  `CSI > 1 u`; that is what the original's OpenTUI pushes (its defaults:
  `disambiguate` and `alternateKeys` on). The pop is unchanged.
- The parser, which already checks the alternate fields
  (`lib/src/input/parser.dart`, `_csi`), keeps the third one.
- The shifted field stays dropped: the key and `shift` already say it.

```dart
/// One key press.
final class KeyEvent extends InputEvent {
  const KeyEvent(
    this.key, {
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    this.superKey = false,
    this.hyper = false,
    this.meta = false,
    this.baseKey,
  });

  /// The key in this press's place on the US PC-101 layout, as a terminal
  /// speaking kitty's keyboard protocol names it: `x` for `ctrl+ч`. Null
  /// when the terminal named none, or named a control code or one of the
  /// protocol's private-use functional keys.
  final String? baseKey;

  /// The press as made on the US layout, with these modifiers; null when
  /// [baseKey] is null or reads as this very press.
  KeyEvent? get onBaseLayout;
}
```

`baseKey` is stored as the terminal sent it, lower-cased (a letter's case
is `shift`'s to say). `onBaseLayout` is the original's `baseOf` plus its
`keystrokeOf`:

- a letter keeps `shift`: shift+ф with base `a` is `shift+a`;
- any other key with shift held becomes what US PC-101 types there with
  shift, and the shift is spent: base `/` with shift is `?`, not
  `shift+/`. The table is the protocol's, not a layout's:
  `` `1234567890-=[]\;',./ `` over `~!@#$%^&*()_+{}|:"<>?`;
- every other modifier is kept as pressed.

Only a key the terminal encodes as `CSI … u` carries the field. Under
flags 1|4 a key that types text with no modifier but shift still arrives
as text, so in practice `baseKey` comes with ctrl, alt and super presses.
That is the original's reach too; it is not widened here.

`toString` adds `base x` when there is one. A legacy terminal never sets
it.

## The app's table: `KeyLayoutFallback`

```dart
/// The US keys a press of the single character [typed] would have been,
/// had the layout been US, most likely first; empty when it knows none.
typedef KeyLayoutFallback = List<String> Function(String typed);
```

It is given where `chordTimeout` is given, and goes to the focus manager:

```dart
runApp(const ChordApp(), layoutFallback: russianToUs);

AppHost(app, layoutFallback: russianToUs);
FocusManager(layoutFallback: russianToUs);
BuildOwner(layoutFallback: russianToUs);
```

Default none: an app that gives no table reads only `baseKey`.

- The framework calls it only for a key of one character (never `enter`,
  `f1`, `space`), and takes what it returns as they are; which characters
  it translates (the original leaves alone anything a US layout types
  itself, so `,` is never read as `?`) is the table's choice.
- Each string returned becomes a press of that character with the typed
  press's modifiers, normalized as a binding is: `A` is `shift+a`,
  `ctrl+ч` read as `x` is `ctrl+x`.
- The framework ships no table. chord's is the port's, in
  `example/chord/lib/ui/shortcuts/bindings.dart` beside the keymap file,
  as the original's `layoutKeys` (the `convert-layout` Russian–PC table,
  then Apple's ё on the backslash key). The package question for that
  table (`convert-layout` has no Dart port that I know of) is developer's
  to settle by the rule in AGENTS.md and to report.

## Readings, and the order of a press

```dart
/// The presses [event] is read as when it does nothing as typed: the
/// terminal's base-layout key first, then [layoutFallback]'s, without
/// repeats and without the press itself.
List<KeyEvent> readingsOf(KeyEvent event); // on FocusManager

/// The press as it was typed, when this event is a reading of it; null for
/// a press as the terminal sent it.
final KeyEvent? typed; // on KeyEvent
```

A reading is a `KeyEvent` whose `typed` is the press it was read from. Its
`char` is null whatever its key: a reading never types.

`FocusManager.dispatchKey` keeps its route (ancestor captures, then from
the focused node up: `onKey`, then that node's bindings) and adds one
rule: when the press went unhandled, each reading goes through the same
route, in order, and the first one handled ends it.

1. The press as typed, the whole route. Handled, or a chord begun: done.
2. Each of `readingsOf(event)`, the whole route again. Handled: done.
3. Nothing: `dispatchKey` returns false as today.

While a chord waits, a press that continues none as typed is tried as each
reading before the chord is dropped and the press swallowed, so `ctrl+x`
then `ф` finishes `ctrl+x a` (what waits on you).

An exact binding as typed always beats a reading, so a key a keymap file
binds in Cyrillic is its own.

### Editing widgets never hear a reading

```dart
Focus(
  ignoreLayoutReadings: true, // default false
  onKey: …,
  child: …,
)
```

`Focus.ignoreLayoutReadings` (and `FocusNode.ignoreLayoutReadings`): a node
that sets it is skipped for readings: its capture, its `onKey` and its own
bindings. The reading goes on to its ancestors. `TextArea`, `TextInput`
and the form's text fields set it. This is the original's
`textareaDid = !translated && …`: `ctrl+о` read as `ctrl+j` is the app's
to act on even though `ctrl+j` is the text area's own newline, and
`ctrl+ф` is never the text area's `ctrl+a`.

`Actions(ignoreLayoutReadings: true)` does the same for the bindings an
`Actions` registers. It is needed because `TextArea`'s own keys (`ctrl+a`,
`ctrl+j`) live on its `Actions` node, a parent of its `Focus` node, so the
flag on the focus node alone would let a reading of `ctrl+j` reach the
newline. `TextArea` sets both. (Added in building, CTUI-34 U5.)

Pickers, lists and scroll bindings do not set it: `ctrl+т` read as
`ctrl+n` moves a picker, as it does in the original.

### What a press that types text does

Text always gets the typed character. A text widget handles a typed
character in its `onKey` at step 1, so no reading is ever made of it:
`ф` typed in a prompt, a form, a search line or vim's insert mode is `ф`.
A reading has a null `char` and editing widgets skip it, so no reading
can put a US character into a box.

The one place the original lets a reading beat typing is chord's own: on
an empty prompt in a kitty terminal, the key in `?`'s place opens the
shortcuts panel instead of typing its `,`. That is a binding the port's
window already checks ahead of the text area in its key capture
(`help:toggle` on an empty draft); it asks `readingsOf(event)` there and
matches each through `matchKey`. The framework's order stays the
focused-widget-first order of Flutter.

`matchKey` is unchanged: it previews the press it is given. A caller that
wants a reading's match passes the reading.

## The tester

```dart
await tester.press('ctrl+ч');                 // as typed, no base key
await tester.sendKey(const KeyEvent('ч', ctrl: true, baseKey: 'x'));
```

`WidgetTester.sendKey(KeyEvent)` sends one event as built, for a base key;
`press` and `type` are unchanged. `pumpWidget` takes `layoutFallback`.

## The port's use, for reference

- `runApp(…, layoutFallback: layoutKeys)` with chord's table.
- The vim normal-mode handler returns false for a key it does not know,
  so `р о л д` reach their readings `h j k l`; after `f`, `t` or `r` it
  takes the typed character itself, as the original's `vimTakesCharacter`.
- The window's capture asks `readingsOf` where it matches by hand
  (`help:toggle` on an empty draft, the `_unshifted` path).

## Tests it needs

- Parser: `CSI 1095::120;5u` gives `ctrl+ч` with base `x`; `CSI 97;5u`
  gives none; a base in the private-use range or ≤ 0x20 gives none.
- `onBaseLayout`: letter keeps shift; `/` with shift is `?` without shift.
- Dispatch: an exact binding as typed beats its reading; base before table;
  a reading reaches an ancestor past a focused `TextArea`; a `TextArea`'s
  own `ctrl+j` does not fire on a reading; typed `ф` lands in a `TextArea`
  with a binding on `a` above it; a waiting chord finishes on a reading.
- `runApp` writes `CSI > 5 u`.

## Why

- Readings after the typed press, not before, is the original's
  `keyAnswer`, and it keeps every existing app's dispatch as it is.
- A flag on the focus node rather than a filter on bindings: the editing
  widget is what the original exempts, and the node is where its keys
  live.
- The table is a callback, not a map, because the original's returns more
  than one key for a character (Russian–PC's, then Apple's) and leaves
  ASCII alone by its own rule.
- Nothing here is a departure from the original.
