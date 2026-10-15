# CHD-172 — interface draft

The screen, its states and keys, and where the state lives, for chord's own
selection. Everything below was run on OpenTUI 0.6.0 in a scratch copy of
the tree (rsync'd into a mktemp directory, `node_modules` linked), with
`selectable: true` and `selectionBg: RGBA.fromIndex(66)` in `TEXT`
(`src/ui/theme/text.ts`) and on the textarea (`src/ui/prompt/TextArea.tsx`),
and a `renderer.on('selection', …)` that appended `getSelectedText()` to a
file in that directory. No clipboard was written by the spike: nothing in it
copies, and Claude Code was only ever held mid-drag and killed, never
released. The scratch copy is gone; `git status` is clean but for this
folder.

Drags were SGR reports typed into a tmux pane (`send-keys -l`): a press
`ESC[<0;x;yM`, motion `ESC[<32;x;yM` row by row, a release `ESC[<0;x;ym`;
a wheel step `ESC[<64;x;yM`. Captures are `capture-pane -e`, saved beside
this draft as `spike-interface-*.txt`, each with the raw rows, the rows with
the `48;5;66` cells between `⟦ ⟧`, and the text OpenTUI gave on release.

## In short

| Question | Answer |
| --- | --- |
| Does OpenTUI's selection draw? | Yes, as it is: a drag paints the cells it covers, live, in the `selectionBg` given, `48;5;66` exactly as Claude Code's. Double click selects a word, triple click a line, for nothing. |
| Per text? | Yes: `selectable` and `selectionBg`/`selectionFg` are per renderable (`TextBufferRenderable`, `EditBufferRenderable`). There is no renderer-wide default colour. |
| Selectable | The transcript's content and the draft; not gutters, the mark, borders, the status line, lists, boxes. |
| Copy key | Owner's. Recommended: ctrl+c copies while a selection is held (widget key, every terminal), plus a rebindable `selection:copy` defaulting to ctrl+shift+c. |
| The note | Owner's. Recommended: `copied 54 chars to clipboard`, CHD-31's slot, alone, 3 s. |
| `selectHint` | Goes. The bypass modifier moves to the README and the guide only. |
| Lifetime | OpenTUI's model as it is (the lead's merge): while the button is down the view stops following; a wheel step during a held drag scrolls and extends the selection; plain scrolling keeps it. After release it stays until a key, a click, a new drag, a tab switch, `/clear`, ctrl+o or a resize clears it; the copy key copies and clears on success (section 4). |
| State | `app/state.ts`'s window half: `selection` and `copied` in place of `selectHint`; pure `app/selection.ts` in place of `drag.ts`. |

## 1. What OpenTUI's selection does (the spike)

How it works, read from `@opentui/core`'s renderer and confirmed by the
runs: a left press on a renderable whose `selectable` is true and whose
`shouldStartSelection(x, y)` agrees starts a `Selection` whose **anchor is
held relative to the renderable it started on** (`SelectionAnchor`, so it
moves with the content) and whose **focus is a screen cell**, the pointer's
last report; each motion report moves the focus and asks every
selectable renderable inside the selection's container (the start's parent,
widened as the pointer leaves it) to take its local part; the release emits
`selection` on the renderer; the highlight stays after release. A press on
something not selectable (a box, a border, empty space) starts nothing. A
ctrl+press extends an existing selection. A single click emits `selection`
with empty text (spike-interface-triple-click.txt), so a copy must skip
empty text.

What it gave, case by case:

