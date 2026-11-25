# CTUI-10: rebinding keys at run time, and grouped key help

The design ship 29 builds for CTUI-10 (units U2 and U3), with CTUI-31's
keybindings file (U4, U5) on top of it, and the place of CTUI-31's vim
reducer (U8). Owner's decision this sits under: `docs/decisions.md`, "No
code generation for actions". The original is
`../chord/src/ui/shortcuts/bindings.ts` and `docs/guide.md`, "Keybindings".

## What it is for

Keys stay bound where they are today: `Actions` with `Binding(keys,
description, onInvoke)`. Two things are added to the framework, and nothing
else:

- a binding can carry a stable **id**, and a **`Keymap`** widget above the
  `Actions` scopes moves, adds or removes keys by that id at run time;
- **`KeyHelp` groups** the keys of one action into one entry, so a step bound
  to `pageup` and `shift+pageup` takes one entry, not two.

The framework knows no file, no contexts, no action names of chord's, no
reserved keys and no wording of warnings. Those are the port's (below).

## The call site

```dart
// The app's bindings, as today, with ids on the ones a person may move.
Actions(
  bindings: [
    Binding('ctrl+o', 'Toggle details', toggle, id: 'app:toggleTranscript'),
    Binding('ctrl+q', 'Quit', quit), // no id: cannot be moved
    ...scrollBindings(controller), // ids scroll:pageUp … scroll:bottom
  ],
  child: ...,
)

// Above them, once, what the person's file made of the defaults.
Keymap(
  data: KeymapData({
    'app:toggleTranscript': [Chord.parse('ctrl+t')], // moved
    'scroll:pageUp': [Chord.parse('pageup'), Chord.parse('ctrl+u')], // added
    'scroll:top': [], // removed
  }),
  child: app,
)
```

A Flutter reader sees `Theme`/`ThemeData` and `MediaQuery`/`MediaQueryData`:
an inherited widget carrying an immutable data object, read with
`Keymap.of(context)`.

## The API

### `Binding`

```dart
Binding(String keys, String description, void Function() onInvoke,
    {bool enabled = true, String? id});

final String? id;
Binding copyWith({Chord? chord, String? description,
    void Function()? onInvoke, bool? enabled});
```

- `id` names the action, not the key: `'chat:submit'`, `'scroll:pageUp'`.
  Several bindings (one per key) share one id. A binding without an id
  cannot be moved by a keymap; that is how a key is kept fixed (chord's
  ctrl+c and ctrl+d).
- `keys` stays as today: one key or a chord of keys separated by spaces,
  `Chord.parse`'s spelling. Nothing new is parsed.
- `copyWith` keeps the id; it is how a rebound binding is made from the
  default one.
- `scrollBindings` gives its six steps the ids `scroll:pageUp`,
  `scroll:pageDown`, `scroll:lineUp`, `scroll:lineDown`, `scroll:top` and
  `scroll:bottom`, which are also the original's (and Claude Code's) names,
  so the port's `Scroll` context needs no mapping.

### `Keymap` and `KeymapData`

```dart
/// Moves the keys of identified bindings for every Actions under it.
class Keymap extends InheritedWidget {
  const Keymap({super.key, required this.data, required super.child});
  final KeymapData data;
  /// The nearest keymap's data; an empty one when there is none.
  static KeymapData of(BuildContext context);
}

/// Keys by binding id: what a keymap makes of the bindings it covers.
@immutable
class KeymapData {
  const KeymapData([Map<String, List<Chord>> keys = const {}]);

  /// The keys of [id], or null when the keymap leaves it as bound.
  /// An empty list unbinds it.
  List<Chord>? keysFor(String id);

  /// [bindings] with this keymap applied, and the keys it could not bind.
  ({List<Binding> bindings, List<KeymapConflict> conflicts}) apply(
      List<Binding> bindings);
}

/// A key the keymap gave [id] that clashes with another binding of the
/// same scope, and was left out.
@immutable
class KeymapConflict {
  final String id;
  final Chord chord;
  final Binding other; // what holds the key
  final bool prefix;   // true when one chord starts the other
}
```

The map holds **final** keys per id, not edits: the port's reader turns
the file's "this key does that, `null` takes it away" into each touched
action's whole key list (as the original's `readKeybindings` turns it
into a `Keymap` of bindings). An id absent from the map keeps its
defaults. An id the map names that no binding carries does nothing.
Inner `Keymap` replaces an outer one whole, as `MediaQuery` does; there is
no merge.

`KeymapData` is `==` by content, so `updateShouldNotify` is
`data != oldWidget.data`.

### `apply`, the one rule

`apply` is pure, and `Actions` calls it on its `bindings` before it checks
and registers them:

1. In order, each binding whose id the keymap names is replaced, at the
   place of the **first** binding with that id, by one `copyWith(chord: c)`
   of that first binding per chord `c` of `keysFor(id)`, in the keymap's
   order; later bindings of the same id are dropped. An empty list leaves
   none. Bindings without an id, or whose id is not in the map, are kept
   as they are.
2. Each binding made in step 1 is checked against every other binding of
   the result as `checkBindings` checks them (same chord, or one chord the
   start of the other). A clash drops the **keymap's** binding and records
   a `KeymapConflict`; the binding it clashed with keeps the key. Between
   two keymap-made bindings, the later one in the list is dropped.
3. What is left goes to `checkBindings`, which still **throws** for two
   bindings the app itself wrote that clash. A programmer's error stays an
   error; a person's file never throws.

### `Actions`

Reads `Keymap.of(context)` with a dependency, so a new keymap re-registers
its scope (`didChangeDependencies`, as `_parentNode` is already read there).
It registers `apply(widget.bindings).bindings` on its node and **does not
report** the conflicts: the app that wants them calls the same `apply` on
the same list and gets the same answer. That is the "reported as data, not
thrown" rule, with nothing new to listen to and no callback fired during a
build.

### Lookup by id

Nothing new in `FocusManager`. Matching, pending chords, `matchKey`,
`activeBindings` and `KeyHelp` read the node's registered bindings, which
are already the rebound ones, so every one of them sees the moved keys
with no change. A binding's `id` is on every snapshot, so "the key bound to
X right now" is `fm.activeBindings.where((b) => b.id == X)`, and "the key X
would have" (for a hint naming a key not live this moment) is the port's
own keymap plus its defaults.

A keymap that changes while a chord is half pressed leaves the pending
keys as they are; the next key is matched against the new bindings and
dropped if nothing continues it. The bindings epoch already makes a
running dispatch stale. (chord reads the file once, at start, so this
case is only kept correct, not designed for.)

## `KeyHelp` groups bindings (U3)

One entry per action: bindings with the same `id`, or with no id and the
same description, are one entry, at the place of the first of them, keys
joined by `/` in their order. `/`, not a space, because a space already
separates the keys of one chord (`ctrl+x a`).

```dart
/// The keys of one action, as one entry of key help.
@immutable
class BindingGroup {
  final List<Binding> bindings; // in order; never empty
  String get description;       // the first binding's
  String? get id;
  List<Chord> get chords;
}

/// [bindings] grouped by id, else by description, in first-seen order.
List<BindingGroup> groupBindings(List<Binding> bindings);
```

- `KeyHelp()` draws `groupBindings(activeBindings)`.
- While a chord is pending, a group shows only its chords that start with
  the pending keys, and is left out when none does; the `ctrl+x …` lead-in
  is unchanged.
- `KeyHelp.builder` keeps its signature (`BuildContext, List<Binding>,
  List<KeyCombo>`); a builder that wants groups calls `groupBindings` on
  the snapshot. The snapshot carries ids, so the port's `?` panel can name
  each catalog row's bound keys from it.

### What it draws

`example/key_help.dart` gains the plain `KeyHelp()` line under its builder,
page keys with their shift twins, and `--rebound`, which wraps the app in
`Keymap(data: KeymapData({'app:quit': [Chord.parse('ctrl+q')]}))` over
`Binding('q', 'Quit', …, id: 'app:quit')`. Mocks of the line alone:

120x40, today, then grouped, then `--rebound`, then ctrl+x pressed:

```text
ctrl+x a Complete chord  q Quit  pageup Scroll up a page  shift+pageup Scroll up a page  pagedown Scroll down a page  s…
ctrl+x a Complete chord  q Quit  pageup/shift+pageup Scroll up a page  pagedown/shift+pagedown Scroll down a page  home…
ctrl+x a Complete chord  ctrl+q Quit  pageup/shift+pageup Scroll up a page  pagedown/shift+pagedown Scroll down a page …
ctrl+x …  ctrl+x a Complete chord
```

80x24, the same four:

```text
ctrl+x a Complete chord  q Quit  pageup Scroll up a page  shift+pageup Scroll u…
ctrl+x a Complete chord  q Quit  pageup/shift+pageup Scroll up a page  pagedown…
ctrl+x a Complete chord  ctrl+q Quit  pageup/shift+pageup Scroll up a page  pag…
ctrl+x …  ctrl+x a Complete chord
```