| Case | Highlight | Text on release | Capture |
| --- | --- | --- | --- |
| A reply chord's markdown wrapped (a list item over two rows) | The cells covered, hanging indent included | The two rows with a `\n` and the indent between: chord's markdown lays text out to the width itself, so the copy is the screen's lines, and differs at 80 and 120 columns | `80-wrapped` |
| A prompt row OpenTUI wrapped (`wrapMode: 'word'`) | The cells covered | One line, the wrap joined with its space: `f an eighty column terminal ` | `80-softwrap` |
| Markdown table and code block | Text cells; the blank row between blocks not | Box-drawing characters included (they are the reply's text); the blank row between the blocks dropped | `table` |
| Diff | Line number and code, each its own run | `1+ /** Greets…`: the line number, then the sign and code, the space between the two renderables gone | `diff` |
| Folded terminal output | `⎿`, the shown lines, `… +2 lines (ctrl+o to expand)`, `Exit code 1` | Exactly what is drawn: the fold marker, not the hidden lines; `⏺Run(…)`, `⎿3/3`, gutter glyphs glued to the text | `fold` |
| The header | Mark and text both | `▀▀▀▄fake · Fake Large…`: the mark's half blocks, glued to the text with the gap gone | `header` |
| The prompt box's border | Nothing; a drag from it starts no selection | — | (border press) |
| The draft (textarea) | The cells covered | `draft I am sti` | `prompt` |
| Transcript into the draft | Both, the `›` gutter not | `The tests failed.\na Xll typin` | `cross` |
| The status line | The cells covered | Empty: CHD-31's hint replaced the line on release, and a text whose content changes under a selection loses its part | `status` |
| Streaming, following | The selected rows moved up off the captured area with the content (the anchor's renderable moved; the focus stayed at the pointer's cell, so the range grew) | Lines 93–97: the anchored content up to the pointer, as OpenTUI defines it | `stream-held`, `stream-later` |
| Scrolled back, wheel while held | Moved 3 rows with the content (anchor and parts kept); the next motion report recomputed the range from the anchor, now 3 rows lower, to the pointer's cell | One row: from the moved anchor to the pointer, which is what the highlight showed after that report | `wheel-held`, `wheel-motion` |
| End while a selection was shown | Gone (the held entries unmounted for the tail) | — | — |
| ctrl+o while shown | Stayed (nothing moved in that case) | — | — |
| No `selectionBg` | OpenTUI swaps fg and bg: default-foreground text becomes `38;2;0;0;0` on the default background, unreadable on a dark terminal | — | `no-selection-bg` |
| `selectionBg` = default fg, `selectionFg` = default bg | Written as SGR 39/49: nothing shows | — | `default-colours` |

Two things it does that chord has to decide about, beyond what to make
selectable:

- **Typing over a textarea selection replaces it.** After a drag over the
  draft, `X` turned `a draft I am still typing` into `a Xll typing`
  (`prompt`). It is an editor's selection: a key, backspace or a paste acts
  on it. With auto-copy on, a person who drags over the draft to copy it and
  then types loses part of the draft. Owner question 3.
- **The textarea clears the whole selection on its own edits.** Typing into
  the draft cleared a transcript selection too (OpenTUI's textarea calls
  `renderer.clearSelection()` on insert and on plain cursor moves). That is
  what chord wants anyway (section 4), but it means chord does not own the
  moment the highlight goes; it can only agree with it.

Keyboard selection comes along: with the textarea selectable, OpenTUI's
shift+←/→ (and shift+home/end where nothing claims them first) select in
the draft. shift+↑/↓ and shift+home/end are chord's `scroll:*` bindings,
heard before the textarea. It is the non-goal "unless OpenTUI gives it for
nothing and it does no harm": it is free, and the harm is the same as a
drag's, typing replaces it. It goes with owner question 3.

Claude Code 2.1.300, opened in tmux with a draft typed and no prompt sent,
paints its draft on `48;5;66` under a held drag too
(`spike-interface-claude-code-prompt.txt`); what a key does after was not
tried, as a release copies to the real clipboard.

## 2. What is selectable

OpenTUI takes `selectable` per text, so chord says it per text. `TEXT`
becomes selectable and takes the palette's selection colour; a second
constant (`CHROME` in `text.ts`) keeps `selectable: false` for what is not
content. The rule: **what the agent or the person wrote is selectable;
chord's furniture is not.**

| Selectable | Not selectable |
| --- | --- |
| A prompt's text, a message's text | The `›`, `←`, `⏺`, `⎿` and `├─` gutters |
| A reply, a thought, a note, a report (`/cost`, `/context`, `/status`) | The header's mark (the header's lines stay selectable: the path is worth copying) |
| A tool call's headline text, its `⎿` lines' text, terminal output, a diff's code with its sign | A diff's line numbers; the `… +N lines (ctrl+o to expand)` marker |
| A compaction's summary, the plan's record in the transcript, a shell run's command and output | The working line, the status line, the leader line, the queue rows |
| The draft (owner question 3) | The prompt box's border, the plan list above the prompt, the agents list |
|  | Pickers, the permission box, forms, the question box, the link box, the shortcuts panel, the splash |

Why each "not": a gutter or a line number glued to the text is what makes
`⏺Edit(…)` and `1+ /**` (`diff`, `fold`); the mark copies as half blocks
glued to the version line (`header`); the status line changes under the
selection and copies empty (`status`); the lists and boxes take keys and
move. Making the gutters unselectable is also what keeps the copy free of
the gap OpenTUI drops between two renderables on one row: with the gutter
out, the row's text is one renderable.