Keys bold in the theme's text, descriptions dim, the `/` in the key style:
as today. States: no bindings draws an empty line; focused/unfocused
changes nothing but which bindings are active; overflow ends in `…` as
today; narrow is the same rule.

### Keys

None added. The keymap moves keys; it binds none of its own.

## What stays in the port

- **The file** (`~/.config/chord/keybindings.json`), its contexts,
  `ACTIONS` with their defaults, the original's key spellings (`esc`,
  `return`, `control`, `opt`, `meta` as alt, `cmd`, `ctrl++`), the reserved
  keys, the removed `session:*` actions, the context-overlap rule
  (`Global` and `Scroll` against every context) and every warning's
  wording: `lib/ui/shortcuts/bindings.dart` (U4), a pure port of
  `bindings.ts`, whose output is the per-action key lists that become one
  `KeymapData`, plus the problems as strings.
- **Contexts** are not a framework thing. The window binds a context's
  actions only while that context is live (as it binds the code-pick keys
  only while picking today), so one key in two contexts (tab:
  `chat:steer` and `autocomplete:accept`) is never two bindings in one
  scope. The reader's overlap rule catches what a person can break; the
  framework's `apply` is the backstop, and U5 calls it on the window's
  bindings at start and reports any conflict it returns with the reader's
  problems.
- **Dispatch by action.** Today the window's bindings call
  `keySteps(Chord.parse(key))`, deciding by the key's spelling, which a
  moved key would break. U5 makes each binding carry its action id and
  decide by it.
- **The catalog and the `?` panel**: `lib/ui/shortcuts/keys.dart` names
  each row's bound keys from the keymap (`actions`, `before`, `after`,
  `first`, `also`, as `keys.ts` does), in the panel's own spelling
  (`ctrl + g`, `↑`). Hints use the first bound key in hint spelling.
- **Warnings** in the transcript, on stderr and counted on the status
  line, as `keybindingsNotice` words them.

## U8: a vim normal mode in the framework

Main's decision (it replaces this doc's first recommendation, that the
reducer stay the port's): the normal-mode reducer is the framework's, pure,
over the text area's editing value, because a vim normal mode over a text
field is generic. It is our own: the original plays its keys on
`@replit/codemirror-vim-core`, which has no Dart port. What it does is
pinned by porting `../chord/tests/ui/prompt/vim_test.ts`. chord's routing
stays in the port: `/vim`, the `-- INSERT --` / `-- NORMAL --` line, Esc
passing through to the window in normal mode, keys normal mode does not
take being dropped, and `editorMode` in the settings.

### The names

`lib/src/foundation/vim.dart`, exported from `chorded_tui.dart`:

```dart
/// Which of vim's two modes a field is in.
enum VimMode { insert, normal }

/// What `p` puts back: the last text deleted or yanked.
@immutable
class VimRegister {
  const VimRegister(this.text, {this.linewise = false});
  final String text;
  final bool linewise;
}

/// Vim's state beside a field's text: plain data, kept by the caller.
@immutable
class VimState {
  const VimState({
    this.mode = VimMode.insert,
    this.pending = const [],
    this.register,
    this.goalColumn,
    this.lastFind,
  });
  final VimMode mode;
  final List<String> pending;   // a command still being typed: '2', 'd'
  final VimRegister? register;
  final int? goalColumn;        // where j and k aim, kept between keys
  final String? lastFind;       // the last f F t T and its character, as 'fq': what ; and , repeat
  VimState copyWith({...});
}

/// The text and where the cursor is, in graphemes, as TextAreaController
/// counts them.
typedef VimValue = ({String text, int cursor});

/// Widens a deletion [start, end) that cuts into an atom to take the whole
/// of it; returns the range unchanged when it cuts into none.
typedef VimAtoms = (int, int) Function(String text, int start, int end);

/// What one key did in normal mode.
@immutable
class VimStep {
  final VimState state;
  final VimValue? value;            // null: text and cursor unchanged
  final bool taken;                 // false: not normal mode's key
  final TextAreaDirection? edge;    // k on the first line, j on the last
  final bool undo;                  // `u`: the caller undoes
}

/// One key in normal mode. [key] is one character, or `left`, `right`,
/// `up`, `down` or `backspace`, as KeyCombo names them.
VimStep vimStep(VimState state, VimValue value, String key, {VimAtoms? atoms});

/// Esc in insert mode: normal mode, the cursor one back, as vim leaves it.
VimStep vimEscape(VimState state, VimValue value);

/// The key normal mode would read [event] as, or null.
String? vimKeyOf(KeyEvent event);

/// The keys normal mode takes: the original's NORMAL_KEYS, and the arrows
/// and backspace.
const vimNormalKeys = 'hjklwbeWBE0123456789\$^xXdcyDCYsSiaIAoOupP~;,fFtTrJ';
```

`taken` follows the original's `vimTakes`: a key in `vimNormalKeys`, or
any key after `f`, `F`, `t`, `T`, `r`, or after an operator's `i`/`a`.
A key that starts insert mode (`i a I A o O s S c…`) returns
`state.mode == VimMode.insert`, with the value its edit made (`o`'s new
line). A command the reducer cannot carry out clears `pending` and changes
nothing, as the original drops it.

### Atoms

`atoms` is called for every deletion (`x X d c s S D C`, and what `J`
joins) with the range about to go; the reducer deletes the range it
returns, and the register holds that text. The port passes the
`[Image #N]` rule it already has for backspace and ctrl+w
(`placeholderBefore`), turned into a range: a range touching a placeholder
grows to cover all of it. Nothing else in `lib/` knows of placeholders.

### Undo

The reducer keeps no undo stack: `u` returns `undo: true`, and the caller
calls `TextAreaController.undo()`, then puts the cursor where normal mode
may stand (on a character, not past a line's end). One normal-mode command
is one controller edit, so it is already one undo step. Insert mode is
many edits, and vim undoes it as one, so `TextAreaController` gains:

```dart
/// Edits until [endUndoGroup] undo as one step: the text before the first.
void beginUndoGroup();
void endUndoGroup();

/// The whole text and cursor at once, as one edit undo takes back. Setting
/// [text] is a reset and clears the undo stack, so a step's value goes in
/// through this.
void replace(String text, int cursor);
```

The caller begins a group when a step enters insert mode (before it
applies that step's value, so `o` and what is typed after it go together)
and ends it on Esc. Ctrl+z in the area undoes groups the same way.

`TextAreaDirection`, which a step's `edge` carries, lives in
`foundation/text_editing.dart` beside the controller, so the pure
reducer imports no widget; its public name and export are unchanged.

### How a text area uses it

No new `TextArea` parameter. The caller keeps a `VimState` and uses the
existing `onKey` (it sees each key before the area edits):

```dart
TextArea(
  controller: draft,
  onEdge: walkHistory, // what a step's edge calls
  cursorStyle: vim.mode == VimMode.normal
      ? CursorStyle.steadyBlock : CursorStyle.steadyBar,
  onKey: (event) {
    if (vim.mode == VimMode.insert) {
      if (!event.matches('escape')) return false;
      apply(vimEscape(vim, (text: draft.text, cursor: draft.cursor)));
      return true;
    }
    final key = vimKeyOf(event);
    if (key == null) return false;
    final step = vimStep(vim, (text: draft.text, cursor: draft.cursor), key,
        atoms: wholePlaceholders);
    if (!step.taken) return false; // the port drops typed ones here
    apply(step); // value into draft, undo, edge, groups, new state
    return true;
  },
)
```

`apply` is a few lines of the caller's. The port adds the routing above
(Esc in normal mode to the window, untaken characters dropped). A second
user writes its own. A `vim:` parameter on `TextArea` can come when a
second user wants the same routing.

## Tests the units owe

- `apply`: move, add, remove, order kept at the first binding's place,
  duplicates of one id collapsed, unknown id ignored, a keymap key
  clashing with a fixed binding dropped and reported (same and prefix),
  two keymap keys clashing (later dropped), app-written clash still
  throws.
- `Actions` under a `Keymap`: a moved key invokes, the old key does not; a
  moved chord goes pending on its first key; a new `Keymap` re-registers;
  `KeyHelp` and the builder snapshot show the moved keys.
- `groupBindings` and `KeyHelp`: twins in one entry, `/` joined, pending
  filtering inside a group, a group with no matching chord left out, at
  120x40 and 80x24.
- `vimStep` and `vimEscape`: `vim_test.ts` ported case for case over
  `VimValue`; atoms widening a cut into `[Image #1]`; `edge` at the first
  and last line; `undo` returned, not applied.
- `TextAreaController` undo groups: edits in a group undo as one, an
  empty group adds no step, ctrl+z and `u` agree.