What stays as it is, and is said here so nobody is surprised:

- A markdown reply copies as chord laid it out: wrapped rows with a `\n`
  and their hanging indent, table and code-block borders included, as the
  terminal's own selection of chord's screen would. Joining the rows back
  would mean either rewriting the copied text (a workaround around
  OpenTUI's `getSelectedText`, not chord's call) or letting OpenTUI wrap
  replies instead of `markdown.ts`. Owner question 6.
- A blank row between two blocks of a reply is dropped from the copy
  (`table`), as OpenTUI joins renderables by row and a margin is no text.

## 3. The prompt box

- **A drag inside the textarea** selects the draft with OpenTUI's textarea
  selection, painted the same, and is the same copy: it is one renderer
  selection, and `getSelectedText()` reads it as any other.
- **A drag from the transcript into the draft** selects both (`cross`);
  chord lets it, as OpenTUI does. A drag from the draft up into the
  transcript is the same selection reversed.
- **The border and the `›` gutter** start nothing.
- **A key after a selection in the draft**: owner question 3. The
  recommendation is that a key that clears the selection (section 4) clears
  it before the textarea hears the key, through `renderer.clearSelection()`,
  OpenTUI's own public call, so a key never replaces selected text. That is
  chord choosing when its selection ends, not changing what the textarea
  does with one; but since it decides what a key does to a library widget's
  state, the owner should say so.
- **A bracketed paste with a selection in the draft**: OpenTUI's textarea
  replaces the selected text with the paste, as an editor does. Under the
  recommendation the paste clears the selection first and goes in at the
  cursor, where the drag's focus left it; an empty paste (ctrl+v's image
  read) clears it too and puts `[Image #N]` at the cursor. With a selection
  only in the transcript, a paste clears it and pastes as always. Owner
  question 3 covers both.

## 4. When the highlight goes

OpenTUI's model as it is, which the lead merges from runtime's tests:

| Event | Selection | And the event |
| --- | --- | --- |
| The button down | Started | The view stops following until release (section 5) |
| A wheel step while the button is held | Extended: OpenTUI's `requestSelectionUpdate` moves the focus over the new rows | Scrolls |
| Release, `copyOnSelect` on | Copied, and **kept**, so the person sees what went | — |
| Release, `copyOnSelect` off | Kept, waiting for the copy key | — |
| A wheel step, pgup/pgdn, shift+↑/↓, home, end after release | Kept: the anchor moves with its renderable | Scrolls |
| New output | Kept | As always |
| The copy key | Copied; cleared once the copy succeeds, kept if it fails (section 6) | Nothing else |
| A chord's first key (a prefix a live chord waits on) | Kept | Waits for the next key |
| Any other key, a chord's miss included, Esc included | Cleared | Does what it always does: Esc still interrupts on the same press |
| A click, a new drag | Cleared (OpenTUI's own), a new drag starts a new one | — |
| A tab switch, `/clear`, ctrl+o, a resize | Cleared | As always |

Esc is not special. Taking the first Esc to clear a selection would mean a
turn cannot be interrupted while something is highlighted without two
presses, and with copy-on-select a highlight is left behind by every copy.

### The dispatch order with a selection

`keyAnswer` → `pressCommand` → `boundCommand` today reads the window's
sessions first, then the sessions picker (`Select`), the agents list
(`Agents`), a form, the search line, then the `Chat` keys, with
`Confirmation` and `Help` answered by their widgets and `Global` and
`Scroll` heard wherever another is (`ALWAYS`). With a selection, a press
goes through these steps, the first that answers winning:

1. **The copy key.** `pressed` (the pending chord's keys and this one)
   completing `selection:copy` in the new `Selection` context, live only
   while a selection exists and heard before every other context, Global's
   sessions included: `copy_selection`. So a rebound chord such as
   `ctrl+x y` works: its `ctrl+x` is step 3's prefix, its `y` completes it
   here.
2. **ctrl+c with no chord pending**: `copy_selection`, in front of every
   context: over the sessions picker's and the Chat keys' clear or quit, a
   form's interrupt (`Confirmation` and a form are open: ctrl+c copies, the
   turn goes on), the search line's cancel and the agents list. The
   highlight on screen is what says ctrl+c will copy.
3. **A prefix.** `pressed` is the start of a live chord, `selection:copy`'s
   or any other (`ctrl+x` of the sessions' leader): `key_pending`, and the
   selection is **kept**, so a chord the person has begun can still be the
   copy.
4. **Everything else**, as `boundCommand` answers it today, Global's
   sessions, `Select`, `Agents`, a form, `Confirmation`'s choices, `Help`'s
   Esc, `HistorySearch`, `Chat`, `Scroll`, with a `clear_selection` step
   played first, except for the scroll steps, which keep it as the wheel
   does. A chord's miss (`key_dropped`) is a key too: it clears. A press that
   answers nothing (typing into the draft or a form) clears before the
   textarea or the field takes it.

`keys_test.tsx` gets the copy key in each context: with the permission box,
a form, a picker, `?` and the agents list open, and ctrl+x y rebound.

## 5. The transcript while the button is down

CHD-327 D holds the mounted window from its first entry while the view is
scrolled back, so new output never unmounts what is on screen. A held drag
asks for the same: **from the press until the release, the transcript is
held as if scrolled back**; following pauses, new output goes below with
CHD-12's `── ↓ new output ──` rule, and nothing above unmounts. After the
release the view is as the person left it: a view that was following
before the press stays where it was until they scroll or press end, as
after any scroll back. This is the interface's side of runtime's questions
2 and 3, whose answers the lead merges.

A drag past the transcript's top or bottom edge does not scroll it (Claude
Code's auto-scroll at the edge is not in this task); the wheel is the way
to extend a selection past what is on screen.

## 6. The status line

### The copied note

Placed where CHD-31's hint was: after an armed line, the closing line and a
failure; before the sessions note and `Starting…`. Vim's `-- INSERT --` or
`-- NORMAL --` still comes first. It **stands alone**, as the hint did, so
the model and usage give way and nothing cuts it at 80 columns. Dim, the
status line's hint style (no colour role): a copy is news, not a warning.
It lasts **3 s** on the timer `timers.ts` ran for the hint; another copy
restarts it. A copy of empty text says nothing.

The words are owner question 2. The count is of what the person would
count, graphemes (`Intl.Segmenter`, built in); Claude Code's is likely the
string's `.length`, which differs only for emoji and combined marks.

### A copy, in order

The same steps for the copy key and for a release with `copyOnSelect` on:

1. **Capture**, synchronously, in the press's (or the release's) own
   handler: `renderer.getSelection()?.getSelectedText()`. Empty text ends it
   here: no copy, no note, and an empty selection (a click's) is cleared.
2. **Keep the highlight** while the copy is out; the status line says
   nothing new yet. The text going is the one captured, whatever happens
   to the selection meanwhile.
3. **Success**: the copy key's selection is cleared, a release's is kept
   (section 4), and the note says the count. If a key cleared the selection
   while the copy was out, the note still says it.
4. **Failure**: the selection is **kept** whatever started the copy, so the
   copy key tries again on the same text, re-captured; the failure line
   says so. A second copy while one is out is ignored, as its result is
   still coming.

### When the copy fails

The failure slot, in the `error` role, standing alone, as ctrl+v's
`pasteFailed` is, and cleared as that one is by the next key, which, if it
is the copy key, tries again: `could not copy: <reason> · ctrl + c to try
again`, with protocol's reasons (`the clipboard did not answer`, `too
large to copy`) and the key named from the bindings. The longest,
`could not copy: the clipboard did not answer · ctrl + c to try again`, is
68 columns, inside 80's 76. When only OSC 52 was written and nobody can
know whether it took, the note is protocol's question 4; the recommended
words are `sent 54 chars to the terminal's clipboard`.

### `copyOnSelect` off

Release copies nothing; the selection waits. While it does, the status
line's hint slot (where `? for shortcuts` is) says `ctrl + c to copy`, dim,
with the key named from the bindings as `hintKey` names the others; the
model and usage stay. The copy key then copies as above: the note, and
the selection cleared once the copy succeeded.

### `selectHint` goes

With chord's own selection a drag no longer fails to select, so a hint
after a drag has nothing to explain. `selectHint`, its `TerminalEnv` read in
`main.tsx`, its state counter and its timer go. The bypass modifier
(option in iTerm2, fn in Terminal.app, shift elsewhere) is still the way to
the terminal's own selection, and the README's paragraph and the guide say
it; the panel has no row for it at 80×24 (section 8). Owner question 4.

## 7. The copy key

What each candidate costs, from what the terminals deliver:

| Key | What arrives | Cost |
| --- | --- | --- |
| ctrl+shift+c (Claude Code's) | Under the kitty keyboard protocol (kitty, Ghostty, WezTerm, foot, iTerm2 with CSI u on), a distinct `ctrl+shift+c`. Without it, byte `0x03`: ctrl+c. GNOME Terminal, Konsole, and kitty and Ghostty on Linux bind it to their own copy and never pass it on. | Where it arrives as ctrl+c it clears the draft or arms a quit: a person following Claude Code's habit in Terminal.app loses their draft. |
| cmd+c | Taken by every macOS terminal for its own copy; never reaches chord. | Cannot be chord's key. |
| ctrl+c while a selection is held | `0x03` in every terminal; the kitty protocol's ctrl+c too. | Overloads ctrl+c: with something highlighted, ctrl+c copies instead of clearing the draft or stopping the turn. The highlight shows which it will do; a second ctrl+c does the usual. Windows Terminal and VS Code's terminal do the same. ctrl+c is reserved (`RESERVED` in `bindings.ts`), so this is a widget key, not a binding. |
| A leader key (`ctrl+x y`) | Everywhere. | Nobody would guess it. |
| `y`, enter | Typed into the draft. | Not possible while the prompt has the keys. |

Recommended, for the owner: ctrl+c while a selection is held, and a new
rebindable action `selection:copy` defaulting to `ctrl+shift+c`, in a new
`Selection` context heard before every other while a selection exists
(section 4's dispatch order). Then
ctrl+shift+c copies everywhere: as itself where the kitty protocol tells it
apart, as ctrl+c where it does not. A person who rebinds `selection:copy`
gets their key beside ctrl+c.

## 8. The shortcuts panel

One line, `ctrl + c to copy`, after `home end for the top and the bottom`,
with the transcript's keys, in the words the status line's hint uses. Its
entry in `keys.ts` is `{ key: 'ctrl + c', does: 'to copy', commands:
['copy_selection'], actions: ['selection:copy'], also: 'ctrl + c' }`, with
ctrl+c in `presses`: while `selection:copy` keeps its default the line is
`key` as written, so ctrl+shift+c, the same press as ctrl+c on most
terminals, is not named; once it is rebound, `shortcuts()`'s existing
`also` rule names the bound keys, then `or ctrl + c`.
`tests/ui/shortcuts/keys_test.tsx` gets ctrl+c-with-a-selection as a
widget-owned key and `selection:copy` as an action.

Computed, not drawn by hand: a scratch script (run with `bun`, as the
module resolves only under the project's own runtime, then deleted) took
`shortcuts()` and `shortcutLine` from `src/ui/shortcuts/keys.ts`, put
the line after `home end …`, and asked `columnCount` and `inColumns`:

| The line | 80 columns | 120 columns |
| --- | --- | --- |
| (today, no line) | 2 columns, 20 rows | 3, 13 |
| `ctrl + c to copy` (default) | 2, 20 | 3, 14 |
| `ctrl + y or ctrl + c to copy` | 2, 20 | 3, 14 |
| `ctrl + x y or ctrl + c to copy` (a chord) | 2, 20 | 3, 14 |
| `ctrl + shift + c or ctrl + c to copy` | 2, 20 | 3, 14 |
| `ctrl + x y ctrl + shift + y or ctrl + c to copy` (two keys bound) | **1, 40** | 2, 20 |
| `ctrl + c or ctrl + x y to copy a selection` (the earlier wording) | **1, 40** | 2, 20 |
| `ctrl + c to copy` and a bypass line (41 entries) | 2, 21 | 3, 14 |

The first column may be 37 wide at 80 (2 + 37 + 3 + 38); a longer line
drops the panel to one column. So the words are `to copy`, not `to copy a
selection`, which with a rebound key already does not fit. The one case
left, two keys bound to `selection:copy` (`shortcuts()` names at most
two), gives one column of 40 rows, which at 80×24 runs off the bottom
below the prompt box, the same as any other action rebound to two long
keys today; read from the layout, not run. If the owner wants it closed,
this entry can name only the first bound key, which keeps every case
above but the two-key one at 2 × 20.

40 entries are 20 rows at 80 columns, as today: **no new row at 80×24**. A
bypass line as well would be 21 rows, which at 80×24 takes the
transcript's last row, so nothing of it is left while `?` is open.

## 9. Where it lives

- **The selection itself** stays OpenTUI's: the renderer's `Selection`,
  painted by each selectable text and the textarea. No component of
  chord's draws it; there is no OpenTUI component to add.
- **`src/ui/app/state.ts`, the window's half** (one for every session, as
  the armed lines are): `selection?: 'held' | 'shown' | 'copying'` (button
  down; released and still highlighted; a copy out, which a second copy
  waits on) in place of `selectHint`, and
  `copied?: { chars: number; via: 'clipboard' | 'terminal'; id: number }`
  for the note and its timer. It is the window's because a tab switch clears
  it and because more than one feature reads it: the transcript holds its
  view on it while the button is down, the status line says the note, the
  keys clear it. The transcript slice (`transcript/state.ts`) takes
  `'held'` only as the reason its view stops following, as `scroll.ts`
  already takes being scrolled back.
- **`src/ui/app/selection.ts`, pure**, in place of `drag.ts`: the
  renderer's events to actions (a non-empty `selection` event on release
  with `copyOnSelect` on is a copy; an empty one is nothing); the note's
  words and the grapheme count; which events clear the selection
  (section 4). Tested without a terminal.
- **`src/ui/app/state.ts`'s `keyAnswer`** and **`src/ui/app/keys.ts`**:
  section 4's dispatch order; `copy_selection` and `clear_selection` as
  steps, the latter played before the key's own.
- **`src/ui/app/App.tsx`** wires the renderer's `selection` event and
  `clearSelection()` as hooks beside `useMouse` (in `input.ts`), and the
  copy through protocol's injectable clipboard service in `terminal.ts`.
- **`src/ui/status/status.ts`**: the note, the failure and the
  `ctrl + c to copy` hint in their slots.
- **`src/ui/theme/theme.ts`**: a `selection` role in every palette, PLAIN
  included (NO_COLOR): OpenTUI has no reverse-video selection, and with no
  colour given its swap makes text black on the default background
  (`no-selection-bg`); the terminal's default colours swapped draw nothing
  (`default-colours`). Proposed: `ansi256(66)` in the dark themes, and a
  light slate such as `ansi256(152)` in the light ones, to be checked by
  hand on a light terminal. `text.ts`'s `TEXT` then needs the palette, so
  the selection colour comes from `useColours()` where texts are drawn, or
  `TEXT` becomes a function of the palette.
- **`src/ui/shortcuts/bindings.ts`**: `Selection` in `CONTEXTS`,
  `selection:copy` in `ACTIONS`; **`keys.ts`**: the panel's line.

## 10. Screens

`⟦ ⟧` marks the cells painted in the `selection` role (`48;5;66` in the
dark theme); the brackets take no cell. Other roles as today: `⏺` in
`accent` while running and the text's own colour after, diff signs in
`diff.added`/`diff.removed`, the border in `DIM_BORDER`, the status line dim.
The header's path is the scratch directory's.

### A drag in progress, 120×40

The button is held; the status line has not changed. The `⎿` gutter is not
painted, as it is not selectable.

```
 ▀▄     chord v0.54.1
 ▀▀▀▄   fake · Fake Large with a 1M context window
 ▄▀▀▀   /private/tmp/chd172-iface.QvZA
 ▀▀     ? for shortcuts · /help

 › edit

 ⏺ Edit(src/greeting.ts)
   ⎿  ⟦Updated src/greeting.ts with 2 additions and 1 rem⟧oval
      1 + /** Greets someone by name. */
      2   export function greet(name: string): string {
      2 -   return "hello " + name;
      3 +   return `hello, ${name}`;
      4   }

 ⏺ Edited.

 › shell

 ⏺ Run(deno task test)
   ⎿  3/3
      ok | 2 passed
      FAILED | 1 failed
      … +2 lines (ctrl+o to expand)
      Exit code 1

 ⏺ The tests failed.










╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                Fake Large with a 1M context window · medium effort · 1% context used
```

### After the release, `copyOnSelect` on, 120×40

The highlight stays; the note stands alone for 3 s.

```
   ⎿  ⟦Updated src/greeting.ts with 2 additions and 1 removal⟧
…
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  copied 54 chars to clipboard
```

### `copyOnSelect` off, a selection waiting, 120×40

```
   ⎿  ⟦Updated src/greeting.ts with 2 additions and 1 removal⟧
…
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ctrl + c to copy                               Fake Large with a 1M context window · medium effort · 1% context used
```

### The copy failed, 120×40

The highlight is kept, so the copy key tries again; the line is in
`error` and stands alone.

```
   ⎿  ⟦Updated src/greeting.ts with 2 additions and 1 removal⟧
…
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  could not copy: the clipboard did not answer · ctrl + c to try again
```

### The copy failed, 80×24

```
   2. ⟦Commit on main once every check has passed and the tree is clean, so⟧
   ⟦  whoever picks the work up next starts from a build that runs.⟧
…
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  could not copy: the clipboard did not answer · ctrl + c to try again
```

### Streaming with a selection, 120×40

The view was following; the press stopped it, and after the release it
stays where it was, as after any scroll back. New output goes below the
rule (`accent`), and the selection, anchored to its rows, is kept.

```
   162. Line 162 of 200, streamed one at a time.
   ⟦163. Line 163 of 200, streamed one at a time.⟧
   ⟦164. Line 164 of 200, strea⟧med one at a time.
   165. Line 165 of 200, streamed one at a time.
…
 ── ↓ new output · end to jump to the bottom ──────────────────────────────────────────────────────────────────────────
 ››› Working… (9s · esc to interrupt)

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  copied 87 chars to clipboard
```

### A drag in progress, 80×24

A markdown reply chord wrapped at 80: the copy keeps its two rows.

```
   │ const turn = session.prompt('hello');                        │
   │ await turn.result;                                           │
   └──────────────────────────────────────────────────────────────┘

   That is the whole loop. To land a change:

   1. Run the checks:
     ┌ sh ─────────────┐
     │ deno task check │
     └─────────────────┘
   2. ⟦Commit on main once every check has passed and the tree is clean, so⟧
   ⟦  whoever picks the work up next starts from a build that runs.⟧

   Then build the binary with:

   ┌ sh ─────────────────────────────────────────────────┐
   │ deno task compile --all                             │
   │ for bin in dist/*/chord; do echo "built $bin"; done │
   └─────────────────────────────────────────────────────┘

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts       Fake Large with a 1M context window · medium · 1% used
```

### After the release, 80×24

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  copied 132 chars to clipboard
```

With vim on: `  -- INSERT -- copied 132 chars to clipboard`.

### `copyOnSelect` off, 80×24

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ctrl + c to copy      Fake Large with a 1M context window · medium · 1% used
```

### A selection in the draft, 80×24

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ › a ⟦draft I am sti⟧ll typing                                                  │
╰──────────────────────────────────────────────────────────────────────────────╯
  copied 14 chars to clipboard
```

### The shortcuts panel, 120×40

One row more than today, the new line at the foot of the first column.

```
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  enter to send                           / for commands                       ctrl + x then a key for sessions
  \ + enter for a newline                 ↑ ↓ to pick a command                1–9 to pick a choice
  shift + enter for a newline             tab to complete a command            ↑ ↓ or j k to move between choices
  ctrl + g to edit in $EDITOR             @ for files                          enter to pick the highlighted choice
  ctrl + v to paste an image              ↑ ↓ to pick a file                   esc to reject a permission
  ↑ ↓ for prompts, agents and monitors    tab enter to add a file              esc to close a picker
  x to close an agent or stop a monitor   esc to close commands or files       ctrl + a to show all directories
  ctrl + r to search prompts              ! for bash mode                      tab ← → ↑ ↓ space to answer forms
  tab enter to take a match               backspace to leave bash mode         ctrl + c to stop the turn and its form
  esc to cancel a search                  esc to interrupt or stop a command   /vim for vim mode
  pgup pgdn or wheel to scroll            shift + tab to cycle modes           ? for shortcuts
  shift + ↑ ↓ to scroll a line            ctrl + o for verbose output          esc to close shortcuts
  home end for the top and the bottom     ctrl + c to clear input
  ctrl + c to copy                        ctrl + d or ctrl + c twice to quit
```

### The shortcuts panel, 80×24

Still 20 rows: the new line takes the first column's twentieth place,
which the second column had one more of.

```

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  enter to send                           esc to close commands or files
  \ + enter for a newline                 ! for bash mode
  shift + enter for a newline             backspace to leave bash mode
  ctrl + g to edit in $EDITOR             esc to interrupt or stop a command
  ctrl + v to paste an image              shift + tab to cycle modes
  ↑ ↓ for prompts, agents and monitors    ctrl + o for verbose output
  x to close an agent or stop a monitor   ctrl + c to clear input
  ctrl + r to search prompts              ctrl + d or ctrl + c twice to quit
  tab enter to take a match               ctrl + x then a key for sessions
  esc to cancel a search                  1–9 to pick a choice
  pgup pgdn or wheel to scroll            ↑ ↓ or j k to move between choices
  shift + ↑ ↓ to scroll a line            enter to pick the highlighted choice
  home end for the top and the bottom     esc to reject a permission
  ctrl + c to copy                        esc to close a picker
  / for commands                          ctrl + a to show all directories
  ↑ ↓ to pick a command                   tab ← → ↑ ↓ space to answer forms
  tab to complete a command               ctrl + c to stop the turn and its form
  @ for files                             /vim for vim mode
  ↑ ↓ to pick a file                      ? for shortcuts
  tab enter to add a file                 esc to close shortcuts
```

### Other states

- **Empty session.** A drag over the header's lines selects them; over the
  mark or empty rows it starts nothing.
- **Waiting on the person** (permission, form, question, link box open). A
  drag over the transcript above selects as usual; the box itself is not
  selectable. ctrl+c with a selection copies rather than stopping the turn
  and its form (section 4, step 2); the highlight is on screen to say so,
  and once the copy succeeds and clears it, ctrl+c stops the turn again.
- **`?` open.** The panel is not selectable; at 80×24 it covers the
  transcript, so there is nothing to drag over but the draft.
- **`"mouse": false`.** OpenTUI gets no mouse modes, so no press reaches it
  and no selection can start; the terminal selects as before. Nothing else
  changes; `copyOnSelect` is then moot.
- **Light terminal.** The `selection` role's light colour, checked by hand.

## Owner questions

Undecided; each with options and a recommendation.

1. **The copy key.**
   - a. ctrl+c while a selection is held (widget key, not rebindable, every
     terminal), plus `selection:copy` defaulting to ctrl+shift+c,
     rebindable, in a new `Selection` context. *(recommended)*
   - b. ctrl+shift+c only, as Claude Code. Without the kitty protocol it
     arrives as ctrl+c and clears the draft or arms a quit; on Linux many
     terminals keep it for their own copy.
   - c. A leader key, `ctrl+x y`, rebindable, everywhere; nobody guesses it.
   - d. No key: `copyOnSelect` cannot be turned off.
2. **The note's words** (the setting's name and default are protocol's
   question 1; recommended there: `copyOnSelect`, default `true`, user's
   file only).
   - a. `copied 54 chars to clipboard`: Claude Code's, without
     `· disable auto-copy in /config`, as chord's `/config` is the agent's.
     *(recommended)*
   - b. `copied 54 characters`.
   - c. `copied 54 chars to clipboard · copyOnSelect: false to stop`, the
     tail naming the setting; long, and it stands alone at 80 columns.
   - And the count: graphemes *(recommended)*, or the string's length as
     Claude Code likely does.
3. **The draft: selectable, and what a key or a paste does after.**
   - a. Selectable; a key that clears the selection (section 4) clears it
     before the textarea hears the key, through
     `renderer.clearSelection()`, so a key never replaces selected text; a
     bracketed paste clears it first too and goes in at the cursor, an
     empty one's image placeholder with it; shift+←/→ keyboard selection is
     turned off with it, as its only use would be replacing.
     *(recommended)*
   - b. Selectable, an editor's selection as OpenTUI has it: typing,
     backspace or a paste replaces what is selected (a paste of text, or an
     empty paste's `[Image #N]`); shift+←/→ select.
   - c. Not selectable, as today; a drag over the draft selects nothing, and
     a drag from the transcript stops at the box.
4. **What replaces `selectHint`.**
   - a. Nothing: it goes, the README and the guide name the bypass
     modifier. *(recommended)*
   - b. The bypass hint after a drag only while `copyOnSelect` is off.
   - c. A panel line for it: 41 entries, 21 rows, which at 80×24 takes the
     transcript's last row while `?` is open (computed, section 8).
5. **Esc with a selection.**
   - a. Clears it and does its usual thing (interrupts, closes) on the same
     press. *(recommended)*
   - b. Clears it only; a second Esc interrupts.
6. **A reply's copy across chord's own wrapping.**
   - a. As laid out: a `\n` and the hanging indent where chord's markdown
     wrapped, borders of tables and code blocks included. *(recommended for
     this task)*
   - b. A follow-up task: replies wrapped by OpenTUI (`wrapMode: 'word'`)
     instead of `markdown.ts`, so a copy joins them as a prompt's does.
   - c. chord unwraps the copied text itself: a rewrite of
     `getSelectedText()`'s output, which the one rule keeps from being
     anyone's call but the owner's.
7. **The selection colour where colour is off (NO_COLOR) or the theme is
   the terminal's 16.**
   - a. A 256-colour slate anyway (`ansi256(66)`, light `ansi256(152)`):
     OpenTUI has no reverse video for a selection, and without a colour it
     draws text black. *(recommended)*
   - b. No selection at all there (`selectable` off), the terminal's bypass
     only.
