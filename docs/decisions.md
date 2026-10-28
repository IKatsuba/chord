# Decisions

Why the stack is what it is. Each entry was checked on a real machine before it
was written down; the date is when. A decision changes by adding an entry that
supersedes it, not by editing the old one.

## 2026-10-04 — Deno, compiled to one binary

chord is written in TypeScript on Deno and shipped as `deno compile` output for
five targets (`scripts/targets.ts`). The binary carries its own runtime, so
installing chord never installs Node, and npm is only the delivery channel: the
`@chorded/chord` package is a shim that execs the platform package's binary, as
esbuild and biome do. Checked: a binary with Ink, acpx and the ACP SDK compiles
(~110 MB on macOS arm64) and completes a real Claude Code turn.

## 2026-10-04 — acpx/runtime for everything below the interface

[acpx](https://github.com/openclaw/acpx) (MIT, pre-1.0) exports `acpx/runtime`:
an agent registry with pinned adapter versions, process start and stop,
persistent sessions on disk, permission policy and callbacks, prompt turns that
queue behind each other, cancel, modes, models, config options, status and usage,
and a normalised event stream. That is the whole client half of ACP that chord
would otherwise write and maintain. Checked under Deno 2.9.7, both `deno run`
and compiled: `ensureSession` + `runTurn` against `claude` streamed text, status
events and `done` with `end_turn`.

Consequences:

- acpx is pinned to an exact version (`0.19.4`), because it is pre-1.0 and says
  its runtime interface is evolving. Upgrades are deliberate and tested.
- Its normalised events drop detail some features need (subagents, terminal
  output, compaction). For those chord reads the raw JSON-RPC messages through
  `watchSession`, or the SDK directly — never by forking acpx.
- Session state goes in chord's own state directory, not `~/.acpx/`, so the two
  tools never fight over a session.
- acpx's default agent is Codex; chord's is Claude Code.

## 2026-10-04 — Ink for the interface

Superseded by "Moving to OpenTUI" (2026-10-10) and its parts: chord draws on
OpenTUI's React bindings, and the rejection of OpenTUI below no longer holds
now that chord runs on Bun.

Ink 8 (React for the terminal) renders a full-screen layout under Deno with
`alternateScreen: true` and `useWindowSize()`; checked in a pseudo-terminal and
in a compiled binary. It is also what Claude Code itself is built on, which
makes "looks and feels like Claude Code" a matter of layout rather than of
fighting the library. Ready-made Ink components (`ink-text-input`, `@inkjs/ui`)
are preferred over writing our own until one is shown not to fit.

Rejected: **OpenTUI** (`@opentui/core` 0.5.14, what OpenCode uses) — its native
Zig core loads over Bun's or Node 26's FFI and throws "OpenTUI native FFI is not
available for this runtime yet" under Deno. Worth re-checking if that changes.

## 2026-10-04 — Cliffy for the command line

The same command-line library quarry uses, so help, completions and errors look
alike across the family.

## 2026-10-04 — The session layer, and what acpx's in-process runtime leaves out

`src/session/` opens one persistent acpx session per chord session with
`createAcpRuntime` + `createFileSessionStore`, starts turns with `startTurn`,
cancels with `cancel`, and on close calls `close` then `shutdown`. acpx's
shutdown already ends the agent's stdin and escalates through SIGTERM and
SIGKILL, but within a fixed budget it gives up silently, and it reports the exit
to `processLifecycle.onExit` only afterwards. So chord counts an agent gone
only once `onExit` says so: it waits five seconds for that, sends SIGKILL, waits
two more, and if the exit is still not seen `close` rejects with
`AgentExitError` rather than claiming success. acpx's `onPermissionRequest` callback parks each request until
the interface answers it. Checked under `deno run` and in a compiled binary
against the fake agent.

- **State directory:** `$XDG_STATE_HOME/chord`, by default `~/.local/state/chord`
  on every platform, from [`xdg-basedir`](https://github.com/sindresorhus/xdg-basedir)
  (it reads the home directory at import, so tests need `--allow-sys`).
  `env-paths` was tried and passed over: it puts state under
  `~/Library/Application Support` on macOS, out of step with `~/.config/chord/`
  for settings.
- **Any agent command:** `chord <name> --agent-command "<command>"` hands the
  command to acpx's registry as an override for `<name>`; acpx splits it the way
  a shell would. `deno task chord:fake` uses it to run chord against
  `tests/fixtures/fake_agent/main.ts`.
- **The fake agent** is the ACP SDK's agent builder (`acp.agent()` over
  `ndJsonStream` on stdio), not hand-rolled JSON-RPC.

What acpx 0.19.4 does not give the in-process runtime, which supersedes the
`watchSession` route in the acpx entry above:

- `watchSession` exists only on `SharedAcpRuntime`, the client of the acpx
  command line's session owner; `AcpxRuntime` has none, and `onAcpMessage` is not
  among its options. There is no public route to the raw messages yet; the
  first slice that needs one decides it.
- `current_mode_update` arrives as a `status` event whose mode id is only in
  its text (`"mode updated: plan"`); the record keeps `current_mode_id`.
- `tool_call_update` events carry no title or kind (`title` is `"tool call"`):
  the transcript merges updates into the call by `toolCallId`.
- A permission is answered by option kind; acpx picks the first option of that
  kind, so two options of one kind cannot be told apart.
- A turn's `result` settles about a second after the agent's reply, while acpx
  waits for trailing updates (`SESSION_REPLY_IDLE_MS`).

## 2026-10-04 — emulon's code style

chord takes the formatting, lint and compiler settings of its sibling Deno
project emulon, so the family reads alike:

- **fmt:** 80 columns, single quotes, spaces inside braces, braces always, a
  single-statement body on its own line. Markdown and `docs/` stay unformatted.
- **lint:** `recommended` (with chord's `react` and `jsx` tags) plus
  `camelcase`, `eqeqeq`, `no-case-declarations`, `no-eval`,
  `no-inferrable-types`, `no-node-globals`,
  `no-non-null-asserted-optional-chain`, `no-throw-literal` and
  `single-var-declarator`.
- **`lint/style.ts`:** emulon's lint plugin, copied unchanged with its test. It
  covers what `deno fmt` cannot — it keeps blank lines but never inserts them —
  by requiring a blank line around declarations, control flow, exits, blocks and
  assignments, and imports before code. `deno lint --fix` inserts the lines;
  an import out of place is only reported.
- **compiler:** `strict`, `noUncheckedIndexedAccess` and
  `exactOptionalPropertyTypes`.

The tree was reformatted in one commit with nothing else in it; it is listed in
`.git-blame-ignore-revs` (`git config blame.ignoreRevsFile
.git-blame-ignore-revs` makes a local blame skip it).

## 2026-10-04 — The transcript reducer is chord's own

`src/session/transcript.ts` folds acpx's runtime events, together with what
the event stream does not carry (the prompt, permission requests and answers,
a cancel, the turn's result), into the state the interface draws. Neither
`acpx/runtime` nor `@agentclientprotocol/sdk` exports a transcript model:
acpx's own reducer persists usage and commands onto its session record and is
internal, and the SDK stops at the wire types. So this one is written here,
on acpx's event types and the SDK's tool-call types.

- A tool call's status only moves forward (`pending` → `in_progress` →
  `completed` / `failed`), so a late, repeated or early update cannot undo a
  finished call; the fake agent's `unordered` scenario sends all three.
- Title and kind come only from a `tool_call`; acpx titles every
  `tool_call_update` `"tool call"`.
- A turn is over at its `result`, not at its last event, since acpx settles
  the result about a second later. Under acpx 0.19.4 the event stream ends at
  the same moment as the result.
- `done` and `error` events are ignored: only `runTurn` emits them, and
  chord's `startTurn` turns report the same thing through `result`.

## 2026-10-04 — ink-spinner for the working line, and ink-text-input's ctrl keys

Superseded by "Moving to OpenTUI" (2026-10-10): the spinner is
`src/ui/status/Status.tsx`'s, a timer on cli-spinners' `star` frames (part
8a), and the box is OpenTUI's `<textarea>` (parts 2 and 3).

The `✻ Working… (12s · esc to interrupt)` line spins with
[`ink-spinner`](https://github.com/vadimdemedes/ink-spinner) and cli-spinners'
`star` frames (`✶ ✸ ✹ ✺ ✹ ✷`), the nearest of its sets to Claude Code's.
`@inkjs/ui`'s `Spinner` was the other candidate: it draws from the same
cli-spinners sets, so it would look the same, and it brings a theme layer for
one glyph. Neither takes custom frames. Checked under `deno run` and in a
compiled binary.

`ink-text-input` types the letter of every ctrl chord it does not know into
the draft (ctrl+d inserts `d`), and `@inkjs/ui`'s `TextInput` does the same.
Until the prompt input gets its own slice, chord puts the draft back after
ctrl+d on a non-empty prompt and remounts the input, the only way to reset its
cursor.

## 2026-10-05 — ink-select-input for the permission prompt

Superseded by "Moving to OpenTUI" (2026-10-10): the choices are chord's own
on OpenTUI's `<box>`, keyed as ink-select-input was (part 2).

The permission prompt's list is
[`ink-select-input`](https://github.com/vadimdemedes/ink-select-input) 6.2:
it reads 1–9 to pick an item directly, ↑/↓ (and j/k) to move the highlight,
and Enter to pick it, and takes custom indicator and item components, so the
list draws as Claude Code's `❯ 1. Allow`. Esc is not the list's: the window
reads it and rejects. Checked under `deno run` and in a compiled binary.

`@inkjs/ui`'s `Select` was the other candidate and was passed over: it has no
number keys and no numbering, so both would have been written here around it.

Ink attaches a component's key handler in an effect, after the frame that
shows the component is drawn. A key pressed in between still reaches the
prompt input, so the input drops edits while a permission is asked.

The transcript keeps an answered request as its own entry (the option chosen,
or none when Esc rejected it); a request withdrawn by a cancel leaves none,
since the turn's own `Interrupted` line says it.

## 2026-10-05 — Tool calls and thinking are drawn here, and ctrl+o is one toggle

A tool call draws as Claude Code's `⏺ Read(src/main.tsx)` with up to three
`⎿` lines of its output and `… +N lines` for the rest; a thought folds to
`∴ Thinking…`. No Ink component draws either: the ecosystem has spinners,
lists and inputs, nothing shaped like a tool call, so `src/ui/tools.ts` and two
small components do it on Ink's own `Box` and `Text`. A call's headline is
drawn whole and wrapped, every line of its title, for every tool, with no
cap, as Claude Code draws it (the owner, 2026-10-17, CHD-393): wrap-ansi,
through `wrapLine`, breaks it between words where OpenTUI's own wrap breaks
at a hyphen too (`--`, `include`). The headline is styled first, as one
string with its codes (the name bold, the note dim, a recipient's colour),
and wrap-ansi carries them across the rows it breaks; `runs` reads each
row back into spans, so nothing maps rows back onto the title, which
wrap-ansi rewrites (a decomposed é, a tab) (owner, Q8).

- ACP gives a call a free-text title, not a tool name and an argument. The
  headline reads a leading capitalised verb as the name (`Read README.md` →
  `Read(README.md)`); a title that is one code span or starts lower-case is
  the argument, and the call's kind names the tool (`execute` → `Bash`).
- The ⏺'s colour is the status: dim while pending, pulsing between the accent
  and dim while in progress, green when completed, red when failed. A failed
  call's output starts `Error:` in red, and a waiting, running or failed call
  with no output says so (`Waiting…`, `Running…`, `Failed`), so no status
  rests on colour alone; once the turn the call came in has ended, or the
  subagent it ran in, nothing waits or runs, so the first two are not said.
- ctrl+o expands every thought and every call's output at once and folds them
  again, rather than one block at a time: nothing on screen is selectable
  without a pointer, and Claude Code's ctrl+o is likewise one switch.
- ink-text-input types the `o` of ctrl+o, as it does the `d` of ctrl+d, and
  which of the two listeners hears a key first depends on mount order, which
  a remount of the input changes. The window marks a key as its own for the
  tick Ink hands it out, and the draft ignores edits made in that tick.
- Until CHD-8 draws diffs, a diff reads as `Updated path with N additions
  and M removals`, and jsdiff (`diff`) counts those lines. Comparing sets of
  lines lost repeated lines and moves, and a line diff is not ours to write.
  jsdiff is the line diff the npm ecosystem uses, ships its own types, and
  runs under `deno run` and in a compiled binary. `@std/internal` has a diff
  too, but it is internal to the standard library and not a public API.
  CRLF and a missing final newline are not counted as edits.

## 2026-10-05 — The `?` panel takes the columns that fit, measured by string-width

The shortcuts panel lays out Claude Code's three columns, read top to bottom,
when they fit the window. When they do not, it takes the most columns that fit
without folding, down to one. A folded entry has no indent to tell it from the
next entry, and at 80 columns two columns hold every key at the same height.
No Ink component lays out a list this way: ink-table draws rows with borders.
So the panel uses Ink's own `Box` and `Text`.

- Choosing the column count needs each line's width in terminal cells, not in
  UTF-16 units. That is string-width, the measure Ink uses itself, already in
  the lockfile under Ink. It is imported directly so the pure module in
  `src/ui/keys.ts` can measure without rendering. It runs under `deno run` and
  in a compiled binary.

## 2026-10-05 — Edits draw as jsdiff's hunks

This supersedes the "Until CHD-8 draws diffs" item of the tool-call entry: a
diff on a call now draws under its `Updated path with N additions and M
removals` line as Claude Code's edit does, numbered rows with `+` additions in
green and `-` removals in red, three lines of context, `…` between hunks.

- The hunks are jsdiff's `structuredPatch` (`diff`, already a dependency), the
  same package that counted the lines before; chord only numbers and colours
  its rows (`src/ui/diff.ts`). No Ink component draws a diff; npm has none.
  `jest-diff` was tried and passed over: it runs under Deno, but it hands back
  one finished string with `@@` headers in place of line numbers and its own
  chalk colours, so folding it and numbering it would mean parsing what it
  printed. Checked under `deno run` and in a compiled binary.
- `structuredPatch` takes `stripTrailingCr` but, in its types, not
  `ignoreNewlineAtEof`, so both texts get a final newline before the diff; a
  line ending still is not an edit.
- A folded diff shows ten rows and `… +N lines (ctrl+o to expand)`, the same
  ctrl+o that expands tool output; ten keeps the prompt on screen at 80×24.
- An added or removed line is marked by its sign as well as its colour.
  Where the terminal takes colour, the row is tinted as Claude Code tints it,
  its code highlighted on the tint (see the syntax highlighting entry); under
  NO_COLOR or off a terminal it stays green or red in the foreground.
- A tab becomes two spaces: Ink measures a tab as no width, so a row with one
  would run past the edge it is cut at.

## 2026-10-05 — react-ink-textarea for the prompt box

Superseded by "Moving to OpenTUI" (2026-10-10): the prompt box is OpenTUI's
`<textarea>` with react-ink-textarea's keys (parts 2 and 3).

The prompt box is [`react-ink-textarea`](https://github.com/omranjamal/ink-textarea)
0.4, in place of `ink-text-input`, which is single-line. This supersedes the
ctrl-key items of the ink-spinner and tool-call entries above: the textarea
ignores every ctrl chord it does not bind, so ctrl+d and ctrl+o no longer type
their letter, and the window no longer puts the draft back after them. Only `?`
on an empty prompt still reaches the draft, and the window still drops that
edit. Checked under `deno run` and in a compiled binary; it names Ink 7 as its
peer, and Deno resolves it against chord's Ink 8, one copy of each.

- It sends on Enter, breaks the line on shift+Enter, option+Enter and ctrl+J,
  takes a bracketed paste as one insert, grows to `viewportLines` rows and
  scrolls after, and reports ↑ on its first row and ↓ on its last
  (`onFirstLineUp`, `onLastLineDown`), which is where history hooks in. Its
  value and cursor are held by the window, so a recalled prompt or a `\`+Enter
  can set both.
- Two candidates were passed over. `ink-multiline-input` 0.1 binds Enter to a
  newline and has no paste handling or ↑/↓ hand-off, so sending, paste and
  history would all have been written around it. `@inkjs/ui` has no multiline
  input. `ink-text-area` 0.0.1 is pinned to Ink 5 and React 18.
- `\`+Enter is chord's, not the textarea's: on Enter the window checks for a
  `\` before the cursor and turns it into a line break (`src/ui/prompt.ts`),
  since most terminals, tmux among them, send shift+Enter as a bare Enter.
- shift+Enter reaches Ink as itself only through the kitty keyboard protocol;
  Ink 8 drops xterm's `modifyOtherKeys` form. chord asks for the protocol with
  Ink's `kittyKeyboard: { mode: 'auto' }`, which turns it on only where the
  terminal answers the query, with the flags in `src/keyboard.ts` (see "A
  bound key's base-layout key", 2026-10-08).
- The textarea skips reporting a cursor equal to the last one it reported, so
  a cursor set from outside starts a fresh textarea (a remount), or moving back
  to the reported spot would be lost.
- The gutter (`›`, and `↑`/`↓` once the box scrolls) is drawn through the
  textarea's `linePrefix`, since only the textarea knows which rows its
  viewport shows and it does not say. Each row's gutter adds itself to a list
  of shown rows while it is on screen, and the top and bottom rows read that
  list (`ShownRows`, `gutterMark` in `src/ui/prompt.ts`). The textarea breaks
  a long line at the box's width, mid-word, prefix or not.
- The textarea writes its cursor as a raw inverse-video escape whatever the
  colour level, so a test measures a line in cells (`string-width`), not in
  UTF-16 units.
- The cursor does not blink (`disableCursorBlink`): a blink redraws the window
  twice a second, and ink-text-input's cursor did not blink either.
- Its readline keys come along: ctrl+a, ctrl+e, ctrl+k, ctrl+u, ctrl+w, option+←
  and option+→, and ctrl+z / ctrl+y for undo and redo. They edit the draft and,
  like typing, are not in the shortcuts panel.

History (`src/ui/history.ts`) is chord's own: this session's prompts, not kept
across sessions yet. ↑ from a draft keeps the draft aside and ↓ past the newest
prompt gives it back, as a shell does. While a recalled prompt is untouched,
every ↑ and ↓ walks history, whatever line the cursor is on, as in Claude Code;
once it is edited, the arrows move the cursor and walk only from the first or
the last line.

## 2026-10-05 — markdansi draws replies as markdown

An agent's reply renders as terminal markdown through
[markdansi](https://github.com/steipete/Markdansi) 0.3 (MIT), which parses
with marked 18 and lays GFM out as ANSI text to a given width: headings,
emphasis, inline code, links with their address after them, lists that hang
their wrapped lines, block quotes, boxed code blocks, and tables that shrink
their columns to fit. `src/ui/markdown.ts` renders a reply to the width it is
drawn in; Ink draws the lines. Checked under `deno run` and in a compiled
binary.

- **Tried and passed over.** `marked-terminal` 7 (what FEATURES.md named): it
  wraps paragraphs but not list items, so a long item loses its hang; its
  tables keep their natural width and run past a narrow window; and it pins
  marked below 16. `ink-markdown` 1.0 is `marked-terminal` 6 in a `Text`, last
  released in 2023. `ink-markdown-es` 1.4 names Ink 6 as its peer, and at 50
  columns its table borders break and its wrapped list lines lose their
  indent. `@kud/ink-markdown` 0.3 is a scrolling viewport for Ink 7, not a
  block that sits in a transcript. `@assistant-ui/react-ink-markdown` is
  markdansi again, behind assistant-ui's store.
- **The whole reply is rendered again on each chunk,** not streamed with
  markdansi's `createMarkdownStreamer`: that one is append-only, renders line
  by line (a nested list item loses its nesting, a paragraph its reflow) and
  holds back a code block until its fence closes. Rendered whole, a reply cut
  mid-stream reads as markdown cut there: an open fence is a code block to the
  end, an unclosed `**` shows as typed until its pair arrives.
- **Blocks are split with marked's lexer** (`marked`, the version markdansi
  uses, imported for `lexer` alone) and rendered one at a time, because
  markdansi puts no blank line between blocks and paragraphs would run
  together. The component puts one line between them. A block rendered alone
  would lose the reply's reference-link definitions (`[docs][ref]` with
  `[ref]: …` further down), so each block is rendered with the definitions
  marked found after it, and their lines are cut from the result; markdansi
  still resolves the links, and the definitions show once, as they do when
  markdansi renders a whole reply.
- **A quote's bar is Ink's** (a left border), with markdansi's own prefix off:
  markdansi wraps a quote's paragraph at the full width and again inside its
  bar, stranding a word on a line of its own.
- **A table's cells wrap inside their columns** (`tableTruncate: false`) while
  that fits; when a word too long for its column would push the borders out of
  line, the table is rendered again with each cell cut to one line and `…`.
  markdansi caps a column at 40 cells, so a wide table wraps a long cell even
  when the window has room.
- **Every code block is boxed in our glue,** with markdansi's own box off:
  markdansi boxes only a block of two lines or more, so a one-line command,
  the commonest block an agent sends, read as prose, and a fence just opened
  mid-stream showed its first line plain. The box's border is dim, and its
  label is the language without markdansi's `[ ]`, which read as debug output.
- **A code block inside a list or a quote is boxed too,** through a hole:
  markdansi draws one in a list as bare lines in its item's hang, where a
  command reads as more of the item's text, boxes one in a quote its own way
  and uncoloured, and has no hook to draw either otherwise. The glue swaps
  each nested code block's lines for one placeholder character from
  Unicode's last private use plane, lets markdansi lay the list or the quote
  out (markers, numbering, hang, a nested quote's bar), and puts the box on
  the placeholder's line, at the indent markdansi gave it and in the width
  left beside it. A block is found on the line marked's `list_item` and
  `blockquote` tokens put it on, never by its text, so code that holds a
  fence line of its own stays as written. No list or quote renderer of our
  own. markdansi's own limits stay: a nested item's wrapped
  lines, and so a box under it, hang at the outer item's indent; a list made
  only of code blocks is merged into code, bullets dropped, so its boxes
  stand alone.
- **An indented code block is drawn as a code block,** from the code marked
  hands over: markdansi reads one alone as a paragraph and runs its lines
  together.
- **A table's borders are dimmed in our glue,** as the code box's are;
  markdansi draws them at full brightness, which made the grid the loudest
  thing on screen. Its header row stays bold.
- **An H1 is bold and underlined,** an H2 and below bold: markdansi has one
  style for every heading, so an H1 is rendered with a theme of its own.
- A heading longer than the window is not wrapped by markdansi; Ink wraps it.
- **A reply's prose and lists are wrapped by OpenTUI, not markdansi**
  (CHD-396, the owner's choice of 2026-10-15). markdansi's wrap is real line
  breaks, so a selection over a wrapped paragraph or item copied a newline
  and the hang's spaces, and differed by window width; OpenTUI's
  `wrapMode: 'word'` is soft, and a copy joins it, as a prompt's does.
  Rewriting the copied text in chord was declined as a workaround. So in a
  reply and a message's body a paragraph, a heading and a quote are rendered
  with markdansi's `wrap: false`, and a list is laid out from marked's
  tokens as OpenTUI boxes: each item's marker a dim text of its own that a
  drag does not copy, its text rendered by markdansi unwrapped beside it,
  hanging at the marker's own width, a nested list under its item's text,
  and a code box in an item as wide as the room left. That lifts markdansi's
  limit on a nested item's hang there. OpenTUI breaks a row after
  `/ - . , :` and `(` as well as at spaces, so a path can break mid-path on
  screen (Q157). A code box is an OpenTUI box (Q150): its border, its
  padding and its label, OpenTUI's title, which OpenTUI sets one cell past
  the corner, are layout, so a drag copies the code alone, and a line too
  long for the box is cut there by `wrapMode: 'char'` and copies whole.
  Tables and a code box inside a quote keep their drawn rows, a list inside
  a quote is still markdansi's, unwrapped, and a proposal's body and a
  saved team's keep the drawn rows, since they fold by counting them
  (Q152). OpenTUI's own `Markdown` renderable was passed over: the owner
  judged it far worse to look at than markdansi (Q161). It also parses and
  draws a whole reply, tables and code included, so it would replace
  markdansi wholesale rather than lay out what markdansi renders. An item is one box with the
  marker's width as `paddingLeft` and the marker at `position: 'absolute'`
  over it, not a row of marker and column: OpenTUI widens a selection by one
  box level per drag event and not on release, so a row and column put a
  sibling item two events away, and a drag straight down to it copied the
  first item alone. A drag out of a nested item to the next outer one still
  takes an event per level, which a pointer moving along the row gives; a
  jump straight there and a release copies the nested item alone (Q163).
- Links print their address after the text rather than as OSC 8 hyperlinks,
  so the address reads in every terminal and in a captured screen.
- The theme is Claude Code's look, not markdansi's yellow headings: headings
  and emphasis by weight and slant, inline code in the permission colour, code
  highlighted by its fence's language (see the syntax highlighting entry).
  markdansi colours only when stdout is
  a terminal, as Ink does; the glue decides the same way for the borders it
  dims.

## 2026-10-05 — The transcript scrolls on Ink's own `contentOffsetY`

Superseded by "Moving to OpenTUI" (2026-10-10): the transcript keeps its own
offset, now laid out by OpenTUI rather than by `contentOffsetY` (part 4).

chord draws on the alternate screen, which has no scrollback, so the window
scrolls its own transcript (the design is `docs/design/CHD-12.md`). Ink 8 has
what a scroll view needs: a box with `overflow='hidden'` shifts its children up
by `contentOffsetY` rows when it draws them, without laying them out again, and
`measureElement` gives each box's row and height after layout. No new
dependency; checked under `deno run` in tmux at 120×40 and 80×24.

- **Tried and passed over.** `ink-scroll-view` 0.4 (`ControlledScrollView`,
  peer Ink 7, which Deno resolves against chord's Ink 8): in chord's window it
  measured every entry as 0 rows for as long as a turn ran, and caught up only
  when the turn ended, so a streaming reply drew nothing. It also hangs its
  content from the top, so following the bottom would need a measured offset
  every frame. `ink-scroll-box` 1.0 (peer Ink 6) and `ink-virtual-list` 0.3
  (fixed-height rows) were not tried further; `ink-scroll-list` is a list of
  selectable items.
- **Following needs no measuring.** While following, the transcript sits on
  the bottom of its box (`justifyContent='flex-end'`), as it did before, and
  new rows push the old ones up. Scrolled back, it hangs from the top with
  `contentOffsetY` at the top row, so new rows land below the view and nothing
  on screen moves, whatever the next measurement says.
- **The position is a pure module** (`src/ui/scroll.ts`): the measured sizes,
  following or the top row, and whether output arrived since; what each key
  does to it; the indicator's words. The window measures after every layout and
  hands the sizes in. While scrolled back it also notes which entry is at the
  top and how far into it, so that ctrl+o and a change of width put that entry
  back at the top rather than a row number that now means something else.
- **shift+↑ and shift+↓ are the window's alone.** Ink hands every key to every
  `useInput` listener and cannot stop one, and neither react-ink-textarea nor
  ink-select-input looks at shift. Each widget has a `WindowKey` drawn ahead of
  it, whose listener Ink calls first, since Ink calls listeners in the order
  their effects ran; it marks the key, and the widget's callbacks ignore a
  marked key. The selection list is drawn afresh on the highlight it had. The
  textarea is not, because a fresh one forgets the draft's undo and redo: the
  cursor it reports for a marked key is shown for one draw and taken back, since
  it never reports the same cursor twice and would otherwise swallow a real move
  to that spot. pgup, pgdn, home and end reach no widget, so they need none of
  this.

## 2026-10-05 — The plan list and the status line are drawn here, cut by cli-truncate

The agent's plan draws above the prompt as Claude Code's todo list, hung off
the spinner with `⎿` while the turn runs: `☒` done, dimmed and struck through;
`◐` under way, in bold while a turn runs; `☐` still to do
(`src/ui/plan.ts`). Between turns an unfinished plan hangs from a dim
`Plan · N of M done` line instead, so it does not read as part of the last
reply. The status line
under the prompt keeps its hint or message on the left and puts on the right
what the agent has reported: model, mode, context used (`src/ui/status.ts`).
No Ink component draws either; both are Ink's own `Box` and `Text`. Checked
under `deno run` in tmux at 120×40, 80×24, 60 and 40 columns.

- **Libraries.** `figures` has `☐` and `☒` but no `◐`, and swaps both for
  `[ ]` and `[×]` on Windows terminals that draw them well today, so the three
  marks are written here. A model name too long for its room is cut by
  [`cli-truncate`](https://github.com/sindresorhus/cli-truncate), the
  truncation Ink itself uses, already in the lockfile under Ink and now
  imported directly; it runs under `deno run` and in a compiled binary.
- **The model is read, not streamed.** acpx's event stream carries no model;
  its session record does, from the agent's `model` config option (or the
  older `models` field), and `getStatus()` hands it back with display names.
  The conversation reads it once the session is up and after every turn.
- **The mode is shown once the agent changes it.** acpx records the mode from
  `current_mode_update` but not the one `session/new` starts in, and
  `getStatus()` returns neither, so a session shows no mode until its first
  change. The default mode says nothing, as in Claude Code; `plan`,
  `acceptEdits` and `bypassPermissions` read in Claude Code's words and
  colours, and any other mode as its id.
- **Context used** is the share of the window taken, from `usage_update`:
  the complement of the free share rounded down, in yellow above 80%. It
  said what was left until the owner asked for what was taken; the number
  is the same one turned round, so it moves at the same token.
- **A narrow line gets shorter, never taller.** The first of these that fits
  is drawn: everything; the mode and context in short words (`⏸ plan`,
  `99% used`); the model cut at a word to the room left; then the same again
  without the key hint; last, without the model. The hint goes late because it
  is the only way to find the keys, and 80 columns, the commonest width, holds
  it beside the short words. A message such as the second ctrl+c's warning
  stays and the facts give way, the context first and then the mode, until
  the message fits whole.
- **The plan takes a quarter of the window,** three rows at least. A taller
  plan folds its finished steps to `… N done` first, then its end to
  `… +N more`. A plan whose every step is done leaves the list when its turn
  ends and goes into the transcript once, dim, as the turn's `⏺ Plan` block,
  so the record of what was done stays in the scrollback as in Claude Code.
  An unfinished one stays live between turns, and the agent's empty plan
  clears it.

## 2026-10-05 — Claude's task list tools are turned on for every session

Claude Code 2.1 gives a model its task list tools — `TodoWrite`, or
`TaskCreate` and `TaskUpdate` — only when the model is one it lists (Claude 4.7
and older), or when the host opts in through `CLAUDE_CODE_ENABLE_TODO_TOOLS`,
`--tools` or `--allowedTools`. On a newer model Claude says it has no such
tools, and the plan chord draws never comes. Neither acpx nor
`claude-agent-acp` opts in: the adapter hands the SDK the full `claude_code`
preset and maps both kinds of tool to an ACP `plan`, and acpx's `session/new`
names no tools.

- **chord opts in with the environment variable**, through acpx's
  `sessionOptions.env`, which reaches the adapter's process and from there the
  Claude CLI. `allowedTools` would do it too, but it is a permission rule and
  reaches only Claude's adapter. Agents that are not Claude ignore the
  variable. A value already in chord's environment is left as it is, so the
  person can turn the tools off with `CLAUDE_CODE_ENABLE_TODO_TOOLS=0`.
- **acpx leaves out the person's own Claude settings.** For Claude's adapter it
  sends `settingSources: ["project", "local"]` unless
  `ACPX_CLAUDE_INCLUDE_USER_SETTINGS=1`, so `~/.claude/settings.json` is not
  where a session's tools come from.

## 2026-10-05 — Modes are cycled through acpx's `setMode` and read from the `mode` config option

shift+tab asks the agent for the mode after the one it is in, in the agent's
own order, wrapping round (`src/session/modes.ts`). This supersedes "the mode
is shown once the agent changes it" in the status line entry above: the mode
is now on screen from the start. Checked under `deno run` in tmux at 120×40
and 80×24 against the fake agent, and under `deno test`.

- **The call is acpx's.** `AcpxRuntime.setMode({ handle, mode })` sends
  `session/set_mode`, through the turn's controller while a turn runs, and
  remembers the mode as the one to restore when acpx reconnects. No SDK call
  is made directly.
- **The list comes from the `mode` config option.** acpx keeps no record of
  the `modes` that `session/new` returns, but it keeps every config option,
  and `getStatus().details.configOptions` hands them back. Claude's adapter
  sends its modes both ways, as ACP asks of agents while config options
  replace the older field, and its `mode` option lists them in Claude Code's
  order. An agent that sends only the older `modes` offers chord nothing to
  cycle, and shift+tab does nothing there until acpx keeps that field.
- **The mode shown is the one the agent reports, never the one asked for.**
  Claude's adapter answers a successful `session/set_mode` with a
  `config_option_update` and no `current_mode_update`; acpx records that
  update even outside a turn. So the conversation reads the modes back after
  every answer, after every turn and before `connected`, and a
  `current_mode_update` in a turn moves the mode as before. A reading the same
  as the last one is not news, so the record's older value cannot undo a mode
  the agent changed by `current_mode_update` alone; the reading after a
  `set_mode` answer always is. A refused mode is an error line in the
  transcript.
- **A quick second shift+tab walks on from the mode still being asked for**,
  not from the one on screen, so three fast presses ask for three different
  modes. Changes go to the agent one after another.
- **The mode sits at the left of the status line**, as in Claude Code, in place
  of `? for shortcuts` and followed by a dim `(shift+tab to cycle)`; the model
  stays alone on the right. This supersedes the mode on the right in the
  status line entry above. A draft hides the shortcut hint, never the mode.
  When the line is narrow the cycle hint goes first, then the model is cut;
  the mode is never cut or shortened. Claude's `default`, `acceptEdits`,
  `plan`, `auto` and `bypassPermissions` keep Claude Code's words and colours;
  any other mode reads as the agent's own name for it, lowercased, as
  `⏵⏵ <name> mode on`, dim, since chord cannot tell whether it is safe. The
  shape is in `docs/design/CHD-43.md`.

## 2026-10-05 — The slash command list: fzf filters it, chord draws it, `/clear` is a new session

`/` at the start of an empty prompt opens a list under the prompt, in place of
the status line, as in Claude Code: chord's own `/clear`, `/help` and `/exit`
and the commands the agent advertises in `available_commands_update`, by name.
Typing filters it, ↑ and ↓ move the highlight round it, Tab puts the name in
the prompt with a space for its words, Enter runs the highlighted command and
Esc puts the list away until the draft is edited again. A space, a second line
or a recalled prompt shuts it; an agent's command goes to the agent as the
prompt `/name words`, which is how Claude's adapter takes one. The list and
what the keys do are `src/ui/commands.ts` and `src/ui/state.ts`. Checked under
`deno run` and in a compiled binary in tmux at 120×40 and 80×24 against the
fake agent, and by opening the list once against Claude Code with no prompt
sent.

- **The filter is [fzf](https://github.com/ajitid/fzf-for-js) 0.5** (BSD-3),
  fzf's own matching ported to JavaScript: the letters in order anywhere in the
  name, best match first, so `rv` finds `review` as Claude Code's list does. It
  runs under `deno run` and in a compiled binary. `fuse.js` 7 was tried and
  passed over: its Bitap scoring found nothing for `rv`.
- **The list is drawn on Ink's own `Box` and `Text`.** `ink-select-input`,
  already the permission prompt's list, was tried and does not fit: while
  focused it takes `j`, `k` and `1`–`9`, which here are letters of the name
  being typed (`/k` moved the highlight, `/1` would run the first command);
  unfocused it has no way to move its highlight but a remount; and with a
  `limit` it rotates the items, so a scrolled list reads out of order, the last
  command above the first. So the window owns the keys and the highlight, and
  the list only draws them: a quarter of the window's rows, three at least,
  scrolling to keep the highlight in view.
- **The agent's commands are read from acpx's session record** as well as from
  the turn's events. Claude's adapter, like the fake agent, sends
  `available_commands_update` just after `session/new`, outside any turn, where
  acpx records it but no event reaches chord. `getStatus().availableCommands`
  hands it back; the conversation reads it before `connected`, after every
  turn, and again when a `/` opens the list. acpx keeps only `hasInput`, not
  ACP's input hint, so no hint is shown.
- **A command's description is its first line.** Claude Code's skills advertise
  descriptions that run to paragraphs; each command is one row, cut at the
  edge.
- **An agent command named like one of chord's is left out**: chord's runs, so
  the agent's could not be picked.
- **`/clear` starts a new session** rather than emptying the screen of the old
  one. An emptied screen over the same session would leave the agent
  remembering a conversation the person can no longer see, and Claude Code's
  `/clear` frees the context. The conversation lets the old session go — a turn
  still running in it ends unseen — opens a new one with a new record, and
  closes the old agent alongside; quitting waits for both. The window keeps
  its ctrl+o setting and the prompt history, which now holds `/clear`; the
  model, the modes and the commands come again from the new session. The new
  agent starts in its default mode.
- **`/help` opens the shortcuts panel and `/exit` quits**, as `?` and ctrl+d
  do. `/status` and `/cost` come with their own rows in FEATURES.md.

## 2026-10-05 — A prompt sent during a turn waits in acpx's queue, and Esc takes it back

Enter during a turn sends the prompt to acpx straight away. acpx's `startTurn`
queues it behind the turn in flight and starts it when that one settles, so
chord keeps no queue of its own to drain. What chord keeps is the window's view
of it: the conversation reports each one `queued`, the window draws it as a dim
`›` row under the working line and its plan (`src/ui/queue.ts`), and the turn's
`prompt` goes into the transcript only once the turn ahead has ended, because
the transcript shows one turn at a time. Checked under `deno run` in tmux at
120×40 and 80×24 against the fake agent's `slow` scenario.

- **Esc interrupts the running turn and takes the queue back**, as Claude Code
  does: the queued prompts go back into the prompt box, oldest first, one a
  line, ahead of whatever was being typed, and acpx's queued turns are
  cancelled. acpx settles a turn cancelled before its prompt went out as
  `cancelled` without sending it, so the agent never sees them. The queued
  turns are cancelled before the running one, or acpx could start the next as
  the running one ends. Leaving the queue to run after an interrupt was passed
  over: Esc means stop, and a queue that runs on would start the work the
  person just stopped.
- **`/clear` puts the queue back the same way**: the session the prompts were
  queued in goes, and what they said is kept for the new one.
- **Esc while a permission is asked still only rejects it**, and the queue
  waits on.
- A client-side queue that sends the next prompt when the turn ends was passed
  over: acpx already does the sending in order, and a turn held by chord
  instead would need its own drain on every way a turn can end.

## 2026-10-05 — Resume reopens acpx's session record, and draws the past it keeps

`chord <agent> --continue` opens the agent's latest session in the directory
again, and `--resume <id>` a session by its id; the `/resume` picker comes
later. Both draw the session's earlier prompts, replies and tool calls in the
transcript through the same reducer as live events (`src/session/replay.ts`),
and the next prompt goes on in the same session. Checked under `deno run` in
tmux at 120×40 and 80×24 against the fake agent, and under `deno test`.

- **The id is the agent's own**, the ACP session id: what the agent loads the
  session by, and for Claude the id Claude Code keeps the conversation under.
  chord prints `Resume this session with: chord <agent> --resume <id>` once the
  window has gone, as Claude Code does, when a prompt went to the session
  (one command for each such session once several are open, CHD-120's entry).
- **The past comes from acpx's session record, not from the agent's replay.**
  acpx records every turn's prompt and updates onto the record as the
  conversation (`messages`), and the in-process runtime hands chord no event
  outside a turn, so an agent's `session/load` replay reaches chord only as
  what acpx records from it. Claude's adapter offers `session/resume`, which
  acpx prefers and which replays nothing; the record is then the only copy
  of the past. So a session chord has a record of reopens that record, under
  its own key: acpx loads the agent's session on the first turn, with the
  replay suppressed so nothing is recorded twice, and the record keeps
  gathering the conversation across runs. An id chord has no record of goes
  to the agent as `resumeSessionId` on a new record; an agent that loads it
  with `session/load` replays its past into that record, and chord draws that.
- **What the record keeps is less than the live turn showed.** acpx keeps a
  call's title, input, raw output and whether it finished or failed, but not
  its kind, locations or content: a replayed edit shows its headline without
  its diff, and a call's raw output is shown only when it is text. Long texts
  are cut at acpx's limits (8000 characters a reply, 200 messages).
- **Finding the session.** acpx's file store loads a record by key but does not
  list them, so chord reads the key from each file name under `sessions/` and
  loads it through the store. `--continue` takes the record used last whose
  directory is this one, in which a prompt was sent, and which belongs to the
  agent: started by the same command, as acpx compares them, or named for it.
  New records are keyed `chord-<agent>-<uuid>` so that the name still holds
  when the command changes, as Claude's adapter version does with each acpx
  release. A record whose command has changed is never reopened, since acpx
  would put a new session in its place under the same key; its session is
  resumed by id on a new record, and its kept past is drawn when the agent
  replays none. `--resume` opens the session in its own directory, whatever
  `-C` says.
- **A past moved to a new record goes with it.** The new record holds only
  the turns after the move, and as the latest it is what the next
  `--continue` or `--resume` finds, so without the old past a second resume
  would lose it. acpx keeps a live record in memory and saves it over the
  file, so chord cannot write the past into the record; it keeps it beside it,
  in `carried/<record id>.json` in its state directory, and puts it in front
  of the record's own messages when it reads records. An agent that replays
  its past into the new record (`session/load`) needs none carried, and gets
  none, so nothing is drawn twice.
- **A session the agent cannot load is an error, not a crash.** An id the
  agent does not know fails the open: the window says `<agent> did not start:
  it cannot resume session <id>: <the agent's reason>`. A reopened record
  starts its agent only at the first prompt, as acpx does, so a load refused
  then fails that turn with acpx's `could not be resumed` and its reason.
  `--continue` with nothing to continue, and an id that belongs to another
  agent, stop at the command line before the window opens.
- `/clear` in a resumed session starts a new one, as it always does.


## 2026-10-05 — `/model` picks through acpx's `setModel`, on a list drawn by hand

`/model` in the slash command list opens a picker of the agent's models above
the prompt, as the permission prompt opens: `Select model`, the models
numbered in the agent's order with `✔` after the one in use, and the
highlight on it. ↑/↓, j/k and 1–9 move or pick, Enter switches and Esc
closes. The status line moves to the new model once acpx's record says the
agent took it. The choices, the window onto them and the keys are
`src/ui/picker.ts`, the reading `src/session/models.ts`. Checked under
`deno run` in tmux at 120×40 and 80×24 against the fake agent, which now
switches between its two models, and against Claude Code's twelve, and under
`deno test`.

- **A long list shows a window onto it, the way Claude Code's picker does.**
  Claude Code offers a dozen models, more than an 80×24 window holds, so the
  picker shows a quarter of the window's rows, three at least, as the slash
  command list does. The window slides with the highlight and stops at either
  end. The numbers are each model's place in the whole list, so a digit picks
  the same model wherever the window is. `↑` before the first row's number and
  `↓` before the last say that models are hidden that way, and a dim
  `… +N more` under the list says how many are out of sight.
- **The list is drawn by hand, on Ink's `Box` and `Text`.** The first cut used
  ink-select-input, the permission prompt's list, with `limit`. It scrolls by
  rotating the items, so past either end the other end follows on and the
  order seems to start over. It does not say where it has scrolled to, and its
  digits pick by the row on screen, so a list that scrolled had to drop its
  numbers. That hid how many models there were, at just the length where it
  matters. `@inkjs/ui`'s `Select` 2.0 scrolls without rotating and was tried
  and passed over too. It always starts on the first option, so the model in
  use could start out of view. Enter on the model already chosen does nothing,
  leaving the picker open. It has no digits, and it does not mark hidden rows
  either. The window is the slash command list's `visibleRange`.
- **The keys are the permission prompt's**, so the shortcuts panel names them
  once, as choices: ↑/↓ and j/k move, j and k whatever is held with them, as
  ink-select-input reads them; 1–9 and Enter pick. shift+↑/↓ stay the
  window's. The permission prompt stays on ink-select-input. Its list is a
  handful of the agent's answers and never scrolls.
- **The models are `getStatus().models`.** acpx reads them from the agent's
  `model` config option or the older `models` field, keeps the display names,
  and records the current one, so chord never looks at either form itself.
  `setModel` sends `session/set_config_option` where the agent has the option
  and `session/set_model` where it has only the older field, through the
  turn's controller while a turn runs; acpx refuses a model the agent did not
  advertise before sending anything.
- **The status line shows the model acpx records after the agent's answer**,
  never the one picked: the conversation reads the models again after every
  change it asks for, as well as at the start and after every turn (this adds
  to "the model is read, not streamed" above). A refused change is an error
  line in the transcript, and the line keeps the old model. Picking the model
  already in use asks the agent for nothing.
- **A permission asked while the picker is open takes its place** until it is
  answered, so the digits and Enter answer one list, not two; Esc rejects the
  permission first, then closes the picker, then interrupts the turn. The
  picker waits for the session to be up, and `/clear` and quitting close it.
- An agent that advertises no models gets the picker all the same, saying so,
  rather than a `/model` that silently does nothing.

## 2026-10-05 — `@` finds files with globby and fzf; acpx cannot send a resource link yet

`@` at the start of a word in the prompt opens a list of the working
directory's files under the prompt, in place of the status line, as the slash
command list opens. Typing after the `@` narrows it, ↑ and ↓ move the
highlight, Tab or Enter puts the path in place of what was typed with a space
after it, and Esc puts the list away and keeps the text until the draft is
edited again. The mention, the matching and the insertion are
`src/ui/mentions.ts`, the walk `src/files.ts`, the keys `src/ui/state.ts`.
Checked under `deno run` and in a compiled binary in tmux at 120×40 and 80×24
against the fake agent, and under `deno test`.

- **The walk is [globby](https://github.com/sindresorhus/globby) 16** (MIT)
  with `gitignore: true`: it reads every `.gitignore` in the tree, nested ones
  too, and works outside a repository. `.git` is left out by hand, and dot
  files are kept, as `git ls-files` keeps them. On this repository it finds
  the same 287 files as `git ls-files -co --exclude-standard`, in under 20 ms;
  on a repository of 2,700 files in under 100 ms. It runs under `deno run` and
  in a compiled binary. `git ls-files` itself was passed over: it needs git on
  the path and a repository to stand in. The files are walked again each time
  an `@` opens the list, so a file made since shows up, and sorted the top of
  the tree first, so an empty query starts there.
- **The filter is fzf again**, as for the slash command list, with the shorter
  path first on a tie and the best hundred kept, since a large tree scored on
  every key costs more than a few rows show.
- **The list is the slash command list's**, drawn on Ink's `Box` and `Text`
  for the same reasons (see that entry), one path a row, cut at its start so
  the file name stays.
- **A path with a space in it goes in quoted**, `@"my file.md"`, as Claude
  Code writes it.
- **A mention is the path in the prompt text** (the owner's call,
  2026-10-06, CHD-60; a `resource_link` now goes beside it, see 2026-10-07,
  CHD-145). ACP's `resource_link` is the block for it, but acpx
  0.19.4's `startTurn` takes text and `attachments`, and turns only `image/*`
  and `audio/*` attachments into prompt blocks; any other type throws.
  Upstream's main is the same, and nothing public reaches the connection acpx
  owns, so a resource link would mean patching acpx. It would buy little:
  Claude and Codex read the file with their own tools from the path, and
  Claude's adapter turns a resource link back into `[@name](file://…)` text
  anyway. So the `@path` goes to the agent as typed, the way Claude Code
  writes it, and FEATURES says so. Inlining the file's text instead was
  rejected: it bloats every prompt with what the agent can read itself. No
  acpx issue is open for it.

## 2026-10-05 — Bash mode runs on `Deno.Command`, strip-ansi cleans its output, and the output rides ahead of the next prompt

`!` on an empty prompt turns the box to bash mode, as in Claude Code: the
border and the gutter's `›` turn to a pink `!`, and the status line says
`! for bash mode`. Backspace on the empty box leaves it. Enter runs the command
in the session's directory and the box is a prompt again, as Claude Code's is
after a command; ↑ brings a command back in bash mode. The run draws in the
transcript as `! command`, its stdout and then its stderr (red) under `⎿`,
folded at ten lines until ctrl+o, and how it ended when that is news
(`Exit code 3`, `Stopped by the user`). Esc stops it, ahead of interrupting a
turn. The mode and the keys are `src/ui/state.ts` and `src/ui/bash.ts`, the
run `src/shell.ts`, the context `src/session/context.ts`. Checked under
`deno run` and in a compiled binary in tmux at 120×40 and 80×24 against the
fake agent, and under `deno test`.

- **Running is `Deno.Command`**, through `$SHELL -c` (`/bin/sh` without one,
  `cmd.exe /d /s /c` on Windows), stdin closed. execa and its kin are Node
  libraries doing what `Deno.Command` does here already. The command gets a
  process group of its own (`detached`), and a stop signals the group,
  SIGTERM then SIGKILL two seconds on: signalling the shell alone leaves a
  `sleep` it started holding the pipes open, and the run with them. A stopped
  run ends only once the group is empty, not when the shell and its pipes do:
  something started in the background that ignores SIGTERM would otherwise
  outlive the stop. Windows kills the shell alone.
- **[strip-ansi](https://github.com/chalk/strip-ansi) 7** (MIT) takes the
  colours and links out, both for the screen, where Ink would measure them as
  text, and for the agent. A line a progress bar rewrote with `\r` keeps what
  was written last; that is a line of code, not a library. It runs under
  `deno run` and in a compiled binary.
- **The output is context, not a turn.** Finished runs are held and go ahead
  of the next prompt, in the tags Claude Code wraps its own bash mode's output
  in: `<bash-input>`, `<bash-stdout>`, `<bash-stderr>`, and a `<bash-status>`
  of chord's for an ending that is news. The transcript shows the prompt as
  typed. A prompt queued behind a turn takes the held output with it; if Esc
  takes the prompt back before it starts, the output is held again, so it
  reaches the agent exactly once. Each stream keeps at most 30,000 characters, Claude Code's default
  for bash output. A resumed session's prompts are split back into the runs
  and the typed text, so the past draws as it did live.
- **One command at a time.** Enter in bash mode while one runs does nothing;
  Esc first.

## 2026-10-05 — ctrl+r searches history by substring, and the textarea's labels mark the match

ctrl+r on the prompt opens a reverse search through the prompts ↑ walks, in
the shape Claude Code's ctrl+r had before it became a filtered picker: the
status line's row reads `search prompts:` and the query, the box shows the
newest prompt containing it with the query marked in standout, each ctrl+r
after that shows the next older one, and the row reads `no matching prompt:`
once there is none, the last match staying in the box. Enter or Tab takes the
match into the box to edit, in bash mode when it is a command; Esc or ctrl+c
leaves with the draft as it was. The search is `src/ui/search.ts`, its keys
`keyCommand` in `src/ui/state.ts`. Checked under `deno run` in tmux at 120×40
and 80×24 against the fake agent, and under `deno test`.

- **The match is `String.includes`, not a library.** fzf is already here for
  the slash command list and `@`, and was weighed for this: it orders by score,
  and ctrl+r's order is recency, the newest match first and the next older on
  each press, so its ranking would have been thrown away and only the
  substring test kept. Plain substring, case-sensitive, is what Claude Code's
  search did and what a shell's does. No Ink component does incremental
  history search.
- **A prompt sent more than once counts where it was sent last**, so ctrl+r
  never shows the same text twice in one search; history itself keeps every
  send but the immediate repeat, as before.
- **The match is marked by react-ink-textarea's own `labels`**: a regex rule
  built with `RegExp.escape` from the query, styled inverse, so the box draws
  the match as it will be edited, wrapped and scrolled the same. While the
  search is open the textarea is not focused, and the window takes typing
  into the query; Enter and Tab reach the window as keys, not as a send.
- **Typing starts from the newest again**, as the task's shape asks: a longer
  query narrows to the newest prompt containing it, not to the next one from
  where ctrl+r had stepped. An empty query matches nothing, so the box shows
  the draft until something is typed.
- **A permission asked while the search is open closes the search**, and the
  draft is back in the box: the permission list and the search line would
  otherwise both take Enter, Esc and typing. Closing it, rather than keeping
  it underneath, leaves one owner for every key; ctrl+r opens it again once
  the permission is answered.

## 2026-10-05 — emphasize highlights code in replies and in diffs

A fenced code block in a reply is coloured by its label's language, and an
edit's diff by its file's extension (or its name, for a `Makefile`); a missing
or unknown language leaves the code plain. A changed row of a diff is tinted
dark green or red across the window, as Claude Code tints it, with its sign
in a light green or red and its code highlighted on the tint; a context row
is highlighted on the terminal's own background. The language and the
colours are `src/ui/highlight.ts`; the code box `src/ui/markdown.ts`; a diff
row's coloured code `src/ui/diff.ts`. Checked under `deno run` and in a
compiled binary in tmux at 120×40 and 80×24 against the fake agent, and
under `deno test`.

- **[emphasize](https://github.com/wooorm/emphasize) 7** (MIT) is
  highlight.js's grammars, through lowlight, coloured as ANSI with a sheet of
  styles per highlight.js class. It runs under `deno run` and in a compiled
  binary, synchronously, which markdown rendered on each chunk needs. Its
  `common` set, 37 languages, is loaded: TypeScript, JavaScript, shell, Python,
  Go, Rust, JSON, YAML and the rest an agent writes most. Tried and passed
  over: **shiki** with `@shikijs/cli`'s `codeToANSI` runs under Deno but is
  asynchronous, brings 46 packages and 14 MB, and writes only 24-bit colour;
  **cli-highlight** is highlight.js 10 behind chalk 4, parse5 and yargs, last
  released in 2021. markdansi's own `highlighter` hook was used first and
  left: it hands over a line at a time, after wrapping, so a comment or a
  string running over several lines lost its colour after the first.
- **emphasize's types are not loaded.** They reach highlight.js's, which
  reference the DOM's lib, and the DOM's streams then clash with Deno's in
  `src/shell.ts`. `src/ui/emphasize.d.ts` declares the three names chord uses,
  through `@ts-types`.
- **A code block is highlighted whole, then cut to its box** with
  [wrap-ansi](https://github.com/chalk/wrap-ansi) 10 (MIT, already under
  Ink), hard at the box's width as markdansi cut it. chalk closes and opens
  its styles again at each line break, so every line, and every piece of a
  cut one, carries its own colour. A diff highlights both whole files the same
  way and takes each row's line by its number, so a row in the middle of a
  comment is a comment; the last 64 files highlighted are kept, since the
  transcript draws again on every tick of the working line.
- **The colours are two sets of tones of chord's own,** one for each ground
  code is drawn on (lavender keywords, amber strings, blue names, cyan types,
  grey comments in both), off green and red so a token never reads as an
  addition or a removal. emphasize's default sheet colours `echo` and `ls`
  red. chalk's detected level picks 24-bit, 256 or 16 colours. These were
  first mid tones meant to read on any background, since chord did not know
  the terminal's; since the themes (below, CHD-87) each theme has its own
  sets, in `src/ui/theme.ts`.
- **The tint replaces the foreground green and red** of the jsdiff entry where
  there is colour. Its text is set by the theme, never left to the terminal,
  so the terminal's own text never sits on a tint it was not made for.
- **NO_COLOR adds nothing:** Ink's chalk does not read it, so chord does
  (`Deno.noColor`), and neither the highlighting nor the tint is drawn; nor
  are they when stdout is not a terminal.

## 2026-10-05 — `chord -p` runs one turn in an acpx oneshot session, and refuses every permission

`chord -p "prompt" [agent]` draws nothing: no Ink, no alternate screen. It
opens an acpx session with `mode: 'oneshot'`, which ends the agent once its
turn is over, plays the prompt, writes the reply's text to stdout as it
streams, and exits 0 when the turn ends with `end_turn`; any other stop
reason, a failed turn or an agent that does not start exits 1 with the reason
on stderr. `src/session/oneshot.ts` is the acpx side, `src/headless.ts` the
output and the exit code. Checked under `deno test` against the fake agent,
by hand under `deno run`, in a compiled binary, and in tmux with a terminal
on both ends.

- **No library for the output.** What `-p` writes is the turn's
  `text_delta`s without thinking, a blank line where a tool call came between
  two stretches, and `JSON.stringify` of one object; acpx and the standard
  library cover all of it.
- **Piped stdin joins the prompt as Claude Code joins it:** the prompt, a line
  break, then what was piped, either left out when empty (its `-p` reads
  stdin whenever it is not a terminal, and waits for its end, as chord does).
- **The JSON uses Claude Code's names** where it says the same thing:
  `type: "result"`, `is_error`, `result`, `session_id`, `stop_reason`, `usage`
  with `input_tokens`, `output_tokens`, `cache_read_input_tokens`,
  `cache_creation_input_tokens` (and `thought_tokens`, `total_tokens`), and
  `total_cost_usd`; a cost in another currency is `cost` with its currency,
  and a failure adds `error`. Usage is acpx's `getStatus().usage` after the
  turn, which it fills from ACP's `PromptResponse.usage`; one turn's
  cumulative is that turn's.
- **Every permission is refused** (`reject_once`), and stderr names the tool
  call, since nobody is there to answer it; acpx's own policy is set to
  `deny-all` behind the callback too. Claude Code has `--permission-mode`,
  `--allowedTools` and `--dangerously-skip-permissions` for this; chord has no
  flag yet, and which it gets is the owner's call.
- **The session is kept** in chord's state directory like any other, so the
  JSON's `session_id` opens it again with `--resume`. `-p` with `--continue` or
  `--resume` is refused for now: continuing in one shot needs a persistent
  session, not a oneshot one.

## 2026-10-05 — `/cost`, `/context` and `/status` report into the transcript from acpx's record

`/cost`, `/context` and `/status` are chord's own commands, in the slash
command list with the rest. Each puts a block in the transcript, as Claude
Code does for its own: the command as typed, then labelled rows under `⎿`
(`src/ui/reports.ts`, drawn by `App.tsx`). The block is what was true when the
command ran; it is not redrawn as the session goes on. Checked under
`deno test` and under `deno run` in tmux at 120×40 and 80×24 against the fake
agent, with usage and with `--no-usage`.

- **No library.** The rows are labels padded to the widest one;
  `Intl.NumberFormat` writes the token counts and a cost in a currency other
  than dollars, and `formatElapsed`, the working line's clock, the session
  time. Nothing new is imported.
- **Tokens are acpx's `getStatus().usage`, each turn's added up, and kept by
  chord.** acpx sets `cumulative` from each turn's `PromptResponse.usage`,
  which ACP defines as that turn's, so it holds only the last turn;
  `perRequest` keeps each turn's by its prompt, but only the latest 100
  (`trimConversationForRuntime`). The conversation reads the record once the
  session is up and after every turn, and `src/session/usage.ts` keeps every
  turn it has read, so turns acpx drops later still count, and a turn read
  twice counts once. Readings are numbered as they begin, and one that ends
  after a later one is dropped. A resumed record already full with a first
  turn chord never saw may have lost older ones, which cannot be had back,
  or may be exactly 100 turns with none lost: acpx trims only past 100, and
  the two look the same. `/cost` then says its tokens count the last so many
  turns and any earlier ones are not included, rather than passing them off
  as the session's or claiming a loss it cannot know.
- **The cost is the agent's own cumulative figure** from `usage_update`. The
  record's cost only ever comes from one, which the window also saw, perhaps
  after the record was last read, so the last `usage_update` in the
  transcript comes first and the record's stands in when the transcript has
  none, as on a resume. Dollars are written as Claude Code writes them: to
  the cent above $0.50, to a hundredth of a cent below.
- **`/context` is the figure the status line uses**, the last
  `usage_update`'s `used` and `size`, and its free share is rounded down as
  the status line's is, so the two never disagree.
- **What the agent has not reported is said, not drawn as zero.** An agent
  with no usage at all gets one sentence (`fake has not reported what this
  session has used.`); one that reports tokens but no cost gets `not reported
  by <agent>` on that row alone. The session time is chord's own, so it is
  always there once the session is up: wall time since it came up in this
  window, not the agent's time spent working.
- **`/status` names the agent, the model and mode by the agent's names for
  them, the session id `--resume` takes, and the directory.** This and the
  two above complete the `/status` and `/cost` half of FEATURES.md's client
  slash commands row, which the slash command list entry left for later.

## 2026-10-05 — `/config` sets the agent's other config options through acpx's `setConfigOption`, on `/model`'s list

`/config` opens a picker above the prompt, as `/model` does: `Settings`, then
the agent's select config options other than its mode and its model, each with
the value it is set to, padded so the values line up. Enter on one lists its
values under `Set <option>`, the one in use marked `✔` and highlighted; Enter
on a value sets it and closes the picker, and Esc backs out one level, from
the values to the options and from the options to the prompt. The reading is
`src/session/config.ts`, the choices `src/ui/picker.ts`. Checked under
`deno run` in tmux at 120×40 and 80×24 against the fake agent, which now
offers an effort, and under `deno test`.

- **The call is acpx's.** `AcpxRuntime.setConfigOption({ handle, key, value })`
  sends `session/set_config_option`, through the turn's controller while a
  turn runs, records the agent's answer, which carries every option as it now
  stands, and remembers the value to restore when acpx reconnects. No SDK call
  is made directly.
- **The options are `getStatus().details.configOptions`**, the same record the
  modes are read from. Only selects are listed: they are the kind ACP gives a
  list of values for. The mode and the model are left out, by category or by
  id, since shift+tab and `/model` already set them; a mode or model listed
  twice would be one setting with two ways to change it.
- **The value shown is the one the agent reports.** The conversation reads
  the options again after every change it asks for, as well as before
  `connected`, after every turn and when `/config` opens, since an agent may
  change them outside a turn. Readings are numbered as they start, and one
  that ends after a newer one is dropped: a reading begun before a change and
  ending after its readback would otherwise put the old value back. Once the
  agent answers, the value it reports goes into the transcript the way
  `/context` reports: `› /config`, then one dim line under it,
  `⎿  Effort set to High`. A bare `⎿` would hang from nothing, or read as
  the result of the agent's reply above it. A refusal is the red error line
  under the same `› /config`, `Could not set Effort to High: …`, and the
  option keeps its old value. Picking the value already in
  use asks the agent for nothing and notes nothing.
- **The list is `/model`'s**, drawn by hand on `picker.ts`, with its keys and
  its window onto a long list; the reasons ink-select-input and `@inkjs/ui`'s
  `Select` were passed over there hold here. Each level is a fresh list, so
  the values open on the one in use, and Esc back to the options opens them
  on the option the values were of. A permission asked while it is open
  takes its place, and `/clear` and quitting close it, as with `/model`.
- An agent with no other options gets the picker all the same, saying
  `<agent> has no settings other than its model and mode.`, as `/model` says
  when there are no models.

## 2026-10-05 — Settings files are checked by zod, and set each agent's start

chord reads `~/.config/chord/settings.json` (`xdg-basedir`'s config home, so
`$XDG_CONFIG_HOME` counts) and `<cwd>/.chord/settings.json`, where `<cwd>` is
the directory `-C` names. A session `--resume` opens from another directory
starts on that directory's project file instead; the agent and command that
found it stay those of `-C`'s. The project's file overrides the user's, key by key
and agent by agent within `agents`; a flag overrides both. The keys are
`agent`, and under `agents.<name>`, `command`, `model` and `permissionMode`,
each the default for a flag that already existed or came with it
(`--agent-command`, and the new `-m, --model` and `--permission-mode`, named
as Claude Code names them). The loading and merging are `src/settings.ts`,
pure but for reading the two files, and tested on temporary directories.

- **zod checks the files** (`jsr:@zod/zod`, v4). valibot was tried alongside
  it; both run under `deno run` and in a `deno compile` binary, and both
  report every unknown key with its path. zod was taken because its issues
  carry a code, so an unknown key and a value of the wrong kind are worded
  differently, and its `unrecognized_keys` issue lists the keys by name.
  `strictObject` is what makes an unknown key an issue at all.
- **A problem costs only its key.** Each issue's key is dropped and the file
  checked again, so a typo in one key leaves every other setting in force.
  Text that is not a JSON object costs the file. Each problem is one line on
  stderr, `chord: <file>: <what>`, printed once before the window opens, for
  `-p` and scripts; the alternate screen covers it until chord quits, so the
  window says each one again as a yellow `⏺` line at the top of the
  transcript, the file from the working directory or `~`. A typo such as
  `permisionMode` would otherwise open the session in the agent's mode with
  nothing on screen to say why. It never stops chord. A missing file is not a
  problem.
- **Model and mode are per agent.** Their ids are the agent's own; a
  top-level `model` would be refused by every other agent at every start.
- **The starting model and mode are asked for after the session opens,**
  through the same `setModel` and `setMode` that `/model` and shift+tab use,
  and before the modes and models are first read, so the session is first
  shown as it starts. acpx's `sessionOptions.model` was passed over: it is
  only applied when a session is created, not when a record is reopened, and
  an unadvertised model fails the whole start. A value the agent does not
  offer is not asked for. The red error line says where it was set and what
  the agent offers instead: `Could not start in bogus mode, set in
  .chord/settings.json: the agent offers default, acceptEdits, plan`, and
  `Could not start on <model>, set by --model: …` the same way. An agent that
  lists none, or refuses a value it lists, is quoted in its own words. acpx's
  added guess that the adapter may not implement the method is left off,
  because the agent did answer. The session goes on as the agent chose. Every session
  chord opens gets them, `/clear`'s and resumed ones included, as each starts.
- `-p` takes the agent and its command from the files; `--model` and
  `--permission-mode` conflict with it, since the oneshot path sets neither.

## 2026-10-05 — chord notifies through the terminal when it waits, BEL inside tmux

When a turn ends, or a permission request arrives while none is open, chord
writes a notification the terminal can act on. `preferredNotifChannel` in
either settings file chooses it, named as Claude Code names its key:
`auto` (the default), `bell` (BEL), `osc9` (`ESC ] 9 ; message BEL`),
`osc777` (`ESC ] 777 ; notify ; chord ; message BEL`) or `off`. The values
name the escape rather than the terminal, as Claude Code's `iterm2`,
`kitty` and `ghostty` do, because several terminals share each escape and
the setting then says what is written. `src/notify.ts` decides it, pure:
which events start a wait, and the bytes for that wait, channel and
environment.

- **`auto`** is OSC 9 where `TERM_PROGRAM` is `iTerm.app`, `WezTerm` or
  `ghostty`, or `TERM` is `xterm-kitty` or `xterm-ghostty`; OSC 777 where
  `TERM` starts with `foot`; BEL everywhere else, which every terminal
  understands as at least a bell or a bounce.
- **Inside tmux** (`TMUX` set), `auto` is BEL. tmux drops an OSC it does not
  know unless `allow-passthrough` is on, and it is off by default since 3.3,
  so OSC there would most often be nothing at all; BEL tmux passes on to the
  terminal outside by default (`bell-action any`), and `TERM_PROGRAM` names
  tmux rather than that terminal. A channel chosen by name is honoured: `osc9`
  and `osc777` go inside tmux's DCS passthrough (`ESC P tmux ; …` with each
  ESC doubled), for whoever turned passthrough on.
- **Not a wait:** a turn cancelled with Esc (by chord's `cancel` or the
  agent's `cancelled` result), a turn a queued prompt follows at once, the
  turns a resumed session replays before it is up, and a second permission
  request while one is still open.
- **Written through Ink's `useStdout().write`,** which takes the frame down,
  writes the bytes and draws the frame again inside synchronized output, so
  the escape never lands in the middle of a frame. The window does not
  change.
- **ansi-escapes** (already under Ink) gives BEL as `beep`; it has no OSC 9 or
  777, nor iTerm2's notification, only `iTerm.setCwd` and `annotation`, so
  those two are written here. The packages on npm that write them are
  plugins for other agents (`pi-notify`, `opencode-osc9`,
  `@lumintian/pi-notify`) with the agent as a peer dependency, not
  libraries. Checked under `deno run` and in a `deno compile` binary in
  tmux against the fake agent: one write per wait.
- What the agent says, such as a permission's title, has its control
  characters made spaces so it cannot end the escape early, and in OSC 777
  its `;` made `,` so it cannot start another field.

## 2026-10-05 — Themes: one palette module, `/theme` on `/model`'s list, is-term-dark asks the terminal

chord paints from one palette (`src/ui/theme.ts`), in seven themes named by
Claude Code's ids: `auto`, `dark`, `light`, their colour-blind friendly
versions and their 16-colour versions. A palette is roles (accent,
permission, inline code, link, bash, the three modes, error, warning,
success), two sets of code tokens (on the terminal, on a diff's tint) and a
diff's tints, signs and text; the values and their contrast ratios are
docs/design/CHD-87.md's. Plain and dim text are never painted, so the wrong
theme on a terminal can fade an accent but never the text. `App.tsx` hands
the palette down through a React context, so `/theme`'s preview redraws every
component at once; highlight.ts makes and keeps one sheet per set of tones.
Checked under `deno run` and in a `deno compile` binary in tmux at 120×40 and
80×24 on a white and a dark `window-style`, and under `deno test`.

- **is-term-dark 1.1** (MIT, no dependencies) asks the terminal for its
  background with OSC 11 and reads the answer's luminance. The search the
  design asked for found it ("osc 11" on the npm registry; the design's own
  search did not), and `pi-theme-sync`, an extension of another agent rather
  than a library. It runs under `deno run` and in a compiled binary, on
  `node:process`'s stdin, the stream Ink reads. It is asked once, in
  `main.tsx`, only with a terminal on both ends and never under `-p`, and
  waited on for at most 100 ms; with no answer, `COLORFGBG`'s last field
  (`7` or `15` light), and otherwise dark. tmux 3.6 answers with the pane's
  `window-style` background, and a pane with no style does not answer.
- **stdin is set flowing before is-term-dark is asked.** When the terminal
  does not answer, is-term-dark pauses stdin with its read still pending, and
  under Deno a stream paused that way never delivers again: chord came up
  with a prompt that took no keys. is-term-dark leaves a stream that was
  flowing as it was, and Ink's own `readable` listener takes it from there.
- **A late answer is taken out of what Ink reads.** An answer slower than
  100 ms, as over a slow ssh link, arrives after is-term-dark has stopped
  listening, and Ink parses `ESC ]` as Alt+] and the rest as typed text, so
  `11;rgb:ffff/ffff/ffff` landed in the prompt. Ink already drops the CSI
  replies it has no key for, but not OSC ones. So `src/replies.ts`
  hands Ink `process.stdin` through a proxy whose `read()` drops OSC replies,
  `ESC ] <number> ; … BEL` or `… ESC \`, even split across reads; the rest of
  the stream is the real one, so raw mode and suspending for `$EDITOR` are
  untouched. Alt+] alone passes, and an unended reply gives the keys back at
  the next control character. A read can end right after the `ESC` or the
  `ESC ]` of a reply, and a link can be slower than any wait, so once the
  terminal said nothing in the 100 ms the filter looks for the rest of a
  reply for as long as chord runs, until one has been dropped. A read
  ending in `ESC` counts as the start of the next read: if that read is the
  rest of a reply, it is dropped, so only the Escape gets through, which no
  filter can tell from a key pressed and which does nothing on an idle
  prompt. A read ending in `ESC ]` is held for the next one, because the
  prompt types Alt+] as `]`: a slow reply leaves nothing in the draft, and
  Alt+] pressed alone arrives with the key after it. For the first 10 s,
  while an answer is likely, a trailing `ESC` is held too, for up to 100 ms
  (Ink waits only 20 ms for the rest of a sequence), so a reply cut there
  passes nothing at all; past that Escape is given at once. The 10 s only
  ends that hold, not the looking, so a reply cut across it is still taken
  out. When the terminal answered in time, nothing is held and Escape
  is as quick as before. No package does this: `strip-ansi` and `ansi-regex`
  strip keys' sequences too and keep no state between chunks.
- **colours through chalk and Ink as they were.** chalk draws a hex at
  whatever level the terminal takes and a named colour for the 16-colour
  themes; Ink's `color` and `backgroundColor` take both; markdansi takes
  chalk's names too, though its types list only eight. No colour package is
  added; the contrast figures are checked by `tests/ui/theme/theme_test.ts` with the
  WCAG formula.
- **NO_COLOR outranks every theme.** Ink's chalk does not read it, so under
  it, or where stdout is not a terminal, the window draws in `PLAIN`, a
  palette with no roles at all: no foreground, no background, no tint, and a
  diff's rows plain behind their `+` and `-`. Bold, italic, underline and dim
  stay. Inline code's colour comes from the palette, which closes CHD-69.
- **`theme` is read only from the user's file,** as it is about a terminal
  and a person's eyes; one in the project's file is a settings problem and
  only that key is lost. `/theme` writes it back: the file read, the key set
  in its place among the others, the object written to a temporary file
  beside it and renamed over it, so a crash leaves the old file or the new
  one. A file that is not a JSON object is never overwritten; the theme then
  lasts until chord quits and a red line says why. This is the first thing
  chord writes to a settings file.
- **`/theme` is drawn on `/model`'s picker list,** with a callback for each
  move, which previews; Esc is the window's, as on the other pickers, and
  brings back the theme in use. Under the choices it draws three rows of a
  diff through the same component the transcript uses. At 24 rows the
  picker, the header, the prompt box and the status line are exactly the
  window; shorter, the gap above it goes first, then the sample, then
  choices (`themePickerLayout`).

## 2026-10-05 — ctrl+g edits the draft in `$EDITOR` through Ink's `suspendTerminal` and @inquirer/external-editor

Superseded by "Moving to OpenTUI" (2026-10-10): the terminal is handed to
the editor through OpenTUI's `suspend` and `resume` (part 5).

ctrl+g on the prompt writes the draft to a temporary file, gives the
terminal to `$VISUAL`, then `$EDITOR`, then `vi`, and puts what the editor
saved back in the box with the cursor at its end. An editor that exits
non-zero or is killed by a signal leaves the draft as it was, and the status line says so, until the
draft is touched again. A permission, a picker or ctrl+r's search has the
box, so ctrl+g does nothing then; during a turn it edits the next prompt.
The run is `src/editor.ts`, the key `keyCommand` in `src/ui/state.ts`.
Checked under `deno run` and in a `deno compile` binary in tmux at 120×40
and 80×24 against the fake agent, with a scripted editor, a failing one,
one that reads a line from the terminal, and vi, and under `deno test`.

- **Ink 8's own `suspendTerminal`** (from `useApp`) does the hand-over: it
  takes the frame down, leaves the alternate screen, turns off bracketed
  paste, kitty keyboard mode and raw mode, and stops reading stdin; after the
  callback it puts all of that back, re-enters the alternate screen and
  draws the whole window again, and it drops frames and stdout writes in
  between, so a turn that streams while the editor is open draws once it
  comes back. Nothing is written for this by hand. Under Deno, an editor that
  reads the terminal got every key typed and a terminal in `icanon echo`.
- **[@inquirer/external-editor](https://github.com/SBoudrias/Inquirer.js)
  3.0** (MIT; chardet and iconv-lite, both MIT) makes the file, in a
  directory of its own under the system's temporary directory, runs the
  editor with the terminal inherited, reads the file back and removes it. It
  runs under `deno run` and in a compiled binary. Two things are chord's
  around it. The library splits `$EDITOR` on spaces and starts it without a
  shell; chord sets its `editor` field to `$SHELL -c '<editor> "$1"'`, so a
  command with quotes, variables or `~` means what it does at the prompt, as
  git runs it (on Windows the library's own split stands). And it returns
  the text whatever the exit status, which chord reads from `lastExitStatus`
  — but that is 0 for a process a signal killed (`code ?? 0` in 3.0.6), so a
  crashed editor's half-written file would come back as the draft. chord
  runs the user's shell under `/bin/sh -c '"$@"; exit $?'`, which turns a
  death by signal N into exit 128 + N, the status line's `was stopped by
  SIGTERM`; the library still owns the file, the spawn and the clean-up.
  `external-editor`, the package it was forked from, was last released in
  2019 and pulls in `tmp` 0.0.33. Its `runAsync` is the one used: the sync
  `run` would block the event loop, and with it the agent's messages, for
  as long as the editor is open.
- **The file ends with a newline the draft gets back without**, so vi
  neither marks it `[noeol]` nor adds one that would become a blank line; a
  draft that ended in a newline keeps it.
- **`?`'s panel has its eighteenth row** (ctrl+v made it nineteen; see the
  image paste entry). At 80×24 the two columns were then
  eighteen rows deep and the transcript kept two rows above the box (it had
  three); at 120×40 the three columns were twelve deep. The next key added
  costs another transcript row there (CHD-67).

## 2026-10-06 — MCP servers come from the settings files and `.mcp.json`, checked by zod, and go to the agent through acpx's `mcpServers`

chord hands the agent MCP servers for every session it opens, through acpx's
runtime option `mcpServers`, which acpx sends with `session/new`,
`session/load` and `session/resume` alike, so `/clear`'s sessions, resumed
ones and `-p`'s get the same servers. They are read from `mcpServers` in the
user's settings file, then the working directory's `.mcp.json`, then
`mcpServers` in the project's `.chord/settings.json`, each over the one
before, a server named again replacing the earlier one whole. `.mcp.json`
sits between the two because it is the project's word shared with other
tools, and `.chord/settings.json` is the project's word to chord. The reading
is `src/mcp.ts`, pure but for the one file read, and tested on temporary
directories; `src/ui/mcp.ts` lays `/mcp`'s rows out.

- **The entry is `.mcp.json`'s shape** in every file: `{ command, args, env }`
  or `{ type: "http" | "sse", url, headers }`, `env` and `headers` as objects,
  turned into ACP's `McpServer` (name and value pairs) only on the way out.
  A server copied between `.mcp.json` and a settings file means the same in
  both.
- **zod checks each server on its own** (already the settings files'
  checker). A wrong server is a settings problem, said as CHD-76 says them,
  on stderr before the window and as a yellow line in it, and costs only
  itself. `.mcp.json` that is not a JSON object costs the file. Keys chord
  does not read are let through in a server and at the top of `.mcp.json`,
  unlike chord's own keys: the shape is a convention other tools extend, and
  a file shared with them must not lose its servers or fill the window with
  warnings here. A `url` with no `type` is a problem rather than a guess
  between HTTP and SSE; a `type` ACP has no transport for, such as `ws`, is
  one too.
- **Tried and passed over:** the ACP SDK's `zMcpServer` schemas check the
  wire shape (`env` as name and value pairs, `name` inside the entry), not
  the file's; acpx's own `parseMcpServers` is the same shape, throws on the
  first problem, and is not exported from `acpx/runtime`. No maintained npm
  package reads `.mcp.json` on its own; the readers there are inside agents.
- **Not done:** `${VAR}` in `.mcp.json` is passed as written; Claude Code
  expands it itself when it reads the file, and chord does not yet (CHD-94). chord
  does not hold a server back from an agent whose `mcpCapabilities` lacks its
  transport; acpx does not either, and the agent's refusal is shown as it
  comes.
- **`/mcp` lists what chord passed, never a state.** ACP carries no word of
  whether the agent reached a server, so the list says that in a sentence
  rather than draw a status it cannot know. `env` and `headers` are never
  drawn: they are where tokens go. It is drawn in the pickers' frame with
  nothing to pick, Esc closes it, and a list taller than the window says how
  many more there are. The file a server came from is drawn whole first, as
  there are only three and a cut one names none of them; the command or URL
  takes the rest and wraps in its own column, breaking at spaces and then
  after a slash, because the end of `npx -y @scope/server-x` is what tells
  servers apart. wrap-ansi, which the transcript wraps with, was tried for
  it and passed over: it breaks at spaces alone and cuts a long word where
  the line ends, mid-name. A path too long even so is cut from the left, at
  a separator. Under the list, a line says how many servers each file lost,
  so a server missing from it is accounted for after the warnings scroll
  away or `/clear` takes them.
- **Read only.** chord never writes `.mcp.json`, nor the agent's own
  configuration.
- The fake agent advertises HTTP and SSE, keeps each session's servers as
  they arrived, and its `mcp` scenario answers with them as JSON, so a test
  proves the agent got exactly what `/mcp` lists, on a new session and on a
  loaded one.

## 2026-10-06 — ctrl+v pastes an image through @mariozechner/clipboard, and it goes as acpx's turn `attachments`

ctrl+v on the prompt reads the image on the system clipboard and puts
`[Image #N]` at the cursor, as Claude Code does; Enter sends the text, and
after it each image whose placeholder is still in the text, through
acpx's `startTurn` `attachments` (`{ mediaType, data }`, base64), which
acpx turns into ACP `image` blocks. A path to a PNG, JPEG, GIF or WebP file
pasted into the prompt becomes the image at once; one typed becomes it on
Enter. The reads are `src/images.ts`; the placeholders, the paths and what
a prompt sends are `src/ui/images.ts`, pure and tested; the key and the
state are `src/ui/state.ts`. Checked under `deno run` and in a compiled
binary, and in tmux at 120×40 and 80×24 against the fake agent with this
machine's clipboard holding a PNG, and empty; under `deno test` with an
injected clipboard, never the real one.

- **The clipboard is [@mariozechner/clipboard](https://github.com/badlogic/clipboard)
  0.3** (MIT), a maintained fork of `@crosscopy/clipboard`: Rust's
  clipboard-rs through N-API, with prebuilt binaries for macOS, Linux
  (glibc and musl, X11 and Wayland) and Windows, arm64 and x64. It reads
  whatever image type the application put there and hands it over as PNG.
  It loads under `deno run` (`--allow-ffi`, which `--allow-all` gives) and
  in a `deno compile` binary, and a cross-compiled one carries the target's
  native part: a Linux x64 build from macOS held
  `clipboard.linux-x64-gnu.node`. It is imported when ctrl+v is pressed,
  not at start, so a platform its native part fails on loses ctrl+v, with
  the status line saying why, and nothing else.
- **Tried and passed over:** clipboardy reads text only. sindresorhus's
  `clipboard-image` reads images on macOS alone, through JXA. tinyclip is
  text only. Shelling out to `osascript`, `pngpaste`, `wl-paste` or `xclip`,
  as the task first asked for Linux, was left out: the library speaks X11
  and Wayland itself, so no tool needs to be installed, and the person
  needs no tool's name in an error.
- **What a file is comes from its bytes**, by
  [file-type](https://github.com/sindresorhus/file-type) 22 (MIT): a `.png`
  that is text stays a path, and a JPEG named `.png` goes as `image/jpeg`.
  It runs under `deno run` and in a compiled binary. Base64 is
  `@std/encoding`.
- **Which paths are taken.** Only the forms a terminal writes for a file
  dropped on it: absolute, `~/`, `file://`, whole, quoted, or with escaped
  spaces; a stop or comma after one is the sentence's. A relative path such
  as `src/logo.png` in a sentence stays text, as the agent is more likely
  asked to edit that file than to look at it. A pasted path is taken as the
  paste lands, so the placeholder shows; a typed one only on Enter, since a
  path typed a key at a time is never whole until then. While Enter's files
  are read, another Enter sends nothing, so the prompt goes once and no
  later draft goes ahead of it; what is typed meanwhile stays in the box,
  with its images, once the prompt has gone. The prompt's numbers are kept
  before the reads, so a ctrl+v meanwhile takes the next one.
- **The placeholder is the image.** The draft keeps the images by number,
  and a prompt sends the ones whose `[Image #N]` is in its text, whole, in
  the order they appear; delete it and the image stays behind. A key that
  cuts into a held image's placeholder (backspace after its `]`, delete
  before its `[`, a word deleted back into it) takes the whole of it, as
  Claude Code's backspace does, rather than leaving half a label that
  stands for nothing. The box is drawn afresh for that, with the cursor
  where the placeholder began, so the textarea's undo does not reach back
  past the cut; a placeholder typed by hand edits as text. Numbers go on across the session, as Claude Code's do, so
  a recalled or queued prompt's images never share a number with a new
  one. A queued prompt takes its images with it and Esc gives them back
  with its text; history keeps each prompt's images by its text, so ↑
  brings them back; `/clear` keeps the draft's.
- **The agent's word decides.** The agent's `promptCapabilities.image`
  from `initialize`, which acpx keeps on its session record, is read before
  the session shows as up. An agent that says no gets no image: ctrl+v says
  `<agent> does not take images` in the status line and reads nothing, and
  paths stay text. Messages from ctrl+v are drawn where the editor's failure
  is, and go when the draft is touched.
- **A resumed session shows `[Image #N]`** where its prompts had images:
  chord's own prompts carry their placeholders in their text; an image the
  text does not stand for, as another client may send, gets one at the end.
  The image itself is not drawn.
- **Not done:** images are sent as they are, with no resizing; Claude Code
  shrinks large ones first. `-p` takes none. The `?` panel has its
  nineteenth row, so at 80×24 the transcript keeps one row above the box
  while it is open (CHD-67); the forms' lines below took that row.
- The fake agent advertises `promptCapabilities.image` (`--no-images` or
  `CHORD_FAKE_NO_IMAGES=1` turns it off) and answers each image first with
  `Received an image: image/png, 141 bytes`, so a capture shows what
  arrived.

## 2026-10-06 — Elicitation forms: acpx's per-turn `onElicitation`, zod's `fromJSONSchema` for the check, the fields drawn here

When the agent sends `elicitation/create` during a turn, chord shows the form
in the prompt box's place and answers `accept` with the values, `decline`, or
`cancel`, as `docs/design/CHD-98.md` draws it. acpx carries the protocol: chord
declares `elicitationModes: ['form', 'url']` on the runtime, which acpx puts in
`initialize`'s client capabilities and checks each request against, and hands
each turn an `onElicitation` callback, which `src/session/elicitations.ts`
parks until a key answers, as the permission bridge does. acpx aborts the
callback's signal when the turn is cancelled or ends, answers `cancel` for it,
and chord records the form as cancelled. Checked under `deno run` and in a
compiled binary, in tmux at 120×40 and 80×24 against the fake agent's `form`
and `link` scenarios.

- **The check is zod's.** `z.fromJSONSchema` in the zod 4 already in the tree
  (through the ACP SDK and the settings files) builds a validator from the
  requested schema, once per form, and reports each problem with its path and
  code: lengths, `pattern`, the `email`, `uri`, `date` and `date-time` formats,
  number bounds, `minItems` and `maxItems`. The words on screen are chord's,
  from the schema's own bounds (`A whole number from 1 to 9`), so they read
  the same whichever side failed. Typed text that is no number is chord's own
  finding, as zod is given numbers. `ajv` would have been a new dependency for
  the same job.
- **The fields are drawn here, on a pure reducer** (`src/ui/form.ts`), which
  is where the tests reach typing, the lists and the answer.
  [`ink-form`](https://github.com/lukasbach/ink-form) 2 was weighed and passed
  over from its README and the designer's look: it draws its own sections and
  its own field chrome, which the sheet's status column, aligned labels and
  one-row fields are not, and its v2 dropped multi-select. `@inkjs/ui`'s
  `TextInput`, `Select` and `MultiSelect` were passed over for the prompt
  before (the ctrl keys, the numbered rows), and its `MultiSelect` has no
  numbered rows or ← to close. `react-ink-textarea`, the prompt box's input,
  holds its value and cursor itself and is steered only by remounting, which
  would fight refusing a letter in a number field and moving between fields
  with ↑ and ↓; a field is one line, so the reducer edits it: typing at the
  cursor, ←/→, home/end, backspace, delete, ctrl+a, ctrl+e, ctrl+u, ctrl+k and
  ctrl+w, and a paste as one insert. The choice and multi-select lists are in
  the same reducer rather than on `ink-select-input`: the multi-select needs
  the reducer anyway, and one key owner for the whole form keeps Esc and ←
  closing a list, never the form.
- **The link prompt is the permission prompt's list**: `ink-select-input`
  through chord's `ChoiceList`, `1. Open in the browser`, `2. Decline`. The
  link opens through [`open`](https://github.com/sindresorhus/open) 11 (MIT),
  the system's opener on each platform and the Windows browser from WSL; it
  runs under `deno run` and in a compiled binary. It is called only on that
  key, and injected in tests, which open nothing. A link that is not `http`
  or `https` gets `Not a web link` and only Decline.
- **Keys while a form is open.** Every key is the form's but ctrl+c, ctrl+o and
  the transcript's pgup, pgdn and shift+↑/↓; home and end move in the field.
  Esc answers the form `cancel` and the turn goes on, as Esc answers the
  permission prompt. ctrl+c, which elsewhere arms quitting, stops the turn,
  as the form leaves no other key for it; the form goes with the turn. The
  `?` panel gives forms two lines, `tab ↑ ↓ space to fill in a form` and
  ctrl+c's, and leaves the rest to the form's own hint line, which names the
  keys for the focused field: the panel had 36 lines, two columns of 18 at
  80×24, and a line a key would push its last ones off the screen. With 38
  it is 19 rows, so at 80×24 no transcript row is left above the box while
  the panel is open.
  A key test presses every key on a form in each of its states.
- **The record** is the permission answer's shape: `⏺ fake asked: <message>`,
  then `⎿ Answered · 7 fields`, `Declined`, `Cancelled` or, for a link,
  `Opened <the link>`, whole, so it can be copied where no browser opened;
  ctrl+o shows the values sent. A request that names a tool call draws only
  its `⎿` line, as a permission's answer does after its call.
- **Not done:** `elicitation/complete` for a link is not drawn; acpx takes the
  notification and says nothing of it. A form's draft is not kept when the
  turn ends under it. The agent's name stands in the title where the MCP
  server's would, as ACP does not name the server.
- The fake agent's `form` asks for one field of each kind and `link` for a
  link to open (`tests/fixtures/forms.ts`), and each answers `Elicitation
  answer: <action>`, with an accepted form's content as JSON on the next line.

## 2026-10-06 — Vim mode: @replit/codemirror-vim-core's engine on the draft, the textarea for insert mode

`/vim` turns vim mode on for the prompt box, and off; `editorMode` (`normal`
or `vim`, Claude Code's key and values) in the user's settings file keeps
the choice, written as `theme` is and, like it, read from no project's file.
Insert mode is the textarea as it always was; normal mode's keys go to
[`@replit/codemirror-vim-core`](https://github.com/replit/codemirror-vim)
0.1.0 (MIT, no dependencies), exact-pinned as it is pre-1.0. It is the vim
engine of `@replit/codemirror-vim` and `cm5-vim`, taken out of them to be
given any editor that answers CodeMirror 5's interface, and it carries their
motions, operators, counts, text objects and registers with the shared test
suite of 700 and more.

- **What was tried.** The engine, under `deno run` and in a `deno compile`
  binary, against an editor written for it here over a string. Every key
  the task names (h j k l, w b e, 0 $ ^, x, dd, dw, cw, D, C, i a I A o O,
  p, counts on motions and operators) did what vim does on the first run.
  Passed over: `@replit/codemirror-vim` and `monaco-vim` need their
  editors, which need a DOM; `cm5-vim` is the engine on CodeMirror 5
  itself, DOM again; `pi-vim`, `pi-vimotion` and `@burneikis/pi-vim` are
  extensions of pi's own editor, and `@naxodev/opencode-vim` of OpenCode's;
  no Ink component has modes.
- **The editor is chord's** (`src/ui/vim.ts`): the draft's lines and one
  cursor, with the part of CodeMirror 5's interface that normal mode's
  motions and operators reach. Two things it must do as CodeMirror
  does: a position past the last line clips to the end of
  the text (or `dd` on the last line takes only its line break), and `o`
  and `O` open their line through `commands.newlineAndIndent`. An error the
  engine throws drops the command and leaves the draft as it was.
- **Each key is played on a fresh editor** made from the draft and the
  cursor, with the keys of a command still being typed (`2`, `d`) played
  first and the register and the column `j` and `k` aim for put back, so
  what a key does is a function of (text, cursor, state) and the tests
  reach it without a terminal. `u` is chord's: the engine leaves undo to
  its editor. Each change, and everything insert mode typed between
  entering it and Esc, is one step.
- **Keys the engine is not given**: anything that would open a visual
  selection, a search, an ex line, a macro or a mark, none of which the box
  draws. After `f`, `t`, `r` or an operator's `i`/`a`, any character goes.
  `k` on the first line and `j` on the last walk history, as ↑ and ↓ do.
  A placeholder (`[Image #N]`) cut into by `x`, `dw` or any deletion goes
  whole, through `cutPlaceholder`, and the register gets the whole of it.
- **react-ink-textarea's API decides the rest.** Its keybindings switch off
  ctrl and arrow chords but never a printable key, so in normal mode it
  loses focus and the window takes the keys. Unfocused it draws no cursor,
  so normal mode's is a label on the character under it, in standout, and
  on an empty line a block after the gutter. A burst of keys read at once
  (`dw`, `ihi`) is played key by key, and what follows a key that enters
  insert mode is typed at the cursor.
- **Esc, as Claude Code maps it.** In insert mode Esc goes to normal mode;
  in normal mode it means what it means without vim. So a running turn, or
  a bash command, takes Esc twice from insert mode, once from normal; the
  first Esc on a half-typed command drops it. Every list, picker, panel,
  permission and form still takes the first Esc before vim does, and ctrl+c
  is untouched. Enter sends from either mode, and the box comes back empty
  in insert mode.
- **The mark** is Claude Code's `-- INSERT --`, dim, first on the status
  line's left, before a mode or the hint. Claude Code marks insert mode
  only; chord marks `-- NORMAL --` too, as the box starts in insert mode and
  normal mode is the one keys are surprising in.
- **The `?` panel** has one line, `/vim for vim mode`, and no line per vim
  key, as a vim user knows them. At 80×24 it fills the rows the transcript
  had left above the box.

## 2026-10-06 — Custom keybindings: Claude Code's file shape, a parser and matcher of chord's own

`~/.config/chord/keybindings.json` (under `$XDG_CONFIG_HOME` when that is
set), beside the user's settings file, rebinds chord's actions. chord never
reads or writes Claude Code's `~/.claude/keybindings.json`; a person copies
what they want over. There is no project file, as keys belong to a person's
hands rather than a project, as `theme` and `editorMode` do.

- **The file is Claude Code's shape**: `{ "bindings": [{ "context",
  "bindings": { "<keys>": "<action>" | null } }] }`, with Claude Code's
  context names, its action names wherever it has the action
  (`chat:submit`, `chat:newline`, `chat:externalEditor`,
  `chat:imagePaste`, `chat:cycleMode`, `chat:cancel`, `history:*`,
  `historySearch:*`, `autocomplete:*`, `confirm:no`, `help:dismiss`,
  `select:cancel`, `scroll:*`, `app:toggleTranscript`), its keystroke
  syntax (modifiers and their aliases, case-insensitive names, named keys)
  and its chords (`ctrl+x ctrl+e`, 3 s for the next key). Its semantics too:
  a binding replaces what its key did in its context, `null` takes a key
  away, and ctrl+c, ctrl+d, ctrl+m, ctrl+[, ctrl+i and ctrl+h cannot be
  rebound. `$schema` and `$docs` are let through.
- **Where chord differs.** The contexts are the eight chord has (`Global`,
  `Chat`, `Autocomplete`, `Confirmation`, `Help`, `HistorySearch`, `Select`,
  `Scroll`); another, such as `Transcript`, is reported and its block left
  out, as its keys would mean something else here. An action must sit in
  its own context. `help:toggle`, `?` on an empty prompt, and the
  `session:` actions on the window's sessions are chord's own names. The defaults are chord's keys as they were, so some differ from
  Claude Code's: `chat:newline` is shift+enter, alt+enter, ctrl+j and
  ctrl+enter; `historySearch:accept` is tab and enter and
  `historySearch:cancel` Esc; `scroll:lineUp` and `lineDown` are shift+↑
  and shift+↓. Not rebindable yet: the lists' own ↑ ↓ j k, digits and Enter
  (ink-select-input reads them itself, so only `select:cancel` and
  `confirm:no` are chord's), the form's keys, and vim's, which Claude Code
  does not remap either. `cmd` matches where the terminal reports super
  through kitty's keyboard protocol; `wheelup`/`wheeldown` are refused, as
  the wheel always scrolls the transcript (CHD-31) and no binding moves it.
- **Problems are said, not fatal.** An unknown context, action or key, a
  reserved key, an action outside its context, one key bound twice in a
  context, and a key that means two actions at once — a key a Global or
  Scroll action holds bound in another context (the transcript scrolls
  before any context's keys are looked at, even under a form), or a key that
  starts another action's chord — are each a problem, and that binding is
  left out; the rest of the file still applies. Claude Code lets the narrower context win silently;
  chord says so, since a key that does one of two things is the surprise
  the task asks to report. Each problem goes to stderr before the window
  and to the transcript as a warning line, as the settings files' do, and
  the status line says how many and the first until the draft is first
  touched: `keybindings.json: 3 problems · ctrl+o already bound to
  app:toggleTranscript, not to chat:externalEditor`. The count leads, as a
  narrow window cuts the end of the line, and the transcript has them all.
  A file that is not JSON or has no `bindings` list counts for nothing.
- **Hints follow the keys.** The `?` panel names the bound key of each
  line whose action was rebound and drops a line whose action has none;
  with no file it is the table it was, entry for entry, which a test holds.
  The working line's `esc to interrupt`, bash mode's `esc to stop`,
  `(shift+tab to cycle)`, `ctrl+o to expand`, `? for shortcuts`,
  `end to jump to the bottom`, `Esc to reject`, the pickers' `Esc to
  close` and `/resume`'s refusal name the bound key, or say nothing of one
  when none is bound.
- **The prompt's textarea keeps its own keys where it can.** react-ink-textarea
  sends on Enter, breaks the line on ctrl+j, ctrl+enter, shift+enter and
  alt+enter, and hands ↑ and ↓ at its edges to history. Its per-chord
  `keybindings` switch turns off whichever of those is no longer bound to
  its action, and any of its editing keys (ctrl+a, ctrl+e, ctrl+k…) that a
  binding gives to an action, so a key does one thing; a key bound to
  `chat:submit`, `chat:newline` or `history:*` that the textarea does not
  have is chord's, and the box loses focus while a chord waits for its next
  key. A chord is waited for only while its action would run: a `Help`
  chord's first key is nothing while the panel is closed, an `Autocomplete`
  one while no list is open, and a `chat:externalEditor` one while the
  search line, which keeps the editor shut, takes the typing. The first key
  of such a chord is off in the textarea for as long as the chord is live,
  so the first key of `ctrl+k ctrl+e` does not cut the line before the box
  lets go, and is the textarea's own again once it is not. ctrl+j reaches a terminal
  program as the line feed byte, which Ink reports as the text `\n` and the
  textarea types whatever its own ctrl+j is set to; chord reads that byte as
  ctrl+j and takes the line break back where ctrl+j is not
  `chat:newline`. A paste comes through bracketed paste, so its line breaks
  stay. A line break typed that way redraws the box, which costs the
  textarea's undo for that step.
- **What was tried.** Each candidate under `deno run` and in a `deno
  compile` binary, with a script that bound keys and fed key events:
  - [`ctrl-keys`](https://github.com/webNeat/ctrl-keys) 1.0.6 has sequences
    and Claude Code's modifier names, but takes any string: `ctrl+foo` binds
    silently (its code is 0) and then fires on any key the encoding does not
    know, so it cannot report an unknown key. It matches a sequence against
    the last keys pressed with no timeout and no way to ask whether a key
    starts one, so a chord's first key cannot be held back from the prompt
    box, and it has no key-to-action lookup for conflicts or for naming a
    bound key. It reads DOM `KeyboardEvent`s, which Ink's keys would have
    to be dressed up as.
  - [`is-hotkey`](https://github.com/ianstormtaylor/is-hotkey) 0.2.0 (last
    released 2020) parses one keystroke but no chord, reads `ctl+g` as
    ctrl+g rather than refusing it, takes `cmd` for `meta` where Claude
    Code's `meta` is alt, says "Unknown modifier" of an unknown key, and
    matches on the legacy `which` field Ink does not give.
  - Not run, from their READMEs and manifests: `tinykeys`, `hotkeys-js`,
    `@github/hotkey` and `@zag-js/hotkeys` listen on a DOM element, and
    `@opentui/keymap` is OpenTUI's and brings `@opentui/core`. npm has no
    keybinding package for Ink. So the parser, the matcher and the
    conflict check are chord's (`src/ui/bindings.ts`), on the key presses
    Ink already parses.
- **No JSON-with-comments reader.** Claude Code's file is plain JSON, and
  so is chord's, read with `JSON.parse` as the settings files are; a file
  copied over parses the same.

## 2026-10-06 — `/resume` across directories: chord's own records, ctrl+a, and a session elsewhere is refused with its command

`/resume`'s ctrl+a lists the agent's earlier sessions from every directory,
newest first, each row naming its directory between when it was used and its
first prompt; ctrl+a again goes back to this directory's. FEATURES carries
the row on ACP's `session/list`, but chord needs none of it. Checked under
`deno run` in tmux at 120×40 and 80×24 against the fake agent, and under
`deno test`.

- **The list is chord's records, not the agent's.** acpx 0.19.4's runtime has
  no `listSessions` (its lower-level client has one, which `acpx/runtime`
  does not reach). It does not need one: chord's session records, the ones
  `--continue` and `--resume` read, are one store in chord's state directory
  for every directory, each record naming its `cwd`. So one read lists them
  all, and the scope is a filter on what came back (`earlierSessions`
  without a `cwd`, then `sessionsIn`). A session the agent kept but chord
  never saw is not on the list, as it is not on this directory's; that is
  what `session/list` would add, and it waits for acpx.
- **ctrl+a, Claude Code's key and order.** Claude Code's `/resume` names it
  `ctrl+a … show all projects` and `only show current repo`. chord's picker
  opens on this directory, as Claude Code's does, even when this directory
  has none, saying `No earlier sessions in this directory.` with the key to
  reach the others; only when no directory has one does `/resume` say so in
  the transcript instead. Claude Code binds no action name to the key, so
  chord's is its own, `select:toggleScope` in `Select`, rebindable as
  `select:cancel` is; `Select` is not the prompt box's context, so ctrl+a
  stays the textarea's line start whenever the picker is shut.
- **A session from another directory is refused, with the command that
  opens it.** A tab's directory is read in `main.tsx` before the window
  opens and everything in the tab hangs on it: the project's settings file and the model and mode
  it starts on, `.mcp.json` and the MCP servers the agent was given, the
  notification channel, `@`'s files, bash mode's shell, `/status` and the
  header. Opening another directory's session in the same window would mean
  reading all of that again mid-window, or leaving the agent working in one
  directory while chord's files and shell work in another. `--resume <id>`
  already starts in the session's own directory, with that directory's
  settings and servers, so the picker says `That session is in ~/other. Quit
  and open it there with:` in the transcript, and `chord <agent> --resume
  <id>` on a line of its own below, so it is selected whole and never wraps
  mid-sentence; the session on screen stays. Claude Code does the same:
  it shows `cd <dir> && claude --resume <id>` and copies it to the clipboard.
  chord needs no `cd`, as its `--resume` moves to the directory; it copies
  nothing, as the line is in the transcript to select.
- **Directories are shortened against the home directory alone**: `~` for
  it, `~/src/app` under it, elsewhere whole, through `homePath` in
  `src/settings.ts`, which `shownPath` now uses for its own `~` (and which
  makes it show the home directory itself as `~` where it showed the whole
  path). Not relative to the working directory, as `shownPath` is, since a
  column of directories reads alike only from one root. A directory longer
  than 30 columns loses its start, where the name that tells two apart is
  not, and is cut at a `/` so its segments stay whole (`cutPath`, which
  `/mcp` already used for its config paths, over cli-truncate).
- **What was tried.** [`tildify`](https://github.com/sindresorhus/tildify)
  3.0.0 runs under `deno run` and does the shortening, but reads the home
  directory from `os.homedir()` only; the window takes its home as a prop,
  as it does for `~/` image paths, so the tests can name one. The few lines
  went beside `shownPath` instead, which already did the same for `~`.
- **The shortcuts panel keeps to 80x24.** ctrl+a is a line of its own in the
  panel, as every key that does something is, and the two lines for esc on a
  turn and on a shell command, one action between them, became one, `esc to
  interrupt or stop a command`, so the panel is no taller than it was.

## 2026-10-06 — `chord -p` takes `--permission-mode` and `--dangerously-skip-permissions`

This supersedes the permission paragraph of the `-p` entry of 2026-10-05 and
the last line of the settings entry, which kept `--permission-mode` for the
window. The owner chose two of Claude Code's three answers for a script that
needs a permission; `--allowedTools` waits.

- **`-p` starts in the mode the window would.** `--permission-mode`, else
  `permissionMode` from the files, is asked for once the oneshot session
  exists and before the prompt goes, through acpx's `setMode` and the modes
  `getStatus` reads from the agent's config options, as the window does.
  `src/session/starting.ts` is that check for both: one the agent does not
  list is not asked for, and the refusal reads the same in either place —
  `Could not start in nosuch mode, set by --permission-mode: the agent offers
  default, acceptEdits, plan` in the window, `chord: could not start in …`
  on stderr for `-p`. The turn still runs, in the agent's own mode, and the
  exit code is the turn's. acpx sets the mode through a short control
  connection and records it as `desired_mode_id`, which it asks for again on
  the turn's own connection. That was lost on a reopened record (CHD-80); a
  oneshot session is always fresh, and the fake agent's `mode` scenario,
  which says from inside the turn the mode it runs in, proves it arrives.
- **An agent that lists no modes is not asked for one**: the line says `the
  agent offers no modes` and the turn runs in the agent's own mode, in the
  window as in `-p`, whether or not the agent would have taken it. A model is
  different: an agent that lists none is asked all the same, and a refusal
  is said in the agent's own words, as before. A value the agent lists and
  refuses is said in its own words either way.
- **`--dangerously-skip-permissions` answers each request with its own allow
  option**: `allow_once`, else `allow_always`; a request that offers neither
  is refused with the usual line. acpx's `permissionMode` behind the callback
  is `approve-all` instead of `deny-all`. Each allowed request is a
  `chord: allowed <title>.` line on stderr, so a script's log shows what ran.
  It is a flag only, never a settings key, so it is typed each time, and
  without `-p` it is refused before anything else is read.

## 2026-10-06 — Several sessions in one window are chord's to build

The owner's call: open chord keeps several sessions in one window on purpose.
Its keys and its shape are its own, as CHD-114's spec set them, and it shares
nothing with Chorded but the idea. `docs/FEATURES.md` used to put "Chorded's
territory" in the Claude Code column of that row. It only ever meant that
Claude Code has no such thing, but it read as "not chord's to build", so the
cell now says "not in Claude Code".

## 2026-10-06 — Several sessions: a tab list of chord's own, each tab its own `Conversation`

CHD-114's sessions in one window start in the session layer:
`src/session/tabs.ts` holds the open sessions in tab order and the one in
front, pure, and `src/session/open_sessions.ts` gives each tab its own
`Conversation`, so its own acpx runtime and agent process. Nothing is shared
between tabs below the interface: a permission parked in one tab's
`onPermissionRequest` holds that tab's turn alone.

- **Keys, not numbers, name a tab.** A tab's number is its place in the
  strip and moves down when a tab to its left closes, as browser tabs do; its
  key is fixed while it is open, so an event from a conversation reaches its
  own tab whatever closed meanwhile. A closed tab's events are dropped.
- **Each tab's wait state is folded from `notify.ts`'s `watchWaits`,** so a
  tab waits on exactly what rings the terminal: a permission or a form or
  link while none is open (kept from when it came, until the last is
  answered or the turn ends), and a turn that ended unless cancelled or
  followed by a queued prompt. A turn ending, or failing, or an agent that
  never came up, counts as unseen only while its tab is behind, and going
  to the tab clears it; a failure is not hidden by a later reply.
- **Attention order:** tabs that wait on a permission or form, longest
  waiting first, then unseen replies and failures, oldest first, a tie to
  the tab further left. `ctrl+x a` goes to the one after the tab in front
  in that order, or the first when the front has no place in it, round to
  the first after the last, so pressing it again reaches every one. Going to
  the first one not in front would not: a tab waiting on a permission keeps
  its place once in front, and three such waits would only ever visit two.
  Where `ctrl+x a` went is remembered with its place until another tab comes
  forward, because seeing a reply takes its tab out of the order and the
  next press would otherwise start the queue over. A tie is broken by the
  tab's key, not its number: tabs open at the end and never move, so keys
  run left to right, but a number changes when a tab to its left closes,
  and a remembered place compared by number would then skip a tab.
- **No library.** An ordered list with a cursor that wraps is a few array
  operations. On npm, `cyclist` is a fixed-size ring buffer with no cursor
  or removal in the middle, and `immutable` would only stand in for array
  spreads; neither was worth a dependency.

## 2026-10-06 — Several sessions: the strip, the leader line and the `session:` keys

CHD-114's parts 7 and 9 and the leader half of 8: `ctrl+x c` opens a session
of the front one's agent, `ctrl+x n`/`p` (and `ctrl+n`/`ctrl+p` as the
second key) and `ctrl+x 1`–`9` switch, and the header grows a strip once two
are open.

- **The strip is a layout of chord's own,** `src/ui/strip.ts`, pure, with
  `App.tsx` only painting its pieces. `ink-tab` 5.2.0, the Ink tabs
  component, was tried: it runs under Ink 8 (with a peer warning), but it
  draws `1. fake | 2. claude ●` in its own format, owns the arrow and Tab
  keys, and has no way to shrink or to hold the directory, so it fits
  neither the mock nor the keys. The gaps are the mocks': three spaces
  around the front tab's padding, so it reads as four, four between the
  tabs behind, three once they have dropped their names.
- **The header's directory stays the path it was,** whole as the working
  directory is given, cut at a `/` once the strip needs the room. The mocks
  show `~/src/app` only as a stand-in for a directory.
- **The leader line replaces `ctrl+x pressed · waiting for the next key…`**
  for every chord, the person's own too: it is built from the chords that
  would run now and start with the keys held, so a rebound or removed
  action shows as bound. Session actions come first in the spec's order,
  any other action follows with the panel's words for it; too wide, it
  takes the short words, then drops items from the end.
- **A chord begun takes the next key from every widget.** The permission
  prompt, forms, link prompts and pickers stop listening while keys are
  held, and `keyCommand` matches the session actions before a form's own
  keys, so `ctrl+x 2` never answers "Always allow". `ctrl+x` is the
  sessions' leader everywhere, the search line included.
- **One panel line for every session action,** `ctrl + x then a key for
  sessions`, while any of them is bound after `ctrl+x`; an action bound to
  keys that do not start with it gets a line of its own (`ctrl + n for the
  next session`). `ctrl + d or ctrl + c twice to quit` takes the place of
  two lines, so the panel keeps its 19 rows at 80×24.
- **Left for the later parts:** `ctrl+x w` and `k` (`ctrl+x a` came with
  the next entry, `ctrl+x k` with the one on closing and quitting, `ctrl+x
  w` with the one on the sessions picker), so the leader line offers only what is bound now, and the status line's word on a tenth
  `ctrl+x c`, which names `ctrl+x k` (it came with `/new`'s entry).

## 2026-10-06 — Quitting is bounded, whatever the agent answers

A quit waited on acpx before it started counting: `close` waited for
`runtime.close`, and only then did the five-second exit grace begin. acpx
closes a session under the same per-session lock its config changes and
model changes hold, and its `shutdown` waits for every lock and pending task
before it stops a retained session's agent; an agent that never answers a
`session/set_config_option` held both forever, with the agent still running
and the terminal still in the alternate screen. A session still starting was
worse: the conversation waited for `ensureSession`, which an agent that never
answers `initialize` holds for acpx's whole startup deadline.

What acpx offers was tried first. `runtime.close` and `runtime.shutdown` take
no deadline and no signal; `ensureSession` takes no signal either. The
runtime's `timeoutMs` bounds startup and control requests, but turns too, so
it would end a long turn the person is waiting on. `processLifecycle` gives
the agent's pid and its exit, which chord already keeps. So the bound is
chord's, in `src/session/session.ts`, on top of those:

- **The exit grace starts when chord lets go,** not when acpx is done: five
  seconds for the agent to exit, then SIGKILL, then two for the exit to be
  seen, as before.
- **acpx's close gets three seconds,** then its shutdown starts anyway, and
  that gets one second once the agent has gone; past those, nothing acpx
  still holds can spend anything. A quit on a wedged agent takes about five
  seconds; one on an agent that answers takes as long as it did.
- **A session still starting is given up.** `openSession` takes an
  `AbortSignal`; the conversation aborts it on quit, and for one `/clear` let
  go, and the open stops the agent the same way and rejects. A start given
  up on quit reports no failure.
- **A session is let go once it exists, not once it is set up.** The
  starting model and mode, and the first readings, are asked for after the
  open, and an agent may never answer them; a quit or a `/clear` closes the
  session without waiting for them, and what they would have said is
  dropped.

The fake agent's `--hang start|config|turn` wedges it at that step and makes
it ignore SIGTERM and its stdin closing, so the tests prove the bound with an
agent only SIGKILL ends.

## 2026-10-06 — A mode change goes through the agent's `mode` config option

Codex's adapter answers `session/set_mode` with an empty object and sends no
`config_option_update`, though its mode moves. acpx's `setMode` records only
the mode it asked for (`desired_mode_id`), not the agent's config options, so
the status line went on naming the old mode until a later turn, for shift+tab
and for `--permission-mode` alike (CHD-129). The mode is a security-relevant
setting, and the line must not misstate it.

`Session.setMode` now asks through acpx's `setConfigOption` on the agent's
mode config option, the one `modes()` reads, whenever the agent offers one.
acpx records the config options the agent answers with, or, when an answer
carries none, the value asked for; a refusal records nothing. So the mode
reads back right before any prompt, from Codex's adapter and Claude's alike,
both of which take `session/set_config_option` for `mode`. An agent with no
mode config option is still asked through `setMode`, as before; chord has no
modes to show for it.

This supersedes "the call is acpx's `setMode`" in the 2026-10-05 entry on
modes; the rest of that entry holds. `-p` still asks through `setMode`: it
shows no mode, and acpx asks for `desired_mode_id` again on the turn's own
connection. The fake agent's `--silent-set-mode` answers `session/set_mode` as
Codex's does, so the tests prove the reading without a real agent.

## 2026-10-06 — chord's own ACP layer on the SDK, in place of acpx/runtime

This supersedes "acpx/runtime for everything below the interface" and "the
session layer, and what acpx's in-process runtime leaves out", and with them the
stdio tee CHD-88 parked as a stop-gap. chord now has a goal acpx cannot serve:
to even agents out. What one agent leaves out of an ACP message chord fills in
where it can — a cost from the turn's tokens and the model's price, a mode read
back after an agent that answers `set_mode` with nothing, a tool call's title
carried onto its updates — so every agent draws the same way and its session
resumes with what was filled in. That needs the raw messages, and a place of
chord's own to change them before anything records or draws them. acpx is itself
that place: a normaliser with its own event model and its own session record,
where an update it has no parser for is dropped (`parsePromptEventLine`) and
nothing a caller adds can reach the record. openclaw/acpx#857 would let chord
read the raw stream, not write into acpx's model, and on 2026-10-06 it is open
with no maintainer's word; acpx main holds nothing newer than 0.19.4.

What acpx did not fit, as found while building on it: no raw messages from the
in-process runtime, so no live terminal output, subagents, compaction or fork;
`startTurn` takes text and image or audio attachments only, so no
`resource_link`; a permission answered by option kind; `elicitation/complete`
dropped; the record keeps less than the live turn (no kind, locations or content
of a call, 8000 characters a reply, 200 messages, 100 turns of usage); no
`listSessions`; nothing outside a turn but what `getStatus()` holds; `close`,
`shutdown` and `ensureSession` take no deadline or signal; a turn's result
settles a fixed second after the reply.

Writing our own is the one rule's last resort, and this is the finding it asks
for. The layer is built on `@agentclientprotocol/sdk`'s `ClientSideConnection`,
which the fake agent's side already uses; no other library fits (the list on
agentclientprotocol.com was checked: `@mastra/acp` is a Mastra agent's subagent,
`@mcpc/acp-ai-provider` an AI SDK model, the rest Python or Rust).

- **The registry is the ACP Registry's, frozen in code.** The agents are taken
  from `https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json`
  and written into a source module with each package's exact version, so a
  version moves only when chord's source does. Only the `npx` distribution is
  kept; an agent the registry offers only as a binary or through `uvx` is left
  out. `--agent-command` still overrides a name, which is how the fake agent
  runs.
- **Enrichers sit between the wire and the reducer.** Each is a pure function
  from an ACP message and the session's state to the message with what was
  missing filled in, tested against the fake agent. They keep ACP's shape on
  both sides, so one could later move into an ACP proxy (the proxy-chains RFD)
  for other clients to use.
- **The session record is chord's,** written from the enriched stream, and is
  what `--continue`, `--resume` and `/resume` read. chord has had no release, so
  acpx's records are not read and nothing migrates.
- **ACP v1 now, v2 behind version negotiation later.** v2 is a draft
  (2026-07-20); the SDK already carries its schema, Claude's and Codex's
  adapters speak v1.
- **What acpx knew is kept, not its code:** adapters that send updates after the
  prompt's answer, a mode to restore on reconnect, which of Claude's settings
  sources a session reads, quitting a wedged agent on a clock. acpx is MIT; a
  piece taken from it says so where it lands.

acpx stayed in `deno.json` until the last slice moved off it, and left with
CHD-138 (below); `deno task check` passed after each.

## 2026-10-06 — Several sessions: a session behind that needs the person

CHD-114's part 3 on screen and the notice half of 8: a tab behind that asks
for a permission or a form, or ends its turn, gets its glyph, the status line
says so, the terminal is told once with the tab named, and `ctrl+x a` goes
to it. The window never switches by itself, so a key typed in front never
lands on another tab's prompt.

- **The notice is `status.ts`'s, pure,** `waitsNotice` from the tabs behind:
  one waiting on a permission or form is named (`● 2 claude needs your
  permission`, `● 2 claude asks for input`), more are counted (`● 3
  sessions wait`); with none, a failure (`✗ 3 fake failed`, error colour)
  then a reply (`✓ 3 fake replied`, dim), counted the same way (`✓ 2
  sessions replied`, or `✗ 2 sessions ended` when one failed, which the spec
  left open). The tab in front is never in it. It goes ahead of the mode or
  the hint, with the bound key after it, `to go` while there is room; the
  words, then the hint, go before the model is cut. A message on the line,
  such as `No session waits` from `ctrl+x a` with none, stands alone.
- **The notification names the tab** through `tabs.ts`'s `tabName`: the
  agent alone while it is the only session, so one session's message reads
  as before, and `fake (2)` once there are more. Still once per wait: the
  wait is the one `watchWaits` starts, in front or not.
- **`ctrl+x a` is `session:attention`,** in `Global` like the rest, on the
  leader line after `1–9` as `a the one that waits`, or `a waits` short.
- **No library:** the notice is a choice among a handful of sentences on
  state chord already keeps.

## 2026-10-06 — The agents are the ACP Registry's, frozen by `deno task registry`

The first slice of chord's own ACP layer: `src/agents.ts` no longer asks
acpx's registry. `scripts/registry.ts` fetches
`https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json` and
writes `src/registry.ts`, with the date in its header, so a version moves only
in a reviewed diff of that file. Nothing is fetched at run time.

- **npx only.** Each agent whose `distribution` has `npx` is kept with its id,
  name, package, exact version, `args` and `env`; 22 of the registry's 41 on
  2026-10-06. One offered only as a binary or through `uvx` is left out, which
  drops Cursor, OpenCode, goose, Amp and others acpx knew; they still start
  with `agents.<name>.command` or `--agent-command`. Every agent now needs
  `npx` on the person's `PATH`. (Since 2026-10-08, uvx agents are frozen too
  and some binary ones come back by their own CLI: "Agents started by their
  own CLI", below.)
- **Names.** The registry's ids, except `claude-acp` and `codex-acp`, which
  stay `claude` and `codex` as chord always called them; the ids themselves are
  not names too, so one agent has one name in settings and session records.
  acpx's other short names that are not registry ids (`copilot`, `droid`,
  `qwen`, `kilocode`, `pi` and the like) are gone, with no alias: chord has
  had no release, and the registry's ids are what `chord agents` lists.
- **Starting one** is `npx -y <package>@<version> <args…>`. Until the transport
  slice lands, acpx still runs it: chord hands acpx a registry built from the
  one name's command through the `overrides` it already took for
  `--agent-command`, and the entry's env through `agentProcessEnv`, so acpx's
  own agents and pins are never reached. An override replaces the entry's env
  with the command.
- **npm-package-arg** (npm's own parser of `name@spec`, ^14) splits each
  package from its version in the script and says whether the version is
  exact; a tag or a range is refused rather than frozen. It runs only in the
  script, never in chord or its binary. The registry's JSON is checked by zod,
  only for the fields kept, so a field it adds later does not stop a refresh.
  No package reads the ACP Registry: npm has the adapters and the SDK, whose
  schema does not cover the registry's format.

## 2026-10-07 — The transport on the SDK: `src/acp/`

The first piece of chord's own ACP layer, built beside acpx and not yet wired to
the window. One agent process and one ACP v1 connection: start, `initialize`,
sessions, prompts, the requests the agent sends, and a bounded close.

- **`client()`, not `ClientSideConnection`.** The 2026-10-06 entry names
  `ClientSideConnection`; in SDK 1.7 it is deprecated in favour of
  `client().onRequest(...).connect(stream)`, which is what the fake agent's
  `agent()` mirrors and what acpx 0.19.4 uses too. Same SDK, same
  `ndJsonStream` on the agent's stdio.
- **Every message reaches one subscriber raw, before the SDK sees it.** A
  stream tap (`traffic.ts`) hands each JSON-RPC message, either way, to the
  subscriber in wire order, and the agent's stderr with them. The agent's
  notifications stop at the tap: the SDK only checks `session/update` against
  its zod schema, and an update of a kind it does not know fails the check and
  is reported with `console.error`, under the window — so nothing is dropped
  for being unknown and nothing is printed. Requests and responses go on to the
  SDK, which answers and matches them; so does `$/cancel_request`, which it acts
  on.
- **Turn end costs nothing.** acpx collects a turn's events into a per-turn
  result and closes it a fixed second after the reply (`SESSION_REPLY_IDLE_MS`,
  with a 5 s cap), so every turn waits a second for updates that rarely come.
  The transport has no per-turn stream to close: `prompt` settles on the
  agent's answer, and every update, before or after that answer, goes to the
  same session-wide subscriber in the order it was written. An update sent
  ahead of the answer is delivered before the answer's promise settles, since
  the tap runs first; one sent after it lands after the turn's end, and the
  reducer folds it into the session as it comes (a late `usage_update` moves
  the totals, a late chunk extends the last reply). `close()` drains: it waits
  for stdout to end after the exit, so what an agent writes as it goes still
  arrives. The cost moves to the reducer, which must take an update outside a
  turn; that is the next slice's to build.
- **Each wait takes a signal.** `openAgent` and every request take an
  `AbortSignal` that stops the wait at once with the signal's reason; a
  prompt's signal also sends `session/cancel`. A wait also ends when the agent
  exits, with the end of its stderr in the error. `cancel(sessionId)` sends
  `session/cancel` and answers that session's permission requests and forms
  still waiting on the person `cancelled` itself, as ACP asks, aborting the
  handlers' signals; the prompt then settles with the agent's own answer.
- **A permission is answered by the option the person picked,** whatever its
  kind; the handler returns ACP's `RequestPermissionResponse`. A form or link
  in a mode chord does not declare is cancelled without reaching the person.
  `elicitation/complete` reaches the subscriber like any notification.
- **`initialize` declares** ACP v1, `clientInfo` `chord` and its version,
  `elicitation.form` and `elicitation.url`, and no `fs` or `terminal`, so agents
  use their own tools (and, since, plans and compactions by id, terminal
  output as `_meta` and subagents as sessions of their own; see below). The answer is kept whole (`agent.init`); `session/load`,
  `session/resume` and `session/list` are refused without asking when its
  capabilities do not offer them. `session/set_model`, not yet stable in v1, is
  sent by name, as cursor's and dimcode's adapters answer it where they offer
  models without a `model` config option; Claude's adapter has no handler for
  it (claude-agent-acp 0.93.0) and takes a model through that option.
- **The process is chord's to stop.** The agent starts in a process group of
  its own (`detached`, as `shell.ts` does), since npx starts the adapter as a
  child and the adapter its tools. `close()` ends stdin, waits, sends SIGTERM to
  the group, waits, sends SIGKILL, and resolves only once the exit is seen —
  else `AgentExitError` — then kills whatever the agent left in its group. Each
  step waits 2 s by default; acpx waited 0.1 s, 1.5 s and 1 s inside an 8 s
  budget. `AgentExitError` and `settledWithin` moved here from
  `session/processes.ts`, which keeps acpx's half until acpx goes.
- **shell-quote splits a command line.** `--agent-command` and the settings'
  `command` may be one string; acpx split it with a tokenizer of its own.
  `shell-quote` (maintained, typed through `@types/shell-quote`, runs under
  `deno run` and in a compiled binary) splits it as a shell would, with `$NAME`
  left as written — the shell already expanded a flag, and a settings file
  names no shell — and shell syntax such as a pipe is refused.

What was taken from acpx's `src/acp/client.ts` (MIT), as lessons, not code:
stdin's end is the gentle stop for a stdio agent; read stderr always and keep
its end for a start that fails; the elicitation capability's shape
(`{ form: {}, url: {} }`); answer pending permissions `cancelled` on a cancel;
cancel an elicitation in a mode not declared; refuse `session/load` without
`loadSession`; drop the agent's notifications before the SDK rather than let it
answer or log them; `session/set_model` by name for adapters without a `model`
config option. Left behind: its process-table snapshots of descendants (a
process group reaches them without guessing at recycled pids), its per-agent
quirks (Gemini's flag, Copilot's probe, Codex's option order), which belong in
the enrichers, and its own ndjson reader: the SDK's has a 32 MiB line limit and
answers a stray non-JSON line with a parse error rather than dropping it, which
agents ignore.

## 2026-10-07 — The window and `-p` run on the transport; the reducer reads raw updates

The second piece of chord's own ACP layer: `src/session/` runs on
`src/acp/`'s transport, and nothing in `src/ui/` or `src/session/` takes a type
from `acpx/runtime` but `sessions.ts`, which still reads the session records
earlier chords left. Checked under `deno test`, and in tmux at 120×40 and 80×24
against the fake agent's `text`, `tools`, `edit`, `permission`, `plan`, `form`,
`link`, `mode`, `status`, `long` and `slow` scenarios and an interrupt, side by
side with the acpx build.

- **The reducer folds ACP's `SessionUpdate`, as the agent sent it.** Its
  `update` action replaces acpx's `event`; chunks, tool calls and their
  updates, the plan, usage, the mode and the commands are read from the wire
  shapes, and a kind it does not draw passes by. A tool call's title and kind
  now come from any update that carries them, not only from the `tool_call`,
  since acpx's placeholder title is gone. Updates are not checked against
  ACP's schema (the SDK's zod schemas are not among its exports), so the
  session layer takes a notification by its shape alone and the reducer keeps
  the last plan or command list when an update has none.
- **An update belongs to the turn on screen, else to the last.** The
  transport has no per-turn stream: every `session/update` goes to the
  session's listeners, and the conversation folds it under the turn running,
  or the last one when it came after that turn's answer or outside any turn.
  A turn ends on the agent's answer, so acpx's second of waiting after every
  reply is gone from the screen, and a late chunk extends the reply it
  belongs to.
- **The queue is chord's.** This supersedes "a prompt sent during a turn
  waits in acpx's queue": the conversation holds the prompts sent during a
  turn and sends the next once the agent has answered the one ahead. Esc
  takes them back before they were ever sent, so the agent never sees them;
  `/clear` drops them with the session, and the window keeps their text.
  A queued prompt is not sent the moment the answer comes, though: once one
  is sent, the transport cannot tell its updates from the last turn's late
  ones, which would land in the middle of the new reply. So the next queued
  prompt waits until the agent has been silent for a second, five at most,
  as acpx waited after every reply; `@std/async`'s `delay` is the abortable
  wait, so closing or `/clear` never sits it out. The answered turn stays on
  screen, still working, through the wait, as it did under acpx: the queued
  prompt reads as waiting behind it rather than stuck, and Esc still takes
  it back, which also ends the wait, as nothing is left to cancel. Waiting
  only when a prompt is queued keeps the answer and an interrupt immediate
  on screen otherwise. Folding
  by turn id was not an option: `session/update` carries none.
- **What the agent says of the session is folded, not polled.** Its config
  options, its modes and models the older way, and its slash commands come
  from `session/new`'s answer, `config_option_update`,
  `current_mode_update`, `available_commands_update` and the answers to the
  `set_*` calls (`src/session/agent_state.ts`); the conversation reports them
  whenever one of those moves them, and nothing reads `getStatus()`. The
  CHD-129 rule stands: the mode shown is the one the agent reports, and a
  `current_mode_update` moves the mode config option too, so an older answer
  cannot undo it. An agent that offers modes or models only the older way,
  in `session/new`'s `modes` or `models`, now offers them to shift+tab and
  `/model`; acpx kept neither. `session/set_model` answers with nothing, so
  an answer at all is the agent taking the model, as acpx read it.
- **A permission is answered by the option picked.** Esc answers the agent's
  reject-once option, else its reject-always one, else `cancelled`.
- **A form or link outlives no turn.** The transport asks for them
  agent-wide, not per turn as acpx did; the conversation cancels one still
  open when its turn's answer comes.
- **Usage is each turn's answer and the last `usage_update`.** A turn's tokens
  are what the agent's answer to its prompt says; the cost and the context
  window are the last `usage_update`'s. There is no record trimming its
  turns, so `/cost` no longer says its tokens may count only the last ones.
  `-p`'s JSON `usage` is the turn's tokens, and its cost the last
  `usage_update`'s.
- **`-p` is a session like the window's,** opened, asked for its starting
  mode through the mode config option as the window asks (this supersedes
  "`-p` still asks through `setMode`"), played, and closed; what the agent
  sends as it closes still reaches stdout.
- **Sessions are kept in memory only, for this part.** chord writes no
  session record: `--continue` and `/resume` find the sessions earlier chords
  recorded through acpx, and `--resume <id>`, as printed on quit, opens any
  session the agent still has. A session is opened again by id at once:
  through `session/resume` when chord's record holds the past to draw, else
  through `session/load`, whose replay is drawn as the past. A session the
  agent cannot load now fails its open, not its first turn. The resume tests
  write their records through acpx's runtime (`tests/fixtures/acpx_records.ts`).
  chord's own record is the next part.
- **`session/processes.ts` is gone.** It held acpx's half of a bounded quit;
  the transport's `close()` is the whole of it now.

## 2026-10-07 — Resume on chord's own session record

The third piece of chord's own ACP layer. This supersedes "Resume reopens
acpx's session record, and draws the past it keeps" and the "Sessions are
kept in memory only, for this part" point of the entry above:
`--continue`, `--resume <id>` and `/resume`, this directory's and every
one's, read records chord writes itself, and acpx's records and the
`carried/` store beside them are no longer read. chord has had no release,
so nothing migrates. Checked under `deno test`, and in tmux at 120×40 and
80×24 against the fake agent, a resumed session drawing its edit's diff.

- **The record is what the reducer was handed.** `Conversation` takes a
  `Recording`, which hears every event it reports, in order, before the
  window does, and each prompt as the agent got it, which the reducer never
  sees: the shell output held for it ahead of the typed text, how many
  images went after it, and the `resource_link` for each file its `@`
  mentions named (2026-10-07, CHD-145). From that it keeps each prompt, every
  `session/update` whole — a tool call's kind, locations and content, so a
  replayed edit shows its diff — each turn's result and tokens, the model,
  mode and config values whenever they move, and, on the record's first
  line, the agent's id for the session, the agent's name and the
  directory. Enrichers, once they exist, sit before the conversation
  reports, so the record holds what they filled in. Permissions, forms and
  notes are not kept; they are the person's answers in a turn that has
  ended, and the agent's updates already say what came of them.
- **One JSON Lines file a session, appended to.** `records/<uuid>.jsonl` in
  chord's state directory. An update is a line appended once it is heard
  (one write at a time, so lines land in order, and what comes during a
  write goes in the next), so a session costs a line per update rather than
  a rewrite of the whole record per turn, and a crash loses at most the
  line being written, which reading passes over. Nothing is written until a
  prompt is: a session only opened, or only looked at after a resume,
  leaves no record, or no trace in the one it came from. A record that
  cannot be written says so once, as an error line, and the session goes
  on. `-p`'s one turn is not recorded.
- **No bound.** Nothing is cut: no reply length, no count of messages or
  turns. A record grows with its session, as Claude Code's own transcripts
  do, and listing reads only each record's first line and its prompt lines
  (found by their prefix, as `JSON.stringify` writes `type` first), not the
  updates; a session's past is parsed only when it is opened.
- **Reopening.** A session chord has a record of is opened with
  `session/resume` when the agent offers it, which replays nothing, and the
  record is then the only copy of the past and is drawn from; else with
  `session/load`, whose replay is drawn and the record is not, so nothing is
  drawn twice. Either way the session goes on in the same record. An id
  chord has no record of goes to the agent as before, by `session/load`
  where offered; the past it replays starts the new record, so a later
  reopen by `session/resume`, as Claude's adapter offers, still has it.
- **A reopened past is the past, its tokens included.** Each turn's tokens
  the record kept are counted again under that turn's own id, so `/cost`
  sums the whole session once however often it is reopened. The mode,
  model, options and commands are reported after the past is drawn, so a
  mode the past moved to never stands for the one the session is in now.
- **A session belongs to the agent it was recorded for by name.** acpx
  compared the command an agent was started by, which moved with every
  adapter release; the name is what `chord <agent>` and the command printed
  on quit say.
- **A turn the record never saw end** (chord stopped mid-turn) is ended on
  screen without saying how, rather than left working.
- **What was tried.** `@std/json`'s `JsonParseStream` over
  `@std/streams`' `TextLineStream` reads JSON Lines, but a stream stops at a
  line it cannot parse, as a line cut short by a crash is; reading the file
  and parsing each line on its own is as short and passes such a line over.
  Writing a line is `JSON.stringify` and `Deno.writeTextFile`'s `append`.

## 2026-10-07 — acpx leaves the repository

The last import of `acpx/runtime` went with chord's own session record, so
`acpx` is gone from `deno.json`'s imports and its packages from `deno.lock`.
Nothing in `src` or `tests` names it but the comments that credit what was
learnt from it. What it kept out of reach — live terminal output, subagents,
compaction and rewind by `session/fork` — is open on chord's own transport and
marked so in `docs/FEATURES.md`; CHD-140 plans them.

## 2026-10-07 — The enricher chain, and its first four enrichers

The last piece of chord's own ACP layer: what an agent leaves out of a message,
chord fills in before anything reads it. Checked under `deno test`, and in tmux
at 120×40 and 80×24 against the fake agent's `--tokens-only`.

- **The chain stands on the wire.** The transport takes a relay
  (`src/acp/traffic.ts`) between the agent's stdio and everything else: it
  hears each message chord sends and turns each one the agent sends into the
  messages read in its place. The SDK, the session's state, the record, the
  window and `-p` see only what it leaves, so an answer is enriched as much as
  an update — the SDK matches `session/prompt`'s answer only after the cost
  for it has gone ahead — and nothing upstream needs to know enrichers exist.
  This is where an ACP proxy stands in the proxy-chains RFD, and the chain
  keeps ACP's shape both sides, so it could move into one. The subscriber
  that `traffic.ts` calls raw now hears what the relay left.
- **Each enricher is pure,** from one message and what the chain knows (each
  session's options, models and modes as `agent_state.ts` folds them, its
  tool calls' titles and kinds, the agent's last context and whether it ever
  gave a cost, chord's estimate so far; chord's open requests by id) to the
  messages in its place (`src/session/enrich.ts`, `enrichers.ts`). What the
  chain knows is folded from the traffic both ways after enriching, so a
  later enricher reads what an earlier one filled in, and a cost it made
  counts toward the next.
- **What chord filled in says so.** `_meta`'s `chord/filled` lists the fields
  chord wrote, on the update, the call or the answer. A cost, a window or a
  context used that chord filled in is its estimate: `/cost` says `(chord's
  estimate)` after the cost, `/context` after the figures, the status line
  puts `~` ahead of the context used, and `-p`'s JSON says `cost_estimated:
  true` beside `total_cost_usd`. The status line shows no cost, so the mark
  there is on the context it shows.
- **A cost from the tokens.** For an agent that has given no cost of its own,
  a turn whose answer carries its tokens is priced on the session's model,
  and a `usage_update` with the session's estimate so far goes ahead of the
  answer, as Claude's adapter sends its own: the context as the agent last
  gave it, else the turn's tokens in and out, which for a turn of several
  requests counts what went in more than once. An agent's own costless
  `usage_update` gets the estimate so far. Once an agent gives a cost, chord
  gives none. A session reopened from chord's record goes on from the
  estimate the record holds; the agent replays nothing then.
- **ACP does not say whether `inputTokens` includes the cache.** Anthropic's
  counts keep them apart, OpenAI's include the cache in the input. The
  agent's `totalTokens` says which sum it made; without one the counts are
  taken as apart, as ACP lists them.
- **The window from the model** for a `usage_update` whose size is not
  positive; a window nobody knows draws no context used rather than `100%`.
- **A tool call's title and kind** are carried onto its `tool_call_update`s
  and onto a permission request about it, so `-p`'s refused and allowed
  lines and the record name the call as the window does.
- **A mode read back.** An empty answer to `session/set_mode` gets the
  `current_mode_update` it left out, unless the agent already reported that
  mode; an answer to `session/set_config_option` for the mode that carries no
  options gets them as they now stand. Neither is filled in when the agent
  reported the mode while the request was open — a `current_mode_update`, or
  config options with the mode moved — since that mode may not be the one
  asked for and the agent's word holds. The fake's `--silent-set-mode` now
  answers the mode's config option that way too, which is what the window
  sends, so the Codex tests go through the enricher.
- **@pydantic/genai-prices for prices and windows**, exact-pinned at 0.1.13
  as it is pre-1.0. Its data is in the package, so nothing is fetched and
  the data moves with the version, as the registry's does with its source;
  `updatePrices` is never called. It matches a model by rules per provider,
  so `gpt-5.3-codex`, a dated Claude id and the like are found; chord tries
  the id, then the id without a `[1m]`, then each side of a slash, for
  Codex's `model/effort` and a router's `provider/model`. Prices are in
  dollars. Runs under `deno run` and in a compiled binary. Tried:
  **tokenlens** (models.dev's data in packages, but last published
  2025-10, a year behind); **models.dev's `api.json`** and **LiteLLM's
  `model_prices_and_context_window.json`**, both maintained, but each a
  file to fetch and freeze with a matcher of chord's own for the names
  agents give, which genai-prices already is. Claude's adapter names its
  models `default`, `opus` and the like, which no data matches; it gives its
  own cost and window, so nothing is lost.

## 2026-10-07 — An `@` mention goes beside its path as a `resource_link`

With acpx gone, the prompt is chord's to build, so each `@path` a prompt names
now also goes to the agent as ACP's block for it: the text stays as typed, and
after it (and after its images) comes a `resource_link` for each file named,
once each, in the order typed, its `uri` the file's absolute `file://` URL and
its `name` the path as typed. The prompt on screen does not change.

- **A link, not an embedded resource.** Claude's adapter (claude-agent-acp
  0.86.0) turns a `file://` link into the text `[@<basename>](<uri>)`, and
  Codex's (codex-acp 2.1.1) into `[@<name>](<uri>)`, name first, which is
  why the name is the path as typed. Neither reads the file, and both read
  it with their own tools, so chord sends no file contents. Both advertise
  `promptCapabilities.embeddedContext`, but that governs embedded
  `resource` blocks only: ACP v1's schema makes text and `resource_link`
  the baseline every agent must take, so every agent gets the links.
- **Only what `@` would offer.** The typed paths (`mentionsIn` in
  `src/ui/mentions.ts`, quoted ones as a pick writes them) are matched
  against the finder's own walk of the session's directory
  (`mentionLinks` in `src/files.ts`), so a directory, a path to nothing,
  one outside the tree or one `.gitignore` leaves out stays text alone.
  The walk runs only for a prompt that mentions something; one that fails
  sends the text without links, which names the paths anyway. A cancel
  while it runs keeps the prompt back: it never reaches the agent, and the
  record keeps neither it nor its end, so a resumed session does not show
  a turn that never was.
- **The typed text alone is read for mentions.** Shell output held for the
  prompt rides ahead of it in the same text block, and an `@` in that
  output is not the person's.
- **The mentions are read by a few lines of our own, the inverse of what a
  pick writes.** Three libraries were tried under `deno run` on prompts such
  as `look at @src/a.ts @docs and @"my notes.md"`, and none fits.
  linkifyjs 4.1.4 with linkify-plugin-mention reads `@src/a.ts` as
  `@src/a` and `@deno.json` as `@deno`: its mentions are user names, which
  end at a dot (4.3.3, the latest, does not even resolve under Deno, its
  plugin pinning `==4.3.3`). twitter-text 3's `extractMentions` takes
  Twitter handles alone, `docs` and nothing with a slash. shell-quote, in
  chord already, splits the quoted path right but reads prose as a shell
  line: `#` drops the rest of the prompt as a comment, `$HOME` vanishes,
  `@src/*.ts` turns into a glob, and a mention inside a quoted phrase is
  lost in its token. `mentionsIn` is one regular expression for exactly
  what `insertMention` writes, `@path` or `@"path with spaces"` after a
  space or at a line's start, and whether each is a file is left to the
  finder's walk.
- **A resumed session draws the prompt once.** chord's record keeps the
  prompt as sent: its text, and the links that went with it, which draw
  nothing; an agent's replay of a prompt with links draws the text alone,
  where it used to add each link's URI to it. The record is written once
  the walk ends and the prompt goes, so it holds the links found, not the
  ones typed.
- **`-p` sends none.** Its prompt has no finder behind it and joins piped
  input to the text, so it goes as text, as before.

## 2026-10-07 — A command's output comes as the tool call's `_meta`, and the reducer folds it

chord runs no terminals for an agent and does not mean to: ACP v1's
`terminal/*` methods would have chord run the agent's commands, and agents
run them well enough themselves. What chord wants is to see what they
write. ACP v1 has no field for that (the v2 draft's display-only terminals,
`terminal_update` and `terminal_output_chunk`, are not negotiated yet), but
both adapters chord starts by name send it under the tool call's `_meta`,
keyed by `terminal_id`: `terminal_info` (and its `cwd`),
`terminal_output_delta` (a piece to append), `terminal_output` (the whole,
to replace) and `terminal_exit` (`exit_code`, `signal`).

- **`clientCapabilities._meta.terminal_output_delta: true`.** Codex's adapter
  (codex-acp 2.1.1) sends a shell call's output in pieces to any client, as
  it comes, and the last of it with the exit. Claude's (claude-agent-acp
  0.86.0) sends it only to a client that sets `terminal_output_delta` or
  `terminal_output` there, and then once, when the command is done, before
  its exit; to any other it sends the output as one `console` code block in
  the call's content. chord asks for the pieces, the form Codex's adapter
  already sends, so both fold one way. Claude's Bash calls then lose that
  code block, and draw the terminal's output in its place (below).
- **The reducer folds it into the call** (`terminals` on a `ToolCall`, in
  `transcript.ts`): each terminal its content or `terminal_info` names, in
  that order, with its output, directory, exit code and signal; in one
  update, info first, then output, then the exit, as Codex's last update
  carries the end of the output and the exit together. Each field is read
  by its own zod schema, so one malformed field leaves the rest of the
  update.
- **Output is kept as a screen would leave it, plain text** (CHD-196).
  Each delta is written through `src/session/terminal_text.ts` as it is
  folded: `\r` goes back to the line's start and what follows overwrites,
  `\n` starts a line, backspace, a tab to the next eighth column, erase in
  line (`CSI K`, 0, 1 and 2), and the cursor moves up and down within the
  lines kept and along the line (`CSI A`–`G`) act, columns counted in cells
  by grapheme and string-width. A move right or a tab stops at column
  `COLUMN_LIMIT` (1000), the margin a state with no width has, so a move
  of a billion columns pads no line with a billion blanks; text runs past
  it. What a delta begins with is read together with the character before
  the cursor, so a mark, a joiner, a flag's second half or a surrogate's
  second half split off by a delta joins its character as it would whole;
  every other escape (SGR, OSC 8 and every
  other OSC, DCS, SOS, PM and APC, escapes with intermediates, C1 forms)
  and every other control is dropped. The escapes are read as DEC's VT500
  parser reads them, so a CAN, a SUB, an `ESC` or a C1 byte ends whatever
  was open, and an OSC an `ESC` breaks off is gone. An escape a delta ends
  inside is held as the parser state it left (its kind, and a CSI's
  parameters up to sixteen characters), never its bytes, so an OSC body
  or a run of intermediates that never ends grows nothing. Of a long run
  only the last `OUTPUT_LIMIT` characters stay, from a line's start (or
  within the last line, at a grapheme, when it alone outruns the bound, so
  a cluster that does not fit whole goes whole): a
  running command's latest lines are the ones to see, where bash mode
  keeps the start, as the context the agent reads. With no escape left in
  the state, the cut has nothing to protect: six fixes in a row (CHD-146,
  CHD-155, CHD-157, CHD-178, CHD-190, CHD-195) had kept a cut of the raw
  output outside an escape and each opened another edge. The cursor is
  kept with the text only when it is not at the end, so a terminal that
  only appends is its output alone.
- **[@ansi-tools/parser](https://github.com/webpro/ANSI.tools/tree/main/packages/parser)
  1.1, tried as the tokenizer under the line model, and not used for it.**
  Its tokenizer reads a whole string; nothing of its state carries from one
  call to the next, so an escape a delta ends inside would have to be held
  as its bytes and read again with the next delta, which is the unbounded
  hold this replaces, and an escape it has no final for yet looks like one
  that ended. The parser stays in chord for the mouse (`src/mouse.ts`).
- **[@xterm/headless](https://github.com/xtermjs/xterm.js) 5.5 tried, and
  passed over.** It runs under `deno run` and in a `deno compile` binary,
  but its `write` parses asynchronously (the buffer is still empty when it
  returns, and filled only in its callback) where the reducer is
  synchronous; it lays lines out to a column count of its own, where the
  state has no width; a bare `\n` keeps the column, as a raw terminal does;
  and its buffer is an object graph, not plain data the transcript can
  hold and replay. Others looked at: escape-carriage 1.3 applies `\r` to a
  whole string but drops no escape and holds nothing across pieces;
  ghostty-opentui and @wterm/core are emulators behind native or WASM code
  that also need a width. The state machine is under two hundred lines and
  pure.
- **A resumed session folds the same,** since chord's record keeps every
  update whole, `_meta` included.
- **No library for the fold itself.** It is a fold of four small objects
  by id; zod, already in chord, reads them.

## 2026-10-07 — A command's output is drawn under its call, folded to its end

A tool call's terminals (above) draw under its `⎿` as Claude Code draws a
Bash call's output, in place of the `Output in a terminal` line every
terminal read as until now: dim as the call's other lines, each cut at the
window's edge, its last three lines while folded with `… +N lines (ctrl+o
to expand)` under them, the whole on ctrl+o, then `Exit code N` (or
`Killed by SIGNAL`) in the error tone. `src/ui/terminal.ts` is the pure
part; the component only draws it.

- **The fold keeps the end, not the start.** A text result keeps its first
  lines, as before; a terminal's newest lines are what a running command is
  doing, and once it is over they are where its result and its error are.
  The first of the kept lines is still the first under `⎿`, and the count
  of the hidden ones sits under them, as everywhere else in the transcript.
- **A terminal that has written nothing draws nothing,** so a call whose
  output has not come (Claude's, until its command is done) keeps its
  `Running…`; once it ends with no output it says `(No output)`, as Claude
  Code does.
- **A failing exit is the failure in words.** The call's own `Failed` line
  is left out where the exit already says it, and a failed call with no
  lines of text no longer reads a bare `Error: `.
- **Escapes never reach the screen,** because the reducer keeps none
  (above, CHD-196): `src/ui/terminal.ts` draws the output as it is, with
  only the blank after its last line trimmed. A killing signal's name,
  which the agent sends, is kept as plain as the output, so it cannot
  colour its own note. Until CHD-196 the reducer kept the raw output and
  the drawing stripped it; Ink's own tokenizer,
  [@alcalzone/ansi-tokenize](https://github.com/AlCalzone/ansi-tokenize)
  0.2, was tried for that and did no better than strip-ansi: it leaves an
  unfinished escape as text and keeps a DCS's payload.
- **The fake's `bash` takes half a second** before its output, as a real
  command takes some, so its call is seen working before the output comes.

## 2026-10-07 — Compaction: by id, one entry, the summary behind ctrl+o

chord declares `clientCapabilities.session.compaction` (`{}`), ACP's
unstable compaction contract in SDK 1.7.0. Claude's adapter (0.86.0) and
Codex's (2.1.1) then send a compaction as `compaction_update`s by
`compactionId` — `in_progress`, then `completed`, `failed` or `cancelled` —
and Claude's streams the summary it keeps as `compaction_summary_chunk`s
between them; Codex's sends no summary. Without the capability both send a
`Compact conversation` tool call of kind `think`, which carries no summary.
`/compact` stays the agent's own slash command; chord adds none.

- **The reducer folds a compaction into one transcript entry by its id**,
  where its first update put it, as ACP says the first update fixes its
  place. `summary` and `error` are patches: left out, kept; `null` (or a
  `summary` of `[]`), cleared; a value, replaced, so a whole summary on the
  last update takes the place of the chunks. A first update that is
  already the last, as a replay sends, still makes the entry; a chunk for
  an id never opened is dropped, as ACP sends none before one.
- **Drawn as Claude Code draws it.** While it runs within a turn the
  spinner reads `Compacting conversation…` in place of `Working…`, and the
  transcript draws nothing for it, as Claude Code swaps its spinner's
  message on `compact_start`; outside a turn, with no spinner to say it,
  the transcript draws `✻ Compacting conversation…` in the working colour.
  Then `⎿ Conversation compacted (ctrl+o for
  history)` dim under what asked for it, the key named only while there is
  a summary to open; `⎿ Compaction failed: <error>` or `⎿ Compaction
  cancelled` in the error colour. ctrl+o's view draws the summary under
  the line, as markdown, with the reply renderer. The wording is
  `src/ui/compaction.ts`, pure; the component only draws it.
- **A resumed session draws it the same**, as the record keeps every
  update whole and replays it to the reducer.
- **No library:** the entry is a few lines of state and a line of words;
  the summary goes through the markdown renderer chord already has.

## 2026-10-07 — Subagents: one ACP shape, each child's work under its parent

chord declares `clientCapabilities.subagents` (`{}`). Claude's adapter
(claude-agent-acp 0.86.0) and Codex's (codex-acp 2.1.1) then announce each
subagent to its parent with `subagent_spawned` (`subagentSessionId`, `name`,
`task`, sometimes `prompt`, `capabilities`) and end it with
`subagent_state_update` (`completed`, `failed`, `cancelled` or
`disconnected`), the shape of ACP's draft PR #1992, and send everything the
subagent does — chunks, tool calls, plans, permission requests — under the
subagent's own session id. Without the capability, Claude's adapter stamps a
child's updates into the parent's under `_meta.claudeCode.parentToolUseId`,
its own format, and Codex's sends only its `spawnAgent` and `wait` calls; so
the capability is the one way that serves both. The window draws it to
CHD-149's design (the next entry). Checked under `deno test`
against the fake agent, live and resumed; no live agent was asked.

- **One shape, by an enricher.** SDK 1.7.0's schema names the same thing
  differently: `subagent_update` (`sessionId`, `title`, `description`,
  `capabilities`, `state` as an object), unstable. `subagentShape`, first in
  the chain, turns the adapters' two updates into it: `subagentSessionId`
  becomes `sessionId`, `name` `title`, `task` `description`, a state word
  `{ state: word }`, and whatever else the draft said, with its own kind,
  goes under `_meta`'s `chord/subagent_draft`, so nothing is lost. An agent
  that already sends `subagent_update` passes untouched. The rest of chord
  reads one ACP shape, and a later SDK or adapter change touches one
  enricher.
- **A subagent's traffic is its parent session's.** The transport drops
  nothing by session id; `session.ts` did, handing its listeners only the
  session it opened. It now follows the session's tree (`subagents.ts`): a
  `subagent_update` from the session or one of its subagents adds the
  subagent it names, as ACP sends it before any of that subagent's own
  traffic, and each of their updates reaches the listeners with the
  subagent's id beside it. A session nobody announced is still dropped. The
  session's own state (modes, options, commands) folds only its own
  updates; `-p` prints only the parent's words.
- **The reducer holds each subagent apart.** A `subagent` entry stands where
  its first update came among its parent's entries, and every later update
  changes it there, so subagents that came back to back stay together with
  nothing of the parent's between them. It holds the title, the
  description, the state, its own entries (messages, thoughts, calls with
  their status, its own subagents, nested at any depth) and its plan, with
  where in its entries the plan first came; a subagent's plan never reaches
  the list above the prompt, nor its usage, modes or commands the session's.
  Its work folds through the same reducer the session's does. An update for
  a subagent the transcript does not hold is dropped rather than drawn as
  the parent's. A reopened subagent (`<id>:generation:N`, as both adapters
  reopen one) is a new entry, and the suffix is not read.
- **States.** The adapters' four words are kept as they come; ACP's
  `running` and `requires_action` read as running, `idle` as completed, and
  `unknown` or a word chord does not know keeps the state there was. A
  turn that ends cancelled cancels every subagent still running, as both
  adapters do and then say; one that ends on its own leaves them running, as
  Claude's background agents outlive it (`runningSubagents` counts them for
  the window). The agent's process exiting, outside a close or a `/clear`,
  disconnects those still running, and so does a past reopened in another
  agent for those it never saw end.
- **Times on chord's clock, kept in the record.** No update carries a time,
  so the conversation stamps `at` on each `subagent_update` it hears, and
  the record keeps it on the line; a filled ending takes the time of the
  Esc that caused it (the record now keeps each interrupt) or of the exit
  (the record keeps that too). A replay through `session/load` has no times
  and makes none up.
- **A subagent's permission request is answered like any other.** It
  reaches the same handler; its wait names the subagent (`subagentId`), so
  the window can say who asks and find the request by the call it is for
  (`waitingOn`), and its answer goes into the subagent's entries. Esc
  cancels the parent's turn as before; the transport now also answers
  `cancelled` to what the session's subagents have waiting, as their work
  is the turn's. A request outside any turn is still refused, so a
  subagent that outlives its turn and then asks is refused, as the session
  itself would be.
- **The record keeps what the reducer was handed**, as before: an update's
  line gains the subagent it was for and its time, and two lines join it,
  each interrupt and the agent's exit. Permissions are still not kept; the
  call's own update says what came of one.
- **No library.** The shapes are the SDK's own types; the fold is a few
  functions over the transcript's entries, and the session tree a set.

## 2026-10-07 — Subagents drawn as blocks under the turn, to CHD-149's design

A subagent draws where its spawn came among its parent's entries, as a block
shaped like a tool call, `⏺ Agent(<title>)`: while it runs, the headlines of
its latest three calls under `⎿` and `+N more tool uses`, or `Initializing…`
before its first; once ended, `Done (N tool uses · 41s)`, or `Failed`,
`Cancelled` or `Disconnected`. Subagents with nothing of the parent's between
them draw as one `Running N agents…` tree, a `├─`/`└─` row each with its
current call or its ending under it. ctrl+o opens each block on its task and
its work, drawn as the parent's is and indented, its own subagents folded. A
child's permission box opens with `Agent(<title>) asks`, and the call it is
for says `· waiting for permission`. Once the turn has ended with subagents
still at work, the status line says `1 agent still running` in the hint's
place. No new key and no new colour.

- **The words are pure, in `src/ui/subagents.ts`:** which entries group, what
  a block folds to, the group's header and each row laid out to the width
  (the counts go before the title is cut, the brackets kept), the line
  under a row, the asker's row cut from the left, and the status line's
  words. `App.tsx` only draws them, reusing the tool call's marker,
  headline, `⎿` and the reducer's entries as they are.
- **Each transcript entry keeps a box of its own**, an empty one for a
  subagent its group draws, so scrolling and ctrl+o's anchor go on counting
  entries as the transcript holds them.
- **The `│` down a child's side is the box's left border**, as a quote's
  bar already is, so it runs the height of whatever the child's work is in
  ctrl+o, blank rows included, with no row counting of our own.
- **The fake's `subagent` scenario now says a line before its third
  subagent** and pauses before that one's first call, so a lone block and
  its `Initializing…` can be seen against a group.
- **Library: tried ink-tree-view 0.4.0** (July 2026, Ink 6+, React 19),
  the one maintained Ink tree on npm. It runs under `deno run`, but it is a
  navigable tree: it draws a focus `❯` and `▼` chevrons, indents by two
  cells a level with no `├─`/`│`, takes keys through its own `useInput`,
  and gives each node one label row, where a child here has rows of its own
  under it and, in ctrl+o, a whole transcript. Laying out CHD-149's rows
  would mean a wrapper of our own around it, so the tree is three glyphs on
  rows chord already draws. ink-task-list (2.0.0, 2022, Ink 3) is a flat
  list with spinners and no nesting. Nothing new is taken.

## 2026-10-07 — Several sessions: closing one, and quitting with several open

CHD-114's parts 4 and 11: `ctrl+x k` (`session:close`, in `Global`, `k
close` on the leader line) closes the session in front, and quitting closes
every one.

- **Busy is one pure reading of a session's state,** `src/ui/closing.ts`'s
  `busyOf`: a permission asked, a form or link open, prompts queued, or a
  turn or a bash-mode command running, in that order, which is also the
  order its words are picked in (`waits for your permission`, `asks for
  input`, `has 2 prompts queued`, `is working`). The armed lines are worded there too, so `App.tsx` only
  says which to draw.
- **A busy close arms, as ctrl+c does for quit:** the first `ctrl+x k` keeps
  the session and says `1 fake is working · ctrl+x k again to stop it and
  close`; any other key, or the same two seconds ctrl+c waits, takes it
  back. The second cancels the turn, so the agent ends it as any cancel,
  then closes the conversation, which refuses an open permission and
  cancels an open form. A bash-mode command the session runs is stopped
  with it, and only that one: `App.tsx` keeps each session's command by its
  key, as nothing would be left to show it or stop it. The agent's exit is waited for in the background,
  and `closeAll` still waits for it on quit. The tab to the left comes
  forward, or the one to the right when it was the first; a session a prompt
  went to says `Closed 2 fake · /resume opens it again`.
- **The last session's close is a quit,** through ctrl+d's check, which with
  one session open never arms: one session quits as it always has.
- **ctrl+d and `/exit` arm only with two or more open and one busy,** in
  front or not. The line names each busy one (`2 sessions are busy: 2 claude
  waits for permission, 3 fake is working · ctrl+d again to quit`), or, where
  that does not fit, counts them (`2 sessions busy · ctrl+d again to quit`).
  ctrl+c's armed line counts them after its own words. A second press of
  either key quits.
- **An armed line stands alone on the status line,** without the model and
  context, as the mocks draw it, so the sessions it names are never cut for
  them; ctrl+c's line, which kept them, now does the same.
- **Quitting prints one resume command a session,** in tab order, for each
  one a prompt or a message went to: `Resume this session with:` for one, as before,
  `Resume these sessions with:` for more (`sessions.ts`'s `resumeMessage`).
  `--agent-command` goes with the sessions of the agent it overrides.
- **No library:** busy is a reading of state chord keeps, the lines are a
  handful of sentences, and closing reuses `OpenSessions.close` and
  `closeAll` as they were.

## 2026-10-07 — M4: agents start agents through an MCP server chord serves

The owner's call (CHD-160). A session can start other agents on any runtime
chord knows, on any model that runtime offers, and talk to them. ACP's own
subagents cannot: an agent spawns those inside its own runtime. So chord
serves an MCP server of its own and passes it to every session the window
opens, beside the user's `mcpServers`; the agent calls its tools, and chord
opens the sessions, sets their models and carries the messages on its own
ACP layer. It works for any agent that takes an MCP server over HTTP, which
Claude's and Codex's adapters both do.

- **Two kinds of child.** A task agent (`spawn_task(agent, model, prompt)`)
  does one job and reports: the call answers an id at once, the job runs
  with no tab, drawn nested in the parent's turn as CHD-149 draws a
  subagent, and its report reaches the parent as a message, after which
  chord closes it. A long-lived agent (`open_agent(agent, model, prompt)`)
  answers an id at once too and opens inside its parent's session, in a
  list of the session's agents under the prompt, never in a tab (the
  owner's change of 2026-10-07; the first shape gave it a tab of its own);
  the parent talks to it with `send_message(id, text)` and ends it with
  `close_agent(id)`, and the person can pick it, write to it and close it.
  Messages go both ways with no limit on how many turns they trade.
- **Who gets which tools.** A session the person opened gets `list_agents`
  (the runtimes and the models each offers), `list_sessions`, `spawn_task`,
  `open_agent`, `send_message` and `close_agent`. A child gets
  `send_message` alone, and only to its parent: children start no agents,
  a limit to revisit. A child's permission requests, forms and links go to
  the person, never to the parent agent: a task agent's in the parent's tab
  as a subagent's do, a long-lived agent's when the person picks it in the
  list.
- **A message is a turn.** It goes to its recipient as a prompt, wrapped so
  the agent sees who sent it (`<message from="codex · tab 2">…</message>`);
  if the recipient is in a turn it waits in the queue as a prompt sent
  during a turn does. `send_message` answers once the message is delivered
  or queued, not when the recipient replies. On screen it is a row of its
  own (`← codex · tab 2`), never the person's `›`, and a tab behind that got
  one is marked as a session that waits is.
- **Transport: Streamable HTTP, in chord's own process.** chord serves on
  127.0.0.1, on a port the system picks, once per window. Each session gets
  its own bearer token in the `McpServer`'s `headers`, and the token is how
  chord knows which session calls and so which tools it has; nothing else on
  the machine can call without one. Both adapters take `http`
  (claude-agent-acp 0.86.0 declares `http` and `sse`; codex-acp 2.1.1 maps
  `http` and refuses `sse` and `acp`). An agent whose `mcpCapabilities`
  lacks `http` does not get chord's server, and `/mcp` says so. Passed over:
  a stdio server, which would be chord starting itself as a second process
  and carrying every call back to the window over some channel of its own,
  the same server with a process and an IPC added; and ACP's own `acp` MCP
  transport, which needs no port and would be the better fit, but which
  neither adapter takes yet — revisit when they do.
- **Library: @modelcontextprotocol/sdk.** 1.26.0's `McpServer` with
  `WebStandardStreamableHTTPServerTransport` answers `Deno.serve`'s
  `Request`s directly; tried with the SDK's own client, under `deno run`
  and from a `deno compile`d binary, both listing and calling a tool. The
  transport must be stateful (`sessionIdGenerator`): a stateless one refuses
  a second request.
- **A task's job ends with its first turn.** Its report is the text of the
  last message the agent sent in that turn; a turn that fails ends it
  `Failed` with the error as the report, a cancelled one `Cancelled`. No
  report tool: ending on the turn needs nothing of the model and works on
  any agent, where a tool the model forgets to call would leave a child
  running for ever.
- **`list_agents` knows a runtime's models only from a session.** ACP gives
  models in `session/new`'s answer, so for a runtime with no session open
  chord opens one on the first ask, reads the models and closes it (and,
  since CHD-258, its modes from the same answer), and
  keeps the answer for the window, within a bound; a runtime that fails to
  start says why in the answer rather than failing the call.
- **The record.** A child is a session like any other and keeps a record of
  its own, which names its parent. The parent's record keeps each child's
  start (its id, kind, runtime, model and record), its end, and every
  message in and out. `--resume` draws a task agent's block from the
  child's record and the messages as they were; a long-lived child is not
  reopened with its parent, `/resume` lists it like any session, and
  one reopened so is the person's, with no parent to message.
- **Closing and quitting.** A running task agent, or a long-lived one
  working or waiting, makes its parent busy, so `ctrl+x k` and quitting arm
  as for a turn. Closing a parent cancels its task agents and closes its
  long-lived children, each recorded: with no tab of their own, left open
  they would be out of sight (CHD-167's option; the decision first kept
  them open as the person's sessions, which assumed they had tabs, and the
  owner confirmed closing them on 2026-10-09, CHD-218). Quitting closes every session,
  children among them, as it does now. A session holds eight long-lived
  children at most, so with `main` its list is never longer than the
  tabs' nine; `open_agent` past the eighth answers that it has eight open.
- **Not in M4:** `chord -p` gets no chord server (there is no window to
  draw a child in), children start no agents, and nothing guards two agents
  that message each other without end.

## 2026-10-07 — The interface split by feature, one folder each

The owner's call (CHD-180). `src/ui/App.tsx` had grown to 4,653 lines with
58 components in it and `src/ui/state.ts` to 1,885, and nearly every task
touched both: changes collided, and every feature made the split dearer. So
the interface is cut by feature, each folder holding a feature's components
and the pure logic they draw from, and the tests follow the code. Nothing on
screen changes; the split lands in parts, each its own commit.

- **The folders under `src/ui/`.**
  - `app/` — `App.tsx`, which only assembles the window, drives its
    sessions and routes keys; the React contexts every component reads
    (`context.ts`: the palette and the keymap, with `paint` and the hint
    helpers); the composed state (`state.ts`); `closing.ts` and `strip.ts`
    with the header's `Strip.tsx`; and, since part 5 (CHD-186), what
    `App.tsx` drives through: the key routing, pure, in `keys.ts`, and the
    hooks beside it — the sessions (`sessions.ts`), the terminal's side
    effects (`terminal.ts`), the slash commands (`commands.ts`), what runs
    out on a timer (`timers.ts`) and the transcript's measuring
    (`layout.ts`).
  - `transcript/` — the transcript's entries (`Transcript.tsx`: an entry,
    a reply, a thought, a note, a report, a shell run, a compaction, the
    `below` line), `markdown.ts`, `highlight.ts`, `scroll.ts`,
    `reports.ts`, `compaction.ts`. Two folders under it:
    - `transcript/tools/` — a tool call, its terminal output and its diff
      (`Tool.tsx`), `tools.ts`, `terminal.ts`, `diff.ts`;
    - `transcript/agents/` — subagent blocks and groups (`Agents.tsx`),
      `subagents.ts`.
  - `prompt/` — the prompt box, the search line, the queue, the slash
    command list and the `@` file list (`Prompt.tsx`), `prompt.ts`,
    `history.ts`, `search.ts`, `queue.ts`, `mentions.ts`, `commands.ts`,
    `images.ts`, `vim.ts`, `bash.ts`.
  - `dialogs/` — the permission prompt, a form and a link
    (`Permission.tsx`, `Form.tsx`, `Link.tsx`, the form's record beside
    it), `permission.ts`, `form.ts`.
  - `pickers/` — the model, resume, config and theme pickers and `/mcp`'s
    panel with the list they share (`Pickers.tsx`), `picker.ts`, `mcp.ts`.
  - `plan/` — the plan list and its record (`Plan.tsx`), `plan.ts`.
  - `status/` — the working line, the status line and the leader line
    (`Status.tsx`), `status.ts`.
  - `shortcuts/` — the shortcuts panel (`Shortcuts.tsx`), `keys.ts`,
    `bindings.ts`.
  - `theme/` — `theme.ts`, read by every folder.
- **Names.** Pure logic keeps snake_case `.ts`; components go in PascalCase
  `.tsx` named for what they draw. A folder holds no `index.ts`: an import
  names the file it needs, so a move is found by the type checker, not by
  a barrel that hides it.
- **Which way imports go.** A feature folder imports `theme/`, `app/
  context.ts` and the session layer, and another feature's pure `.ts` where
  it must; it never imports `app/App.tsx` or `app/state.ts`. That keeps
  each folder testable on its own and cycles out.
- **State.** `state.ts` is cut into a reducer per feature, each in its own
  folder as `state.ts` beside the feature's logic and knowing only its own
  slice, and `app/state.ts` composes them into the window's state and the
  session's, as today's two halves are. A slice that two features write is
  the window's and stays in `app/state.ts`.
- **The session side.** `src/session/transcript.ts` becomes
  `src/session/transcript/`, one module per kind of update (messages and
  thoughts, tool calls and their terminals, plans, compactions, subagents,
  permissions and forms, the turn) under one reducer that composes them.
  Since part 6 (CHD-187) those are `messages.ts`, `tools.ts`, `plans.ts`,
  `compactions.ts`, `subagents.ts`, `permissions.ts` and `turn.ts` under
  `reducer.ts`, with `shell.ts` for a bash-mode run, which is none of those
  kinds. The shapes and the empty transcript are in `types.ts`, so every
  module imports them and none imports `reducer.ts`; a subagent's update
  folds through the session's own fold, which `reducer.ts` hands
  `subagents.ts` rather than the module importing it back, so there is no
  cycle.
  `src/session/conversation.ts` and `src/ui/dialogs/form.ts` stay whole
  until a task finds a seam worth cutting.
- **Tests.** `tests/` mirrors `src/`: `tests/ui/prompt/history_test.ts`
  tests `src/ui/prompt/history.ts`, and `tests/session/` mirrors
  `src/session/` the same way. `tests/app_test.tsx` is cut by the
  feature each test drives, into the folder of that feature, with the
  helpers that render the window in `tests/ui/app/render.tsx`. Since part
  8 (CHD-189) each folder's window tests are in a `_test.tsx` named for
  the component they reach (`tests/ui/prompt/Prompt_test.tsx`,
  `tests/ui/pickers/Pickers_test.tsx` and the rest), the window's own in
  `tests/ui/app/App_test.tsx`, and `tests/acp_test.ts` is
  `tests/acp/connection_test.ts`.
  `tests/fixtures/fake_agent.ts` becomes `tests/fixtures/fake_agent/`: the
  agent and its options in `main.ts`, one module per family of scenarios
  under `scenarios/`. Since part 7 (CHD-188) `main.ts` is the agent: the
  scenario chosen, every request answered, sessions listed, loaded and
  resumed, and the usage a turn reports; it plays one table spread from
  `scenarios/`' `text.ts`, `tools.ts`, `permissions.ts`, `plans.ts`,
  `forms.ts`, `shell.ts`, `compaction.ts`, `modes.ts`, `subagents.ts` and
  `misbehaving.ts`. What the scenarios read too sits beside it, since a
  scenario importing `main.ts` would be a cycle: the flags and their
  environment variables in `options.ts`, the turn and its call ids in
  `turn.ts`, what the client declared at `initialize` in `client.ts`, and
  each session's directory, MCP servers, model, mode and effort with the
  config options that offer them in `sessions.ts`. The fixtures the
  scenarios play (`forms.ts`, `terminals.ts`, `commands.ts` and the rest)
  stay in `tests/fixtures/`, where the tests import them.
- **Why not by kind (`components/`, `logic/`).** A change to a feature
  touches its component and its logic together; by kind, every change still
  spans two folders and the files stay as large. By feature, one change is
  mostly one folder.

## 2026-10-07 — The mouse: SGR reports taken out of stdin, the wheel scrolls

On the alternate screen, iTerm2 and Terminal.app turn a wheel or trackpad
step into ↑/↓ (alternate scroll mode, 1007) unless the program reads the
mouse, so the wheel walked prompt history and replaced the draft (CHD-31).
chord now reads the mouse, as Claude Code does; the design is
`docs/design/CHD-31.md`. No new dependency.

- **Button tracking and SGR, 1000 and 1006.** Plain button tracking reports
  the wheel; any-event tracking (1003, Claude Code's) would report every cell
  the pointer crosses, and nothing reads them. chord does not touch 1007:
  while it reads the mouse the terminal sends reports, not arrows.
- **On and off with the alternate screen.** Ink's `stdout` is wrapped
  (`src/mouse.ts`'s `withMouseModes`) so that every write that enters the
  alternate screen turns the modes on after it and every write that leaves it
  turns them off before it. Ink leaves it on unmount, which it also runs on a
  crash and on a signal through signal-exit, and around `suspendTerminal`,
  which ctrl+g's editor runs in, so the mouse is chord's exactly as long as
  the screen is, with no exit path of chord's own to keep in step. `chord -p`
  draws no window and never asks.
- **Reports are taken out before Ink reads keys.** Ink 8 already drops a
  complete CSI sequence that is no key, so a report never typed by itself,
  but Ink also never hands it on. `withMouse` sits on stdin after
  `withoutReplies`, as that one does: it takes each SGR report out of what
  `read()` returns, hands it to the window, and keeps a report cut across two
  reads whole, holding a trailing `ESC` or `ESC [` for 20 ms (Ink's own wait
  for the rest of an escape) and carrying an unfinished `ESC [ <…` to the
  next read, which no key starts with. A bracketed paste is left as pasted.
- **@ansi-tools/parser finds the reports,** as it already splits a
  command's output for the transcript: it tokenises `ESC [ < 64 ; 10 ; 10 M`
  as one private CSI with its parameters, and an unfinished one as a CSI with
  no final byte, which is what a cut needs.
- **Tried and passed over.** `xterm-mouse` 1.0 (and `@ink-tools/ink-mouse`
  2.1, its React layer, peer Ink ≥6): it reads stdin through a `data`
  listener of its own beside Ink's `readable` one, turns on 1000, 1002, 1003
  and 1006 with no choice, takes nothing out of what Ink reads, reads each
  chunk on its own so a cut report is lost, and drops a report equal to the
  one before it in the same chunk, which is two wheel steps read as one. It
  says it is early and at your own risk. `@sorrell/ink-mouse` depends on a
  `file:` path and does not install; `@zenobius/ink-mouse` is for Ink 5.
- **What a report does is a pure module** (`src/ui/mouse.ts`): a wheel step
  up or down runs `scroll:lineUp` or `scroll:lineDown`, the action and not
  its keys, so it scrolls one row wherever they do and however they are bound,
  modifiers held or not; a left press let go on another cell is a drag; the
  rest, the horizontal wheel and clicks included, does nothing yet.
- **Selecting text is the terminal's own, past chord.** With the mouse read,
  a plain drag no longer selects, so the status line says for 3 s after a
  drag which modifier does: option in iTerm2 (`TERM_PROGRAM` or
  `LC_TERMINAL`, which survives tmux and ssh), fn in Terminal.app, shift
  elsewhere. chord drawing its own selection, as Claude Code does, is
  CHD-177.
- **`"mouse": false`** in the user's settings file asks for nothing and
  takes nothing out, and the terminal has the wheel back; read from the
  user's file only, as `theme` and `editorMode` are.

## 2026-10-07 — Bound keys on a Russian layout: convert-layout's table, tried only after a miss

With a Russian layout on, the terminal sends the layout's characters (ч, с,
т) and chord's keymap knows US keys, so ctrl+x's follow-ups, vim's normal
mode and any letter a keybindings file binds did nothing (CHD-181, part 1 is
CHD-191).

- **convert-layout 0.11.1** gives the table: `ru.toEn` turns a character
  typed on Russian ЙЦУКЕН into the US one in the same place, case and all.
  It is plain CommonJS with no dependencies, loads under `deno run` and in a
  `deno compile` binary, and is exact-pinned as a pre-1.0 package; its other
  layouts (Ukrainian, Belarusian, Kazakh, German, …) are there for the parts
  after this one. Its types are two functions, in `src/ui/convert-layout.d.ts`.
- **Both of macOS's Russian layouts.** Read from macOS's own layout data
  (UCKeyTranslate over "Russian" and "Russian – PC"), the letters sit in the
  same places on both; convert-layout follows "Russian – PC". Apple's
  "Russian" differs in punctuation: `/` and `?` stay on the US key, the
  number row's shifted signs move, and ё sits on the backslash key, not the
  backquote. Of the characters a US layout cannot type only ё and Ё differ,
  so `layoutKeys` tries "Russian – PC"'s key first and Apple's after.
- **Only characters a US layout cannot type are read again.** A press does
  not say which layout it came from, and `,` is both a US comma and what
  "Russian – PC" types where `?` is: reading it as `?` would open the panel
  for a US user's first comma. So punctuation stays itself on either layout;
  on "Russian – PC" `?` is shift+7, which opens the panel as typed, and vim's
  `$` has no key there, as in vim itself. Under kitty's protocol the terminal does
  say where the key is, and `?`'s own key opens the panel there too (see "A
  bound key's base-layout key", 2026-10-08).
- **After a miss, never before.** `keyAnswer` matches the press as typed
  first; only when it asks for nothing (or would drop a chord's first keys)
  is it read as the US key, and that answer is taken only if it asks for
  something. So a key bound in Cyrillic in the keybindings file wins, the
  file's US keys are reached the same way as the defaults, what types into a
  form or the search line is never read again, and text in the prompt stays
  as typed: only a key that is bound once read is taken back, as `?` is. The
  window keeps the key it was read as for a chord's next key and for vim,
  where `f` and `r` still take the next character as typed. Vim takes any
  key after an operator's `i` or `a`, so there a Cyrillic key is read again
  even though it asks for something: `d i ц` is `diw`.
- **ctrl and alt.** ctrl+ч reaches Ink as the control byte (most terminals,
  already ctrl+x), as `ч` with ctrl held, or as kitty's `CSI 1095;5u`, which
  Ink 8 reads as the same; the last two are read again as ctrl+x.
- **Claude Code has no such table.** Its 2.1.292 bundle has no Cyrillic
  layout data; it reads kitty's `CSI code:shifted:base ; mods u` and asks for
  kitty's flags 1 or 5. The base-layout key came after this one (see "A
  bound key's base-layout key", 2026-10-08), and is tried before the table.
- **The textarea's line break.** ctrl+j is a default binding the prompt's
  textarea acts on itself, but the textarea hears ctrl+о as it came, so a
  key read again as one of the textarea's sends, breaks the line or walks
  history from chord instead.
- **Not reached here:** the textarea's editing keys outside the keymap
  (react-ink-textarea's ctrl+a, ctrl+e, ctrl+k, alt+b, …) read Ink's press
  themselves, so ctrl+ф is still not ctrl+a there under kitty's protocol;
  the control byte, which most terminals send, already works (CHD-200).

## 2026-10-08 — Chorded's mark in half cells: resvg in the script, culori at draw time

CHD-198's startup header draws Chorded's mark as pixel art, to CHD-201's
spec (`docs/design/CHD-201.md`). This part (CHD-202) is the grid and how it
is painted; nothing is on screen until the header itself (CHD-203).

- **`deno task mark` rasterises with @resvg/resvg-wasm** (^2.6.2), resvg
  compiled to WebAssembly: it renders the path's arcs (the round corners, tip
  and notch) under Deno with no native addon, and its wasm file is read from
  the npm package. The script zooms the render so one half cell is 32 × 32
  pixels and takes a half cell's coverage as their mean alpha, filled at 0.5
  or more, as the spec says. It reproduced the spec's grids exactly: 8 rows
  × 9 columns and 4 × 4; the owner has since dropped the 8-row mark
  (CHD-203), so it wrote the 4 × 4 alone until the startup splash (CHD-241)
  brought the 8 × 9 back as `SPLASH_MARK`. It runs only as a script, never
  in chord or its binary. `scripts/mark.svg` is a copy of the brand's `mark.svg`, so the
  script reads nothing outside the repository.
- **resvg's `width` is rounded** (54 for the viewBox's 54.367), which tilts
  the gradient enough to move two half cells across a 256-colour step; the
  script reads the viewBox from the SVG instead.
- **The module holds each half cell's place on the gradient, not colours**,
  so the theme and the colour level choose the stops when the header is
  drawn, and `src/ui/header/mark.ts` is the same for every theme.
- **culori** (^4.0.2, typed by @types/culori) interpolates the gradient in
  sRGB, as an SVG `linearGradient` does, and finds the nearest of xterm's
  colours 16–255 by distance in OKLab, at draw time in `mark_rows.ts`. chalk's
  own `rgbToAnsi256` rounds each channel to a sixth, and the cube's levels
  are not evenly spaced, so it turns the brand's light green #147d55 teal.
  CHD-201's thread had the 256 index baked per stop set to keep culori out of
  the binary; computing it at draw time keeps the module free of stop sets
  instead, and culori is plain JavaScript that runs in a `deno compile`
  binary (checked). The tests hold the result to the spec's 256 maps, dark
  and light.
- **`src/ui/header/`**, not `src/ui/mark.ts` as the task named it: the
  interface is one folder per feature, and the header the mark goes into is
  a feature of its own.

## 2026-10-08 — The sessions picker, and `/resume` knowing the open sessions

CHD-114's parts 10 and 5. `ctrl+x w` (`session:list`, `Global`, `w list` on
the leader line after `1–9`) opens a picker of the sessions open in the
window; `/resume` marks a session open in a tab `open in 2`, and picking it
goes to that tab. A long-lived child (CHD-170) is open in its parent's tab:
its row says that tab, and picking it goes there and picks the child, so no
second conversation writes its record.

- **No new library.** The picker is `picker.ts`'s list and `Pickers.tsx`'s
  `PickerList`, which `/model` and `/resume` already use (ink-select-input
  was ruled out for them earlier: it scrolls by rotating). Its rows are a
  pure `tabChoices`, the times `formatElapsed` (then `status.ts`'s, now
  `session/elapsed.ts`'s) cut to its first
  unit, and the glyphs the strip's.
- **It stands in front of a permission or a form,** unlike the other
  pickers, which a permission takes the place of. Its key is `Global` so
  that it works while one is asked, and it is how the person leaves that
  session for another; while it is open the permission and the form are not
  drawn, Esc closes the picker rather than rejecting the permission, and
  what was asked is there again, as it was, once it closes.
- **It opens in place of any other picker,** as its key works with one
  open: a theme previewed goes back to the one in use, and a `/resume`
  still reading the records opens nothing over it.
- **Its highlight starts on the tab `ctrl+x a` would go to,** else on the
  one after the front (`tabs.ts`'s `listStart`), and the hint names the
  digits there are, `1–3 to pick`, rather than the mock's `1–9`, as a digit
  past the last does nothing.
- **`/resume` goes to the tab, never loads a session twice:** two
  conversations on one session would both write its record, each over the
  other's turns. The session in front is still left out of the list, as
  before. The list is the front session's agent's, as `/resume` acts on the
  session in front.

## 2026-10-08 — cmd+V of an image: an empty bracketed paste reads the clipboard, through Ink's `usePaste`

Superseded by "Moving to OpenTUI" (2026-10-10): the empty paste comes
through OpenTUI's paste event (part 5).

On macOS the terminal takes cmd+V and pastes the clipboard's text, so chord
never sees the key. For a clipboard that holds only an image Ghostty sends
an empty bracketed paste, `ESC[200~ESC[201~`; chord reads that as ctrl+v:
the clipboard's image at the cursor as `[Image #N]`. Unlike ctrl+v it is
quiet: a clipboard with no image changes nothing and says nothing, as the
person may have pasted nothing at all. An image to an agent that takes none
still says so.

- **No marker parsing of our own.** Ink 8 parses bracketed pastes, one cut
  across reads included, and hands each to `usePaste` listeners, the empty
  one as `''`; react-ink-textarea listens already (which is what turns
  bracketed paste on) and drops the empty one. The prompt box adds a second
  listener with the textarea's own `focus` as `isActive`: while any
  listener is on, Ink keeps pastes from `useInput`, so one heard while the
  textarea is off would take pastes from a form or the search line.
  `mouse.ts` already hands both markers on whole across reads.
- **Vim's normal mode.** There the textarea is off, so no listener hears
  the paste and Ink hands it to `useInput` as its text: an empty one is an
  input of no bytes, which no key press is. `usePress` reads each input's
  sequence from Ink's emitter already, so it tells the empty paste apart
  there and hands it on as one; a paste with text still reaches normal mode
  as it did. Halfway through a chord an empty paste is dropped.
- **Other terminals**, from their source, not by hand. kitty sends nothing
  for a clipboard with no text (`paste_with_actions` in `kitty/window.py`
  returns on empty text). WezTerm on macOS sends nothing either: its
  clipboard read fails without a text or file flavour
  (`window/src/os/macos/clipboard.rs`), and `send_paste` is called only on
  a read that worked (`wezterm-gui/src/termwindow/clipboard.rs`). iTerm2
  sends no empty paste: a clipboard with no text goes to its non-text paste
  (`attemptNonTextPaste`), which for an image offers to paste a temporary
  file's path, base64 or an upload, or cancel (`iTermNonTextPasteHelper`);
  a path chosen there becomes the image, as any pasted path does.
  Terminal.app is unknown: Apple documents its text paste only. A terminal
  that sends nothing is as before: ctrl+v still works there.

## 2026-10-08 — `/new <agent>`, each agent's starting values, and `/status`'s sessions

CHD-114's parts 2 and 12. `/new` opens a session beside the rest, as
`ctrl+x c` does; `/new fake2` opens one of the agent it names. `/status`
adds `Sessions: 3 open (1 waits)` once two or more are open.

- **Each tab starts on its own agent's values.** `settings.ts`'s
  `startupOf` gives the window's own startup for the agent chord was
  started on, flags and all, and for any other the command, model and mode
  the settings files set for it, as `resolveStartup` reads them with no
  flags. `--agent-command`, `--model` and `--permission-mode` are left to
  the named agent: their ids are its own, and a `--model opus` would be
  refused by every codex tab. The files read are those of the directory
  the tab works in, a resumed session's included, as everything else in
  the tab is (since several `--resume` ids, below, a tab's directory).
- **An agent chord cannot start** is one with neither a registry entry nor
  a command in the files: refused in the front session's transcript, `No
  agent named codx · chord agents lists them`, and nothing opens. One that
  is known but fails to start draws its own tab's error line, as any start
  does.
- **The words after a name of chord's go with it** (`Submitted`'s `args`),
  and into history as typed, so ↑ brings back `/new codex` whole. A name
  picked from the open list takes none; the list closes at the first
  space, so `/new codex` reaches Enter with no highlight.
- **What is drawn is the front tab's agent:** the header, the status line,
  the permission prompt, `/status`'s `Agent` and the resume refusal name
  it, no longer the agent the window was started on.
- **A tenth session** is the status line's `Nine sessions are open; close
  one with ctrl+x k first`, from `ctrl+x c` and `/new` alike.
- **`waits` counts** the tabs asking for a permission, a form or a link,
  the `●` ones; a reply not yet seen does not wait on anyone.
- No library: an argument after a command's name is a regular expression,
  and the rest is chord's own settings and tabs.

## 2026-10-08 — A bound key's base-layout key, from kitty's protocol, read where Ink hands its listeners the press

Superseded by "Moving to OpenTUI" (2026-10-10): the base-layout key is
OpenTUI's `baseCode` (parts 2 and 5).

A terminal speaking the kitty keyboard protocol (kitty, Ghostty, WezTerm,
iTerm2 with CSI u on) names, when asked for its alternate keys, the key in
the same place on the base layout with every press it sends as an escape
code: ctrl+ч on Russian is `CSI 1095::120;5u`, 120 being US x. That covers
every layout, Greek, Ukrainian, Hebrew and the rest, with no table (CHD-181,
part 2, CHD-192).

- **Asked for:** `src/keyboard.ts`'s flags, `disambiguateEscapeCodes` (as
  before), `reportAlternateKeys`, `reportAllKeysAsEscapeCodes` and
  `reportAssociatedText`, through Ink 8's `kittyKeyboard.flags`. The
  alternate keys come only with a press sent as an escape code, and without
  the third flag a key that types, alone or with shift, is sent as its text:
  `?`'s key on "Russian – PC" would type `,` with nothing to say where it
  is, and a chord's bare next key (`ctrl+x c`) on a layout with no table
  would be lost. The fourth puts the text a key types in its sequence, which
  Ink 8 gives `useInput` as the input, so text still types as itself. Ink
  still turns the protocol on only where the terminal answers its query.
- **Ink reads the field and drops it.** Its kitty pattern in
  `parse-keypress.js` matches the shifted and base fields without keeping
  them, and `useInput`'s `Key` has nothing for them. Ink 8.0.0 is the latest
  release, with no option for it.
- **Tried, and not taken:**
  - A stdin wrapper beside `withMouse` that reads the sequence before Ink
    does: it sees the bytes, but not which `useInput` call a press becomes,
    so it could only guess by matching characters, and ink-testing-library
    renders with a stdin of its own, so no test would go through it.
  - Rewriting the sequence there, its codepoint swapped for the base key:
    the press's own key would be lost, and a key bound as typed must win.
  - Another input library: none plugs into Ink's `useInput`, and the
    textarea, the pickers and the forms all hear keys through it.
  - Patching Ink, or a fork: not done, by the one rule.
- **Taken: the sequence from Ink's own emitter.** Ink hands every press, as
  its sequence, to the `input` listeners of the event emitter in its stdin
  context, the one `useInput` itself listens on. `src/ui/app/terminal.ts`'s
  `usePress` puts a listener first on it (`prependListener`) that reads the
  base key out of the sequence with @ansi-tools/parser, already chord's for
  the mouse, then hears the press through `useInput` with the key it read as
  `base`. (Since CHD-304 the listener and `useInput` are
  `src/ui/tui.tsx`'s `useKeys`, which hands `usePress` each press with its
  sequence.) The emitter is `internal_eventEmitter`, outside Ink's public type:
  the one part of Ink's internals chord reads. Without it no press has a
  base key, and the Russian table still answers; the keys tests go through
  real Ink, so a release that renames it fails `deno task check`.
- **Order:** a press bound as typed first, then its base-layout key, then
  the Russian table (`keyAnswer`): the terminal knows where the key is, the
  table guesses. Text is never read again, as before.
- **A shifted base key is US PC-101's shifted character.** The protocol's
  base layout is US PC-101 whatever the person's, so `baseKey` reads shift
  on a key with no case as what that layout types: the key of `/` with
  shift is `?`. That is the protocol's own layout, not a table of a layout.
  So "Russian – PC"'s shift on `?`'s key (`CSI 46:44:47;2;44u`, typing `,`)
  opens the panel on an empty prompt, as `?` does, and types its `,` after
  a draft; a `,` the keybindings file binds is its own first. The same goes
  for any layout: on German, shift on the key of US `/` types `_`, which on
  an empty prompt now opens the panel, as `?` there would.
- **A modifier pressed alone is no press.** With every key an escape code,
  the terminal reports shift, ctrl, alt, cmd and the locks pressed alone
  (`CSI 57441;2u` is left shift). Ink hands them on as a press with no
  input, which would end a chord begun at the next key's modifier, so
  `usePress` drops them (`modifierAlone`). The prompt's textarea and
  ink-select-input's lists hear them through their own `useInput` and do
  nothing with an empty input; since CHD-304 the pickers, the forms and the
  start picker hear keys through `usePress` too, so it drops them there.
- **Nothing else moves, by Ink's own reading.** Ink 8 reads every key as
  the protocol sends it: Enter is `CSI 13u` (return), Tab `CSI 9u`,
  Backspace `CSI 127u`, Esc `CSI 27u`, text its associated text (`a` is
  `CSI 97;1;97u`, shift+b `CSI 98:66;2;66u`), the keypad's digits with num
  lock their text, and shift+enter and ctrl+c (`CSI 99;5u`, Russian ctrl+с
  `CSI 1089::99;5u`) as before. A bracketed paste is not a key press at
  all, and comes as it did. The keys tests press each of these through real
  Ink and get what the plain bytes get.
- **Checked by hand** only in tmux, which does not relay the protocol: the
  window starts, types, sends, opens a tab and quits as before. No terminal
  speaking the protocol was at hand, so none of the sequences above has
  come from a real one; they are the protocol's, from its specification.


## 2026-10-08 — chord's MCP server: @modelcontextprotocol/sdk 1.32.1 on `Deno.serve`, a token per session, tools by role

M4's first part (CHD-168), as "M4: agents start agents through an MCP server
chord serves" settles it: the server, every window session given it, and
the two tools that read, `list_agents` and `list_sessions`.

- **The version taken is 1.32.1**, the latest; the decision tried 1.26.0.
  Tried again here under `deno run` and from a `deno compile`d binary:
  `McpServer` on `WebStandardStreamableHTTPServerTransport` answering
  `Deno.serve`'s requests, the SDK's own client listing and calling tools,
  a request without the token refused. Caret-pinned, as a 1.x package.
- **With @zod/zod 4.** The SDK takes zod `^3.25 || ^4.0` and tells a v4
  schema by its shape, so jsr's @zod/zod, chord's zod, makes a tool's input
  schema: it is turned into JSON Schema for `tools/list`, a wrong argument
  is refused with zod's own words, and the handler's argument types infer.
  npm's zod still comes in under the SDK, unused by chord.
- **Two traps.** The SDK's `./*` export maps types to `*.js.d.ts`, which do
  not exist, so every import of a subpath names its types with a
  `// @ts-types` line; and `Request.clone()` makes Deno print a warning on
  stderr, over the window, about the request's abort signal, so the server
  reads an `initialize`'s body once and hands it to the transport as
  `parsedBody` rather than let anything clone the request. `onListen` and
  `onError` are chord's for the same reason: Deno's would write over the
  window.
- **Where it lives.** `src/server/`: `server.ts` serves and checks tokens,
  `tools.ts` is each role's tools and their answers, worked out from what
  the window reads of itself (`WindowView`) so they are tested without a
  server, and `runtimes.ts` is the runtimes' models and modes. `main.tsx` starts it
  before the window and closes it after; the window (`useSessions`) admits
  each session and reads itself for the tools. `-p` never starts one.
- **A token per session, for as long as its agent lives.** Each session a
  tab opens, `/clear`'s included, gets a fresh token, which names the tab
  it is in. It is revoked once the agent's process exits, or the open fails,
  and the MCP sessions it opened end with it. An unknown token is a 401, an
  MCP session id unknown a 404, and one opened with another token a 403, so
  no session can speak as another.
- **Only to an agent that takes HTTP.** `openSession` takes chord's server
  apart from the user's and adds it after them only when `initialize`'s
  `mcpCapabilities.http` is true; the user's go as before. Where one of the
  user's is already named `chord`, chord's goes as the first free `chord-2`,
  `chord-3`, …: two of one name leave the agent to keep one, and either way a
  server is lost, while a renamed one keeps both reachable and the user's
  where they put it.
- **Tools by role.** A table from a role to the tools it registers; a
  session the person opened is `person`, with `list_agents` and
  `list_sessions`. M4's next part adds a child's role and `spawn_task` as
  lines there. Each MCP session gets an `McpServer` of its own, with its
  caller's tools.
- **`list_agents` probes only the runtime it is asked about.** Without an
  argument it names every runtime chord can start (the window's, those the
  settings files give a command, then the registry's) with the models known
  without starting anything: an open session's, or one read earlier in the
  window. Given `agent`, it reads that one, opening a session to do so if
  none is open, within 60 s, and keeps the answer for the window; a runtime
  that fails says why, and is tried again on the next ask. Probing every
  runtime on the first ask, as the decision first read, would install and
  start every one of the registry's 22 agents through npx on the person's
  machine for one call.
- **`list_sessions`** gives each open session's id (null while it starts),
  runtime, model id and tab number, the caller's own marked `you`.
- **Not yet:** `/mcp` lists the user's servers alone; chord's row there is
  CHD-167's design. The fake agent connects to chord's server with the SDK's
  client in its `chordtools` scenario, and `--no-http` leaves HTTP out of
  its `mcpCapabilities`, so tests prove both sides with no real agent.

## 2026-10-08 — `-r <id> -r <id> …`: a tab each, each in its own place

Several sessions are named by repeating the option: `chord -r <id> -r <id>`,
or `--resume` each time. Cliffy parses it natively, as `-r, --resume
<id:string>` with `collect`, into the ids in order; one `--resume` takes
exactly one id, as it always did (until "Windows in `/resume`" below made
the id optional), and `[agent]` stays where Cliffy puts it,
before or after. Cliffy's variadic option, `<ids...:string>`, was tried
first and dropped: it ends the list at any word that names one of chord's
flags, with or without its dash (`c`, `C`, `model`, `help`), and refuses
such a word even as the only id; 1.3.1 does the same. A rewrite of
`--resume a b c` into repeated options, and then a rule guessing whether the
word after the ids was an id or the agent, were written around it and
removed: the owner chose the repeated option, which needs neither.
`chordCommand` (`src/cli.ts`) holds the flags apart from what `main.tsx`
does with them, so a test parses argv through the very declarations chord
runs on.

- **One id is as it was**: `sessionById`, the agent the command line
  resolves to, a record of another agent's refused, an id chord never saw
  passed to the agent, which replays it.
- **Several open only sessions chord has a record of.** Each id is checked
  before the window opens, so an unknown one refuses the whole command
  (`No session <id> among chord's records; one it never saw opens only on
  its own.`) and no window is left half open, as it would be if the agent
  refused one tab's load after the others had come up. The same id twice,
  which would put two conversations on one record, and more ids than the
  nine tabs a window holds are refused the same way, before anything starts.
- **Each tab runs its record's agent**, so a window can come back with
  sessions of several agents; an agent named on the command line is every
  tab's, and a record of another's is refused, as with one id.
- **Each tab has a place**: the directory its session works in, with that
  directory's project settings (the model and mode it starts on, read as
  `resumedStartup` reads a resumed session's) and MCP servers. `main.tsx`
  reads each directory once, before the window, so their problems are said
  in it; `useSessions` keeps the place by the tab's key. What reads a
  directory reads the front tab's: `@`'s files, `/mcp`, `/status`, the
  header and `/resume`'s list and its refusal of another directory's
  session; bash mode runs in its own tab's. ctrl+x c and `/new` open beside
  the front tab, in its place. The window's own settings (theme, keys,
  mouse, notifications) stay those of the directory of the first tab.

## 2026-10-08 — Task agents: a child's session relayed as a subagent, its report a message

M4's second part (CHD-169), to CHD-167's parts 1–3, the task half of 5 and
part 6. `spawn_task(agent, model, prompt, name?)` answers chord's id for the
task at once; chord opens a session of that runtime where the parent's tab
works, with no tab, on the model asked for, and sends it the prompt. Checked
under `deno test` and in tmux against the fake agent, whose `task` scenario
calls `spawn_task` on the fake runtime and whose `taskchild` messages its
parent before its report; no live agent was asked.

- **The child is relayed, not drawn.** `TaskAgent` (`src/session/tasks.ts`)
  hears the child's own `Conversation` and hands its parent's the child's
  updates under the task's id, opened and ended by a `subagent_update` chord
  writes with the task's name, runtime and model under `_meta`'s
  `chord/task`. The reducer folds it as CHD-149's subagent, `Agents.tsx`
  draws it as one with ` · codex · gpt-5.3-codex` after the title, and the
  parent's record keeps it as it keeps any subagent's: no second renderer
  and no record line of a new kind for it. (CHD-171: the parent's record
  keeps the task's start and end; its work is in the task's own record.)
  The child keeps its own record, whose first line names its parent;
  `--continue` passes over such a record, as it is the parent's work.
- **chord knows its own calls by what it served.** Each tool call's answer
  goes to the caller's session as a `served` action (recorded too), which the
  reducer ties to the tool call with the same arguments (`@std/assert`'s
  `equal`, deep and order-blind; chord already took @std/assert, and it was
  tried under `deno run` and in a `deno compile`d binary), now or once the
  call comes, a call whose title names the tool first. Titles differ by
  adapter (`mcp__chord__spawn_task` from Claude's); the arguments are the
  agent's own either way. A `spawn_task` call is replaced by the task, which
  stands where the call stood and takes its updates.
- **The job ends with the child's first turn.** Its last agent message is the
  report, delivered as `← <name> · <runtime> · report`; a failed turn's error
  as `· failed`. A model the runtime does not list, or lists and refuses,
  fails it the same way before the job is sent: the child's starting model
  is `required`, so its refusal fails the session's start rather than going
  into the transcript, and the job never runs on the runtime's default
  (when the models were known up front, `spawn_task` refuses at once,
  naming those offered, as it does a runtime chord cannot start). Then
  chord closes the child, and the parent's close waits for that.
- **A message is a prompt with a sender.** `Conversation.deliver` wraps it,
  `<message from="Fix the tokenizer · codex · report">`, its `from` the row's
  header word for word, and queues it behind a running turn as a prompt is;
  the reducer draws its turn's start as a `message` entry, `←`, never `›`.
  The record keeps the wrapped prompt and reads it back as the row.
- **Esc stops the turn's task agents**, which send no report: a turn right
  after Esc would undo it. A line saying so goes ahead of the person's next
  prompt, as held bash output does. A message still queued goes as the next
  turn once the interrupted one ends (CHD-360); Esc never puts a message in
  the draft. A
  task still starting has no turn to stop: it ends there, and its job is
  never sent.
- **`/clear` closes the session's task agents** with the session it lets
  go, and drops the messages and lines they left for the next prompt. Each
  task reaches its parent through callbacks bound to its id, which do
  nothing once the task is no longer the session's, so nothing an old task
  says as it closes reaches the new session. A request is answered by the
  task that relayed it, whichever of its own subagents asked.
- **A task's requests outlive the turn.** A task may still run, and ask, once
  the turn that started it has ended, which a subagent of the runtime's own
  may not. Its permission waits as `awaiting_permission` with `between`,
  carried into the next turn if one starts, and the session is idle again
  once it is answered; its forms and links wait beside, by its id. Answers
  go back to the child through the parent's `Conversation`.
- **Busy.** A running task agent makes its session busy, after the person's
  queued prompts and before the turn: `1 fake has 1 task agent running ·
  ctrl+x k again to stop it and close`. A queued message no longer counts as
  a prompt queued; it goes with the work that sent it.
- **`/mcp`** lists chord's server first, `chord itself`, with its URL or
  `not passed`, and a line of the tools it gives, or why the agent got none.
- **No library for the rest.** The relay is a switch over events chord
  already has, the wrapper a template and a regular expression, and the
  headlines a few sentences; the MCP calls are the SDK's, as before.

## 2026-10-08 — Long-lived agents: a list under the prompt, picked as a tab is

M4's third part (CHD-170), to CHD-167's part 4 and the long-lived half of
part 5, after the owner's change of 2026-10-07: a long-lived agent gets no
tab. Checked under `deno test` and in tmux against the fake agent, whose
`agents` scenario opens `parser` and `docs` on the fake runtime and messages
`parser` twice, whose `agentchild` messages its parent twice, and whose
`agentclose` closes `parser` and messages it after; no live agent was asked.

- **A child is a session the window keeps beside the tabs.** `open_agent`
  opens its own `Conversation` where the parent's tab works, on the model
  asked for or not at all, as a task's, with chord's server given it as a
  child of the tab. `tabs.ts` keeps each tab's children, the one picked,
  those it closed and how many it opened; a child takes its key from the
  tabs' own counter, so the window's state holds it by its key as a tab's,
  and picking it swaps the transcript, scroll, queue, draft, open
  permission or form and the status line's model as switching tabs does,
  inside one tab. The header and the strip stay the parent's.
- **Messages both ways reuse CHD-169's delivery.** The parent's first prompt
  goes as a message from `main`, as every later one does; one sent while the
  child still starts is held and goes once it is up. A child's
  `send_message` reaches its parent alone, as `← @parser · codex`. (Since
  CHD-259 a long-lived child also has `spawn_task` and `list_agents`, and
  its parent hears `← chord` when its agent exits or its turn fails.) The
  parent's `send_message(to, text)` and `close_agent(to)` take the child by
  chord's id (eight hex digits, so the person's close can quote it) or its
  name; a message to a closed one is refused with
  `parser is closed; open_agent starts another`.
- **Names and colours.** A child is called what `name` asks, or its runtime,
  numbered past the first (`codex 2`), never `main` or `chord`. The theme's
  new `agents` role is six colours, the dark and light sets and the 16
  colours CHD-167 gives; the children take them in the order they opened,
  so closing one recolours none. The name on the list, the box's border and
  name, and a message's arrow and sender are in it; `main` has none.
- **Keys.** ↓ goes into the list from an empty draft not walking history,
  the place ↓ did nothing, through `newerSteps`, so the textarea's own ↓ on
  its last line reaches it. In the list ↑ ↓ or j k pick, ↑ on `main` and
  Enter and Esc go back, `x` (`agents:close`, context `Agents`) closes; a
  permission or form of the picked agent waits while the list has the keys,
  so moving never answers one. The shortcuts panel names it on the history
  line, `↑ ↓ for earlier prompts and agents` (since CHD-245
  `↑ ↓ for prompts, agents and monitors`, with a line for `x`), rather than the four lines
  CHD-167 drew: the panel's 19 rows at 80x24 had no room, and the status
  line names the list's keys while it has them.
- **Closing.** `x` on a busy child arms first, as `ctrl+x k` does; then
  chord tells the parent `The person closed parser (codex · gpt-5.3-codex,
  id 7f3a9c2e). It takes no more messages; open_agent starts another.` as
  a message from `chord`. `close_agent` sends nothing: its call says
  `Closed`. `/clear` with a child picked is refused; on `main` it closes the
  children with the session it lets go, as `/resume`'s pick does, since a
  new parent would know nothing of them.
- **Waits.** Each child folds its own wait as a tab does, with a message
  not yet seen as one more kind, which marks no tab and wants no one. A
  tab's glyph, the notice of a tab behind and the sessions picker take the
  most urgent of its agents' (`claude · 2 agents`, `● docs: permission`);
  `ctrl+x a` and the picker go to the child that waits. The front tab's
  other agents are named on the status line by their names.
- **Library.** The box's named top border is a row drawn over an Ink `Box`
  with no top edge. @mishieck/ink-titled-box 0.4.2 was tried under
  `deno run` on Ink 8: it measures in an effect, so its first frame has no
  top border, and the box remounts on every redraw, so it would flicker; it
  measures once, not on a resize; and a title with a space each side made
  its border two columns short. @inkjs/ui 2's `Select` was tried for the
  list: its label is one plain string, so the name, the runtime and the
  state cannot take their own colours, it marks the chosen row `✔`, and it
  reads ↑ ↓ itself where the window routes keys. The list is a few `Text`
  rows from `agents.ts`'s layout, as the queue's are.

## 2026-10-08 — Agents started by their own CLI, and uvx agents

CHD-227's first part (CHD-228). The registry offered 41 agents and chord
started the 22 it ships through npx. Of the rest, 2 come through uvx and 17
only as per-platform binary archives. The owner chose acpx's way for the
binaries, not downloading the archives.

- **uvx agents are frozen like npx ones.** `scripts/registry.ts` keeps an
  entry's `uvx` package when it has no `npx` one (npx wins where it offers
  both), with its exact version, `args` and `env`, and chord starts it as
  `uvx <package>@<version> <args…>`; fast-agent and minion-code today. The
  registry writes a uvx package either as uv's own `<name>@<version>`, which
  uv splits at the `@` before anything else and so does the script, or as a
  PEP 508 requirement, which **pip-requirements-js** (^1.0.3) parses; only a
  single `==` with no extras or markers pins it. **@renovatebot/pep440**
  (^5.0.1, Renovate's PEP 440) says the version is one, so `1.*` and
  `latest` are refused. Both run only in the script. Every entry also keeps
  the registry's `website` and `repository`, for the refusal below.
- **A hand-written table, `src/clis.ts`,** of agents started by a CLI the
  person installs themselves, each with the argv that CLI takes ACP on and
  where its docs say to install it. It started from acpx 0.19.4's table, and
  each argv was checked against the agent's own docs, linked beside it.
  Kept: `cursor` (`agent acp`; acpx had `cursor-agent`, but Cursor's docs
  name only `agent`), `devin` (`devin acp`), `fx` (`fx acp`), `goose` (`goose
  acp`), `junie` (`junie --acp true`, as its docs write it; acpx had
  `--acp=true`), `kimi` (`kimi acp`, now Kimi Code), `kiro` (`kiro-cli acp`;
  acpx had `kiro-cli-chat`), `openclaw`, `opencode`, `poolside` (`pool acp`)
  and `zeroclaw`. Left out: Antigravity (`agy_acp_server`), iFlow
  (`--experimental-acp`) and Trae (`traecli acp serve`), whose ACP command no
  doc of theirs states; MCode, which is MiniMax Code, the registry's npx
  `minimax-code`; and acpx's npx entries (mux, and those the registry
  starts). A name is the registry's id where it lists the agent.
- **Why the CLI and not the archive (the owner's call).** The archives would
  need chord to download, unpack, checksum and update a binary per platform,
  code that has nothing to do with being a client. The person's own CLI is
  the one they already signed in to and keep up to date, and its maker
  documents how it speaks ACP. Downloading the archives is out of scope for
  now.
- **A name in both is the registry's.** Its entry pins a version and needs
  nothing installed beyond npx or uvx, and a refresh that brings an agent to
  npx moves it there without a change to the table. A person who wants their
  installed CLI for such a name gives it with `agents.<name>.command`. No
  name is in both today.
- **A missing command is refused before the window**, and before `-p`, with
  one plain line on stderr and exit code 1: `chord: cursor runs "agent",
  which is not on PATH; install it from https://cursor.com/docs/cli/installation`.
  It is not Cliffy's `ValidationError`, which prints the help first, as
  nothing is wrong with how chord was called. For a registry agent the
  command is `npx` or `uvx`, and the line points at what installs that
  runner, `npx comes with Node.js: https://nodejs.org/en/download` or
  `uvx comes with uv: https://docs.astral.sh/uv/getting-started/installation/`,
  not at the agent's site: chord fetches the agent itself, so the runner is
  what is missing. A command that overrides the name, from `--agent-command` or
  `agents.<name>.command`, is the person's own and is not looked for. Only
  the agents that start are looked for: the one named, or for `--resume` of
  several sessions or of a window, each tab's own, so a restore never needs
  the command of an agent none of its tabs runs. A tab `/new` opens of
  another agent is not looked for yet.
- **@david/which** (0.7.4, exact as it is pre-1.0; dsherret's, the one dax
  uses) finds the command on PATH, PATHEXT included on Windows, and takes an
  environment of the caller's, which the tests use for a PATH of their own.
  It runs under `deno run` and in the `deno compile` binary, both checked.
  npm's `which` would work too, through Node's compatibility layer; the JSR
  one is plain Deno.

## 2026-10-08 — `chord agents` marks own CLIs, and names only the settings define

CHD-227's second part (CHD-229).

- **`chord agents` lists every agent chord can start**: the registry's and
  the table's, then each name only `agents.<name>.command` in the settings
  files (`-C`'s, the user's under the project's) defines. A column says
  where the start comes from: `npx` or `uvx`, `own CLI · found` or `own CLI
  · not on PATH` for the table's, PATH asked through @david/which as the
  refusal asks it, and `settings` where a settings command starts it; the
  start is that command then, in the table's or the registry's place, as it
  is what `chord <name>` runs. The start comes last, as the registry's npx
  lines run long and would push any column after them off an 80-column
  line. On a terminal the start wraps within its own column, so the names
  still read down the left; piped, each agent stays one line for grep and
  awk. A name only the settings define is titled `from settings`, the
  words `/new` describes it by.
- **The start wraps with wrap-ansi**, already chord's, cut hard so a long
  package name fills its lines. Cliffy's own `maxWidth` on the column was
  tried first: it broke the long npm names into pieces as wide as the
  first word, six characters to a line.
- **@cliffy/table** (^1.2.1) lays the columns out. It is the table Cliffy's
  own help is drawn with, so it was in the graph already and in the compiled
  binary; it is named in the import map now that chord imports it. Tabs, as
  the list had, left each column where the terminal's tab stops put it.
- **A name only the settings define starts** as `chord <name>` and `/new
  <name>`, as it did; `/new ` and part of a name now opens the slash command
  list on the agents the window can start, the same names `list_agents`
  gives, each with its title or, for one only the settings define, `from
  settings`, and an own CLI PATH lacks marked `· not on PATH` as `chord
  agents` marks it, PATH looked at once as the window opens. Those the
  settings start come first, then own CLIs PATH has, then the registry's,
  and own CLIs PATH lacks last, whichever agent the window started on. Tab puts `/new <name> ` in the prompt and Enter opens
  it. The fzf match is the commands' one, with the name typed exactly put
  first, so `/new fake` and Enter opens `fake`, not `fake2`. As with
  commands, Enter on an open list takes the highlighted name: a typed name
  the list matches nothing of is refused as before.

## 2026-10-08 — A window record, and `--resume w-…`

Quitting a window with two or more tabs a prompt went to (the test the quit
message already used) writes a window record and prints one command,
`Resume this window with:` / `chord --resume w-<id>`, with no agent name, as
each tab's agent is in the record. One such tab prints the session's own
command, as before, and leaves any window record alone.

- **One JSON file a window**, `windows/<id>.json` in chord's state
  directory, beside `records/`: the id, when it quit, the tabs in order
  (each session's id, agent and directory) and the front tab's index. It is
  read back through a zod schema, as the settings files are, and written
  whole to a file beside it that is renamed over it, as `saveSetting`
  writes. A window is a small whole that is replaced, not a log, so it is
  not JSON Lines. chord has had no release, so the format is free.
- **The id is `w-` and eight hex digits** of `crypto.randomUUID()`: short to
  type, and the web platform's own; no id library was needed. `--resume`
  tells a window by the `w-` prefix, and only an id of chord's own shape is
  looked for, as it names a file.
- **Opened from a record, quit again: the same record**, rewritten as the
  window is then, grown or shrunk, so the windows `/resume` will list
  (CHD-175) do not fill with copies. The tab in front at quit is recorded;
  one with no prompt gives the front to the nearest resumable tab on its
  left.
- **A tab whose session record is gone is left out**, the rest open, and the
  status line says which by agent and short id, not by the tab number,
  which the opened tab bar would give to another tab (`Not reopened: codex
  tab 1a2b3c4d, its record is gone`), through the window's `sessionsNote`, as `ctrl+x a`'s notes are. Only
  a window none of whose sessions is left is refused. Each tab is otherwise
  opened as `-r <id> -r <id>` opens it: from its session record, on its
  agent, in its directory; one tab left opens on its recorded agent too.
- **A window id among session ids is refused** before anything starts
  (`Window w-… opens on its own; --resume takes it without session ids.`).
  It is still Cliffy's repeated `--resume`, parsed as it was; the prefix is
  read from the ids Cliffy hands over.
- **A record that cannot be written** is said on stderr, and the command
  for each session is printed in its place, so nothing is lost.

## 2026-10-08 — Windows in `/resume`, and `--resume` with no id

Built to CHD-174's spec (`docs/design/CHD-174.md`). No dependency was added.

- **`/resume`'s list is the picker it was** (`picker.ts`'s hand-drawn list,
  one line a choice), now of sessions and windows merged by time. A window
  is one more row, `▣ 3 sessions · claude, codex, claude · <front prompt>`,
  in the sessions' columns; no expanding row, which would be a tree widget.
  Its agents fold to counts past 30 columns and are cut only at a `, `,
  measured by string-width, which the rows already use.
- **Enter on a window opens beside, or nothing.** Its tabs go to the end of
  the strip through `OpenSessions.open`, as `ctrl+x c`'s do; one already
  open is not opened twice; a front tab no prompt went to is closed first so
  the window has its place. Past nine it opens none and says so on the
  status line, in the shorter wording where the line is narrow; a tab in
  another directory refuses the whole window as `/resume` refuses a session
  from there.
- **`--resume` takes an optional value**, Cliffy's own `[id:string]` with
  `collect`, so `-r` with no id is `true` among the ids and asks for the
  picker; no argv is rewritten. **The limit, accepted by the owner:** Cliffy
  does not take a word that equals one of chord's option names (`c`, `C`,
  `m`, `model`, `r`, `p`, `cwd`, `continue`, `help`, …) as an optional
  option's value, so `--resume model` is the picker with `model` as
  `[agent]`, `--resume=c` is the picker, and `-r aaa -r c` is `aaa` and the
  picker with `c` as `[agent]`. Under `<id:string>` all of these were ids.
  The owner kept `[id:string]` all the same: a bare `--resume` needs an
  optional value, which is Cliffy's boolean-or-string option and nothing
  else in it; ids as agents make them (UUIDs) and chord's `w-…` never
  equal a flag's name; and a rewrite of argv or a guess at what the word
  meant is what the owner turned down for `-r` before (above). An agent
  whose ids could spell a flag's name is the case this gives up.
  `tests/cli_test.ts` pins it.
- **The start picker is drawn on the Ink that then draws the window.**
  `Start.tsx` is rendered first and the window replaces it through
  `rerender`, so the alternate screen is not left between a pick and the
  window; anything said on stderr after the pick unmounts the picker first,
  so it is not drawn over. Unmounting and rendering anew was the
  alternative, at the cost of the shell flashing between the two.
- **Nothing anywhere, or no terminal**, is refused before Ink, as
  `--continue`'s refusal is: `No earlier <agent> session or window to
  resume.`, and `--resume needs an id when not in a terminal`.

## 2026-10-08 — A parent resumed after its agents ran, drawn from its record

Built to CHD-167's part 7 (CHD-171). No dependency was added; the closing
note's list of names is `Intl.ListFormat`, which Deno has built in.

- **A session chord has a record of is drawn from the record, however the
  agent reopens it.** This supersedes the "Reopening" point of "Resume on
  chord's own session record": a session an agent reopens by
  `session/load` was drawn from the agent's replay, which knows nothing of
  what chord did beside the agent — a task agent's work and ending, a
  message's sender, the calls chord served. The agent still loads the
  session, so it has its context; its replay is passed over. A session
  chord never recorded is drawn from the replay as before, and starts the
  record. What this gives up: turns the session took in another client
  after chord's record of it ended are not drawn, though the agent still
  has them. That loss is the owner's decision (2026-10-09, CHD-252), taken
  for every recorded session an agent reopens by `session/load`; merging
  the replayed history with chord's own task and message data is revisited
  only if the owner asks. Claude's adapter, which offers `session/resume`,
  was drawn from the record already.
- **A task block's work comes from the task's own record.** A task's work
  is relayed into its parent's session as a subagent's, but the parent's
  record keeps only the block's start and end, with the task's name,
  runtime and model; its updates and the calls chord served it are written
  to the task's record alone, whose first line now carries the task's id
  (`task`) beside its parent. The parent resumed reads the records beside
  its own whose `parent` is it, and puts each task's work back after the
  line that started its block, under the task's id, its own subagents'
  under theirs, as they were relayed live. A task whose record has gone
  draws its block, its ending and its report from the parent's record,
  and the resume goes on; the merge marks its start (`workLost` in
  `chord/task`), so its ending says how long it ran but no count of work
  the parent never kept: `Cancelled (9s)`, not `0 tool uses`, and ctrl+o
  draws one dim line where its work would be, `Its work was not kept: the
  task's record is gone.`, as an empty block read as a task that did
  nothing. A task the quit
  cancelled ends as it did then. Keeping the work in both records was the
  first build; it drew the parent's copy and never read the task's, so a
  task's record said nothing a resume used, and every task's work was
  written twice.
- **Long-lived children are not reopened, and the past closes by naming
  those that were open.** The parent's record now keeps a `closed` line for
  a child closed while the session went on, by `close_agent` or the
  person's `x`; a child that closed with its parent (the tab closed,
  `/clear`, `/resume` in its place, the quit) has none, so it was open when
  the session was left. The past closes with chord's own dim `⏺` line,
  `parser (codex) and docs (claude) were open when this session was left
  and are not reopened · /resume lists them`. The parent is told nothing;
  a `send_message` or `close_agent` to one of them is refused with `parser
  was closed when this session was left; open_agent starts another`.
- **A child in `/resume`'s list reads as its name, then what it was
  asked.** Its first prompt is its parent's message, so its row showed the
  `<message from="main">` wrapper; a message's prompt now reads as what was
  said. What it was asked does not say which child it is, so a child's
  record names it on its first line (`name`: a long-lived one's name, a
  task's description), its row leads with that (`parser · agentchild`), and
  the header of one reopened ends with it (`resumed · 2 minutes ago ·
  parser`).
- **A child reopened through `/resume` is the person's, so quitting prints
  its resume command.** A session was left to resume once a `›` prompt went
  to it; a child's first turn is its parent's `←` message, so a message
  counts as well.
- **A call a subagent left unfinished waits on nothing once it has ended.**
  Inside a block that says `Cancelled`, `Disconnected` or the rest, a call
  still pending or running drops its `Waiting…` or `Running…` line and
  stops pulsing, as nothing on screen is waiting for it any more. The same
  holds for a session's own calls once their turn is over (CHD-254): a
  resumed record cut short, a cancelled turn, or a prompt that returned while
  a task it started still asks between turns. Only the turn in flight says
  `Waiting…` or `Running…`.

## 2026-10-08 — The monitor engine: `shell.ts`'s process group, `TextLineStream`, monitors owned by each conversation

Built to CHD-243's parts 3, 5 and 6 (CHD-244): the `monitor`,
`stop_monitor` and `list_monitors` tools, the process, the batching, the
ends, the record and the state the screen task (CHD-245) draws from.

- **@std/streams 1.2.0's `TextLineStream` splits a monitor's stdout.** It
  splits on `\n`, drops a `\r` before it and hands on the last line without
  one when the stream ends, which is CHD-243's rule as written; a lone `\r`
  stays in its line. Behind `TextDecoderStream`, which replaces bad UTF-8.
  Pure TypeScript from jsr; checked under `deno run`, and nothing in it
  differs under `deno compile`.
- **strip-ansi, already chord's, strips escapes, not @std/fmt's
  `stripAnsiCode`.** `context.ts` uses strip-ansi for bash mode's output
  already; one stripper keeps a log line and a bash line read alike, and
  adds nothing.
- **@std/testing 1.0.21's `FakeTime` drives the clock in tests only**: the
  batch window, the timeout and the flood's sliding 10 s use the globals it
  replaces (`setTimeout`, `Date.now`), so the engine takes no clock of its
  own. The tests that run real `printf`, `sleep` and a shell loop through the
  fake agent use real time.
- **One spawner.** `shell.ts` takes `onLine` beside `onOutput`: stdout line
  by line, stderr opened as `/dev/null`, the signal a command died by in its
  end, and why the shell did not start known at once (`failed`), which is
  `monitor`'s refusal. The process group, the stop and the wait for the
  group to be gone are bash mode's. A monitor's shell that exits on its own
  takes its group with it (`reap`, its exit code kept): something it left
  in the background with the pipes let go would outlive the monitor, which
  is off the list and owned by nobody. The reaping starts when the shell
  exits (`exited`), not when stdout closes, since a child still holding
  stdout would otherwise keep it running to its timeout; and the shell's
  code is the end the agent hears from then on, so a timeout or flood while
  a child that ignores SIGTERM waits for its SIGKILL cannot replace it. Bash
  mode does not reap, so a command it backgrounds still outlives the line,
  as before.
- **Each conversation owns its agent's monitors.** A monitor's events go to
  the agent that started it, and the conversation holds that agent's queue,
  so it can join a batch into the monitor's message still queued (reported
  `queued` again under the same id, which the queue's row takes in place)
  and fold the undelivered lines into the end, so an end never costs a
  second turn. Its `/clear`, close and the agent's exit stop them without a
  word, the close waiting for the groups to go, so a tab closed, a child
  closed and a quit leave no process behind.
- **Ids are per agent session.** CHD-243 says `m1`, `m2`, … "for each
  session"; a long-lived child's session counts its own, as an agent sees
  and stops only its own. The limit of 8 counts the tab and its children
  together, as CHD-243 asks, in `window_monitors.ts`, pure over the tabs,
  beside whose monitors a caller reaches.
- **A monitor's callbacks name their run, not only its id.** One the
  person stopped, or one timed out or flooded, can end after a `/clear`,
  when the new session's `m1` is another; its end then finds nothing of
  its own and says nothing.
- **The record needed no line of its own.** The `monitor` and
  `stop_monitor` calls are recorded as served, and each message with its
  sender, which now carries the monitor's id and end. A resumed past reads
  from them the next id, how each ended (`stop_monitor`'s refusals) and
  those that were running when it was left, which close the past with
  chord's dim note, `watch was running when this session was left and is
  not restarted`. What this gives up: an end message still queued at a quit
  never went, so that monitor reads as left running.
- **The wrapper names the monitor:** `<message from="CI run 4812 · monitor
  · exit code 1" monitor="m2">`; chord's sentence is always the message's
  last line, and an event carries at most 100 lines or 16 KiB, the rest
  counted on a line of its own.
- **Left for CHD-245** (built there, see below): the rows, the list under the status line and `x`
  (the engine's `stopMonitor(id, 'person')` is what `x` calls), `/mcp`'s
  line (`toolNames` still lists the earlier tools), the turn an event starts
  not notifying the terminal, and the permission box's raw input. Two
  pieces of screen came with the engine because the compiler asks for them:
  the calls' headlines (`Monitor(…)`, `Stop monitor(…)`, `List monitors`)
  as CHD-243's table gives them, and the resumed past's closing note.
- **`formatElapsed` moved to `src/session/elapsed.ts`**, as a monitor's end
  says how long it ran and the session layer imports nothing from `ui/`.

## 2026-10-09 — The monitor on screen: verbatim event rows, monitor rows in the agent list, `x` stops one

Built to CHD-243's parts 1, 2 and 6 and part 3's `/mcp` line (CHD-245).

- **No new library.** An event's lines are Ink `Text` rows, wrapped by Ink
  at the row's indent; the list keeps its columns with `string-width` and
  `cli-truncate`, as the agent rows already did. markdown is skipped for an
  event on purpose: a log's `*` and `_` are no emphasis, and joining lines
  would merge a trace into its error.
- **One list, one table.** Monitor rows join `agentsLayout`'s columns:
  description, `$ command`, `running 6m · 3 events` (a child's ending
  `· parser` in its colour). Fitting goes command cut first (no shorter
  than `$`, twelve cells and `…`), then an agent's model, then a monitor's
  running time, then an agent's state words, then names. The `main` row
  stays drawn only with a child, so monitors alone show alone.
- **The `❯` on a monitor is window state, not a pick.** `monitorFocus` holds
  the monitor's session key and id (ids are per session, so `m1` can be
  main's and a child's); with none, or one that has ended, the `❯` is on the
  agent picked, or with no agents on the first monitor. `moveListFocus` and
  `stopFocused` are pure over the rows; an agent's row still picks it.
- **`x` is still `agents:close`.** On a monitor's row it calls the engine's
  `stopMonitor(id, 'person')` at once, with no arming, and the `❯` goes to
  the row above. A list that empties while it has the keys hands them back
  to the box.
- **The shortcuts panel is indented on the left alone.** With
  `x to close an agent or stop a monitor` (37 cells) beside
  `ctrl + c to stop the turn and its form` (38), two columns need 82 cells
  with an indent on each side, so at 80 the panel fell to one column and
  past 24 rows. CHD-243's mock lets the last column reach the edge; so does
  `columnCount` now.
- **An event's turn does not notify.** `watchWaits` keeps the turns a
  monitor's event started and gives their result no wait; an end message's
  turn, and a permission or form inside either, notify as ever.
- **`/mcp`** names the three monitor tools, and a picked child's line reads
  `send_message, to main only, and monitor, stop_monitor and list_monitors`.

## 2026-10-09 — Team files: @std/front-matter and @std/yaml, checked by zod

Built to `docs/design/M5-teams.md` part 1 (CHD-258).

- **@std/front-matter reads, @std/yaml writes.** `extract` from
  `@std/front-matter/yaml` parses the frontmatter with `@std/yaml`, block
  scalars included, and `test` from `@std/front-matter/test` tells a file
  with no frontmatter from one with broken YAML (which `extract` gives a
  line and column for). `@std/front-matter` has no writer, so a team is
  written as `@std/yaml`'s `stringify` of its frontmatter between two `---`
  lines, then the body. Both are Deno's standard library on JSR, and both
  were tried on part 1's example under `deno run` and from a `deno
  compile`d binary, first by the designer and again here. Passed over:
  `gray-matter` (CommonJS on js-yaml 3, no release since 2023) and npm's
  `front-matter` (reads only).
- **The check is zod's, worded in its paths.** A broken file is listed, not
  dropped, with its first issue: `members.1.agent is missing`,
  `members.1.agent: chord knows no runtime named codx`. Runtimes are checked
  by name against the ones chord knows; model and mode ids are not, as only
  a started runtime knows them.
- **The body is kept trimmed**, and written after one blank line with one
  newline at the end, so a file read, written and read again gives the same
  team. `stringify` folds a long description across lines; it reads back
  the same.
- **A write goes to a file beside the target and is renamed over it**, as
  `saveSetting` writes the settings file, so a failed write leaves the old
  file whole.
- **`list_agents` gives each runtime's modes beside its models**
  (`modes`, `currentMode`), read from the same `session/new` answer as the
  models, so a proposing agent picks real mode ids. A runtime that offers
  modes and no models answers with no models; one that offers neither says
  so.

## 2026-10-09 — The startup splash: a table of eight places and one timer

CHD-241's splash (`docs/design/CHD-241.md`) drifts the mark round a small
ellipse while the first session starts.

- **No animation library.** ink-spinner, already in the window, plays only
  cli-spinners' named one-line spinners and takes no frames of its own, so
  it cannot draw a ten-row box. A spring or tween library (react-spring and
  the like) computes positions between cells, which a grid of half rows and
  whole columns cannot draw; the design's path is eight places, so it is a
  table (`SPLASH_PATH`) and one `setInterval` of 300 ms in `Splash.tsx`.
- **The window stays mounted under the splash**, laid out with Ink's
  `display="none"` and not drawn, so the keys pressed during the start land
  in it as if typed there, the prompt's own textarea included. Holding the
  presses and playing them into the window later would have meant feeding
  Ink's stdin events back in by hand. Esc is the one key `keys.ts` takes for
  the splash itself.
- **The 8-row mark comes from `deno task mark`** beside the 4-row one; its
  half cells keep the threshold's margin (below 0.29 or at 0.59 and above).

## 2026-10-09 — Every agent spawns tasks, and a parent hears a child's end

Built to `docs/design/M5-teams.md` parts 3 and 6 for M4's agents (CHD-259).
No library: it is chord's own routing between its sessions.

- **A long-lived child gets `spawn_task` and `list_agents`**, as owner's
  answer 7 has it, and a task still gets `send_message` alone. The task runs
  in the child's `Conversation`, so it draws in the child's turn, its
  permissions open in the child's box, it reports to the child, and closing
  the child closes it as closing a session closes its tasks. The task's
  `Caller` names the child (`by`), which is how its `send_message` finds the
  child rather than the tab's session.
- **"Last words" are the end of the agent's stderr**, the same text a turn
  cut short by the exit already fails with (`The agent exited: …`).
  `Session.gone()` reads it once the connection has gone and is undefined
  while the agent is up, which is also how a turn that failed because the
  agent went is told from one the agent failed and survived: the first is
  the exit's to report, so the parent hears one `← chord`, not two.
- **A failed turn has its own sentence**: `parser's turn failed: <why>. It
  is still open; send_message reaches it.` The design words only the exit;
  "open_agent opens it again" would be wrong for an agent still up.
- **`/mcp`'s line for a picked child** names `send_message` last, as the
  one tool qualified (`… and send_message to main only`), now that it is no
  longer the child's first tool.

## 2026-10-09 — A team runs as M4's children, one level deeper

Built to `docs/design/M5-teams.md` parts 3, 4 ("A member picked"), 5 and 6
(CHD-260). No library: it is chord's own routing between its sessions, on
the team files `src/teams.ts` already reads.

- **A lead and its members are children of the tab**, as M4's are, kept in
  one list with a member after its lead; a child's `team` names its file
  and a member's `lead` its lead's id. That reuses picking, the box, the
  permission box, waits and closing as they are. The list is still M4's
  flat one; nesting and folding are the list's own task.
- **The eight-children cap counts main's own children**, a lead as one, and
  no member, so a team does not crowd main out; the file caps members at
  eight.
- **A member keeps its file name**, unnumbered, so two runs each have a
  `tester`. Messages are routed by who sends them, never by a name across
  the tab: main reaches its own children, a lead its members, main and the
  other leads, a member its lead and its team's other members.
- **A run's name is numbered past every lead of that team the tab has had**,
  open or closed, so `bugfix 2` in an old message still means that run.
- **The team part rides in the first prompt** as `<team name="bugfix"
  role="member" member="tester">…</team>` ahead of the wrapped message, and
  a record reads it back from the prompt it kept, so a resumed member draws
  the same one line. `member=` rather than the design's second `name=`, as
  an element cannot carry `name` twice.
- **The run keeps the file as read when it started**, so a lead opens the
  members its job was planned with even if the file changes meanwhile.
- **A refused mode is said before the open** where the runtime's modes are
  known (`codex has no mode yolo · read-only, auto, full-access`), as a
  model is; otherwise the member's start fails on it, as a task's model does.
- **The Team and Open rows wrap what they handed over** under `⎿`, three
  lines and `… +N lines` until ctrl+o, as the mocks draw them: the job is
  the person's own words to the team, unreadable cut at 80 columns. M4's
  Open wraps with them, as one row draws both; every other chord call, the
  `→ @name` rows among them, is still cut, their bodies being CHD-266's.
- **A member is named with its run where it would be ambiguous**: while two
  open agents share its name, the status line says `tester · bugfix 2 needs
  your permission`, as the box always says `tester · bugfix 2`.

## 2026-10-09 — `propose_team`: the proposal as a @cliffy/table, the save box as a permission

Built to `docs/design/M5-teams.md` part 2, "Making a team" and "Changing a
team" (CHD-261). No new dependency.

- **@cliffy/table lays the proposal's columns out**, as it does `chord
  agents`' (tried against the rows of `120-1-proposal.txt`, at 120 and 80
  columns). It pads columns but cuts nothing, so each cell is cut first to
  the room its column has, by cli-truncate, as `/mcp` cuts its cells: the
  role down to 12 cells, then the runtime's model, never the name or the
  mode, which is the permission the person approves. The mode's place in
  each laid-out line follows from the same widths, so it is painted in the
  `warning` colour where it skips the person's ok (`bypassPermissions`,
  codex's `full-access`); the words stay for `NO_COLOR`.
- **The save box is a permission request of chord's own.** `Conversation.ask`
  parks a `PermissionWait` carrying `save` (the question, each choice's
  file, what Esc does) beside the agent's own requests, so the box is the
  permission box's ink-select-input list, 1–3, ↑ ↓, Enter and Esc as the
  last choice, and the waits, the status line's notice and the terminal's
  bell come with it. Its answer is drawn on the call, `Saved to …` or `Not
  saved …`, so the reducer leaves no `Allowed`/`Rejected` line for it. It
  is withdrawn with the turn, an interrupt, `/clear` and the close, and by
  the MCP request's own signal, and the call then refuses.
- **The proposal is drawn while the box is open**: the tool serves its call
  `pending`, and the answer served after takes its place on the same call,
  whether the call came before, between or after them. The two share an id
  chord makes for the question, not the arguments: two proposals of the same
  team can wait at once, and each answer is its own call's. A team's changes
  keep the lead's apart from the members', since a member may be named
  `lead`. A record written before the id leaves its proposal pending when
  replayed; chord has had no release, so nothing reads the old shape.
- **The input's types are the MCP SDK's check, the rest is chord's.** The
  tool's input schema is the team file's structure with each part's JSON
  type and what it is for, so the agent reads it as JSON Schema; the SDK
  refuses a call with a wrong type in zod's words, and `checkTeam` checks
  the rest (names, one-line fields, lengths, known runtimes, 1–8 members, a
  body) as it checks a file, its first problem the refusal under `⎿`. Tried
  first: every part passed through with zod's `.catch((ctx) => ctx.value)`,
  so that chord's check would word every problem; zod's `toJSONSchema`
  refuses a dynamic catch, which would leave the agent no schema.
- **chord writes the file, through part 1's writer**, to the place picked;
  a change is saved back where the team was found, as the design has it.
- **The body folds to its first two lines where the window has 30 rows or
  more, and to none below**, so at 80×24 the table, the box and the prompt
  fit, as the mocks show; `… +N lines` counts what ctrl+o adds, the agents'
  instructions included.
- **A change's body is counted, not narrated**: `bugfix.md's body · 1
  addition, 1 removal`, not an edit's `Updated …`, which would read as
  written before the person says yes. Folded, jsdiff's diff keeps its
  changed lines with one line of context, at most five rows, where the
  window has 30 rows, and none below, so at 80×24 the table, that line and
  the box fit; the one `… +N lines` counts the rest with the instructions,
  and ctrl+o draws the diff whole, as an edit's. A `~` row whose mode
  changed says the mode it had, dim, after the new one (`bypassPermissions
  was acceptEdits`), in the mode's column, which is never cut, so at 80
  columns the model is cut sooner.
- **Where the mocks disagree with themselves, two cells between columns
  everywhere**: `120-1-proposal.txt` has three after the runtime column and
  five before the box's files, `80-1-proposal.txt` two.

## 2026-10-09 — The team in the agent list: nested, folded where it does not fit

Built to `docs/design/M5-teams.md` part 4 and part 6's arming (CHD-262).

- **No library: the list's own layout, one step ahead of it.** The rows
  were already `agents.ts`'s own columns (CHD-149, CHD-225); the tree is two
  glyphs, CHD-149's, and folding is choosing which rows to draw, which no
  widget does for a layout it does not own, so none was tried. `teamRows`
  is a pure step between the window's agents and `agentsLayout`, and the
  window, the layout and ↑ ↓ read the same rows.
- **The list folds when the whole of it, monitors included, would pass its
  row limit**, and then every team folds but the one the picked agent is
  in, whether or not the list has the keys: `ctrl+x a` on a member, and esc
  back to the box with a member picked, leave its team open, as the box
  writes to it. ↑ ↓ walk the rows as drawn, so ↑ from below a folded team
  lands on its lead, which unfolds it.
- **A folded lead's state is the most urgent of its team's, as
  `agentState` orders them** (a permission or form, a failure, an exit, a
  message, a reply, work), the longest standing first within one kind,
  named `tester: ` when it is a member's. Its size, `4 agents`, stands
  where its model would, but outlasts the models when the row narrows: a
  long model elsewhere (the fake agent's `Fake Large with a 1M context
  window`) would otherwise take the size with it.
- **The name column is as wide as the widest name unfolded**, branch and
  all, so folding moves no column, as the mocks have it. The detail column
  is the widest over every row drawn or scrolled past, as before:
  `80-4-team-focused.txt` pads it over the visible rows alone, one cell
  narrower, but the existing rule keeps a column still while the list
  scrolls.
- **`x` on a lead arms while any of its team works**, the lead idle or not,
  with `bugfix and its 3 members are working · x again to stop them and
  close` (`its member` for one). The shortcuts panel keeps `x to close an
  agent or stop a monitor`: the design's `an agent or a team, or stop a
  monitor` is 47 cells and drops the panel to one column at 80×24.
- **A notification names a member with its run**, `tester (bugfix) needs
  your permission`, always; the status line adds the run only when two open
  runs share the name, as `namedChild` already did.

## 2026-10-09 — `/team`: the picker, show, run and stop

Built to `docs/design/M5-teams.md` part 2, part 5's `/team show` and part
6's `/team stop` (CHD-263).

- **No new library.** The picker is `/resume`'s list (`PickerList` in
  `Pickers.tsx`), its rows laid out in columns as `/resume`'s are; `/team
  show`'s saved form reuses `propose_team`'s @cliffy/table rows and folded
  body, and its running form is a @cliffy/table of the same columns with
  the state and latest headline in place of the role. `/team run`'s row is
  `run_team`'s call drawn by `Tool.tsx`, so the two cannot drift apart.
- **The picker's rows keep `/resume`'s numbers** (`1. bugfix`), as the list
  takes digits as `/resume`'s does; the mocks have none.
- **There is no `/team edit`, in either form** (the owner's decision). A
  team is changed by asking main in plain words; main changes it through
  `propose_team`, which already shows the change against the saved team
  and asks where to save. The native form was built on
  @inquirer/external-editor, as ctrl+g is, and QA showed it rewrote an
  unchanged UTF-8 file as mojibake: the library writes its temporary file
  as UTF-8 but reads it back through chardet's guess, which takes a long,
  mostly ASCII file with an em dash for windows-1252. The picker's Enter on
  a broken file so puts nothing in the box; its row already says the
  problem and the path.
- **chord's note of a `/team run` goes ahead of main's next prompt only**,
  as held shell output and a stopped task's line do, not ahead of a
  message's turn: a resumed session reads a message turn back from its
  prompt's wrapper, which a note in front of it would break. The lead's
  first report so reaches main before the note does; it says who it is
  from, and `send_message` reaches it either way.
- **`/team stop` tells main with `← chord`**, the sentence `x` on a lead
  sends, which starts main's turn (part 6, "Main is told whenever the
  person closed the team"); its own line comes first in the transcript.
  The line counts the members with a serial comma (`its lead, tester, and
  coder are closed`), as `Intl.ListFormat` and chord's other lists do.
- **`/team` acts for the front tab's `main` whatever is picked**: what it
  draws goes into main's transcript, and the first `/team` with a child
  picked says `/team talks to main` on the status line.

## 2026-10-10 — Teams on resume

Built to `docs/design/M5-teams.md` part 7 (CHD-264). `--resume` does not
reopen a team (the owner's answer 5); the past is drawn from main's record
as M4's children's is.

- **A lead's record names main as its parent and its team** (`team:
  bugfix`), and every long-lived agent's names chord's id for it (`id`),
  which its parent's `run_team` or `open_agent` answer and `closed` line
  use. A member's names its lead as its parent and its member name, as an
  M4 child's names its parent and its name.
- **The closing note counts each run as one item**, `team bugfix (4
  agents)`: its lead and the members its lead's own record had open, read
  beside main's by the lead's id, as a task's work is. A lead whose record
  has gone counts itself alone. Several runs are named one by one, each
  with its own count (`team bugfix (4 agents) and team bugfix 2 (3
  agents)`), which the task asks for ("counts each run as one item"); the
  design's example gives the two runs one count. The way back is one
  `/team run bugfix` per team, however many of its runs were open; `/resume
  lists them` whenever a team is among them, as it lists every agent of the
  run.
- **A `/team run` the person typed is kept in main's record as the
  `run_team` call it was**, so the note names its run too, on a `ran` line of
  its own. It draws nothing on resume, as no other slash command's output is
  drawn again. It is not a `served` line: a resumed `served` answer with no
  call of the agent's waits for one, and the agent's own `run_team` with the
  same team and job would take the typed run's answer for its own.
- **A message to a run left open is refused with `run_team starts the team
  again`** in place of M4's `open_agent starts another`.
- No library was needed: the change is record lines and a sentence, on the
  records' own reader and `Intl.ListFormat`, which the note used already.

## 2026-10-10 — Moving to Bun: the plan, what was tried, and the owner's open choices

CHD-276. chord moves from Deno to Bun. This entry is the plan. When the
owner answers the open choices below, the entry that records those answers
supersedes "Deno, compiled to one binary" and "emulon's code style". Until
then, nobody moves code. Everything below was measured on today's tree
(commit 10a7eca) and tried with Bun 1.4.2 on macOS arm64, in a scratch
directory outside the repository.

### What moves, measured

- **Runtime APIs.** 21 files in `src/` call `Deno.*`, as do 115 test files,
  the four scripts and `lint/`. By count, most of it is files and
  directories (`remove`, `makeTempDir`, `readTextFile`, `writeTextFile`,
  `mkdir`, `readDir`, `stat`, `rename`, `copyFile`, `chmod`), then
  `env`, `cwd`, `args`, `exit`, `execPath`, `build.os`, `stdin`/`stdout`
  `isTerminal`, `noColor`, `consoleSize`, `unrefTimer` and
  `errors.NotFound`. Each of those has a direct `node:fs/promises`,
  `node:process` or `node:os` counterpart, and Bun implements all of them.
  The risky ones are few:
  - **Process groups and signals** (`Deno.Command`, `Deno.kill(-pid)` in
    `src/acp/process.ts` and `src/shell.ts`, `Deno.addSignalListener`).
    Tried: `node:child_process` `spawn(…, { detached: true })` puts the
    shell in a group of its own, and `process.kill(-pid, 'SIGTERM')`
    stopped the shell and both of its background `sleep`s. `exit` reported
    `null/SIGTERM`, and nothing was left in the group. `Bun.spawn` with
    `detached: true` leads its own group too. The plan takes
    `node:child_process`, because its `exit` event carries the signal name
    that `ShellEnd` reports and it runs unchanged under `bun test`.
  - **chord's MCP server** (`Deno.serve` in `src/server/server.ts`). It
    already runs on the SDK's `WebStandardStreamableHTTPServerTransport`,
    which takes a `Request` and answers a `Response`, so `Bun.serve({
    fetch })` is a straight swap. One trap: `Bun.serve` closes a connection
    that sits idle for 10 seconds by default, which would cut an MCP SSE
    stream while a tool waits on the person (`propose_team`'s save box).
    The part sets `idleTimeout: 0` and tests a held stream. The version
    `server.ts` reads from `deno.json` comes from `package.json` instead.
  - `Deno.build.target` in `scripts/compile.ts` becomes
    `process.platform`/`process.arch`.
- **Tests.** There are 1,429 `Deno.test`s, 20 `t.step`s and one `ignore:`.
  No test uses sanitizer options or Deno permissions. Tried under `bun
  test`: `@std/assert` and `@std/testing/time`'s `FakeTime` (with `using`
  and `tickAsync`) both pass, so the 109 files that import `@std/assert`
  keep their assertions. Only `Deno.test` becomes `test` from `bun:test`,
  and each `t.step` becomes a `describe`/`test`. ink-testing-library is
  plain Node. The fake agent (`tests/fixtures/fake.ts` starts
  `fake_agent/main.ts` as a subprocess) is started with `process.execPath`
  in place of `deno run`.
- **Dependencies.** Bun does not resolve `jsr:` specifiers (`bun add
  jsr:@cliffy/command` fails: Bun tries to clone it as a git repository).
  jsr's npm registry works: with `"@jsr" = "https://npm.jsr.io"` under
  `[install.scopes]` in `bunfig.toml` (and the same in `.npmrc` for npm),
  `@jsr/cliffy__command`, `cliffy__table`, `david__which`, `std__front-matter`,
  `std__yaml`, `std__streams`, `std__path`, `std__encoding`, `std__async`,
  `std__testing` and `std__assert` all install and run under Bun.
  Checked: Cliffy parsing `-r a -r b` into a collected list, a
  `@cliffy/table`, `which('git')`, front-matter's YAML `extract`,
  `TextLineStream`. Aliased in `package.json` (`"@std/path":
  "npm:@jsr/std__path@^1.1.0"`), the import specifiers in the source stay
  exactly as they are, and `tsc` types them. `@zod/zod` becomes npm's
  `zod`, which is the same package. The `npm:` imports in `deno.json`
  become `package.json` dependencies at the same ranges, with
  `bun.lock` committed. The pre-1.0 exact pins stay exact.
- **Tooling.** `deno fmt` is dprint's TypeScript plugin, and the `dprint`
  CLI ships on npm. With `lineWidth: 80`, single quotes (JSX too),
  `useBraces: always`, `singleBodyPosition: nextLine`, spaces inside
  braces, binary operators on the same line, ternary operators on the next
  line and a space after `function`, `dprint check` with plugin 0.95.13
  agreed with `deno fmt` on 283 of the 284 TypeScript files.
  The one difference, a `&&` chain inside a ternary in
  `src/ui/app/sessions.ts`, comes from the plugin version, and part 1 pins
  the plugin. Moving the formatter therefore needs no reformat commit.
  Lint has no such twin. `deno lint`'s rules map onto ESLint's (`eqeqeq`,
  `camelcase`, `no-case-declarations`, `no-eval`, `no-throw-literal`, the
  typescript-eslint counterparts of `no-inferrable-types` and
  `no-non-null-asserted-optional-chain`, and eslint-plugin-react-hooks
  for the `react` tag). `no-node-globals` goes, because under Bun the Node
  globals are the platform. `lint/style.ts` is written against Deno's lint
  plugin API, which follows ESLint's (`create(context)` returning
  visitors, `context.report` with a fix), so it ports to a local ESLint
  plugin almost line for line, `--fix` included. Its test moves with it
  onto ESLint's `RuleTester`. Types: `deno check` becomes `tsc --noEmit`
  with `@types/bun`, `allowImportingTsExtensions`, and the three strict
  flags kept.
- **Build and release.** Tried: an Ink 8 app rendered with
  `alternateScreen: true`, `exitOnCtrlC: false` and `kittyKeyboard: { mode:
  'auto' }` compiles with `bun build --compile` (about 63 MB on macOS
  arm64, against Deno's ~110 MB). Driven in tmux at 80×24, it drew,
  read `a`, `ctrl+x` and Enter in raw mode, quit on Esc, and left the
  alternate screen clean with exit code 0. Cross-compiling to
  `bun-linux-x64` and `bun-windows-x64` works from this Mac.
  `@mariozechner/clipboard`'s N-API addon is embedded and loads from the
  compiled binary. Two findings:
  - **Ink's devtools import.** Ink's reconciler imports `./devtools.js`
    only when `DEV=true`, but `bun build` bundles it, and `devtools.js`
    imports `react-devtools-core` statically, which chord does not
    install. The build fails, or with `--external react-devtools-core` the
    binary dies at start. Defining `process.env.DEV` does not help. Two
    ways work: installing `react-devtools-core` as a dependency (never
    connected unless `DEV=true` and a devtools server answers), or
    `--external react-devtools-core --splitting`, which keeps the import
    lazy. Both drew and quit cleanly. This touches how a library is built,
    so it is the owner's choice 6 below, not the engineer's.
  - **Native addons for other targets.** A cross-compiled binary embeds
    only the clipboard package that is installed, which is the host's.
    The compile part installs every platform's optional package (`bun
    install --os='*' --cpu='*'`) before `--all` and checks that each
    binary starts. The Linux and Windows binaries are checked by `file`
    and a start on the host where one is at hand. The owner checks
    Windows by hand, as today.
  - Not checked yet: the kitty keyboard protocol through the compiled
    binary, because tmux does not pass it on. The compile part checks it
    in a terminal that speaks the protocol (shift+Enter as a newline), and
    the owner confirms it.

### Order of the parts

Each part keeps one `check` green at its commit. While both runtimes live
side by side, `check` runs both.

1. **Bun beside Deno** (invisible): `package.json`, `bun.lock`,
   `bunfig.toml`, `tsconfig.json` and the dprint and ESLint configs, with
   `lint/style.ts` ported to the ESLint plugin and its test. `deno task
   check` still runs the Deno suite and also runs `bun check:static`
   (tsc, ESLint, dprint) on the same tree.
2. **A thin platform layer** (invisible): `src/platform/` with the few
   things that are not plain `node:` calls: spawning in a process group,
   signalling that group, serving HTTP, and the binary's own path. It
   starts on Deno's API, so moving it later is one module's change.
   Everything else goes straight to `node:fs`, `node:process` and
   `node:path`, which Deno also runs. Module by module (acp and session,
   then server, then UI, then the CLI), each a task, each keeping the
   Deno suite green.
3. **Tests onto `bun test`** (invisible): `Deno.test` becomes `test`,
   `t.step` becomes nested tests, `@std/assert` and `FakeTime` stay. The
   fake agent starts under `process.execPath`. The privacy test lists
   tracked files through `node:child_process`. The platform layer moves to
   Bun (`Bun.serve` with `idleTimeout: 0`). From this part, `check` is
   `bun check`.
4. **Compile and release** (visible: the binary is what a person runs):
   `scripts/compile.ts` on `bun build --compile` for every target in
   `scripts/targets.ts` (the `deno` field becomes `bun`), and `install`,
   `npm`, `registry` and `mark` on Bun. The engineer builds, then the
   designer and QA compare 120×40 and 80×24 captures of the compiled
   binary before and after, as the refactor did: the splash, a turn with
   the fake agent, a permission prompt, `/team`, quit.
5. **Deno leaves** (invisible): `deno.json`, `deno.lock` and the Deno
   half of `check` are removed. CLAUDE.md's "Commands" and "How code is
   written", the chord-tui skill's commands and README's install-from-
   source lines are rewritten.

### Open choices for the owner, each with the lead's recommendation

1. **Test runner.** Recommended: `bun test`, keeping `@std/assert` and
   `@std/testing` through jsr's npm registry, so 1,429 test bodies keep
   their assertions. Alternatives: Vitest (Jest-like, more dependencies, a
   second runtime layer), or `node:test` (works under Bun, but its
   reporter and mocks are thinner).
2. **Formatter and linter.** Recommended: dprint (`deno fmt`'s own engine,
   so the tree needs no reformat) and ESLint with typescript-eslint,
   react-hooks and `lint/style.ts` as a local plugin. Alternative: Biome
   for both. It is one fast tool, but its formatter follows Prettier, so
   the whole tree would be reformatted, and its plugins (GritQL) report
   without fixing, which costs `lint/style.ts` its `--fix`.
3. **jsr packages.** Recommended: keep them all through
   `npm.jsr.io`, aliased under their current names, so no import changes,
   with `@zod/zod` moved to npm's `zod`. Alternative: replace them now
   (`@std/path` with `node:path`, `@std/encoding/base64` with `Buffer`,
   Cliffy with commander). That is more churn, and Cliffy has no drop-in:
   `-r a -r b` and its help output would need re-checking.
4. **Minimum Bun version.** Recommended: `>=1.4.2`, the version every
   trial above ran on, set in `package.json`'s `engines` and checked by
   the compile script. Nothing older was tried.
5. **Helper scripts.** Recommended: move them too (`compile`, `install`,
   `npm`, `registry`, `mark`), so a contributor needs only Bun. Keeping
   them on Deno would keep Deno as a second toolchain for the one step
   that matters most, the release build.
6. **Ink's devtools import in the compiled binary.** Recommended: add
   `react-devtools-core` as a dependency, which keeps `bun build
   --compile` plain. Alternative: build with `--external
   react-devtools-core --splitting`. The binary stays a little smaller,
   but this is a build flag that works around how Ink is bundled.

## 2026-10-10 — Moving to Bun: the owner's answers, and the plan they change

CHD-276. The owner answered the six open choices in the entry above. This
entry supersedes that entry's choices and the parts of its plan they change.
Once part 5 lands, it also supersedes "Deno, compiled to one binary" and
"emulon's code style".

### The answers

1. **Test runner: `bun test`, and Deno's standard library leaves with it.**
   Tests use `bun:test`'s `expect`, mocks and fake timers. No test imports
   `@std/assert` or `@std/testing`. The owner reads this as the whole `@std`
   family leaving, `src/` included.
2. **Formatter: Prettier, not dprint.** A one-off reformat commit is
   accepted where Prettier's output differs from `deno fmt`'s. It is a
   commit of its own. The linter stays ESLint, with `lint/style.ts` as a
   local plugin.
3. **jsr packages** go through `npm.jsr.io` under their current names, and
   `@zod/zod` becomes npm's `zod`. After answer 1 this covers only the
   non-`@std` ones: `@cliffy/command`, `@cliffy/table` and `@david/which`.
4. **Minimum Bun: `>=1.4.2`.**
5. **The helper scripts move to Bun too.**
6. **Ink's devtools import: `--external react-devtools-core --splitting`.**
   This holds only if everything else keeps working in the compiled
   binary: start, keys, the alternate screen, the clipboard, and every
   release target. If something breaks, what broke goes to the owner
   before anyone falls back to the dependency.

### Where each `@std` package goes

Each one has a built-in that runs under both Deno and Bun, so `src/` can
move while the Deno suite still guards it. The one exception is front
matter.

| Today | Used in | Goes to |
| --- | --- | --- |
| `@std/path` | 17 files in `src/` and scripts | `node:path` |
| `@std/assert/equal` | `teams.ts`, `session/transcript/chord.ts` | `node:util`'s `isDeepStrictEqual` |
| `@std/encoding/base64` | `images.ts`, a test fixture | `Buffer`'s `base64` |
| `@std/async`'s `delay` | `session/conversation.ts`, a test | `node:timers/promises`' `setTimeout` |
| `@std/streams`' `TextLineStream` | `shell.ts` | `node:readline` over the child's stdout, which `node:child_process` already gives |
| `@std/yaml`'s `stringify` | `teams.ts` | npm's `yaml` (eemeli/yaml), which runs on both runtimes |
| `@std/front-matter` (`extract`, `test`) | `teams.ts` | a maintained npm front-matter package if one fits, with its YAML parsed by `yaml`. The engineer tries candidates and records them. If none fits, it goes to the owner as a question and is not written by hand |
| `@std/assert` | 109 test files | `bun:test`'s `expect` |
| `@std/testing/time`'s `FakeTime` | `session/monitors_test.ts` | `bun:test`'s fake timers. If they cannot drive what `tickAsync` drives, that goes to the owner |

`Bun.YAML` is built in, but Deno does not run it. `yaml` is chosen so
that part 2 can land while Deno still runs the suite.

### Prettier and what moves to ESLint

Prettier keeps blank lines but never inserts them, and it does not move
imports. That is the same limit `deno fmt` had, so none of the eight rules
in `lint/style.ts` becomes moot, and all eight move to the ESLint plugin
with their fixes. One rule joins them. Prettier does not add braces, so
`deno fmt`'s `useBraces: always` becomes ESLint's `curly: all`, which has
an autofix. With braces always on, `singleBodyPosition: nextLine` has
nothing left to place. Prettier's options come as close to the current
style as they reach: `printWidth: 80`, `singleQuote` and `jsxSingleQuote`,
and `bracketSpacing`. The `deno lint` rules map as the entry above says.

### The style plugin's cast

`tsc` checks `eslint.config.ts` like the rest of the tree, and one cast
lets it: `lint/style.ts` goes into `plugins` as
`style as unknown as ESLint.Plugin`. Its rules are typescript-eslint 8's
`RuleModule`, whose nodes are typed more narrowly than ESLint 10's; the
latest of both, typescript-eslint 8.72 and ESLint 10.13, still disagree.
Retyping the rules with ESLint's own types costs twenty errors in the rules
(ranges that may be missing, statements without a parent), so the cast
stays at the one place the two meet, as `lint/style_test.ts` already does
for `RuleTester`. The owner agreed to it (CHD-475). eslint-plugin-react-hooks
needs no cast: only its `rules` are passed, since its `configs` are what
ESLint 10's `Plugin` type rejects, and chord takes none of them.

### The parts, revised

Each part keeps `check` green at every commit.

1. **Bun beside Deno** (invisible). This part adds `package.json`,
   `bun.lock`, `bunfig.toml`, `tsconfig.json`, Prettier and ESLint, with
   `lint/style.ts` ported and its test on ESLint's `RuleTester`. `check`
   runs both suites. The Prettier reformat is a commit of its own,
   holding only Prettier's output and the swap of `deno fmt --check` for
   `prettier --check`.
2. **Off Deno's API and `@std` in `src/`** (invisible). Every change in
   this part runs under Deno too, so the Deno suite keeps guarding it.
   - 2a: `src/platform/` holds spawning in a process group, signalling the
     group, serving HTTP and the binary's own path. `src/acp/process.ts`,
     `src/shell.ts` and `src/server/` move onto it. `shell.ts`'s
     `TextLineStream` goes in the same change.
   - 2b: every other `Deno.*` call and `@std` import in `src/` moves to
     `node:` built-ins or to the packages in the table above.
3. **Tests onto `bun test`** (invisible).
   - 3a, the flip: `Deno.test` becomes `bun:test`, and `t.step` becomes
     nested tests. `@std/assert` and `FakeTime` still run for this one
     part. The fake agent starts under `process.execPath`, the privacy test
     lists tracked files through `node:child_process`, and the platform
     layer moves to Bun (`Bun.serve` with `idleTimeout: 0`). From here
     `check` is `bun check`. CLAUDE.md's "Commands" and "How code is
     written" and the chord-tui skill's commands are rewritten here,
     because this part flips the runtime.
   - 3b: `@std/assert` becomes `expect`, and `FakeTime` becomes
     `bun:test`'s fake timers. No `@std` package is left in the tree.
4. **Compile and release** (visible). The binary is built with `bun build
   --compile --external react-devtools-core --splitting` for every target
   in `scripts/targets.ts`, and `install`, `npm`, `registry` and `mark` run
   on Bun. Answer 6's condition is checked target by target. The designer
   and QA compare 120×40 and 80×24 captures before and after.
5. **Deno leaves** (invisible). `deno.json`, `deno.lock` and every
   remaining Deno line go, including README's install-from-source lines.

## 2026-10-10 — Bun part 1: Bun's tools beside Deno

CHD-287, the first part of the two "Moving to Bun" entries above. chord
still runs and is tested on Deno; Bun brings `tsc`, ESLint and the
formatter, and `deno task check` calls `bun check:static` after the Deno
suite. Tried with Bun 1.4.2 and Deno 2.9.7 on macOS arm64.

- **`package.json` and `bun.lock`.** Every `npm:` import in `deno.json` is a
  dependency at the same range, the pre-1.0 exact pins exact. The jsr
  packages come from `npm.jsr.io` (`bunfig.toml`'s `[install.scopes]`, and
  `.npmrc` for npm) aliased under their own names (`"@cliffy/command":
  "npm:@jsr/cliffy__command@^1.2.1"`), so no import changed; `@zod/zod` is
  npm's `zod`. `@std/cli`, which `scripts/compile.ts` imported as a bare
  `jsr:` URL that `tsc` cannot resolve, moved into both import lists.
  `bunfig.toml`'s `[run] bun = true` runs ESLint and the rest on Bun even
  where their bin asks for `node`, so Bun is the only toolchain needed.
  `bunx` and an editor's ESLint run it on Node, where ESLint loads a
  TypeScript config only through `jiti`, so `jiti` is a dev dependency too.
- **Deno and `package.json`.** With a `package.json` beside it, Deno reads
  `node_modules` (Bun's), and `deno check` then failed to find
  `@modelcontextprotocol/sdk/client/index.js`. `"nodeModulesDir": "none"` in
  `deno.json` keeps Deno on its own cache, and the Deno suite passed
  unchanged. `deno.lock` gains the `packageJson` list it records.
- **TypeScript 7 and typescript-eslint.** `typescript` on npm is now 7.0, the
  native compiler, and typescript-eslint refuses to load with it (TS 7 has
  no API yet). As TypeScript's own release notes advise, `typescript` is
  aliased to `@typescript/typescript6` for the tools that import it, and
  `@typescript/native` is TypeScript 7, whose `tsc` checks the tree in about
  a second.
- **`tsconfig.json`.** `@types/bun`, `allowImportingTsExtensions`,
  `react-jsx`, and `strict`, `noUncheckedIndexedAccess` and
  `exactOptionalPropertyTypes`. While the code still calls `Deno.*`,
  `@types/deno` (DefinitelyTyped, 2.7) types it; part 3 drops it. Deno's
  `// @ts-types` comments mean nothing to `tsc`, which found its own types
  for all but two: `convert-layout/ru.js` is mapped to the `.d.ts` beside
  `bindings.ts` through `paths`, and `npm-package-arg` takes
  `@types/npm-package-arg`. Three places differ between Deno's types and
  Bun's and are bridged until part 2 replaces them: `Deno.unrefTimer` takes
  `Number(held)`, as Bun's types call a timer a `Timeout`, and `shell.ts`
  names its `TextDecoderStream` as the transform Deno's streams take.
  `tsc` on macOS skipped eight test files whose names differ only in case
  from another's with the other extension (`Agents_test.tsx` beside
  `agents_test.ts`): its include treats them as one module on a
  case-insensitive disk. `files` lists them; Linux finds them anyway.
- **ESLint.** `eslint.config.ts`: `@eslint/js` and typescript-eslint
  `recommended`, deno lint's extra rules as the first entry maps them
  (`single-var-declarator` is `one-var: never`), `curly: all`, and
  `lint/style.ts`'s eight rules as the local plugin `style`, each with the
  fix it had. Where the presets go past deno lint, the tree was held to
  deno lint's line, not rewritten: `camelcase` leaves property and
  destructured names alone (the wire's `session_id`, `stop_reason`), as
  deno lint did; unused names starting with `_` pass;
  `preserve-caught-error`, new in ESLint's recommended set, is off (its one
  hit already wraps the error in an `AggregateError`); and
  eslint-plugin-react-hooks gives only `rules-of-hooks`. Its recommended
  set added `exhaustive-deps` (8 warnings) and the React Compiler's rules
  (28 errors: refs read during render, impure calls, `setState` in
  effects). The owner chose only `rules-of-hooks` on CHD-287;
  `exhaustive-deps` and the React Compiler rules stay off. The
  first cut of this part stopped there, and review found it dropped guards:
  `deno lint --rules --json` (Deno 2.9.7) shows the `react` and `jsx` tags
  carry eleven JSX rules plus `react-no-danger`,
  `react-no-danger-with-children` and `react-rules-of-hooks`, not hooks
  alone, and the two recommended presets differ. Every one of the 98 rules
  chord's `deno.json` enabled was then checked against ESLint's effective
  config and against `tsc`, with a probe file deno lint rejected:
  - The jsx and react tags map one for one onto eslint-plugin-react
    (`jsx-key`, `jsx-boolean-value`, `jsx-curly-brace-presence`,
    `jsx-no-duplicate-props`, `jsx-props-no-spread-multi`,
    `no-unescaped-entities`, `jsx-no-useless-fragment`, `no-children-prop`,
    `jsx-no-comment-textnodes`, `button-has-type`,
    `void-dom-elements-no-children`, `no-danger`,
    `no-danger-with-children`). Tried first: @eslint-react 5.24, which is
    newer and declares any ESLint, but lacks `jsx-boolean-value`,
    `jsx-curly-brace-presence`, `jsx-no-duplicate-props`,
    `jsx-props-no-spread-multi` and `no-unescaped-entities`.
    eslint-plugin-react 7.37.5 has all thirteen; its peer range stops at
    ESLint 9.7, but it loads and reports under ESLint 10 on Bun and on Node.
  - Recommended rules neither preset turns on: `require-await`,
    `no-unreachable` (`tsc` reports it only with `allowUnreachableCode:
    false`), `no-inner-declarations` (with `blockScopedFunctions:
    disallow`, as ESLint 9 allows block functions by default),
    `@typescript-eslint/adjacent-overload-signatures`, `no-window` and
    `no-window-prefix` as `no-restricted-globals: window`, and
    `no-empty-enum` and `no-sloppy-imports` (a relative import names its
    file and extension) as `no-restricted-syntax` selectors.
  - Ignore comments: `reportUnusedDisableDirectives: error` for
    `ban-unused-ignore`; ESLint itself reports an unknown rule in a
    directive (`ban-unknown-rule-code`); and
    @eslint-community/eslint-plugin-eslint-comments' `no-unlimited-disable`
    for `ban-untagged-ignore`.
  - Left to `tsc`, which typescript-eslint's preset turns them off for and
    which reported each probe: `constructor-super`, `getter-return`,
    `no-class-assign`, `no-const-assign`, `no-dupe-args`,
    `no-dupe-class-members`, `no-dupe-keys`, `no-func-assign`,
    `no-import-assign`, `no-import-assertions`, `no-new-symbol`,
    `no-obj-calls`, `no-redeclare`, `no-setter-return`,
    `no-this-before-super`, `no-unsafe-negation` and `no-with`;
    `no-await-in-sync-fn` is a parse error. `ban-types` and
    `no-empty-interface` are typescript-eslint's `no-empty-object-type`,
    `no-unsafe-function-type` and `no-wrapper-object-types`.
  - Not carried: `no-node-globals`, which the plan drops;
    `no-unversioned-import`, which checks `npm:` and `jsr:` specifiers that
    `package.json` replaces; and `no-deprecated-deno-api`, whose Deno 2
    targets are gone from `@types/deno`, so `tsc` rejects them, and whose
    Deno calls part 3 removes.
  The tree passed all of it unchanged. `lint/config_test.ts` lints one
  rejected snippet per restored rule, so dropping one fails `check`. The
  `deno-lint-ignore` comments became `eslint-disable-next-line` for the
  same rules, and one constant used only
  for its type became the type itself.
- **`lint/style.ts` on ESLint.** The rules moved almost line for line:
  `create` and the visitors are the same, `context.report` takes a
  `messageId` instead of a message, and the nodes are typescript-eslint's.
  `lint/style_test.ts` runs each rule through ESLint's `RuleTester` with
  typescript-eslint's parser, under `bun test`, 27 cases where there were
  13 tests, each fix checked by its output. A scratch file with a misplaced
  blank line and a brace-less `if` is reported by `eslint` and fixed by
  `eslint --fix`. deno lint and the Deno-API plugin left `check` with it.
- **Prettier in place of `deno fmt`.** `.prettierrc.json` holds the owner's
  options (`printWidth: 80`, `singleQuote`, `jsxSingleQuote`,
  `bracketSpacing`) and nothing else; `.prettierignore` holds `deno.json`'s
  fmt excludes and its `.claude/worktrees/`. The reformat touched 256 files
  and is a commit of its own, listed in `.git-blame-ignore-revs`; ESLint's
  rules, `lint/style.ts`'s included, passed on Prettier's output unchanged,
  so the two do not fight. `deno task mark` and `deno task registry` lay out
  what they generate through `scripts/format.ts`, on Prettier's API under
  Deno, and the mark test compares through the same call, so the generators
  agree with `prettier --check`; Prettier reads the environment and the CPU
  count, which the two tasks now allow, and no longer spawns `deno fmt`.
  `deno.json`'s `fmt` stays only until part 5 removes the file; Zed's
  settings format with Prettier.

## 2026-10-10 — Bun part 2a: `src/platform/`, processes on `node:child_process`

CHD-288, part 2a of the "Moving to Bun" entries above, with CHD-79 (the
shell stop test that failed under load) in it. `src/platform/` holds what is
not a plain `node:` call. Tried with Deno 2.9.7 and Bun 1.4.2 on macOS
arm64, in a scratch directory outside the repository, before the change.

- **`platform/process.ts` on `node:child_process`.** `spawn` with
  `detached: true` leads a group of its own under both runtimes;
  `process.kill(-pid, 'SIGTERM')` and `'SIGKILL'` reach the group, and
  signal 0 to the group says whether anything in it is left, reaped or
  not, where Deno's `Deno.kill` had no signal 0 and `shell.ts` asked with
  SIGCONT. `exit` gives `null` and the signal's name where Deno's status
  gave the code 143 for SIGTERM. The layer gives the code a shell's `$?`
  reads, 128 and the signal's number (`os.constants.signals`), so bash
  mode's "Exit code 143" and `ShellEnd`'s signal are as before. Both
  runtimes give `pid` as `undefined` at once when a spawn fails, but the
  error only a tick later, on `error`. `Deno.Command` threw it at once.
  `spawnAgent` therefore waits for `spawn` or `error` and is async; its one
  caller, `openAgent`, already was. `runShell` still says at once that the
  shell did not start (`failed`, which `monitor`'s refusal needs at once),
  but now as "`<shell>` did not start", while the reason comes in `ended`.
  `execPath()` is `process.execPath`, the runtime under `deno run` and the
  binary when compiled; the fake agent's command starts with it.
- **`platform/serve.ts` on `Deno.serve`** until part 3a moves it to
  `Bun.serve` with `idleTimeout: 0`. `server.ts` gives it the loopback,
  port 0 and the 500 answer, and closes through it.
- **split2 4.2.0 splits a monitor's stdout in place of `TextLineStream`**,
  where the owner's table named `node:readline`; `@std/streams` leaves both
  import lists. readline splits on `\n` and `\r\n` and hands on the last
  line without its end, but it also ends a line at a lone `\r`, which
  CHD-243 keeps in its line, and has no option to stop it. A progress bar's
  1,001 redraws then were 1,001 lines, and a monitor printing them was
  stopped as flooded where it had ended with its code. The owner chose
  split2 to keep CHD-243's rule: it splits on `/\r?\n/`, decodes UTF-8 with
  replacement through `string_decoder`, keeps empty lines, and hands on the
  last line without its end. `printf 'one\rtwo\nthree\r\nlast'` gave
  `["one\rtwo","three","last"]` under `deno run`, in a `deno compile` binary
  and under Bun. No dependencies, 17 KB; its types come from
  `@types/split2`. It reads the child's stdout through `stream.pipeline`, so
  a stdout that fails fails the lines too.
- **A stop waits for the group to be reaped (CHD-79).** The wait used to
  give up at a deadline counted from when it began, 1 s past when the
  SIGKILL was due. Under load the SIGKILL's timer fired late, the wait
  gave up first, and the `sleep` that ignored SIGTERM outlived the stop.
  The wait now runs until signal 0 finds nothing in the group, and gives
  up only 5 s after the SIGKILL was actually sent. That alone still failed
  the first full check: the stop took 2 s and the test found the `sleep`
  there after it. Once its shell is gone, the `sleep` is launchd's to reap,
  and under load launchd is slow. macOS answers signal 0 to a group left
  with only unreaped processes with EPERM, where an empty group is ESRCH
  (checked with a zombie that perl kept, under Deno and Bun alike), while
  signal 0 to the zombie's own pid succeeds, which is what the test asks.
  The probe therefore counts EPERM as something left, and the stop is over
  once the group is reaped.

## 2026-10-10 — Bun part 2b: the rest of `src/` off Deno's API and `@std`

CHD-289, part 2b of the two "Moving to Bun" entries above. Outside
`src/platform/`, nothing in `src/` calls `Deno.*` or imports `@std`; each
call went to the `node:` built-in the plan names, which Deno and Bun both
run, so the Deno suite still guards the tree.

- **Files, the environment and the terminal.** `node:fs/promises` for
  reads, writes, `mkdir`, `rename`, `rm` and `readdir` (with file types);
  `Deno.errors.NotFound` is `ENOENT`, asked in one place (`not_found.ts`).
  `process.env`, `process.cwd()`, `process.argv.slice(2)`, `process.exit`,
  `process.platform`, `process.stdin`/`stdout.isTTY` and
  `process.stdout.columns`. `Deno.noColor` is `NO_COLOR` set and not empty,
  as Deno reads it. `-p`'s piped stdin is read by `node:stream/consumers`'
  `text`, and its output written through `process.stdout`'s `write`, waited
  on, so the exit after it cuts nothing off a pipe. `Deno.unrefTimer` is the
  timer's own `unref()`: the two stdin filters take `setTimeout` from
  `node:timers`, since Deno's global one returns a number.
- **`@std`.** `node:path` (`SEPARATOR` is `sep`, `toFileUrl` is `node:url`'s
  `pathToFileURL`), `node:util`'s `isDeepStrictEqual`, `Buffer`'s base64,
  `node:timers/promises`' `setTimeout` with its signal, and npm's `yaml` for
  the team file's `stringify`. `@std/front-matter` and `@std/yaml` left both
  dependency lists; `@std/path`, `@std/assert`, `@std/async`,
  `@std/encoding`, `@std/testing` and `@std/cli` stay for the tests and
  scripts until part 3.
- **Front matter: vfile-matter.** Tried, under Deno and under Bun, on the
  team file's cases against `@std/front-matter`: a mapping, none, broken
  YAML, a sequence, an empty block, CRLF line ends, a `...` end and a BOM.
  - **vfile-matter** 5.0.1 (unified's, last release 2025), which parses with
    `yaml`, as the plan asks. It agreed with `@std/front-matter` on every
    case but two: a closing `...` and a leading BOM are not front matter to
    it in a string. `parseTeam` already refused the `...` end before it.
    The BOM chord read before, so `parseTeam` gives vfile the text as
    UTF-8 bytes, and vfile's own decoder drops the BOM as it reads them. It
    reads a file without front matter as an empty mapping, as it does an
    empty block, so `parseTeam` tells them apart by whether `strip` took
    anything off. Taken, with `vfile`, whose file it reads.
  - **@11ty/gray-matter** 3.0.0 (11ty's maintained fork of gray-matter),
    with `yaml` as its engine: with CRLF line ends it kept the `\r` in every
    value (`name: "a\r"`), its `test` refused a BOM its parse accepted, and
    it brings `js-yaml` beside `yaml`.
  - Passed over without a trial: `gray-matter` 4.0.3 and `front-matter`
    4.0.2 (both last released in 2021, on `js-yaml` 3), `yaml-front-matter`
    (2022, `js-yaml` 3), and remark-frontmatter, which needs a markdown
    parse to find it.
  Both packages and `yaml` run under `deno run` and `bun`; the binary
  `deno compile` builds reads a team file with them.
- **A seam for `/resume`'s read.** One window test held `/resume`'s read of
  the records by swapping `Deno.readDir`; a `node:` import cannot be
  swapped, so `App` takes `readRecords`, chord's own by default, as it takes
  its other reads, and the test holds that.

## 2026-10-10 — Bun part 3a: the runtime flips

CHD-290, part 3a of the two "Moving to Bun" entries above. chord runs from
source and is tested on Bun, and `bun check` is the check: `tsc`,
ESLint, `prettier --check`, `lint/`'s tests and `bun test` over `tests/`.
The Deno suite left it; `deno.json` keeps only the helper scripts' tasks,
which part 4 moves. Tried with Bun 1.4.2 and Deno 2.9.7 on macOS arm64.

- **Tests on `bun:test`.** Every `Deno.test` is `test`, the three
  `ignore: Deno.build.os === 'windows'` are `test.skipIf`, and the one test
  of 20 `t.step`s (the reducer's, over every scenario played once) is a
  `describe` whose `beforeAll` plays them. `@std/assert` and `FakeTime` run
  unchanged under `bun test`, until part 3b. The tests' own `Deno.*` calls
  went to `node:` as `src/` did in part 2b: `mkdtemp` under `tmpdir()` for
  `makeTempDir`, `rm`, `readFile`, `writeFile`, `readdir`, `process.env` and
  `process.kill`. Where a test started a process, `node:child_process` does,
  with two differences from `Deno.Command` kept in mind: `env` replaces the
  environment rather than adding to it, so a test that sets a few variables
  spreads `process.env` under them, and an exit other than 0 is no throw for
  `spawnSync`, while it is an error for `execFile`'s callback (which the `ps`
  probe reads as "not alive", and `pgrep`'s "nothing matched" ignores).
  `bun test` runs every file in one process; `--isolate` gives each its own
  global, so what one file leaves behind cannot reach the next, and
  `--timeout=60000` stands in for Deno's lack of one, since Bun's default
  of 5 s is shorter than a window test that starts agents.
- **The suite, counted.** The Deno suite at the commit before this part
  passed 1,488 tests and 20 steps. `bun run test` passes 1,508: the same
  tests, the reducer's one test of 20 steps now 20 tests (1,488 − 1 + 20),
  and the one new test below.
- **Four tests that held to V8 or to timing.** A broken `.mcp.json`'s problem
  quotes the runtime's own `JSON.parse` error, and JavaScriptCore words it
  differently (`JSON Parse error: Unexpected EOF`, where V8 says
  `Unexpected end of JSON input`); the test now asks the runtime for the
  words. The permission box test for an MCP call waited to see the prompt's
  row, which that box, tall with the call's arguments, pushes off a 24-row
  screen as soon as it comes; under Bun the row was gone before the first
  look, so the test waits for the box itself. And the test of
  `stop_monitor` took the `sleep`s' pids in the order their monitors' first
  lines came, as m1, m2 and m3; under load they came in another, and the
  `sleep` it waited on was one the stop rightly left running. It takes them
  by their monitor's id. The header test looked for `fake · ` as soon as
  `chord` showed, though the model it comes with follows the session; it
  waits for it.
- **The fake agent on Bun.** `tests/fixtures/fake.ts` starts it as
  `process.execPath` and the script's path: Bun resolves its imports from
  where the script is, so no config is passed, and no permission flags
  exist to pass. Its flags are `process.argv`, its stdio
  `Readable.toWeb`/`Writable.toWeb` of the process's own, and its SIGTERM
  shrug a `process.on` listener.
- **`Bun.serve` with `idleTimeout: 0`.** Tried first: with Bun's default, a
  request held without a byte for 11 s was answered, while ones held for
  13, 16 and 20 s were cut at about 12 s (its idle timer ticks late), and
  each cut printed `Bun.serve() timed out a request after 10 seconds` on
  stderr, which would write over the window. `src/platform/serve.ts` sets
  `idleTimeout: 0` and `development: false`; `server_test.ts` holds a
  `spawn_task` call's stream open for 15 s, and fails with `idleTimeout: 10`.
  `stop()` settles once every connection has closed, as `Deno.serve`'s
  `finished` did.
- **The version from `package.json`.** chord's `--version`, the window, its
  MCP server and the ACP client info, and `scripts/npm.ts`, read
  `package.json`'s version where they read `deno.json`'s.
- **The binary until part 4.** `deno compile` still builds it, now with
  `--no-check`: Deno's checker knows no `Bun` global and stopped at
  `src/platform/serve.ts` with TS2868, failing CI's compile step, and the
  types are tsc's job in `bun check` anyway. Deno has no `Bun.serve`: the
  window stops at start with `Bun is not defined`, while `-p`, which starts
  no server, still runs. Part 4 builds it with `bun build --compile`.

## 2026-10-10 — Bun part 3b: `@std` leaves the tests

CHD-291, part 3b of the "Moving to Bun" entries above. Tried with Bun 1.4.2
on macOS arm64, in a scratch directory outside the repository, before the
change.

- **`@std/assert` becomes `expect`.** `assertEquals` is `toStrictEqual`,
  which, as `assertEquals` did, tells `{ a: undefined }` from `{}` and a
  class from a plain object; `assertNotEquals` is its `.not`.
  `assertStringIncludes` is `toContain`, `assertMatch` `toMatch`,
  `assertThrows` `toThrow` and `assertRejects` `rejects.toThrow` on the
  promise itself, since `rejects` takes no function. A message is
  `expect`'s second argument, which Bun prints in place of its own.
  `toThrow` takes one argument, a class or a substring, where the 32
  `assertThrows` and `assertRejects` given a class checked both, so each
  checks twice: `toThrow(Error)` or `toThrow(ResumeError)`, then
  `toThrow(message)`, on the one promise held in a `const`, or on the one
  function. The class is an `instanceof`: a thrown string, a plain
  `{ message }` and an `Error` renamed `ResumeError` all fail it, where a
  message alone passes the first two and an `objectContaining` on `name`
  the third. `assertAlmostEquals(a, b, 1e-4)` is `Math.abs(a - b)` at
  most `1e-4`; `toBeCloseTo` takes decimal digits and a tolerance half as
  wide.
- **Where a check narrows a type, `node:assert`.** `assert` and
  `assertExists` are typed `asserts value`, and the tests lean on that:
  `assert(call?.type === 'update')` and then `call.update`. Bun's `expect`
  declares no assertion signature, so the first cut, every `assert` as
  `expect(…).toBeTruthy()`, left 264 type errors. `node:assert/strict`'s
  `assert` is typed the same way and runs under Bun. Each of the 563
  `assert`s was tried as `expect` and kept as `assert` only where `tsc`
  failed without it: 84, in 23 files. This is a choice the owner's answer
  ("tests use `bun:test`'s `expect`") did not name, so it is on CHD-291
  for the owner; the other way is `expect` with `!` and casts at those 84.
- **`FakeTime` becomes `jest.useFakeTimers`.** `FakeTime`'s `tickAsync(ms)`
  waits one real macrotask, so every settled promise's callbacks run, then
  moves the clock, firing the timers due. Bun has no async advance, but its
  fake timers leave `setImmediate` real: `monitors_test.ts`'s `fakeTime()`
  waits on it, then calls `jest.advanceTimersByTime`, which is the same two
  steps; `runMicrotasks` is the wait alone. `Date.now` starts at 0 and moves
  with the clock, so the timeout test still sees its stop at 1000.
  `using` puts the real timers back.
- **The rest of `@std`.** `delay` is `node:timers/promises`' `setTimeout`,
  `decodeBase64` `Buffer.from(…, 'base64')` copied into a `Uint8Array`, and
  the tests' and scripts' `@std/path` `node:path`, its `fromFileUrl` and
  `toFileUrl` `node:url`'s `fileURLToPath` and `pathToFileURL`.
  `scripts/compile.ts` reads `--all` and `--install` with `node:util`'s
  `parseArgs`, which refuses a flag it does not know where `@std/cli`'s
  ignored it.
- **The lock files.** The `@std` aliases leave `package.json` and
  `deno.json`. `deno remove` re-resolved `@cliffy/command` and
  `@cliffy/table` to 1.3.1 in `deno.lock`, the version `bun.lock` already
  had. `@std/` is still named in this file's history, in the evidence under
  `docs/design/` and `docs/qa/`, and in `deno.lock`, where Cliffy's own
  `jsr:` dependencies (`@std/fmt`, `@std/text`, `@std/semver` and the like)
  stay while Deno runs the helper scripts. `bun.lock` holds the same
  packages as `@jsr/std__*`. The owner scoped the task's "no `@std/`" to our
  code and our manifests: Cliffy stays, so its transitive entries stay in
  both locks until CHD-293 removes `deno.lock`, and the history and evidence
  are left as the record.
- **Counts.** `bun check` runs 1,508 tests across 109 files, as part 3a
  did.

## 2026-10-10 — Bun part 4: the binary on `bun build --compile`

Superseded in its targets by "Moving to OpenTUI" (2026-10-10), the owner's
answer 4: Windows is not a target for now, and `scripts/targets.ts` lists
macOS and Linux alone (part 6).

CHD-292, part 4 of the "Moving to Bun" entries above. The binary is built by
`bun build --compile --external react-devtools-core --splitting`, the
owner's choice 6, for every target in `scripts/targets.ts`, whose `deno`
field became `bun` (`bun-darwin-arm64` and the rest). `compile`, `npm`,
`registry` and `mark` run on Bun as `bun run <name>`. Nothing runs on Deno
any more. Tried with Bun 1.4.2 on macOS arm64.

- **The flags, and what they work around.** Ink's reconciler imports
  `./devtools.js` only when `DEV=true`, and `devtools.js` imports
  `react-devtools-core`, which chord does not install. Checked again on
  today's tree. Without the flags the build fails with `Could not resolve:
  "react-devtools-core"`. With `--external` alone, the binary dies at start
  with `Cannot find package 'react-devtools-core'`. With `--splitting` added,
  the import stays lazy and is never loaded. Answer 6's condition held on
  every point, so `react-devtools-core` was not added.
- **Start, keys, the alternate screen, before and after.** The before binary
  was built by `deno compile` at the commit before part 3a (Deno has no
  `Bun.serve`, so later commits' binaries stop at start). Both were driven
  in tmux at 120×40 and 80×24 against the fake agent: the splash, a turn,
  a permission prompt, `/team`, and quit. The screens are the same, colours
  included, apart from the spinner's frame, its seconds and the session ids.
  Each quit left the shell with `icanon isig echo` and exit 0. The raw bytes
  each binary writes hold the same setup and teardown: the kitty keyboard
  protocol's query (`CSI ? u`), the alternate screen, bracketed paste and
  the mouse, each turned off again on quit. The kitty protocol's shift+Enter
  (`CSI 13;2u`), sent as bytes through tmux, is a newline in both.
  Whether a terminal that speaks the protocol gets it pushed is for the
  owner to confirm, because tmux does not answer the query.
  Evidence is in `docs/design/evidence/CHD-292/`.
- **The clipboard.** A binary embeds only the `@mariozechner/clipboard`
  addons that are installed, so `compile` first runs `bun install --os='*'
  --cpu='*'`. That installs every platform's addon and leaves `bun.lock` as
  it was. ctrl+v of a PNG on the macOS clipboard reached the fake agent
  (`image/png, 918798 bytes`) from the arm64 binary and from the x64 one
  under Rosetta. In Debian containers (OrbStack, arm64 and x64) the Linux
  binaries drew the window, ran a turn, quit with exit 0, and on ctrl+v
  showed clipboard-rs's own `$DISPLAY variable not set`. That is the
  addon loading and finding no display. The Windows binary is checked by
  `file` only (PE32+ x86-64); the owner checks Windows by hand, as before.
- **Sizes.** 73 MB for darwin-arm64, 80 MB for darwin-x64, 89 MB for each
  Linux target and 94 MB for Windows. The `deno compile` binary was 248 MB.
- **`install` is `compile --install`.** A `package.json` script named
  `install` is the package's own install step: `bun install` runs it (tried
  in a scratch package), and `compile`'s own `bun install` would then
  recurse. The installer is therefore a flag on `compile`, as it already was
  in the script.
- **The Bun version.** `compile` refuses a Bun outside `engines.bun`
  (`>=1.4.2`) through `Bun.semver.satisfies`, before it builds anything.
- **The npm shim** is unchanged. Laid out by `bun run npm` from the new
  `dist/<bun target>/`, `bin/chord.js` found the darwin-arm64 package beside
  it and ran it under `node` and under `bun`.
- **The x64 targets** are Bun's default x64 build, which needs a CPU with
  AVX2 (Haswell, 2013, or later). Bun's `-baseline` targets run on older
  CPUs too. The default was kept, as the plan named the targets one for
  one.
- `deno.json` loses its tasks, and CI builds with `bun run compile` with no
  Deno installed. `deno.json` and `deno.lock` themselves go in part 5.

## 2026-10-10 — Bun part 5: Deno leaves

CHD-293, the last part of the "Moving to Bun" entries above. This entry
supersedes "Deno, compiled to one binary" and "emulon's code style": chord
is written in TypeScript on Bun and shipped as `bun build --compile` output
(Bun part 4), and its style is what `tsconfig.json`, `eslint.config.ts`,
`lint/style.ts` and `.prettierrc.json` hold (Bun part 1). The packaging
those entries describe, a shim on npm that runs the platform package's
binary, is unchanged.

- **What went.** `deno.json`, `deno.lock`, `@types/deno` and `"deno"` in
  `tsconfig.json`'s `types`. `tsc` passes without them, because nothing in
  the tree uses a `Deno` type any more.
- **`// @ts-types` comments.** Ten imports carried Deno's directive that
  points an import at other types. `tsc` ignores it, so `bun check` has
  typed those imports from each package's own types since part 1. The
  directives went, and so did `src/ui/transcript/emphasize.d.ts`, which only
  such a directive used. `convert-layout.d.ts` stays: `tsconfig.json`'s
  `paths` reaches it.
- **Zed** no longer starts Deno's language server; it uses its default
  TypeScript servers with Prettier as the formatter.
- **What still says Deno, on purpose.** The design and QA records under
  `docs/design/` and `docs/qa/` keep the commands that were run when they
  were written. They record what happened, not how to run chord today. The
  fake agent's scenarios and the tests that draw them keep their `deno task
  test` lines, because they are what some agent prints, not commands for
  chord's contributors. A few comments say what Deno did when the code was
  written (`src/main.tsx`'s `stdin.resume()`, `src/server/server.ts`'s body
  read, `src/teams.ts`'s BOM, the origin of the lint rules).
- **Checked.** `bun check` passes in a clean clone with no `deno` on
  `PATH`.

## 2026-10-10 — Moving to OpenTUI: the plan, the parts, and the owner's open choices

CHD-302. chord's interface moves from Ink 8 to OpenTUI (`@opentui/core` and
`@opentui/react`, pinned to exactly 0.5.17). The owner has decided four
things already: OpenTUI, its React bindings rather than Solid, replies kept
on chord's own markdown (markdansi and `src/ui/transcript/markdown.ts`, not
OpenTUI's `<markdown>`), and the alternate screen as today. An upgrade of
OpenTUI is a task of its own, because its patch releases change behaviour
and it promises no stable API before 1.0. This entry is the plan. Once the
last part lands, it supersedes "Ink and its component ecosystem are the
widgets" wherever CLAUDE.md, README and `docs/FEATURES.md` say it. The
research behind it is on CHD-302; the earlier spike (branch
`worktree-opentui-spike`, on Deno) is the map of what moves.

### Why the move is one branch

Ink 8 needs `react-reconciler` 0.34 and `@opentui/react` 0.5.17 is built on
0.33, so the two renderers cannot draw the same React tree, and there is no
half-way window that runs on both. Both packages can be installed side by
side (each keeps its own reconciler), but only one of them can draw. So:

- What can land on Ink first does, on `main`, as invisible parts: seams
  that make the flip change one module each instead of 23 files and 23 test
  files.
- The flip and the parts that restore what it loses run on one local
  branch, `opentui`, cut from `main` once the seams are in. Every commit on
  the branch keeps `bun check` green. A test whose behaviour a part
  knowingly drops is marked `test.todo` with the part that restores it in
  its name, so the losses are counted, not forgotten. The branch is merged
  into `main` by fast-forward only when no such `todo` is left and the whole
  acceptance below holds. Nothing else is committed to `main` while the
  branch is open; the parked work (CHD-163's stash, CHD-131, CHD-132,
  CHD-152 and the rest) waits. The branch is never pushed; the owner pushes
  `main`.

### The seams on Ink (on `main`)

Measured on 160c274: 23 files in `src/` import Ink, almost all only `Box`
and `Text`; `useInput` is called in 7 places, which already pass through
chord's own `usePress` in `src/ui/app/terminal.ts` for the base-layout key
and the empty paste. Of the 1,439 tests, about 311 in 23 files render the
window through ink-testing-library, most of them through
`tests/ui/app/render.tsx`, which drives the window with raw bytes (`ESC`,
`UP`, `CTRL_R`…) and reads the frame as text. OpenTUI's test kit
(`@opentui/react/test-utils`' `testRender`) reads the frame as text too
(`captureCharFrame()`), and its mock input writes raw bytes to the
renderer's stdin (`renderer.stdin.emit('data', …)`, which `pressKeys` itself
uses), so a byte-driven harness carries over.

Part 1 puts both seams in, on Ink, with no behaviour change:

- One module, `src/ui/tui.tsx`, is the only file in `src/` that imports
  `ink`, `ink-select-input`, `ink-spinner` or `react-ink-textarea`; it
  re-exports what the components use. Key handling everywhere goes through
  `usePress` with chord's own press type rather than Ink's `Key`.
- One harness module under `tests/ui/` is the only test file that imports
  ink-testing-library. Every window test renders, types, pastes, resizes,
  reads the frame and unmounts through its functions, whose shapes are the
  ones `testRender` can also back (tried against 0.5.17 in a scratch
  directory before the shapes are fixed, and the trial written into this
  file). The test count does not change.

**The trial, CHD-304.** Before the harness's shapes were fixed they were
tried against `@opentui/react` 0.5.17 and `@opentui/core` 0.5.17 (React
19.3, Bun 1.4.2) in a scratch project outside the repository, on a probe
component with `useKeyboard`, `usePaste` and `useTerminalDimensions`. What
`tests/ui/harness.tsx`'s `draw` and its `Drawn` became, and what backs each
on OpenTUI:

- `draw(node, { columns, rows })` is async, because `testRender(node, {
  width, height })` is. Every caller awaits it, so the flip does not touch
  them.
- `write(bytes)`: `renderer.stdin.emit('data', Buffer.from(bytes))`. `a`,
  `ESC [ A`, ctrl+r (`\x12`) and a lone `ESC` reached `useKeyboard` as
  `a`, `up`, ctrl `r` and `escape`, each with its raw `sequence`, which is
  what `usePress` needs for the base key and a modifier pressed alone. It
  returns a promise, though Ink's needs none.
- `paste(text)`: the bracketed markers around the text through the same
  `emit`; `usePaste` heard `one\ntwo` whole, as its bytes.
- `frame()`: `captureCharFrame()`. Two differences the flip has to take: it
  is the plain characters, no escapes (the tests that read colours, such as
  `message_test.tsx`'s `painted`, need the harness to write the escapes
  back from `captureSpans()`, which gives each run's text with its
  foreground, background and attributes), and every row of the terminal is
  there, padded with spaces to its width, where Ink's last frame trims each
  row's trailing spaces and ends at the height of what it drew.
- `written()`: `renderer.setFrameCallback`, which the trial heard on every
  frame drawn (11 for the probe's steps), keeping `captureCharFrame()` each
  time. What Ink also counts there, the bytes written between frames (the
  notifications), comes from OpenTUI's output instead, and is part 5's.
- `resize({ columns, rows })`: `resize(width, height)`; the next frame and
  `useTerminalDimensions` both had the new size.
- `unmount()`: `renderer.destroy()`, which `testRender`'s `onDestroy`
  turns into the React root's unmount inside `act`.
- **act.** `testRender` turns React's act environment on, so every update
  outside `act` warns, and the window updates on its own as the agent
  replies; a lone `ESC` also resolves on a timer, outside any `act` round
  `emit`. With `globalThis.IS_REACT_ACT_ENVIRONMENT = false` set after
  `testRender`, a timer's updates and the raw bytes drew on their own with
  no `renderOnce()` and no warning, and `captureCharFrame()` read them, so
  the harness backs `frame()` without `act` and the tests' `until` loops
  still do the waiting.

Not covered by the harness, as they test what goes with Ink: the editor's
suspension test in `tests/ui/app/App_test.tsx`, which renders through
Ink's own `render` to read its alternate-screen bytes (part 5 restores
`$EDITOR`), and `tests/replies_test.tsx` and `tests/ui/app/mouse_test.tsx`,
which go with `src/replies.ts` and `src/mouse.ts`.

### The flip and what it loses (on the branch)

The flip swaps both seams' insides for OpenTUI and deletes what existed only
around Ink. From the spike, `src/ui/tui.tsx` becomes a bridge that draws
Ink's `Box` and `Text` props (`wrap='truncate…'` included) with OpenTUI's
`<box>`, `<text>` and `<span>`, and serves `usePress`, the paste, the window
size, exit and stdout on `useKeyboard`, `usePaste`, `useTerminalDimensions`
and the renderer. The bridge is a step, not the end: the last parts take
the components onto OpenTUI's own elements and delete it, because a
lookalike of Ink kept on top of OpenTUI is code chord maintains around a
library.

The flip must also handle what the research found:

- **The renderer is destroyed on every exit path**: quit by ctrl+c twice and
  ctrl+d, `/exit`, the start picker's Esc, SIGTERM and SIGHUP, an uncaught
  exception and an unhandled rejection. OpenTUI's console overlay is off.
  What an uncaught error does is the owner's choice 1 below. A signal or a
  crash also waits, as a quit does, for the window's agents and their
  monitors to be closed and reaped within the agents' own stop bounds,
  before chord dies by the signal or exits 1: destroying the renderer only
  starts that close, and a hung agent outlived chord (CHD-331). A second
  signal or crash while it waits waits for the same close, and a second
  signal is held, chord still dying by the first.
- **Text with no colour** is drawn in the terminal's own foreground
  (`RGBA.defaultForeground()`), never a hard white.
- **Every sibling of a scrolling area** gets `flexShrink={0}`, or it
  overlaps instead of being clipped.
- **ANSI strings become spans.** markdansi, chalk, emphasize and the diff
  produce ANSI; OpenTUI draws cells. The engineer takes a maintained parser
  first (`@ansi-tools/parser` is already a dependency) and strips an
  agent's own escapes before drawing, as the spike learned. CHD-279 (dim lost
  after a bold span) goes away here, since OpenTUI writes the full SGR for
  each run of cells.
- **The prompt moves onto OpenTUI's `<textarea>`**, its edit buffer, its
  `keyBindings`, `setText` and `setCursor`, in place of react-ink-textarea.
  Pickers move off ink-select-input onto OpenTUI's `<select>` or chord's own
  list on `<box>`, whichever keeps the pickers' look; the spinner off
  ink-spinner onto a maintained OpenTUI one, or a timer, whichever is
  smaller.
- **Gone with Ink**: `src/mouse.ts`, `src/replies.ts`, `src/keyboard.ts`,
  `src/ui/app/layout.ts`, `src/ui/app/mouse.ts`, the internal emitter in
  `src/ui/app/terminal.ts`, `WindowKey`, and the `is-term-dark` and
  `stdin.resume()` dance in `src/main.tsx`, each as soon as OpenTUI's own
  mouse, key parser, `baseCode`, OSC 11 theme detection, scroll and
  measurement take its place. The tests that go with them go too (about 50).

The spike lost these, and the flip may lose them too, each restored by a
named later part on the branch:

| Lost in the flip | Restored in |
| --- | --- |
| ctrl+r's search highlight in the prompt | part 3, the prompt |
| vim normal mode's block cursor | part 3 |
| the textarea keys a keybindings file rebinds | part 3 |
| the ↑ / ↓ gutter marks beside the prompt | part 3 |
| the undo key as today (OpenTUI's default ctrl+- needs kitty) | part 3 |
| ctrl+w straight after an image paste takes the placeholder whole | part 3 |
| the mouse wheel and the scroll keys over the transcript, the view kept on its entry across ctrl+o and a resize | part 4, the transcript |
| the "news below" indicator while scrolled back | part 4 |
| the diff's ctrl+o fold | part 4 |
| `$EDITOR` on ctrl+g (`renderer.suspend()` / `resume()`) | part 5, the terminal's services |
| the notification bytes (BEL, OSC 9, OSC 777) | part 5 |
| the theme from the terminal's background | part 5 |
| ctrl+v's image and the empty bracketed paste (cmd+V of an image) | part 5 |
| bound keys by their base-layout key, and the Russian table | part 5 |
| the modifier the status line names after a drag | part 5 |

The flip may restore any row of this table itself where it is cheap; it may
not lose anything not in it.

The ctrl+w row was added by the owner's answer on CHD-315, after the flip
found the loss. Part 3 restores it through OpenTUI's own settings if they
can; if they cannot, the owner consents to chord handling ctrl+w itself,
limited to an image placeholder with its trailing space right before the
cursor, with OpenTUI's default word delete kept everywhere else.

### The parts, in order

Each part is one task, and each waits for the one before it.

1. **The seams, on Ink** (invisible; `main`). As above. Proves: the
   components and the window tests each reach Ink through one module;
   `bun check` green with the same test count.
2. **The flip** (visible; the branch). OpenTUI 0.5.17 pinned exactly; Ink,
   ink-select-input, ink-spinner, react-ink-textarea, ink-testing-library
   and is-term-dark leave `package.json`; the bridge; the window tests on
   `testRender`; the renderer destroyed on every exit path. Proves, against
   captures of `main` from source at 120×40 and 80×24: the splash, the empty
   window, a turn on the fake agent with markdown, a code block, a tool call
   and a diff, a permission prompt, `?`'s keys, `/model`'s picker, `/team`,
   and quit; everything differs only by the table's rows; `stty -a` is the
   same after quitting by each exit path, an uncaught error included, and no
   alternate screen or mouse tracking is left on.
3. **The prompt restored** (visible; the branch). The table's prompt rows.
   Proves: captures of ctrl+r with a match, vim's normal mode, a rebound
   key from a keybindings file, the gutter marks, and undo, against `main`.
4. **The transcript restored** (visible; the branch). The scroll, the
   indicator and the diff's fold, on OpenTUI's scrollbox with sticky bottom
   where it keeps chord's anchoring, chord's own offset where it cannot
   (the finding goes into this file). Proves: captures scrolled back, after
   ctrl+o and after a resize, and a long session's memory against `main`'s
   (the scrollbox does not virtualize; Ink did not either, so equal is
   enough, and folding or virtualizing is a later task).
5. **The terminal's services restored** (visible; the branch). The table's
   part 5 rows on OpenTUI's own APIs: `suspend`/`resume`, its notifications
   if they take chord's channel setting or chord's bytes written through
   the renderer if not, its OSC 11 detection, its paste event, its
   `baseCode`. Proves: each row by capture or by the bytes, and no
   `test.todo` left on the branch.
6. **The binary and the docs** (visible; the branch). `scripts/compile.ts`
   builds every target with OpenTUI's native library embedded (`bun install
   --os='*' --cpu='*'` already runs); whether `--external
   react-devtools-core --splitting` can go is checked rather than assumed,
   because `@opentui/react` also names `react-devtools-core` as a peer.
   CLAUDE.md, README, `docs/FEATURES.md` and this file's earlier Ink
   entries are brought up to date (each superseded entry pointed here).
   Proves: every target builds, the host binary starts, draws, takes keys
   and quits with `stty` unchanged, and captures of the binary match those
   from source.
7. **The whole acceptance** (QA; the branch). CHD-299's and CHD-300's
   matrices, every row, from source and from the binary, at 120×40 and
   80×24 on the fake agent; the exit paths; `bun check` green. Then the
   lead merges the branch into `main`.
8. **The bridge goes** (invisible; `main`). The components onto `<box>`,
   `<text>`, `<span>` and OpenTUI's hooks, folder by folder in two tasks,
   and `src/ui/tui.tsx` deleted. Proves: captures unchanged, check green.

Beside them: the owner checks shift+Enter in a kitty-protocol terminal on
the binary from part 6, and CHD-241 (keys typed while the splash is up)
carries its own question to the owner, since `renderer.keyInput` can now
hold them through a supported API.

### Open choices for the owner, each with the lead's recommendation

1. **What an uncaught error does.** Recommended: the renderer is destroyed,
   the error and its stack go to stderr, and chord exits with code 1, which
   is what a crash looks like today. Alternative: OpenTUI's console overlay,
   which keeps the window up and later exits 0; that hides crashes from a
   script and from the person.
2. **The move on a local branch.** Recommended: parts 2–7 on a local branch
   `opentui`, merged into `main` by fast-forward after part 7, with nothing
   else committed to `main` meanwhile. Alternative: every part on `main`,
   which leaves `main` without the table's rows between the flip and part 5.
3. **Selection with the mouse.** Recommended: as today for the move — mouse
   tracking on for the wheel and clicks, the terminal's own selection with
   the modifier the status line names. OpenTUI's own selection with OSC 52
   copy, and following the terminal's theme live (its theme-mode events),
   would each be a new behaviour; each becomes a task of its own for later.
4. **Windows.** OpenTUI has open keyboard bugs on Windows (#1042, #1405).
   Recommended: keep the Windows target and check it by hand as CHD-296
   already asks; a Windows bug found there is a task, not a reason to hold
   the move.

Two things the owner should know but need not decide: each binary grows by
about 12–19 MB, and IME composition is not supported upstream (#942, closed
as not planned).

### The owner's answers (CHD-303)

1. An uncaught exception or unhandled rejection destroys the renderer,
   writes the error and its stack to stderr, and exits with code 1. The
   console overlay stays off.
2. Parts 2–7 run on the local branch `opentui`, never pushed, cut from
   `main` once part 1 is in, and `main` is fast-forwarded to it after part
   7's QA. Nothing else is committed to `main` while the branch is open.
3. Selection with the mouse stays as today: tracking on for the wheel and
   clicks, the terminal's own selection with the modifier the status line
   names. OpenTUI's own selection with OSC 52 copy, and following the
   terminal's theme live, are later tasks.
4. Windows is not a target for now. The OpenTUI parts neither build nor
   check `windows-x64`; part 6 takes it out of `scripts/targets.ts`, the npm
   layout (`npm/chord-win32-x64`, the shim's optional dependencies and its
   `chord.exe` branch) and the docs that name Windows as a platform. Bringing
   Windows back, with OpenTUI's Windows keyboard bugs (#1042, #1405) and the
   hand check CHD-296 asks for, is a backlog task of its own.

## 2026-10-10 — OpenTUI part 2: the flip

CHD-305, on the local branch `opentui`, the second part of "Moving to
OpenTUI" above. `@opentui/core` and `@opentui/react` are pinned to exactly
0.5.17; ink, ink-select-input, ink-spinner, react-ink-textarea,
ink-testing-library and is-term-dark have left `package.json`.
`src/ui/tui.tsx` is the bridge the plan describes, and `tests/ui/harness.tsx`
draws on `testRender`. `src/mouse.ts`, `src/replies.ts`, `src/keyboard.ts`,
`src/ui/app/layout.ts`, `src/ui/app/mouse.ts`, `WindowKey`, terminal.ts's
emitter and main.tsx's is-term-dark dance are gone, with their tests.

### What was tried

- **The spike's runtime patches.** Under Bun neither is needed: OpenTUI
  loads its native library through `bun:ffi`, and its tree-sitter worker is
  never started, as replies stay on chord's own markdown. `src/opentui/` did
  not come over.
- **ANSI strings to runs.** Two parsers that also read SGR were tried before
  writing that part: `ansi-sequence-parser` 1.1.3 stops parsing at the first
  OSC (a hyperlink leaves the rest of the string raw), and `anser` 2.3.5
  turns the sixteen colours into fixed RGB, where chord's palette uses the
  terminal's own. So `@ansi-tools/parser`, already a dependency, finds the
  escapes, and the bridge reads SGR's parameters into each run's colour and
  attributes; every escape that is not SGR is left out. A dim `Text` is dim
  from its props, not from its string's escapes, so a bold run that closes
  with `22` no longer turns the rest bright (CHD-279; `tests/ui/tui_test.tsx`).
  A reply's and a message's own escapes are stripped before chord's
  markdown (strip-ansi), as the spike learned.
- **A dim border is grey 244.** OpenTUI's border takes a colour and no
  attributes, so a border Ink drew dim needs a colour. Palette colour 8 is
  the terminal's own and is the background itself in Solarized Dark, so
  the prompt box vanished there; 244 is a fixed #808080 that reads on dark
  and on light, and is what Claude Code's prompt border uses (CHD-305, the
  designer's look).
- **Wrapping and cutting.** OpenTUI's word wrap breaks inside a path at
  `/`, and its truncation puts `...` in the middle. Ink wrapped with
  wrap-ansi (`trim: false, hard: true`) and cut with cli-truncate, an
  ellipsis at the end, the start or the middle; the bridge does the same at
  the width its box is laid out to, with both, already dependencies. Each
  works on the plain text, and its result goes back between each run's own
  characters: wrap-ansi only puts line breaks in, and what cli-truncate keeps
  is a head and a tail either side of its ellipsis. The first flip cut by
  hand; the review asked for cli-truncate, and on 1,764 cuts (CJK, emoji
  sequences, combining marks, a text with an ellipsis of its own, two styled
  runs, 0–20 columns, all three positions) it kept the same text as the
  hand-written cut. The one difference: where a wide character at the cut
  leaves nothing beside the ellipsis, it takes the text's first style rather
  than none. A text's own ellipses made cli-truncate's ambiguous (a red `…`
  then a blue `……`, cut at the end to two columns, came out blue), so the
  bridge passes cli-truncate's `truncationCharacter` a one-column
  private-use character the text does not have, and puts the ellipsis
  where that mark is.
- **The pickers.** OpenTUI's `<select>` draws a description line and a
  background highlight, not the pickers' look, so the numbered list is
  chord's own on `<box>`, keyed as ink-select-input was (↑ ↓ and k j round,
  Enter, a choice's number); `choiceKey` in `pickers/picker.ts` is pure.
- **The spinner.** No maintained OpenTUI spinner was smaller than a timer:
  the bridge turns ink-spinner's `star` frames every 70 ms.
- **The prompt** is OpenTUI's `<textarea>`, with react-ink-textarea's keys:
  Enter sends, shift+, ctrl+ and alt+Enter and ctrl+J break the line,
  ctrl+Z and ctrl+Y undo and redo, and its edges hand ↑ and ↓ to history.
  OpenTUI's textarea has keys of its own the box never had (ctrl+D deletes,
  home and end move, shift+arrows select), each of them one of chord's, so
  the box claims every press but its own keys and typed text
  (`textareaTakes`), and a binding moved off one of its keys turns that one
  off as before.

### What OpenTUI does that Ink did not, and how the bridge meets it

Each is how 0.5.17 behaves; an upgrade checks them again.

- `@opentui/react`'s `root.render` makes a new tree each call, so the start
  picker's renderer handed to the window drew a second window that was never
  unmounted. `render` mounts once and swaps the node through a store.
- Its root renders concurrently; Ink drew every change at once, and chord
  reads the window's state right after a key and after a read that settles
  within microtasks. Each key, paste and textarea event runs inside React's
  `flushSync` (exported by `@opentui/react`), so what it set off is drawn
  before the next is read.
- The focused widget hears a key after every `useKeyboard` listener, so a
  key whose work gives the box the keys (Enter answering a permission) would
  also reach the box. The textarea takes the keys a microtask after the key
  that gave them; it lets go at once.
- React takes a renderable out of the tree without destroying it, and a
  focused one goes on hearing keys: a textarea left focused sent its draft.
  The bridge's textarea blurs as it unmounts.
- Every renderable is at least one cell high, so a box laid out to no rows
  drew a row with everything in it on top of each other (the transcript
  with `?`'s panel open at 80×24). A clipping box (`overflow='hidden'`)
  reads Yoga's size when its own changes and draws nothing while it is none.
- A box given a width or height in cells stops shrinking (OpenTUI's setter
  turns `flexShrink` 1 into 0); Ink's went on shrinking. The bridge sets it
  back after each new size.
- A text's own resize never calls `onSizeChange`, so a text is measured on
  a box around it.
- The textarea writes white unless told, reports its cursor only at the
  next call into its native buffer, and reports the window's own
  `setCursor`; the bridge gives it the terminal's foreground, the prompt
  reads the cursor once a key has been acted on, and only a focused box
  reports a move.
- The test renderer quits on ctrl+C unless told not to (`exitOnCtrlC:
  false`), and a frame read from a destroyed renderer reads freed memory.

### The terminal given back

`openTerminal` takes the terminal with the console overlay off and OpenTUI's
own signal handlers off (`exitSignals: []`): on SIGINT, SIGTERM, SIGQUIT,
SIGABRT, SIGHUP, SIGPIPE and SIGBUS chord destroys the renderer and dies by
the signal, as it would have; on an uncaught exception or unhandled
rejection (listened for ahead of OpenTUI's own) it destroys the renderer,
writes the error and its stack to stderr and exits 1, as CHD-303 answered.
ctrl+C twice, ctrl+D, `/exit` and the start picker's Esc go through
`render`'s exit, which destroys it too. Each was checked in tmux: `stty -a`
the same before and after, and no alternate screen or mouse mode left on.

### Restored already

Two of the table's rows were cheap: the theme from the terminal's background
(OpenTUI's own OSC 11 query, `waitForThemeMode(100)`), and bound keys by
their base-layout key (OpenTUI's `baseCode`, with US PC-101's shifted
characters, as `keyboard.ts` had them), so the Russian table works too.

### Lost until a later part

Each test that covers a row of the table is `test.todo`, named with the
part that restores it. Undo is part 3's in full: OpenTUI's textarea undoes
key by key, where react-ink-textarea grouped edits of one kind within a
moment. OpenTUI's ctrl+W stops at punctuation, so straight after a pasted
image's `[Image #1] ` it takes the space alone, where react-ink-textarea's
took the word back to the space before it and so the placeholder whole.
That loss was outside the table when the flip found it; the owner added it
as a part 3 row (CHD-315), and its test is `test.todo` with the rest.

## 2026-10-11 — OpenTUI part 3: the prompt restored

CHD-306, on the local branch `opentui`, the third part of "Moving to
OpenTUI" above, on OpenTUI 0.5.17's `<textarea>`. The table's six prompt
rows are restored, vim's cursor and ctrl+r's highlight by other means than
`main`'s; undo by groups is let go, as the owner chose.

### Restored

- **The textarea keys a keybindings file rebinds.** The flip already kept
  them: a textarea key bound elsewhere is claimed by the window
  (`textareaTakes`), and OpenTUI's focused widget hears no key a listener
  prevented. ctrl+k bound to `chat:submit` sends the draft, as on `main`,
  where it cut to the line's end.
- **The ↑ and ↓ gutter marks.** OpenTUI's `LineNumberRenderable` was
  tried first: its signs are per logical line and drawn only on a line's
  first row, so a wrapped line's later row, which `↑` marks when the box is
  scrolled into it, cannot carry one. So the gutter is chord's own column,
  as on `main`, each row's mark from `gutterMark` over the rows the
  textarea shows (`shownRows`, from its `lineInfo` and `scrollY`). The
  textarea scrolls as it is laid out with no event (its resize calls no
  `onSizeChange`, its draw no `renderAfter`), so the rows are read in the
  `renderAfter` of the box round it, its layout done; the marks follow a
  frame after the text.
- **The undo key.** ctrl+Z and ctrl+Y were already the textarea's undo and
  redo, but OpenTUI's undo changes the text with no content-change event,
  so the draft never heard it: the prompt reads the text back after
  either key.
- **ctrl+w straight after an image paste.** OpenTUI's textarea has no
  setting for what a word is (its boundary is the native buffer's own), so
  chord takes it, as the owner allowed on CHD-315: ctrl+w with a held
  image's `[Image #N] ` right before the cursor takes it whole
  (`placeholderBefore`); every other ctrl+w is OpenTUI's. The cut is the
  textarea's own `deleteRange`, so its undo and redo take it back and
  forth: setting the cut draft into the box, as a first try did, went
  through `setText`, which clears the textarea's history, and ctrl+z then
  had nothing to bring back.
- **Vim normal mode's cursor**, in part: the textarea keeps the keys'
  focus in normal mode for its cursor alone, every key and paste kept from
  it, so the terminal draws its own steady block on the character vim's
  cursor is on, where insert mode's is. On `main` it was an inverse cell
  drawn into the text; the place is the same, the escapes are not. The
  textarea sets the cursor's colour itself (OSC 12), white unless told,
  even when told the terminal's default, which a light terminal all but
  hides; `TextArea` gives it the terminal's foreground, as OpenTUI's
  palette query (`getPalette`, OSC 10 and 11) answers it (`useInk`), and
  the terminal's own colour is put back on exit. The query asks OSC 10 and
  11 only of a terminal that answers OSC 4 first, and tmux does not:
  there, as under test, OpenTUI's guess stands, white, black where the
  terminal said it is light (`themeMode`, which tmux does answer, and
  `useInk` hears whenever it comes, before the palette's answer or after).
  OpenTUI keeps tmux's OSC 10 and 11 answers for its theme mode in fields
  of its own, which chord leaves alone. A theme changed mid-session is not
  followed.

### As the owner chose

- **ctrl+r's highlight.** `main` draws the match inverse (SGR 7). A
  textarea highlight's style (`SyntaxStyle`) takes a foreground, a
  background, bold, italic, underline and dim, and no inverse; tried in
  tmux, a highlight in the terminal's default foreground and background
  draws nothing, and the selection with no colours of its own draws a hard
  black foreground. The owner first took the terminal's own colours
  swapped, from the palette query, with the ranges put through
  `addHighlightByCharRange`. The reviewer then found the ranges wrong past
  a tab, a decomposed accent or a joined emoji, and no public API gives
  the unit that call counts in: a tab is two, as the buffer's offsets
  count it, but each code point of a grapheme is one more, where the
  offsets count the grapheme once. So the owner took the third option:
  while the search is open the box's rows are drawn over the textarea by
  chord's own `Text`, the match in inverse runs (`foundPieces`, split by
  the string, so nothing is measured), and the textarea under them is
  drawn at no opacity, still laid out, so its height, its scroll and the
  gutter's marks stand. `Text` takes `wrap='char'` for it, OpenTUI's own
  wrap by the cell, which breaks the rows where the textarea does,
  tabs, accents and joined emoji included (`tui_test.tsx`). OpenTUI
  0.5.17's text has the same unit fault in its runs: a run after a
  grapheme of several code points starts a cell late for each extra one,
  in every `Text` with more than one run, so the decomposed accent and
  the joined emoji are still marked a cell late (`Prompt_test.tsx`'s
  todo). OpenTUI 0.6.0 draws them right; on it, with `getLayoutNode`
  renamed `getLayout`, 44 of chord's tests fail, so moving to it is a
  change of its own, for the owner (CHD-306). It was made in CHD-319,
  below, which found the fault only where OpenTUI measures by grapheme.
- **Undo by groups is let go.** `main` (react-ink-textarea) undid edits of
  one kind within a moment at once, so `one two` typed went in one ctrl+Z;
  OpenTUI's edit buffer undoes key by key and has no setting for groups.
  The owner took key by key, nothing built round the library, and
  `keys_test.tsx`'s two shift+arrow undo tests say so.

## 2026-10-11 — OpenTUI 0.5.17 → 0.6.0

CHD-319, on the local branch `opentui`, between part 3 and part 4 of
"Moving to OpenTUI" above, so parts 4 to 8 are built on it. `@opentui/core`
and `@opentui/react` are pinned to exactly 0.6.0, the newest release when
this started (published 2026-10-10; no 0.6.x patch yet), as the owner
asked: the latest, whatever it is, and no waiting for a patch. Its release
notes were read in full against chord.

### What 0.6.0 changed for chord

- **The run after a grapheme of several code points.** 0.5.17 started a
  run after a decomposed accent, a joined or toned emoji or a VS16 emoji
  one cell late for each extra code point; 0.6.0 does not. The notes do
  not say so. `tui_test.tsx` proves it (a `Text` with an inverse run after
  `e` + U+0301, 👩‍💻 and ⚠️), and `Prompt_test.tsx`'s todo for ctrl+r's
  match after them is a test again. The same three tried on 0.5.17 in a
  scratch project read `say é| aut|h`. The fault is in OpenTUI's `unicode`
  width method, which the test renderer uses and which it takes for a
  terminal it finds measures by grapheme. Under tmux it takes `wcwidth`,
  by code point, and there 0.5.17 and 0.6.0 write the same bytes (tmux
  `pipe-pane`, ctrl+r over `say é auth`), so a capture in tmux shows no
  before and after. What tmux shows on both instead (👩‍💻 four cells
  wide, ⚠️ erased, the accent written after the match) is CHD-324.
- **`getLayoutNode()` is gone**: `getLayout()` gives the computed size the
  bridge's clipping box reads.
- **The terminal is given back after `destroy()` returns.** `destroy()`
  restores it asynchronously, and `renderer.closed` settles when it is
  done; it rejects where the output failed or did not finish within a
  second. Every way out waits for it: `render`'s quit, so
  `waitUntilExit()` settles once the terminal is back, and `unmount()`
  returns a promise that the start picker's every leaving awaits before
  it writes to stderr or exits; a signal and a crash wait for it before
  dying, and go on dying if it rejects, as a rejection there would only
  come back to the crash. The CHD-305 matrix was run again in tmux on
  0.6.0: ctrl+C twice, ctrl+D, `/exit`, SIGTERM, SIGHUP and SIGINT each
  left the shell with the alternate screen, the mouse and the cursor as
  they were, and `stty -a` the same but `pendin`, the kernel's
  pending-input mark, which 0.5.17 leaves the same way.
- **`suspend()` and `resume()` return promises**, and throw while another
  transition is pending; ctrl+g's editor awaits both.
- **The textarea refuses control characters.** `setText`, `insertText`
  and `initialValue` throw for C0 but tab, LF and CR, and for DEL and C1
  (tried one code point at a time on 0.6.0); a paste is cleaned by OpenTUI
  first. ctrl+g's editor text and ↑, ↓ and ctrl+r's history reach the box
  through `setText`, so one there was an uncaught error and chord exited.
  The owner chose refusing over rewriting (CHD-323, option a): editor text
  with one goes the way of a failing editor — the draft stays and the
  status line names the character, `U+000C` — and ↑, ↓ and ctrl+r step
  over a prompt with one. Dropping the characters, or drawing a stand-in,
  would change what the person wrote. One check, `unholdable` in
  `src/ui/prompt/prompt.ts`, held the set. 0.6.1 holds them, and the owner
  dropped the refusal on 0.6.6 ("OpenTUI 0.6.0 → 0.6.6", CHD-480).
- Not chord's: the `Clipboard` class (chord reads images through
  `@mariozechner/clipboard`), `SyntaxStyle` and buffer owners (chord makes
  neither since CHD-306 dropped the search's highlight), paint hooks that
  cannot read cells (the prompt's `renderAfter` reads the textarea's
  `lineInfo`, not cells), the global `requestAnimationFrame`, Bun 1.3.14
  as the least (chord wants 1.4.2), and the base-layout key, now used by
  OpenTUI's own bindings only for a typed key of one non-ASCII character;
  chord's bound keys read `baseCode` themselves, and the Russian-layout
  tests pass.

### The test harness on 0.6.0

The 44 failures of CHD-306's trial were three causes, each in
`tests/ui/harness.tsx` or the code above, none in a test:

- **A frame on its way out cannot be read.** 0.6.0's native writer holds
  the buffer while it writes, and reading it then throws `OutputBusy`;
  the tests read frames whenever they poll, mid-render too. The harness
  keeps the frame last presented (OpenTUI's `frame` event, after the
  output), and `frame()` gives it while a render is in flight, as a
  terminal shows the last frame until the next is out. `written()` is
  the frames as presented.
- **The test renderer's terminal was never set up**, and 0.6.0 suspends
  only one that is, so ctrl+g's editor threw. The harness calls
  `setupTerminal()` after `testRender`, as `createCliRenderer` does for
  the window.
- **`unmount()` waits for `renderer.closed`**, as the window's does.

React's warnings about updates outside `act` in some files' output are
the same on 0.5.17 (ten in `Tool_test.tsx` on each).

### Checked again from the flip's list

The list under "What OpenTUI does that Ink did not" was 0.5.17's. On
0.6.0 the tests that cover each item pass, and `flexShrink` given a size
is still turned to 0 (OpenTUI's source), so the bridge's answers stay;
none was found unneeded, though each was not tried alone.

## 2026-10-11 — OpenTUI part 4: the transcript restored

CHD-307, on the local branch `opentui`, the fourth part of "Moving to
OpenTUI" above, on OpenTUI 0.6.0. The table's three transcript rows are
restored on chord's own offset, as on `main`, because OpenTUI's scrollbox
does not keep chord's anchoring; `src/ui/transcript/scroll.ts` is
unchanged, and `src/ui/app/layout.ts`, which the plan counted as gone with
Ink, is back, measuring in OpenTUI's frame.

### The scrollbox, tried

`<scrollbox stickyScroll stickyStart='bottom'>` was tried in a scratch
test on 0.6.0, a box of 10 rows over 30, and its source read:

- **Following**, it keeps the bottom as rows come in, and scrolled back
  it keeps its row while rows come in below, as chord's does. It sticks
  to the bottom again whenever a change leaves it within one row of it.
- **A relayout above the view moves the view.** It keeps a number of rows,
  not an entry: a box above the view grown from 2 rows to 8 took the top
  row from `row 8` to `row 2`. ctrl+o and a resize are exactly that.
- **Its wheel is its own.** Its `onMouseEvent` scrolls it, through its
  scroll acceleration, on every wheel report that reaches it, after any
  listener and whatever the listener did, so the wheel would move a view
  chord's state does not know. Clicked, it takes the keys from the prompt
  (OpenTUI focuses the focusable renderable under a left click).

So the view is chord's: the transcript's area is a clipping box, the
transcript in it is drawn `scroll.top` rows higher (`translateY`) while
scrolled back and hangs from the bottom (`flex-end`) while following, as
on `main`.

### Measuring in OpenTUI's frame

Ink's layout was done by the time a layout effect ran; OpenTUI lays out
inside its frame, after React has committed. The transcript is measured
from its own `onSizeChange`, which a frame calls once it has laid out a
new size and before it paints, and its `renderAfter`, for a relayout that
keeps the size. Two things learned there:

- **Inside one renderable's size hook, another's place is the last
  painted frame's.** The entries' `.y`, read from the transcript's
  `onSizeChange` after ctrl+o, were where they were drawn before it, so
  the view stayed on the old row; `getLayout()` is Yoga's for this frame.
  `measureElement` reads `getLayout()`: an entry's top within the
  transcript, and its height.
- **A move set through React is drawn a frame late.** The measure calls
  `dispatch`, and React draws the new `translateY` in a later frame, so
  ctrl+o drew one frame on the wrong rows (the test's frame log caught
  it). The measure sets the same offset on the transcript in the frame
  that laid it out (`offsetElement`), as the scrollbox sets its own
  `translateY` from its size hook; React's prop arrives later with the
  same value.

### The view held on its entry

While scrolled back, the entry at the top of the view and how far into it
the view starts are kept, and every measure puts the view back on them;
the person's own scroll (a top the measure did not set) reads the entry
again. On `main` the entry was read again on every layout and used only
when ctrl+o or the width had changed. OpenTUI lays a resize out over
several frames (a cut text is fitted in the frame after the one that
gave it its width), and an entry read from a frame half laid out was the
wrong one. Holding it also means an entry above the view that grows while
scrolled back no longer pushes the view down, where on `main` it did.
Each session, a tab or a child, keeps its own: another's top can be the
same row of other entries, and a session shown again finds its entry
where a resize meanwhile moved it.

### The wheel

OpenTUI reads the mouse since the flip, and hands a wheel report to the
renderable under the pointer, from which it bubbles. The window's outer
box takes it (`Box`'s `onWheel` in the bridge): a step up or down is
`scroll:lineUp` or `lineDown`, one row, as on `main`; sideways moves
nothing. One difference: over a draft taller than the prompt box, OpenTUI's
textarea scrolls its own rows on the same step, before it bubbles, and
that handler is the textarea's own.

### The diff's fold

ctrl+o's fold of a diff was already as on `main` after the flip. Its
captures still differed: a row cut at the window's edge lost its `…`
(an opened diff's long row at 80 columns, a headline after a resize).
The bridge's cut text sits in a box as wide as its text, shrunk; beside
a sibling (a diff row's number), the box came out one or two cells wider
than the room its row has right of it, so the text was cut to that width
and the row clipped the ellipsis off. The cut now takes the smaller of the
box's width and that room (`tui_test.tsx`). Why the box came out wider
was found later, in "CHD-332": its `maxWidth` of `100%`, not rounding.

### Memory

`long` ten times on the fake agent (`CHORD_FAKE_STEP_MS=1`), 2,000 rows
of replies, at 120×40; chord's RSS by `ps`, in KB, two runs each:

| | start | after 2,000 rows | 20 s idle | 10× pgup | ctrl+o |
| --- | --- | --- | --- | --- | --- |
| `main` | 195,600 / 198,896 | 451,824 / 601,264 | 392,016 / 601,072 | 422,176 / 601,184 | 440,912 / 601,232 |
| `opentui` | 168,384 / 166,208 | 852,512 / 840,432 | 554,480 / 326,944 | 619,680 / 275,840 | 500,320 / 292,320 |

At rest the two are within each other's spread; while the rows stream in,
the branch peaks higher, as it did before this part (757,392 after the
same 2,000 rows), with the garbage of each frame's text refitted. Neither
virtualizes; that, or folding old turns, is a later task.

## 2026-10-11 — OpenTUI part 5: the terminal's services restored

CHD-308, on the local branch `opentui`, the fifth part of "Moving to
OpenTUI" above, on OpenTUI 0.6.0. No `test.todo` is left on the branch.

### Restored already, and still holding

The theme from the terminal's background and bound keys by their
base-layout key, the Russian table with them, came back in the flip (see
"Restored already" under part 2) and their tests still pass here.

### ctrl+g's editor

`useApp`'s `suspendTerminal` was already `renderer.suspend()` and
`resume()` around the editor; what was missing was its two tests, which
on `main` rendered through Ink's own `render` to read the terminal's
bytes. They now run in the window's harness on a terminal that logs what
it is told (`draw`'s `Logged`): the renderer's bytes on its own stdout,
on the alternate screen, and raw mode turned on and off. OpenTUI's order
is its own: it turns raw mode off before it leaves the alternate screen,
and enters the screen again before raw mode comes back, where Ink did
each the other way round. The tests hold each pair done before the editor
runs and after, not their order within it.

### Notifications

OpenTUI's `triggerNotification(message, title)` picks the escape itself
from the terminal's capabilities, so it cannot take chord's channel
setting (`bell`, `osc9`, `osc777` or `auto` as chord resolves it), and it
has no call that writes bytes of the caller's. chord's own bytes go to
the stream the renderer draws on once `renderer.idle()` says no frame is
on its way out, so a notification never lands inside a frame's escapes.
The window's `Output` names the stream: the process's stdout, or a test's
harness, which keeps the writes among the frames as `written()`.

### The empty bracketed paste in normal mode

OpenTUI hands an empty bracketed paste on as a paste event, so cmd+V of
an image needed no reading of the bytes. In vim's normal mode the prompt
took every paste from the textarea and dropped it; it now hands it to the
window as insert mode does, where an empty one reads the clipboard's
image. A paste of text in normal mode is dropped, where on `main` Ink
heard it as normal mode's keys. That is a decided difference, not a loss:
running pasted text as commands was an accident of Ink's input, and a
destructive one, as a pasted `x` deleted a character. The owner kept the
drop (CHD-308).

### The drag

`src/mouse.ts` and `src/ui/app/mouse.ts` went with Ink. OpenTUI hands a
mouse press and its release to the renderable under the pointer, from
which they bubble, so the window's outer box hears both (`Box`'s
`onDrag` in the bridge), and `src/ui/app/drag.ts` keeps `main`'s rule: the
left button let go on another cell is a drag. The modifier the status
line names comes from the terminal as before (`selectHint`), given to the
window by `main.tsx` unless the `mouse` setting leaves the mouse to the
terminal. OpenTUI selects text on a drag itself, and draws the
selection, though nothing copies it; the bridge's texts and its textarea
are `selectable={false}`, so a drag draws nothing, as on `main`, and the
terminal's own selection, with the modifier the status line names, is the
one there is. OpenTUI's selection is a later task (the owner, CHD-303).
The textarea's shift+arrow selection goes with it; chord never had one.

## 2026-10-11 — OpenTUI part 6: the binary on every target, and Windows out

CHD-309, on the branch `opentui`. `bun run compile --all` builds darwin
arm64 and x64 and linux x64 and arm64, and each binary embeds OpenTUI's
native library for its target (`libopentui.dylib` or `libopentui.so`,
glibc's and musl's both on Linux), which the `bun install --os='*'
--cpu='*'` before the builds already put in `node_modules`. The darwin
binaries started here (x64 under Rosetta); the Linux ones are checked by
`file` and by the library they carry. The host binary, driven in tmux at
120×40 and 80×24 on the fake agent, drew the same splash, turn,
permission and quit as `bun src/main.tsx`, the session id and a timer's
second aside, and `stty -a` read the same before and after.

**Windows is not a target** (the owner's answer 4 on CHD-303):
`bun-windows-x64` left `scripts/targets.ts`, `Target`'s `os` lost `win32`
and its `exe` field, since every binary is now `chord`, and the npm shim
lost its `chord.exe` branch, so `bun run npm` lays out no `chord-win32-x64`
and names none in `@chorded/chord`'s optional dependencies. chord's own
Windows branches in `src/` (`cmd.exe` for bash mode, process groups,
notepad) stay for when Windows comes back, which is a backlog task with
OpenTUI's Windows keyboard bugs (#1042, #1405) and CHD-296's hand check.

**`--external react-devtools-core --splitting` stays**, for a new reason.
Ink's devtools import is gone with Ink, but `@opentui/react` imports
`react-devtools-core` behind `DEV=true` too, and `bun install` installs it
as that package's peer. Built without the two flags, the build passes and
the binary is 0.7 MB larger; it starts and quits as usual, but run with
`DEV=true` it connects to a devtools server nobody runs and never exits
after ctrl+c ctrl+c, the pane left blank. With the flags, `DEV=true` makes
OpenTUI's lazy import fail, OpenTUI prints its warning and carries on, and
chord quits with code 0. `DEV` is a common variable for a person to have
set, so the flags stay, with the comment in `scripts/compile.ts` naming
OpenTUI rather than Ink.

The trial went to the owner, since one side of it broke. Their answer, on
CHD-309: keep the two flags, and OpenTUI's warning when `DEV=true` finds no
devtools. They are `bun build`'s documented options for leaving an
optional, developer-only import out of a binary, not a patch around a
library; React devtools are for running from source, not for the shipped
binary.

The earlier Ink entries in this file, and "Bun part 4" for its Windows
target, point at "Moving to OpenTUI"; CLAUDE.md, README and
`docs/FEATURES.md` name OpenTUI as the interface and macOS and Linux as
the platforms. Comments in `src/` that name Ink describe the bridge's
Ink-shaped props, which part 8 takes away with the bridge.

## 2026-10-11 — CHD-332: an opened proposal's instructions, whole

An agent's instructions in an opened proposal, or in `/team show` opened,
were drawn as blank rows: each was one long line, cut with
`wrap='truncate-end'`, and the cut line came out empty.

**The cause was the layout, not the cut.** cli-truncate cut a long
Cyrillic line with backticks correctly, the bridge's mark included. The
bridge laid each fitted text out in a box `width` its whole text,
`flexShrink: 1` and `maxWidth: '100%'`. Yoga 3.2.1 (OpenTUI 0.6.0's), in a
row with a padding, shrinks such a box from beyond its maximum wrongly: a
little beyond it, to a cell or two wider than the room (part 4's clipped
ellipsis, which "The diff's fold" put down to rounding), and from about two
and a half times the parent's width, to no width at all. Checked on Yoga
alone: an 80-wide row, padding 2, a fixed 3-wide gutter and the box; a
200-wide box is laid out 78 wide in a room of 75, a 202-wide one 0, and
without the `maxWidth` each is 75. The `maxWidth` is gone: a row shrinks
the box to its room, and in a column, where nothing shrinks it, the room
its parent has right of it, which the bridge already took the smaller of,
bounds the cut. Every test passed without it, part 4's included.

Review found what the `maxWidth` had also done: in a column it made the
box follow its parent's width, so the box's own resize, which refits the
text, came with the parent's. Without it the box keeps its whole text's
width in a column and never resizes; a terminal shrunk or grown left the
text fitted to its first width, its ellipsis clipped off or its wrapped
tail lost. The bridge now listens for the parent's resize too, through
OpenTUI's `resize` event, and refits from there (`tui_test.tsx`, a column
40 → 20 → 60 cut and wrapped).

QA then found what a listener for each fitted text did (CHD-334): the
shortcuts column holds more than ten, past EventEmitter's default limit,
and Node's `MaxListenersExceededWarning` was written straight to the
terminal, over the full screen. Each parent now holds one `resize`
listener, which refits every fitted text in it, added with the first and
removed with the last. Raising the parent's limit with `setMaxListeners`
was the one other way weighed; it only hides the warning, and a column of
fitted texts is not a leak to be told about. OpenTUI has no resize
observer or layout hook that reaches a child for its parent's size, and no
library was found that does this for an OpenTUI renderable
(`tui_test.tsx`, twelve cut texts in one column, one listener, none after
unmount, no warning).

**Opened, the instructions are wrapped, not cut.** The owner's rule: a
person reviewing a proposal sees everything that will be written to the
file. `instructionLines` wraps each line to the width with `wrapLine`,
wrap-ansi as the description and messages are wrapped, so `… +N lines`
counts the rows ctrl+o adds. Folded, nothing changes: the instructions are
not drawn, and the fold line counts them.

## 2026-10-12 — CHD-333: an opened proposal's roles, whole

The same rule reaches the table: opened, nothing in it is cut with `…`, in
the proposal and in `/team show` alike. Each member takes two rows: the
mark, name, agent · model and mode, then the role, dim, from the agent
column to the right edge and wrapped there (`docs/design/CHD-333.md`). The
first try wrapped the role inside its own column; a change's long mode
left it 10 cells wide, a member 4 to 7 lines tall, and the model still cut
to make room, so the role moved to a row of its own, the same shape at
every width.

@cliffy/table does it as it is: the role row is two empty cells and
`new Cell(role).colSpan(n)`, and a spanned cell wraps at word boundaries
within the columns it spans. An empty last column, given the width the
first row leaves through `minColWidth` and `maxColWidth`, carries the span
to the right edge. Where a long mode leaves no room for that column, the
row is wider than the width anyway, as the mode is never cut, and the role
spans the agent's and mode's columns only, as wide as the row; an earlier
try wrapped the role's text to the width with `wrapLine` before the table
took it, rewriting the library's input, and was taken out in review.
Opened, the agent · model is not cut either. Where the row does not fit,
its cells give way in the order the design gives: the mode cell first,
narrowed to what the row leaves but never below its longest word, so
`was acceptEdits` goes under the mode; then agent · model, in the rest,
which cliffy wraps at its spaces (`claude ·` / the id whole); only where
that rest is narrower than the id does cliffy break inside it, as the id
and the mode's longest word no longer fit side by side. A first try wrapped the
model in its column before the mode, and split `claude-sonnet-4-5-20250929`
at 80 columns. Each row and its role are laid out as tables of their own
with the same column widths, so a model's later lines are told from the
role's. No new dependency, and nothing written around the table but those
widths: the mode is on a row's first line, painted in the warning colour,
and a changed mode's old one is found again in the mode column on the
lines cliffy put it. Folded, nothing
changes: one line a member, the role cut, so the table and the save box fit
at 80x24.

## 2026-10-12 — OpenTUI part 8a: the transcript side off the bridge

The transcript, its tools and subagents, the agent list, the plan, the
header, the splash and the status line draw on OpenTUI's own `<box>`,
`<text>` and `<span>`. `src/ui/tui.tsx` is left to the prompt, the
pickers, the dialogs, the teams and the shortcuts (part 8b, CHD-312).

**OpenTUI's text as it is, not Ink's.** The bridge wrapped a text with
wrap-ansi and cut one with cli-truncate, as Ink did. OpenTUI wraps at
words and at a `/`, and its `truncate` keeps both ends of the line with
`...` between them. Keeping Ink's look would have meant code of chord's
around OpenTUI's text: either every row fitted to a width worked out by
hand, or the bridge's fitted text kept under another name. The owner's
answer on CHD-311, for CHD-312 too, was OpenTUI's text as it is. The
acceptance became "captures differ only where a text does not fit". On
the fake agent at 120×40 and 80×24, what differs is a tool's headline, a
subagent's line of work and a diff's row cut in the middle. At 80
columns, `Bash(deno test --allow-read --allow-write --allow-env
--allow-run --allow-s…` became `Bash(deno test --allow-read
--allow-...ilter "tool calls draw their status")`. Wrapped text, a long
prompt among it, draws as before.

**A wrapped text beside a gutter takes the rest of its row.** OpenTUI
measures a `<text>` in a row whose width the row has not settled as no
taller than the room its ancestors offer. In the transcript that room is
the view, so a reply longer than the view was laid out as tall as the
view. The view then stopped following the stream and scrolled back wrong.
The bridge never met this, because each of its texts sat in a box as wide
as the text. `overflow: 'scroll'` on the transcript's content box, which
makes Yoga stop offering the room, measured the text as one row instead.
With `flexGrow: 1`, the row settles the text's width and OpenTUI measures
every line: `theme/text.ts`'s `FILL`, and the reply's box.

**Strings with SGR become spans** through `theme/text.ts`, on
@ansi-tools/parser, as the plan said. It is the bridge's reading moved
out, and the bridge now reads through it too. A reset goes back to
nothing set, and a `<span>` takes what is unset from the text around it,
so a dim text stays dim after a bold run.

**The spinner stays a timer.** opentui-spinner 0.0.7, the maintained
OpenTUI spinner, was tried again. It takes cli-spinners' `star` by name.
But its peers are `@opentui/core` and `@opentui/react` `^0.3.4`, which
0.6.0 is outside. A run of the window tests with it in had 61 time out
waiting for the screen, and with the timer back they pass. Part 2's
finding stands: the working line's spinner is a timer of `Status.tsx`'s,
on `<text>`.

**JSX is OpenTUI's.** `tsconfig.json`'s `jsxImportSource` is
`@opentui/react`, which re-exports React's runtime and types `<box>`,
`<text>` and `<span>` with OpenTUI's props. Its `JSX.Element` is a
`ReactNode`, so the test harness's `draw` takes one.


## 2026-10-12 — OpenTUI part 8b: the bridge goes

The window, the prompt, the pickers, the dialogs, the teams and the
shortcuts draw on OpenTUI's own `<box>`, `<text>` and `<span>`, size
themselves by `useTerminalDimensions`, and hear the terminal through
`useKeyboard`, `usePaste` and `useRenderer`. `src/ui/tui.tsx` is deleted,
and with it every Ink-shaped prop: CHD-302's move is done. Its text is
OpenTUI's as part 8a took it, the owner's option C on CHD-311: wrapped at
words, and cut by `truncate` with `...` in the middle, where the bridge cut
at the end or the start with `…`. A string an agent sent (a permission's
title, paths and arguments, a form's message, labels and options, a link,
a picker's choice, a command's description, a queued message, a team's
body) goes through `theme/Ansi.tsx`, as the bridge read SGR in every string.

What the bridge held that was never Ink's has a home of its own:

- `app/renderer.tsx`: the terminal taken and given back, the React root,
  the quit, the editor's suspension and the bytes written between frames,
  moved whole.
- `app/input.ts`: `usePress` and `usePasted` on `useKeyboard` and
  `usePaste`, each still run inside `flushSync` and turned on a microtask
  late, as "What OpenTUI does that Ink did not" above has it, and
  `useMouse`, the window's wheel and drag on `<box>`'s `onMouseScroll` and
  `onMouse`. `shortcuts/press.ts` reads OpenTUI's `KeyEvent` as chord's
  `Press`, pure.
- `prompt/TextArea.tsx`: the `<textarea>` with the terminal's foreground
  and cursor colour, focused a microtask late and blurred as it unmounts.
- `app/Clip.tsx`: a box that draws nothing while it is laid out to no rows.
  OpenTUI still draws every box at least a row high, so the transcript's
  area keeps it.
  **Widened 2026-10-19, the owner's consent (Q57, option 1; CHD-158 C6).**
  Clip learnt of a size laid out to nothing through `onSizeChange`. A box
  going from one row to none is drawn one cell high both before and after,
  so OpenTUI reports no change, and what it held stayed drawn over the row
  below it: a held box's queued line over the splash at 80x24 (CHD-158
  C5). Clip now also reads Yoga's layout again in `renderAfter`, after
  each frame drawn, and asks React for nothing unless what it read
  differs. The upstream report, that a box laid out to no rows still
  draws one and that one row to none fires no `onSizeChange`, is drafted
  on CHD-438 for the owner to file; once OpenTUI fixes either, this read
  goes.

Two of the bridge's answers are not carried on. It set `flexShrink` back to
1 after each new size in cells; in these folders the only box whose size
in cells changes is the window's own, which has nothing beside it to give
way to, and each column of a fixed width already pins `flexShrink={0}`.
A spacer of one cell takes `flexShrink={1}` as the bridge gave it. And
`translateY`, which OpenTUI's `<box>` props leave out of their types, is
set on the transcript's renderable in a layout effect, where `layout.ts`
already set it inside the frame.

The bridge's tests of its own fitted text went with it; the rest moved
beside what they test (`tests/ui/app/renderer_test.ts`, `Clip_test.tsx`,
`tests/ui/prompt/TextArea_test.tsx`, `tests/ui/theme/Ansi_test.tsx`).

Captures against part 8a on the fake agent, at 120×40 and 80×24, of the
prompt, `?`, `/`, `@`, a permission, a form, a link, `/model`, `/config`,
`/theme`, `/mcp`, `/resume`, `/team`, ctrl+r, the queue, two tabs and the
start picker, text and colours: the same but in two rows at 80×24. `/mcp`'s
sentence wraps a word earlier, as it is 77 columns in a 76-column row,
which the bridge overran into the padding by a cell (the Yoga overshoot of
"CHD-332"). `/team`'s user directory breaks at a `/`, as OpenTUI's word
wrap does.

## 2026-10-12 — CHD-342: an entry is drawn again only when it changes

Every state change drew every transcript entry again: each chunk of a
streamed reply, each key typed into the prompt. On a long session that kept
the main thread busy through a whole stream. `TranscriptEntry` and `Agents`
are now `React.memo`, React's own answer, and nothing is written around
OpenTUI. The reducer already keeps an entry a chunk did not land in, as its
arrays are spread and `with`'d, never mapped anew. Two props were new on
every draw and are not any more: each entry's box `ref`, now one function
per index from `layout.ts`'s `place`, and a subagent group, which the
window slices out of the transcript afresh, so `Agents` compares it by its
subagents. The `turn` an entry gets still changes when a turn starts or
ends, and every entry is drawn again then, once a turn, not once a chunk.

Measured on the fake agent at 120x40 with 80 turns behind (40 `markdown`
replies and 40 `tools` turns), then a 1001-chunk reply: `Ansi` drawn
190,513 times during the stream before, 2,161 after; a key typed into the
prompt drew 1,200 before and none after; CPU 15 ms a key before, 9 ms
after, and 1,489 ms over the stream before, 1,019 ms after. What remains is
Yoga laying out every node, which CHD-327's virtualisation takes on.

## 2026-10-12 — CHD-343: a heap snapshot on a signal, and memlab for the check

Nothing could look inside a running chord's heap, and the owner's window had
reached 5.3 GB after two and a half hours with a team. `SIGUSR2` now writes
a snapshot (`src/platform/heap.ts`), from Bun's own
`Bun.generateHeapSnapshot('v8', 'arraybuffer')`, which Chrome's DevTools
open, and `bun:jsc`'s `heapStats()` beside it. The V8 format rather than
JSC's own, which DevTools does not open; the `arraybuffer` encoding, as the
string would be a second copy of a snapshot the size of the heap, inside
that heap. `SIGUSR2` because nothing in chord or OpenTUI listens for it,
and a signal reaches a chord whose terminal is taken without a key or a
word on screen.

`scripts/memory.ts` compares two snapshots through memlab
(`@memlab/heap-analysis` and `@memlab/core`, Meta's, MIT, dev dependencies
only, never in the binary): it parses Bun's V8 snapshots as they are,
under Bun, and gives each object's shortest path from a root, which is
the retainer the check reports. Nothing of ours parses a snapshot. memlab
depends on puppeteer, whose install script Bun trusts by default and
which downloads Chrome; `.puppeteerrc.json` sets `skipDownload`, so
`bun install` fetches no browser. Its leak finder (`find-leaks`) and its
unbound-growth analyses match objects by id across snapshots, and Bun's ids
do not carry over from one snapshot to the next, so the script compares
counts and sizes per type and name instead. Importing `@memlab/core`
registers a SIGINT listener that only flushes memlab's log, which keeps
Ctrl+C from ending the process; the script answers SIGINT and SIGTERM
itself, ending its tmux session and waiting for chord and its fake agents,
rather than patching memlab. What it found is in `docs/memory.md`.

The fake agent's `soak` runs the team for the check. A team agent's first
prompt that names a scenario now plays it rather than the agent's role, as
any other message naming one does, so `run_team`'s job and `open_agent`'s
prompt can start one.

## 2026-10-12 — CHD-344: React's production build, from source and in the binary

Nothing set `NODE_ENV`, so React loaded its development build everywhere,
and CHD-343's check found it holding a `performance.measure` for every
render, never cleared, and a stack on every fiber (`docs/memory.md`).
`bun build --compile` and the `chord` and `chord:fake` scripts now pass
Bun's own `--define process.env.NODE_ENV:"production"`, and
`react-reconciler`'s `index.js` takes its production file. Nothing of ours
is written for it.

Tried and not taken:

- `bun build --production`: it loads the production build too, but also
  minifies, and the binary lost names such as `dispatchSetState` that the
  memory check's retainer paths and a stack trace read by.
- `[define]` in `bunfig.toml`, which would cover plain `bun src/main.tsx`:
  it reaches `bun test` as well, which then runs React's production build,
  and neither `[test.define]` nor `[run.define]` scopes it. `bun test
  --define process.env.NODE_ENV:"test"` undoes it, but a test run on its
  own without the flag would not.

Not tried: setting `process.env.NODE_ENV` in chord before React is
imported, since the agents and commands chord starts would inherit it.

`DEV=true` behaves as CHD-309 left it: the binary prints OpenTUI's warning
and quits with code 0, and from source chord still does not exit after
quit, as before this change; for DevTools, `bun src/main.tsx` keeps
the development build. `scripts/memory.ts` runs the source as
`bun chord` does, and `--development` (in place of `--production`)
measures the development build.


## 2026-10-12 — CHD-327 A: the native scene culls the transcript

Every entry of a session's transcript is a mounted renderable, and every
frame painted all of them, on screen or not. At 10,000 rows on the fake
agent (120x40) a key typed cost a 6 ms frame, a pgup 8 ms and ctrl+o a
119 ms frame at the 95th percentile, almost all of it OpenTUI's native
scene.

OpenTUI 0.6.0's `<scrollbox viewportCulling>` is its `ContentRenderable`
calling `renderer.nativeScene.setViewport(content, viewport)`, after which
the native scene paints none of the content's children outside the
viewport. The scrollbox itself stays out, for the reasons in "OpenTUI
part 4", so `layout.ts` makes that one call on chord's own transcript box
with its `Clip` as the viewport, the owner's consent to use the public
scene API outside the scrollbox. It is made again whenever the boxes are
new, as `Clip` mounts its children anew when its area comes back from no
rows. chord's own offset is untouched: the content is still moved by
`translateY`, which the native scene reads.

It roughly halves the frame of a key, a pgup and ctrl+o at 10,000 rows. It
does nothing for memory or for a streamed turn: every entry is still
mounted, and Yoga still lays every one out; CHD-327's tail-first mounting
takes those on. Captured against `main`, scrolled back, with the `Below`
rule, through ctrl+o, a resize to 80x24 and back, home and new output
below, every screen is the same.

## 2026-10-12 — CHD-327 D: only the transcript's tail is mounted

Culling (A, above) stops painting what is off screen, but every entry was
still a mounted React tree of OpenTUI renderables that Yoga laid out on
every change: at 10,000 rows, 6,628 renderables, a 1.1 GB footprint and
50 ms frames while a turn streamed. The owner chose tail-first mounting as
opencode's TUI does it (`packages/tui/src/routes/session/index.tsx` and
`mount-budget.ts`, also on OpenTUI), followed, not copied:

- Only the newest entries are mounted, 40 by weight; the rest are only
  state. A folded subagent group costs one, an opened one (ctrl+o) one
  more for each block of its agents' work, and every other entry one.
  The budget counts entries, not rows: a tool call is one entry whether
  ctrl+o is on or not. The owner's decision said an opened tool call
  costs its children, but in chord ctrl+o mounts nothing new in a tool;
  its diffs, terminals and text are drawn either way and only show all
  their rows. Only the subagent group gains children on ctrl+o, so only
  it weighs more opened (the owner's answer, 2026-10-12).
  The tail is at least one more entry than the view has rows, so it
  always overflows and can be scrolled back, as every entry drawn takes
  a row; at 120x40 that is the 40. A flat 40 would leave a terminal
  taller than 40 rows with a tail that cannot be scrolled back; the owner
  confirmed `max(40, view rows + 1)` (2026-10-12).
- As the view leaves the bottom, the window is held from its first entry,
  so new output does not unmount what is on screen. Within a view of the
  top of what is mounted, the 60 older entries above it mount, and the
  view stays where it was: `layout.ts` holds the view on its entry as it
  already did for ctrl+o and a resize, now counting the entry from the
  transcript's first rather than the first mounted.
- Back at the bottom, the window is the tail again, and what was above it
  unmounts. Home mounts every entry, then goes to the top, so it and pgup
  still reach the first entry; nothing else in chord moves the view to an
  entry (ctrl+r searches the prompt history).
- An entry is mounted whole or not at all. No virtual heights and no
  placeholder boxes, so the scroll counts only rows that are laid out, and
  the `Below` rule's count stays right, as the entries below the view are
  always mounted.

What chord has that opencode does not, and how it fits: the header (or a
child's line) is the transcript's start and is drawn only with its first
entry; each tab and child keeps its own held window, as it keeps its own
scroll; only the session in front is mounted at all, as before. opencode
keeps its window while text is selected; chord has no selection of its
own (a drag is the terminal's, "OpenTUI part 5"), so nothing waits on one.
No library does this for OpenTUI: opencode's is its own code on its own
scrollbox, and npm's virtual lists are for the DOM.

Measured at 10,000 rows on the fake agent (200 `soakturn` turns, 120x40,
`CHORD_FAKE_STEP_MS=1`), each case once, so about ±20 % noise. RSS on
macOS swings with compression, so the JSC heap is beside it; the footprint
is at the end. A key is 20 typed and 20 deleted 150 ms apart; pgup is 5
pages; ctrl+o is 10 toggles.

| case | RSS / heap at rest | footprint | key frame avg / p95 | CPU per key | stream frame p95 | pgup frame avg | ctrl+o frame p95 / CPU for 10 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| before (2982fe0b) | 638 MB / — | 1,063 MB | 6.3 / 8.4 ms | 11.8 ms | 50 ms | 8.1 ms | 119 ms / 1,617 ms |
| A | 150–462 MB / 147 MB | 1,100 MB | 3.7 / 4.4 ms | 8.9 ms | 58 ms | 4.3 ms | 76 ms / 1,627 ms |
| D | 171–205 MB / 43 MB | 244 MB | 0.9 / 1.1 ms | 4.5 ms | 51 ms | 1.0 ms | 12 ms / 237 ms |
| A + D | 102–189 MB / 43 MB | 246 MB | 0.3 / 0.6 ms | 2.9–3.4 ms | 12–29 ms | 0.8–2.0 ms | 5–9 ms / 143–158 ms |
| A + D, 3 tabs | 222–261 MB / 46 MB | 358 MB | 0.4 / 0.7 ms | 2.8 ms | 4 ms | 1.0 ms | 24 ms / 141 ms |

With A and D, 347 renderables are mounted at the bottom of a 10,000-row
transcript, against 6,628. Thirty pages up mount 1,250 rows' worth at
frames under 6 ms. Home mounts the whole transcript once (400–530 ms of
CPU, one 46–50 ms frame), and end unmounts it again; the 3-tab and second
1-tab footprints are after that home. A tab switch costs 28 ms of CPU,
against about 200 ms. A stream's 95th percentile is a single frame out of
12 to 16, and swung from 12 to 51 ms between runs of the same build.

## 2026-10-12 — CHD-360: after Esc, queued messages go at once

The owner's decision. An interrupt used to keep the messages queued behind
the turn (another agent's, a lead's, `@main`'s, a monitor's events) for
after the person's next prompt, so that the interrupt was not undone; they
sat unread until the person sent something and that turn ended. Now, once
the interrupted turn has ended, the messages left go as the next turn, as
after any turn that ended on its own. The person's own queued prompts still
go back to the draft, and a task agent Esc stopped still sends no report,
only its line ahead of the next prompt. Interrupted while it waits out a
finished turn's trailing updates, a session with a message left lets the
wait run out, so that late updates fold under the turn they follow; with
nothing left, the wait is cut short as before. No library: the change is
the removal of a flag.

## 2026-10-13 — CHD-365: other agents' messages steered into the running turn

The owner's decisions are on CHD-363 and the design on CHD-364. A message an
agent sends with `send_message` goes into the recipient's running turn
through `_session/steering`, the extension Claude's adapter (0.87.0) and
Codex's (2.1.1, as the registry pins it; 1.10.0 the same) answer and
advertise as `InitializeResponse._meta.steering.supported`. No new library:
the ACP SDK sends a method its schema lacks through the same
`connection.agent.request(method, params)` as the rest, which its
deprecated `extMethod` now defers to, and nothing is hand-rolled on the
wire. chord reads the advertisement in `connection.ts` and refuses to ask an
agent that does not make it.

What the adapters do, read from their shipped code. Neither says in
`initialize` what it does with no turn running. Claude's checks for a
running turn and injects in one synchronous step: with the request's
`_meta.steering.idleBehavior: "promptRequired"`, which chord always sends,
an idle session answers `promptRequired` and does nothing, and an injected
message holds the turn's `session/prompt` until it is answered, so a steer
that meets the turn's end is either in the turn or refused, never lost or
doubled. Codex's parser keeps only `sessionId` and `prompt`: with no
steerable turn it waits for the last prompt and starts a turn of its own,
`startedNewTurn`, which no `session/prompt` of chord's owns; a steer that
meets a turn's end can start one. Its `prompt()` does not wait for an
earlier one, so a prompt of chord's sent then would run beside it.

The owner's decision on CHD-365 (2026-10-13), option C of four: steer both
adapters, and when the answer is `startedNewTurn`, `session/cancel` that
turn at once and queue the message as today, to go as chord's next turn.
What the agent did with it before the cancel landed stands. The owner left
the screen to the designer if the updates alone read wrong, and they did:
folded under the turn before, the cancelled turn's first chunk ran on into
that turn's reply. So that turn's updates fold under an id of its own, which
starts a block of its own, and chord's dim line closes it as the cancel goes
(`Interrupted · the agent started this on its own; @main's message goes as
the next turn`, `docs/design/CHD-365.md`), a `⏺` of its own while the turn
has drawn nothing, as is usual live; the record keeps the line, so a resumed
session draws it there too. The options set aside were
steering Claude's adapter alone (told apart by `agentInfo.name`, as
`initialize` does not say), treating the agent's turn as one chord holds its
queue behind, and steering neither until Codex's adapter honours
`promptRequired`. So that nothing of chord's runs beside that turn, an
unanswered steer holds the queue, the person's prompts included, and the
message, queued, waits out the agent's quiet after the cancel, as a prompt
queued behind a turn waits out its trailing updates (CHD-360's
one-second quiet, five at most). Steers go one at a time, each sent only
while chord's turn still takes messages, and a turn the agent answered a
steer for as over (`promptRequired` or `startedNewTurn`) takes none after:
Codex's adapter, which also takes steers one at a time, would otherwise put
the next one into the turn it started with the first, the one chord
cancels, and lose it. A steer behind another looks again before it goes:
a permission, form or link asked meanwhile holds it, marked `after your
answer`, until the person answers, or the turn ends and it goes as the
next. A turn takes messages only once its prompt has gone to the agent:
one with mentions waits on their walk first, and a steer before then
would find no turn of chord's running, and on Codex's adapter start one
of its own ahead of chord's prompt; a message told meanwhile is queued
behind the turn, as on an agent that does not steer. `startedNewTurn` is handled whatever the
adapter: Claude's does not answer it to a request that asks for
`promptRequired`, and chord always asks.

`Conversation.tell` is the `send_message` path, apart from `deliver`, so a
task's report, chord's own notes and a monitor's events keep the queue
without chord guessing a sender's kind from its row's fields. It answers
`sent` as soon as the steer is under way, since the request is in flight
when the tool answers; making every `send_message` wait for the steer's
answer was judged not worth it. A steer the agent refuses or cancels as a
turn of its own (the race above) then goes as the next turn, and its
sender's `→` row gains `· queued` in place (CHD-368, below).
A steered message is drawn and recorded once the agent has taken it, as a
`prompt` with `into` the running turn, so the queue, the `←` mark in the
agent list and the terminal's notices read it as today's message, and a
resumed session draws it where it went.

## 2026-10-13 — CHD-368: a steer that went as the next turn marks its sender's row

`Conversation.tell` takes a callback it calls when a steer it answered
`sent` for goes as the next turn after all: the agent answered
`promptRequired` or `startedNewTurn`, or chord refused it itself, the turn
being sealed or the steer failing. `send_message` passes one that serves
the call again, `queued`, under the `asked` id the first was served with;
the transcript's reducer lets a call served again take the place of the
one with its `asked`, as an answer took a pending proposal's (CHD-261's
mechanism, widened), so the row changes in place wherever it is drawn and
the record keeps both, a resumed session ending as the live one did. The
agent's tool result, given already, stays `sent`. No library is involved:
the row is chord's own transcript state (`docs/design/CHD-368.md`).

Where the call served again goes is found when `send_message` is called
(`WindowView.servedLater`), not when the steer is answered, since a task
can report and end in between: its conversation is closed by then and its
`TaskAgent` hears nothing more. For a task that has ended, the call is kept
in the task's own record, which its resumed parent reads the task's work
from, and drawn in its block in the parent, while the parent's session is
still the one the task ran in, so a `/clear` in between draws nothing. No
agent is kept alive for it.

## 2026-10-13 — CHD-353: a session's effort, read by ACP's category and asked for at its start

Effort is the select config option of ACP's `thought_level` category
(`SessionConfigOptionCategory`). Both adapters chord starts by name mark
theirs so, under ids of their own: Claude's adapter (0.87.0) sends `effort`,
Codex's (2.1.1) `reasoning_effort`. `src/session/efforts.ts` finds the
option by that category alone, never by an id or a name, so an agent that
marks its effort no other way has none as far as chord is concerned.

Both adapters offer the efforts of the model the session is on, and build
the option again when the model changes; Claude's leaves it out for a model
with no effort. So:

- **A starting effort is asked for after the starting model,** through
  `session/set_config_option` on the option's own id, before the mode, in
  `Conversation`'s start, which every session chord opens goes through: the
  person's, a task's, a long-lived child's and a team agent's.
- **A refused effort never fails a start** (the owner's answer on CHD-352):
  the session goes on on the agent's own, and the refusal is said in the
  transcript in `starting.ts`'s words, as a model's or a mode's is: `Could
  not start on high effort, asked by spawn_task: the agent offers low,
  medium`, `…: the agent offers no efforts`, or the agent's own words for
  one it lists and refuses. Even a value marked `required` is not. A task's
  transcript is not on screen, so `TaskAgent` passes a refusal it hears
  before it is up to the parent's, after the task's name: `Fix it: Could not
  start on high effort, …`. That event, before `connected`, is the outcome
  a caller's tool answer reads its line from.
- **`list_agents` puts the efforts on the model they were read for**
  (`efforts`, and `effort` for the one it is on), as a session of the
  runtime gave them; beside the models only for an agent that names no model
  it is on. Only that one model's efforts are known: reading every model's
  would mean switching the model of a session through each, which is the
  owner's call.

No library was needed: the SDK's types give the option and its category,
and the reading is a find over the options, as `models.ts` and `modes.ts`
do theirs.

## 2026-10-13 — CHD-354: `spawn_task` and `open_agent` start an agent on an effort

Both tools take an optional `effort`, described for the model as
`list_agents` lists the values, and the child's `Conversation` asks for it
through CHD-353's start, never required. The owner's answer 4 on CHD-352
says a refusal reaches the caller as a line, so:

- **Given an effort, the answer waits for the child to be up.** Before the
  child's session exists nothing says whether the runtime takes the value
  for the model asked for: `list_agents` knows only the efforts of the model
  a session was read on, and a runtime not read yet knows none. So the
  answer, which was the child's id at once (CHD-167's two kinds of child,
  CHD-169), comes once the child is up, failed or closing when an effort was
  asked for, and still at once when none was. It carries `effort`, the one
  the child is on, and, on a refusal, `note`, the transcript's own line:
  `Could not start on max effort, asked by spawn_task: the agent offers
  low, medium, high`. A runtime with no effort answers no `effort` and that
  note, `…: the agent offers no efforts`. The tool descriptions say the
  wait.
- **The task block and the call say the effort it is on, after the model.**
  A task's block is drawn before its agent is up, so `TaskAgent` sends one
  more `subagent_update` with the effort in chord's task `_meta` once the
  window has the answer, and the reducer takes a later task `_meta` over the
  first. Only a task asked for an effort says one, as only one asked for a
  model says that. A refused one says the runtime's own, which it runs on;
  the refusal is the line in the parent's transcript.
- **The agent list shows the live effort after the model,** for `main` and
  every child, as CHD-356 designed it, read from the session's own
  efforts, and dropped one fitting step before the model.

No library was needed: the wait is a promise on the child's own events.

## 2026-10-13 — CHD-355: the person's own sessions start on an effort from the files or `--effort`

`agents.<name>.effort` in either settings file and `--effort` on the command
line set it, weighed as `model` and `permissionMode` are: the flag over the
project's file over the user's, per agent, since an effort's id is its
runtime's own, and the flag only for the agent the command line names. The
window's first session, each `/new` and `-p` ask for it through CHD-353's
start, so a refusal is the same line with where it was set:
`Could not start on max effort, set by --effort: the agent offers low,
medium, high`, or `…: the agent offers no efforts` for a runtime with none.
It never fails a start.

- **`-p` takes `--effort` though not `--model`.** The oneshot asks for the
  effort, then the mode, in the window's order, and says a refusal on
  stderr as `chord: could not start on …`, the turn running on the
  agent's own. `-p` starts on the agent's own model, so an effort is asked
  of that model's list; one set beside a `model` the window would start on
  may be refused under `-p`, which the line says.
- **A session resumed from another directory takes that directory's
  effort,** as its model and mode, and `--effort` still beats it.

No library was needed: the flag is one more Cliffy option and the key one
more zod field beside `model`.

## 2026-10-13 — CHD-357: effort in team files and `propose_team`

A team file's lead and each member take an optional `effort`, a zod string
beside `model` and `mode`, not checked against the runtime for the reason
those are not; `propose_team`'s input carries it for each, and a change
counts it as it counts any other key. A run's lead and a member start on it
through CHD-353's start, never required, as `open_agent`'s effort is
(CHD-354), with `set by team <name>` as where it was asked for.

- **`run_team` waits for the lead as `open_agent` waits for a member,**
  where the file gives it an effort: the answer carries the effort it is
  on and, on a refusal, the transcript's line as `note`. `/team run` does
  not wait: its row is drawn at once, as before, since the person typed it
  and the agent list already says the effort the lead is on, and a
  refusal is in the lead's transcript.
- **The table draws CHD-356's design.** The effort is a column of its own
  between `agent · model` and the mode, only where an agent of the table
  sets one or had one, `—` for none; a change's cell reads `high was
  medium`, the `was …` dim. Folded, a changed effort's `was …` goes after
  the role is cut to 12 and before the model is cut. Opened, the mode
  wraps first, then the effort, then `agent · model`, and a changed cell
  wider than its column is handed to @cliffy/table with a line break
  before `was`, which cliffy keeps as a line of the cell, so the new value
  is never read as the old one. `/team show`'s running form shows the
  file's effort the same way, and leaves the column out where the latest
  headline would keep fewer than 12 cells.
- **The team part lists a member's effort** after its model, as
  `(codex · gpt-5.3-codex · xhigh · auto)`.

No library was needed: the column, the cuts and the break before `was` are
@cliffy/table, cli-truncate and string-width, which the table already used.

## 2026-10-14 — Releasing: signed, notarised, published from the owner's Mac; `chord upgrade`

The release is `scripts/release.sh`, ported from board's: on the owner's
arm64 Mac, not in CI, it checks a clean tree, a version npm does not have
and the owner's npm login, runs `bun check`, builds every target in
`scripts/targets.ts`, signs the two macOS binaries with the team's
Developer ID (hardened runtime, `allow-jit` alone), self-tests them,
notarises them as one zip, lays out and packs the five packages, installs
the tarballs and checks the installed copies, then publishes the platform
packages and `@chorded/chord` last, resuming a run stopped between
publishes. `--dry-run` stops before publishing. The Linux binaries are not
signed: there is nothing to sign them with. CI keeps running the checks.

- **The native libraries a binary embeds are signed by the team (owner).**
  A compiled chord writes OpenTUI's renderer and the clipboard's addon to a
  temporary file and loads them from there, and the hardened runtime loads
  only a library signed by the binary's own team: with `allow-jit` alone, as
  board ships, the window does not start ("mapping process and mapped file
  have different Team IDs"). The owner chose re-signing every macOS
  `.dylib` and `.node` in `node_modules` before the build
  (`scripts/release/natives.sh`) over the
  `com.apple.security.cs.disable-library-validation` entitlement, which
  works too but lets any library into the process. Each is signed as a copy
  renamed over the original, so a chord running from source keeps the one
  it mapped. The self-test opens the window and reads the clipboard on each
  signed binary, so a library the list misses fails the release.
- **`chord upgrade` is cliffy's `UpgradeCommand`** (`@cliffy/upgrade`'s npm
  provider, `standalone: false`) over the package manager that installed
  the running binary, read off its real path as board reads its own: npm,
  bun, pnpm or yarn, each installing the exact version globally, and a
  refusal naming each manager's command where none is identified (a build
  from source, a copy, npx, bunx). The provider never reaches the registry
  for help or `--version`.
- **The npm shim forwards signals** (board's): `spawn` rather than
  `spawnSync`, SIGINT, SIGTERM and SIGHUP passed to the binary and its own
  signal raised again, so a SIGTERM to the shim does not leave chord running.
- **The version starts at 0.54.0** (owner).
- **Notarisation is checked against Apple's log, by cdhash** (owner): each
  macOS binary's cdhash must be one the accepted submission's log lists a
  ticket for. codesign's `=notarized` requirement, board's check, asks this
  Mac's view of Apple's ticket service, which said no for about 8 minutes
  after 0.54.0's binaries were accepted and their tickets were online, and
  stopped the dry run.
- **`@chorded/chord` is published only once every platform package answers
  `npm view` at the version** (CHD-388, board's fix for its 1.0.0). npm can
  hold a package it accepted in validation for minutes, and treats a
  missing exact-version optional dependency as no error: a main package
  published in that window installs with no binary, and `chord upgrade`,
  which prunes the old platform package, leaves a `chord` that cannot run
  and so cannot upgrade itself. The fix is in the release, not in `chord
  upgrade`: after the four platform packages, on a fresh run and a resumed
  one, each is asked up to 60 times 15 s apart, each miss said on stderr; a
  timeout stops before the main package and names the one that did not
  answer, and a rerun resumes from there. The bound is a guess: how long
  validation takes is not known. Any npm failure other than a 404 still
  stops at once. `tests/scripts/release_test.ts` runs the resume path with
  npm, sleep and plutil faked on PATH; the fresh path builds everything, so
  it shares the same `publish_missing` untested.

### CHD-395 — The local dev CLI (owner, 2026-10-16)

`bun dev <command>` is one local CLI on `@cliffy/command`, declared in
`scripts/dev.ts`, with modules under `scripts/dev/`. Its commands are
`release`, `selftest <binary>`, `compile` (`--all` or `--install`), `npm`,
`registry`, `mark`, `screenshots [names…]` and `memory [options]`. The old
package.json scripts and shell scripts are removed, with no aliases or
shims. The release stages are `install`, `check`, `natives`, `compile`,
`sign`, `selftest`, `notarise`, `pack` and `publish`, in that order.

- **Stages can be selected.** `--skip` and `--only` take comma-separated
  stages; `--from` and `--to` bound the run. `--only` conflicts with those
  three. Any stage may be skipped, checks included, on a real release too.
  `--package` limits publishing to one package. `--dry-run` excludes
  publishing, still submits to Apple unless `--skip notarise` is given,
  and refuses `--only publish` and `--package`. A stopped publish resumes
  from the existing tarballs without rebuilding; a dry run or a run without
  `publish` refuses that resume.
- **Preflight always runs.** It checks the clean tree (untracked files
  included), package.json's version, whether npm already has it, and
  `npm whoami`. Only a run including `publish` requires `main` equal to
  fetched `origin/main` and no `v<version>` tag locally or on origin.
  A run including `natives`, `sign` or `notarise` checks for an arm64 Mac
  first. The signing identity and Apple's notary credentials are checked
  before building when their stages are selected.
- **Packed bytes are the published bytes.** `pack` records `SHA256SUMS`
  beside the tarballs in `dist/release/tgz/`; each tarball must match before
  it is published, including one packed by an earlier dry run. Publishing
  does not require self-test, signing and notarisation in the same run.
- **The owner authorises npm at the keyboard.** Before the first publish,
  the CLI requires a terminal and says npm will ask. Each `npm publish`
  inherits stdin, stdout and stderr, with no spinner, and is waited on as
  long as the owner takes. With npm 11.6.2, authorisation is per publish
  process when the registry challenges it; the announced five-minute
  remember-me window is unconfirmed. Staged publishing stays out.
- **The tag follows npm visibility.** Already published versions are
  skipped. `@chorded/chord` still waits for all four platform packages at
  the version. Once all five answer `npm view`, the CLI creates the
  annotated tag with `git tag -a v<version> -m "chord v<version>"` and pushes
  it to origin. A single-package run leaves tagging to a later run while
  any package is missing. If the main package was published but does not
  answer in time, the CLI stops with the manual tagging command.

## 2026-10-14 — The working line in Chorded's colours (owner)

The accent and the working line's spinner were Claude Code's: its orange
(`#d77757`, `#b9532f` on light) and cli-spinners' `star`. The owner chose
Chorded's own: the accent is the mark's mint (`#47e7a5` on dark, `#147d55`
on light, the mark's middle stops), and the spinner is three `›`, the
mark's shape, with its light colour running along them on its dark one
every 140 ms, then a rest (`status.ts`'s `spinnerMarks`). On the
16-colour theme, whose mark has no gradient, they take its one tone and
all but the lit one are dim. A running call's `⏺` blinks in the accent,
now close to a finished one's green; the blink tells them apart.

## 2026-10-15 — CHD-1: the question box's steps and window are chord's own (owner)

The question box (layout A) draws a row of steps and one question's
options with their descriptions, bounded to the rows the window leaves it.
OpenTUI 0.6.0 has a widget for each, and each was tried before chord's own
were kept:

- **`<tab-select>` for the steps.** Every tab is one fixed `tabWidth`, so a
  longer header is cut (`* ◉ Next st…`); it draws an underline row under
  the selected tab; a tab's name is one plain string in one colour, so the
  `*` in `warning`, the `◉` in `permission` and the `✔` in `success` cannot
  sit in one chip; and the selection is its own background, moved by its
  own ← and → while it is focused. Layout A's row cannot be drawn with it,
  so the steps are one `<text>` of spans, and ← → and Tab are the box's.
- **`<scrollbox>` for the options.** It bounds the box, and
  `scrollChildIntoView` keeps the `❯` row in view without taking the keys.
  But `maxHeight` does not shrink for short content, so the box would set
  its height itself; `scrollChildIntoView` does nothing before the frame
  is laid out; it scrolls by line, so the top edge can start inside an
  option, its description without its title; and it has no count of what
  is cut off, only its scrollbar. The owner chose whole rows and `↑ N more`
  / `↓ N more` (`windowOf` in `dialogs/questions.ts`), with a description
  too tall for the box cut to the room left and ended in `…`.
- **The option list** is the pickers' numbered list on `<box>`, as "OpenTUI
  part 2: The pickers" settled against `<select>`.

## 2026-10-15 — CHD-172: chord's selection is OpenTUI's, as it is (owner)

With the mouse read (CHD-31), a plain drag selected nothing, and chord drew
nothing: every text was `selectable: false` ("OpenTUI part 5", The drag).
Claude Code draws its own selection and copies it, and the owner asked for
the same (`docs/design/CHD-172.md`).

- **Options.** (a) OpenTUI 0.6.0's own selection: the renderer's
  `Selection`, `selectable` and `selectionBg` per text and on the textarea,
  and `getSelectedText()`. (b) A selection of chord's own over the cells
  it draws. (c) Keep the terminal's bypass modifier and a better hint.
- **Tried.** (a) ran in scratch copies of the tree on the fake agent,
  through tmux and through `harness.tsx`
  (`docs/design/evidence/CHD-172/drafts/`). It paints `48;5;66` exactly,
  live, and gives a word on a double click and a line on a triple. It
  costs nothing per frame. It holds its anchor relative to the
  renderable and its focus on a screen cell, so a scroll or a box growing
  below carries the highlight with its text. It joins its own soft wraps.
  It glues two renderables on one row with no gap, copies chord's own
  markdown wrapping as the screen's rows, and turns default-foreground
  text black when no `selectionBg` is given.
- **Choice: (a), as it is.** What the agent or the person wrote is
  selectable. chord's furniture (gutters, the mark, diff line numbers,
  the fold marker, borders, the status line, lists, boxes) is not, which
  is also what keeps the glue out of a copy. A `selection` palette role
  gives every theme a colour: 66 on dark, 152 on light, and a slate
  under `NO_COLOR` and the 16-colour theme too (owner, 2026-10-15).
- **Consequences.** A reply copies with chord's wrapping, borders and
  indents. The owner took that as it is (2026-10-15) and filed CHD-396 for
  letting OpenTUI wrap replies; unwrapping the copied text in chord would
  rewrite the library's output. The draft is selectable. A key or a paste
  clears the selection through `renderer.clearSelection()` before the
  textarea hears it, so OpenTUI's editor never replaces selected text, and
  the textarea's shift+←/→ selection is off (owner, 2026-10-15). Content
  changing inside a selected text keeps the cells and changes what they
  hold. chord neither re-anchors nor clears on it, and a copy copies what
  is highlighted at the moment of the copy, except where nothing at all is
  left selected, which clears it (the lifecycle entry below, owner,
  2026-10-15).

## 2026-10-15 — CHD-172: the mouse modes are 1000, 1002 and 1006

CHD-31 asked for 1000 and said the selection task would move to 1002.
OpenTUI's renderer already writes `?1000h ?1002h ?1003h ?1006h`, with
`enableMouseMovement` at its default.

- **Options.** Keep 1003, or set `enableMouseMovement: false`, OpenTUI's
  documented option, for `?1000h ?1002h ?1006h`.
- **Choice: `enableMouseMovement: false`.** Nothing in chord reads hover
  motion. A hover report cost about 15 µs and no frame, so this is
  tidiness, not speed. A drag reports motion under 1002, which is all a
  selection needs. `"mouse": false` still writes no mode.

## 2026-10-15 — CHD-172: the copy goes through OpenTUI's clipboard service (owner)

The task asked for "OSC 52, pbcopy where OSC 52 is refused".

- **Tried.** OpenTUI 0.6.0's `createHostClipboard` writes the system
  clipboard through `libopentui`: NSPasteboard on macOS, X11 and Wayland
  on Linux. It worked from source, compiled, and inside tmux, with a typed
  result, a timeout and an abort. `createRendererClipboardAdapter` writes
  OSC 52 and can only say `attempted`. A terminal that drops OSC 52
  answers nothing, so a refusal is never seen. `createClipboard` puts the
  two together, with a policy per write. `@mariozechner/clipboard`'s
  `setText` and `pbcopy` both worked. Inside tmux, OpenTUI's OSC 52 is
  wrapped in DCS passthrough, which tmux drops unless `allow-passthrough`
  is on.
- **Options.** (a) `best-available`: the host locally, OSC 52 when the host
  fails or is unsupported, OSC 52 alone over SSH. (b) `all-available`:
  both locally. (c) OSC 52 only.
- **Choice: (a)** (owner, 2026-10-15). The task's order cannot be built,
  because no refusal is seen, so the owner changed it to fit the library.
  There is no pbcopy: OpenTUI's native write does the same in process,
  on Linux too. `@mariozechner/clipboard` stays for ctrl+v's images.
- **The note.** `copied N chars to clipboard` when the host wrote it.
  `sent N chars to the terminal's clipboard` when only OSC 52 went,
  because nobody can know it arrived (owner, 2026-10-15). N counts
  graphemes. A failure says `could not copy: <reason> · ctrl + c to try
  again` and keeps the selection.
- **Kept as OpenTUI does.** There is no OSC 52 after a host timeout, and no
  OSC 52 cap of chord's own; the service's 8 MiB bound stands.
- **Consequences.** `main.tsx` builds the service with the host's
  `timeoutMs` (1,000 ms, chord's constant) and hands `App` one `copy(text,
  signal)` prop. A generation and a bound of chord's (`timeoutMs + 200`)
  drop superseded and late results. Disposal on the renderer's `destroy`
  is raced against 100 ms, and quit never waits on a copy. A host that
  ignores the abort leaves `dispose()` pending for ever. Tests get the prop
  only, and a guard test fails on `createHostClipboard` or `pbcopy` under
  `tests/`: `testRender`'s renderer is local, so a test that built the real
  service would write the person's clipboard. A spike in this design did
  that once, and lost an image the owner had copied. Whether a Linux
  clipboard survives chord's exit without a clipboard manager is
  unverified.

## 2026-10-15 — CHD-172: `copyOnSelect` and the copy key (owner)

- **The setting.** `copyOnSelect`, boolean, default `true`, user's file
  only, read at start, as Claude Code names it (owner, 2026-10-15). The
  file is its only toggle: Claude Code's note says `disable auto-copy in
  /config`, but chord's `/config` lists the agent's options, so the note
  names nothing. A `/vim`-like command and chord's own rows in `/config`
  were the other options.
- **The key.** cmd+c never reaches a terminal program on macOS.
  ctrl+shift+c arrives as ctrl+c without the kitty protocol, and several
  Linux terminals keep it for their own copy. The options were ctrl+c while
  a selection is shown, ctrl+shift+c alone, and a leader key. The owner
  chose (2026-10-15) ctrl+c while a selection is shown, as a widget key
  (ctrl+c stays reserved), plus a rebindable `selection:copy` on
  ctrl+shift+c, in a new `Selection` context heard before every other.
  With a selection shown, ctrl+c copies even with a permission or a form
  open, and the highlight is what says so. A chord's first key keeps the
  selection, so a rebound `ctrl+x y` copies. Every other key clears it
  first and then does what it does, Esc included.
- **The panel.** `ctrl + c to copy`, computed with `keys.ts`'s own layout:
  2 × 20 at 80 columns and 3 × 14 at 120 for the default and any single
  rebound key or chord. The entry names only the first bound key, as two
  long ones drop 80 columns to one column of 40 rows. The bypass modifier
  gets no line (a 21st row at 80×24). `selectHint` and its timer go, and
  the README and the guide keep the modifier.

## 2026-10-15 — CHD-172: a selection's lifecycle, through public API (owner)

OpenTUI emits `selection` only when a drag finishes. It emits nothing at
the start, nothing when it clears a selection itself (a press elsewhere, a
textarea edit), and nothing when a selected renderable goes. Wrapping the
renderer's methods to invent those events was ruled out.

- **Choice.** chord reads the start from its own `onMouse` press
  (`getSelection()?.isStart`), the end from the `selection` event, and
  OpenTUI's own clears from `renderer.hasSelection` on the renderer's
  `frame` event. That last one is seen one frame late, which is accepted.
  chord's own clears (a tab switch, `/clear`, ctrl+o, a resize, a key)
  call `clearSelection()` themselves. A window test with a stubbed copy
  proves the mapping (`spike-runtime-lifecycle.txt`). An event on a clear,
  asked for upstream in
  [opentui#1685](https://github.com/anomalyco/opentui/issues/1685), would
  replace the `frame` read once OpenTUI has it.
- **The view.** Following stops at the press and comes back at the release
  unless the person scrolled during the drag. A wheel step during a drag
  extends the selection (`requestSelectionUpdate()`). There is no
  autoscroll at the edges: OpenTUI has it only in `<scrollbox>`, which
  chord does not use ("OpenTUI part 4"), and doing it in chord would be
  writing around the library (owner, 2026-10-15). Plain scrolling keeps a
  selection.
- **How long it lives.** A selection stays until a key, a click, a new
  drag, a tab switch, `/clear`, ctrl+o, a resize or the copy key's copy,
  with `copyOnSelect` on or off; on, the copied note goes after 3 s and
  the highlight stays, as Claude Code's does, with `ctrl + c to copy` in
  the note's place. The owner first chose that the highlight go with the
  note, then revised it (2026-10-15): a selection that vanishes by itself
  reads as a fault, and what it holds is bounded by the next key or click.
- **A selection of nothing.** A selected text unmounted outside the held
  window, such as a plan step the agent drops, leaves OpenTUI holding a
  selection with no text: `hasSelection` stays true. chord would go on
  saying `ctrl + c to copy`, and ctrl+c would copy nothing instead of
  stopping the turn. The owner chose (2026-10-15) to clear it: while a
  selection is shown, the `frame` watcher also reads
  `getSelection()?.getSelectedText()`, and when it is empty calls
  `clearSelection()` and goes to none. Leaving it, or only letting ctrl+c
  fall through, were the other options.
- **The draft's cursor after a drag.** A drag over the draft leaves the
  textarea's cursor where OpenTUI puts it, on the drag's last cell, so a
  key typed after a left-to-right drag goes in before the last highlighted
  character. chord takes that as it is (owner, 2026-10-15); moving the
  cursor itself would write around the library. Asked upstream in
  [opentui#1686](https://github.com/anomalyco/opentui/issues/1686).
- **What it holds.** While a selection is shown, the transcript's mounted
  window is held, as CHD-327 D holds it while scrolled back, so a
  selection is not emptied by its entry leaving the tail. Each entry that
  arrives meanwhile costs about six renderables and 50 KB of heap: 3,645
  renderables and 58 MB after 600 entries, against 257 and 34 MB on the
  tail. The owner chose (2026-10-15) no limit: a shown selection holds the
  mounted entries until it is cleared, as scrolling back does, with
  `copyOnSelect` on as well since the owner's revision of 2026-10-15: the
  next key or click clears it. A cap that clears the selection past some
  number of entries, and no hold after the release, were the other
  options.

## 2026-10-16 — AGENTS.md replaces CLAUDE.md (CHD-400)

`CLAUDE.md` had grown to 1,174 lines, 1,030 of them Layout, and its map of
the code was out of step. `AGENTS.md` now holds the binding guidance for
people and coding agents: the one rule, commands, conventions and checks.
Folder `AGENTS.md` files keep the rules that belong to `src/`,
`src/platform/`, `src/session/` (also covering `src/acp/`), `src/ui/`,
`tests/` and `scripts/`. The fake agent's scenario catalogue moves unchanged
to `tests/fixtures/fake_agent/AGENTS.md`; the rest of Layout is dropped.

- **Codex.** [Instruction discovery](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
  reads one file per directory, preferring `AGENTS.override.md` to
  `AGENTS.md`, from the project root down to the working directory, root
  first. It reads nothing below that directory. `project_doc_max_bytes`
  bounds the total (32 KiB by default; the root file is about 8 KB). The
  root therefore tells agents to read the rules for the folder they change.
- **Claude Code.** From v2.1.277, its built-in plugin reads every `AGENTS.md`
  from the working directory up at start and expands `@imports`, only when
  no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` is in that
  directory or above. A user-level `CLAUDE.md` does not block it.
  `CLAUDE.md` is removed so that fallback applies. A nested `AGENTS.md`
  loads only when the Read tool reads a file in its folder, and only if
  that folder has no `CLAUDE.md`; unlike a nested `CLAUDE.md`, edits and
  writes do not load it ([memory docs](https://code.claude.com/docs/en/memory)).
- **When support is unavailable.** Before v2.1.277, with the plugin
  disabled, sometimes in the first session after an upgrade, and before
  v2.1.281 on Bedrock or with telemetry off, Claude Code reads `CLAUDE.md`
  alone. The memory docs prescribe a `CLAUDE.md` with `@AGENTS.md`, or a
  symlink. Neither is added: removing `CLAUDE.md` is the owner's choice.
- **Claude Code subagents.** They inherit the main session's instruction
  files, `AGENTS.md` included. The built-in Explore and Plan agents, and
  a subagent defined with `omitClaudeMd`, start without them
  ([subagent startup](https://code.claude.com/docs/en/sub-agents)).
- **chord's agents.** The pinned `claude-agent-acp` 0.87.0 starts Claude
  with `settingSources` user, project and local; chord overrides none.
  `codex-acp` starts Codex core in the session's directory for its own
  discovery. Tabs, `spawn_task` tasks, `open_agent` children, team leads
  and members all get the tab's directory in `session/new`, so each
  discovers the same instruction chain. chord relies on each adapter for
  project-instruction discovery; team prompts also tell agents to read
  `AGENTS.md`.

## 2026-10-16 — CHD-395: the release runs npm on node, past Bun's (owner)

`bunfig.toml`'s `[run] bun = true` makes every package.json script run on
Bun even where a bin asks for node: under `bun run`, Bun puts a `node` that
is itself first on PATH, and every child's `#!/usr/bin/env node` finds it.
`bun dev release` is such a script, so its npm ran on Bun. npm 11.6.2
fails there: the dry run's pack stage stopped at the scratch `npm init -y`
with `mod.require is not a function`, and npm's log showed Bun as its
runtime. `scripts/release.sh`, started by bash, had run npm on the user's
node. Bun 1.4.3 has `--bun` to force the shim, and no flag that turns it off
for a single script.

The options put to the owner:

- **(a)** The CLI strips Bun's node-symlink directory from PATH for its
  child processes, so npm finds the user's node as `release.sh`'s did. This
  edits the environment Bun set up, which is a workaround.
- **(b)** The entry point is `bun scripts/dev.ts <command>`, not a
  package.json script: a file run directly gets no node shim. This uses Bun
  as it is, but changes the agreed `bun dev` shape.
- **(c)** Turn off `[run] bun = true`. Every package.json script (tsc,
  eslint, prettier) would then run on the user's node, against its stated
  reason.
- **(d)** The CLI runs npm as `node <npm>`, with the real node found past
  Bun's on PATH. This is (a) by other means.

The owner chose (d), consenting to it as a workaround, so that `bun dev`
stays and `bunfig.toml` is untouched. Every npm call of the release (view,
whoami, pack, init, install, publish) goes through one helper in
`scripts/dev/release/lib.ts`: it runs the first `node` on PATH whose
realpath is not Bun's own executable, on the first such `npm`'s realpath
(npm's script), and dies when either is missing.

## 2026-10-16 — The suite runs on `bun test --parallel`

`bun run test` ran every file in one process, one after another, and took
about 12 minutes: the files' times add up to some 13. Bun 1.4 has
`--parallel`, a worker process per core that takes the next file as it
finishes one, and it implies `--isolate`, so each file still starts with a
fresh global. On 12 cores the suite passes in about 72 s, four runs in a row
without a failure.

`--timings=tests/timings.json` hands the workers the slowest files first, so
a 60 s file does not start last and set the end of the run. `bun run
test:timings` rewrites the file from a run; a file it does not list is not
put first, so it is rerun after a slow file is added or split. A run on
fewer cores is bound by the total rather than by the slowest file, and
gains less.

`tests/ui/app/App_test.tsx` alone took 113 s, longer than the rest of the
suite on 12 workers. Its tests moved, unchanged, into files of 20–30 s each:
`Tasks_test.tsx`, `Held_test.tsx`, `Selection_test.tsx` and
`SelectionEdges_test.tsx`, with the selection tests' helpers in
`selecting.ts`. The fixed waits the window tests take (`settle`'s 50 ms
after each key, `asked`'s 150 ms) are the next cost, and are left as they
are.

CHD-513 (the owner, 2026-10-23) removed the timing gate CHD-501 put on
whole runs, a file over 90 s or slower than its record failing the run,
and with it keeping the record current as anyone's duty: `bun dev test`
answers the tests' status alone, and CI runs the suite in three
`--shard`s. `tests/timings.json` stays only to place files: Bun's
`--parallel` starts each worker's slowest files first by it, and
`--shard` cuts the shards by its times, taking a file it does not list
at the median.

## CHD-411 — package.json keeps only dev (owner, 2026-10-16)

package.json's scripts keep only `dev` (`bun scripts/dev.ts`). The other
scripts became commands of the Cliffy dev CLI, in `scripts/dev.ts` with the
spawning in `scripts/dev/tools.ts`, with no aliases.

- **The names.** `bun dev chord [args…]` and `bun dev chord --fake
  [args…]` replace `chord` and `chord:fake`; `bun dev test [args…]`
  replaces `test`, and `bun dev test --update-timings` replaces
  `test:timings`, so there is no timings command; `bun dev check` and
  `bun dev check --static` replace `check` and `check:static`; `bun dev
  fmt` and `bun dev lint [args…]` replace `fmt` and `lint`.
- **`--fake` is an option** of `chord`, parsed by Cliffy, never picked out
  of argv by hand. It adds `fake --agent-command` with the fake agent in
  `tests/fixtures/fake_agent/main.ts`.
- **The rest of the arguments pass on as written, but empty words.**
  `chord`, `test` and `lint` have `.stopEarly()` and `[args...]`: Cliffy
  parses its own options until the first word or option it does not know
  and hands on the rest. Words after a literal `--` follow them, without
  the `--`, so `bun dev chord -- --help` reaches chord's own help. Cliffy
  drops an empty word before `--` and keeps one after it; the owner took
  that as it is, so an empty argument needs `--` (`bun dev test -- -t ''`),
  as the three commands' help says.
- **chord runs in a child.** The CLI spawns `bun --define
  process.env.NODE_ENV:"production" src/main.tsx`, as the script did, with
  the terminal handed over, and exits with the child's status.
- **check orchestrates in one process.** It calls tsc, ESLint, Prettier,
  `lint/`'s own test and then the suite as functions, each spawning its
  tool, and stops at the first failure with that tool's exit status. tsc,
  ESLint and Prettier are spawned as `bun run <bin>`, so they run as the
  scripts ran them, on Bun by `bunfig.toml`, also when the release's check
  stage runs `bun scripts/dev.ts check` directly.

### CHD-412 — the release takes a version or a bump (owner, 2026-10-16)

`bun dev release [version]` takes one positional: an exact version, or
`major`, `minor`, `patch` or `fix` (`patch`'s other name), parsed, compared
and bumped by the `semver` package (`scripts/dev/release/version.ts`).
Without one, the release is package.json's version, as before.

- **Only canonical release versions.** An exact version is written as
  semver writes it: no `v` or `=` prefix, no build metadata. Pre-releases
  are refused, and every version, a bump or an exact one, is refused while
  package.json's own version is a pre-release.
- **An exact version is above package.json's, or is it.** package.json's
  own version is accepted and releases it with no new commit, so a rerun
  after a failed publish can name the version that run committed.
- **A run that publishes commits and pushes first.** Preflight checks the
  new version (not on npm, not tagged, the tree clean, main level with
  origin's). Then, before any stage, the release writes the version into
  package.json, commits that file alone as `chore: chord v<version>` and
  pushes main to origin. If the push fails, the commit is dropped, the
  branch and tree left as found, and the release stops. A later failure
  leaves the pushed commit there; a rerun with no version, or with that
  one, releases package.json's, with no new commit.
- **Any other run drops its commit.** A dry run, or a run without publish,
  makes the same commit locally, runs its stages on it, and drops it at the
  end (`git reset --keep`), on a failure too, pushing nothing.
- **A new version needs the compile stage.** The version enters the binary
  at compile, so a run whose stages leave it out (`--only publish`,
  `--only check,pack,publish`, `--from pack`, `--skip compile`) would pack
  or publish what was built at package.json's version; it is refused before
  preflight. package.json's own version is fine with any stages.
- **A signal drops an unpushed commit.** While a local version commit is
  held (a dry run, a run without publish, or a real run before its push
  succeeds), SIGINT, SIGTERM and SIGHUP drop it, and the signal is raised
  again, as selftest's cleanup raises it, so selftest's own cleanup still
  runs and the release ends by the signal (130, 143 or 129 in a shell).
  Once pushed there is nothing to drop. SIGKILL cannot be
  caught: a killed run may leave the commit, dropped with
  `git reset --keep HEAD~1`, as the release's help says.
- **A stopped publish resumes package.json's version only.**

## 2026-10-20 — OpenTUI 0.6.0 → 0.6.6 (CHD-480)

`@opentui/core` and `@opentui/react` are pinned to exactly 0.6.6, for
CHD-382's `renderer.setProgramStatus` (owner, Q67). The release notes of
0.6.1 to 0.6.6 were read against chord; types, lint and the suite passed
on 0.6.6 with no change to `src/`.

### What 0.6.6 changed for chord

- **The textarea holds control characters** (0.6.1, OpenTUI #1636).
  `setText`, `insertText` and `initialValue` no longer throw for C0 but
  tab, LF and CR, or for DEL and C1; the box draws one as Vim does, `^L`
  in two cells, `<85>` in four, and gives it back as written. A paste
  keeps them too: 0.6.0's `handlePaste` dropped them
  (`unsupportedPasteCharacters` in its `Textarea.ts`), 0.6.6's strips
  only escape sequences, a lone ESC among them. Its `stripAnsiSequences`
  takes a C1 CSI, 0x9b, as a sequence's start, so a paste loses it and the
  byte after it (`c` 0x9b `d` reaches the box as `c`); chord takes that as
  it is. A DEL is kept. chord passes a paste on
  unchanged, so on 0.6.0 a pasted `\f` was gone before it reached the
  box, and on 0.6.6 it is sent.
- **CHD-323's refusal is gone** (owner, CHD-480, option 1). ctrl+g's
  editor text, and ↑, ↓ and ctrl+r's history, take a control character as
  a paste does, and chord sends what the box holds. `unholdable`, the
  status line's `The prompt cannot hold …` and the skipping in
  `history.ts` and `search.ts` were removed. Text that is not the box's
  own still gives a control character no cells, as OpenTUI's read-only
  text does: the transcript's echo of the prompt, and the match ctrl+r
  draws over the box.
- **A style prop dropped is reset** (0.6.6, OpenTUI #1678). A layout prop
  a React element no longer passes goes back to the default it has when
  never given; `visible` given `null` or `undefined` shows the node. The
  agents list's rows named `paddingLeft: 0` beside the border for a row
  that stops being last (Q41); they no longer do, and a test in
  `Agents_test.tsx` holds a row's padding and border to what it is now.
- **Combining marks** (0.6.2, OpenTUI #1651). A mark in a chunk of its
  own is drawn on the character before it; 0.6.0 drew `e` + U+0301 typed
  apart as `e`. Text typed after it goes in before the mark on 0.6.0 and
  0.6.6 alike, as a bare textarea shows (`e`, U+0301, ` y` holds `e ý`);
  0.6.6 draws what the box holds. Accepted as it is (owner).
- **Width of joined emoji typed in parts** (0.6.2, #1650): a skin tone or
  ZWJ sequence typed into the box takes its real width.
- **The last column's attributes** (0.6.2, #1652): a styled cell at a
  row's end no longer passes its attributes to the next cells drawn.
- `strip-ansi` left OpenTUI's dependencies (0.6.1); chord declares its
  own.
- Not chord's: the embedded terminal's fixes (0.6.2), `measureEditText`
  and `EditBuffer.measureText` (0.6.1, 0.6.2; chord counts no editor
  offsets from string widths), Kitty images in iTerm2 (0.6.4), the Yoga
  style getters (0.6.5), `defaultDimension` (0.6.6; chord has no custom
  renderable), and `setProgramStatus` (0.6.3), which CHD-382 takes up.

## 2026-10-20 — CHD-467: the test harness sets the terminal up before the first render (owner, Q76)

`tests/ui/harness.tsx` drew through `@opentui/react`'s `testRender`, then
called `renderer.setupTerminal()`, as `createCliRenderer` does for chord's
own window. Under load the setup failed now and then with
`ot_session_setup_terminal failed: InvalidPhase`.

- **Why.** `testRender` renders the React root before it returns, so the
  harness set the terminal up while the renderer's first frame could
  still be out: at a failing call the native terminal phase was
  Uninitialized and the renderer's scheduler `isRendering`. The native
  session refuses a setup in that phase. `createCliRenderer` sets the
  terminal up before any render.
- **Tried.** A probe drew a busy renderer and a second one beside it, 40
  times a run, under 12 busy loops and 16 copies: 3 of 320 runs failed
  before, none of 320 after.
- **Options.** (1) Build from `testRender`'s public parts,
  `createTestRenderer` and `createRoot`, in `createCliRenderer`'s order.
  (2) Wait until the renderer is idle before the setup, which an
  animating window may never be. (3) Retry the setup on InvalidPhase,
  a workaround.
- **Choice: (1)** (owner, Q76). `draw()` makes the renderer, sets the
  terminal up, then renders inside `act()`; `testRender`'s teardown, the
  root unmounted on destroy and the act environment cleared, is kept as
  it was. `testRender` itself is no longer called.

## 2026-10-20 — CHD-467: a graceful close in the test harness may take 10 s (owner, Q77)

OpenTUI's `NativeSession` cancels a graceful close after 1 s, and a test
whose close ran late failed with `NativeSession graceful close timed out`.

- **Why.** Timed under load, 6,909 closes finished: p50 47 ms, p99.9
  1,076 ms, the longest 1,464 ms. Ten finished past 1 s, as the deadline
  is checked only when the session's pump runs. The 3 that failed, of
  3,456 runs, fell in the same band, nothing pending on chord's side.
- **Options.** The session's `closeTimeoutMs` is public, but the renderer
  takes a `nativeSession` only with stdout-buffered output, which changes
  two of the plain path's defaults that public config cannot set back:
  `remote` goes from unset (the native side decides) to true, and with it
  the forwarded environment (`TERM`, `TMUX`, `COLORTERM` and the rest of
  OpenTUI's list, which it does not export) goes to none. (1) Take both.
  (2) Pass `remote: false`, which is neither the old default nor proven
  the same. (3) Revert, and ask upstream for a close timeout on the
  memory-buffered test renderer.
- **Choice: (1)** (owner, Q77). `draw()` gives its session
  `closeTimeoutMs: 10_000`, about 7× the slowest close seen to finish,
  and the plain terminal writes to a stream that keeps nothing. The
  plain path is now as the logged one already was: remote, with no
  environment of the person running the tests. chord's own window keeps
  OpenTUI's 1 s.

## 2026-10-20 — CHD-468: OpenTUI's `jsxDEV` in the binary, on React's production runtime (owner, Q75)

In the compiled binary, chord's root ErrorBoundary, OpenTUI's own, threw
while painting its fallback: `jsxDEV is not a function`, so a crash screen
crashed.

- **Why.** `@opentui/react` 0.6.6, the latest on npm, ships prebuilt JS
  that imports `jsxDEV` from `react/jsx-dev-runtime`: its ErrorBoundary's
  fallback (`chunk-cc2dg8kx.js`) and the Slot and plugin code in
  `index.js`. chord's compile defines `process.env.NODE_ENV` as
  `"production"` (CHD-344), and React 19.3's production
  `jsx-dev-runtime` exports `jsxDEV` as undefined, by design. From
  source, with no define, React's development build answers and it works.
- **Tried.** A bundle of a component that throws, built as the binary is,
  ran the fallback into `jsxDEV is not a function`; the same bundle with
  OpenTUI's import resolved to a shim paints the error's stack.
- **Options.** (1) Resolve OpenTUI's `react/jsx-dev-runtime` at compile
  time to a shim built on `react/jsx-runtime`. (2) `bun patch` OpenTUI's
  published files, redone on every bump. (3) A root boundary of chord's
  own, which leaves OpenTUI's other `jsxDEV` calls broken. (4) Drop the
  define, which brings CHD-344's memory growth back. (5) Report upstream
  and wait, with the crash screen broken meanwhile.
- **Choice: (1)** (owner, Q75). `scripts/dev/compile.ts` builds through
  `Bun.build`, as the command line takes no plugin, and its plugin
  resolves `react/jsx-dev-runtime` imported from `@opentui/` to
  `scripts/dev/jsx_dev_runtime.ts`, whose `jsxDEV` calls `jsx` or `jsxs`
  without the source and owner only the development build reads. chord's
  own imports and a run from source are unchanged. No upstream issue was
  filed. `buildOptions` is the one set of build options, which a test of
  the production build shares.

## 2026-10-21 — CHD-468: React's log of the crash screen's error is dropped by chord's `console.error` (owner, Q79, Q81, Q82)

chord's crash screen (Q78) is a boundary of its own, on
`react-error-boundary`. When it catches, React logs the error through its
caught-error callback, and `@opentui/react`'s `createRoot` hands React
`console.error`, by value, for it (`createContainer` in its chunk). chord
runs OpenTUI's console `disabled`, so the log went to stderr, which is the
window, and drew over the screen.

- **Tried, through public API, in the compiled binary with stderr on the
  terminal.** (Q79) `renderer.resize` at the current size in an effect
  after the commit, which repaints what OpenTUI drew: the log's text stayed
  in every cell OpenTUI had not drawn, and a 300 ms delay changed nothing.
  (Q81) `consoleMode = 'console-overlay'` from a layout effect, which runs
  before React logs: the overlay swaps in a new `global.console`, while
  React still holds the original `console.error`, so the log still came
  out.
- **Options left** (Q82). (1) A `console.error` of chord's, set before the
  root so React is handed it, that drops only React's one log of the error
  the boundary caught. (2) The overlay from the start, which would keep
  every library's console output from stderr. (3) Accept the log and ask
  OpenTUI upstream.
- **Choice: (1)** (owner, Q82). `render` sets `console.error` once to
  `quietCaught` (`src/ui/app/caught.ts`), wrapping the original. The
  boundary's fallback marks the error as it renders, ahead of the commit in
  which React logs, and the call whose first argument is that error, as
  React's `onCaughtError(error, info)` is, is dropped once; every other
  call, a later one of the same error among them, goes on unchanged. On a
  key the crash path writes the stack to stderr after the terminal is
  given back, as for an uncaught exception.

## 2026-10-21 — CHD-492: chord tells the terminal the session id to resume, in a user variable (owner, Q124)

Chorded (CHRD-412) wants to reopen chord after its pane ends, however it
ended. The owner's direction: chord tells the terminal the main session's
agent session id, and Chorded later runs the existing `chord --resume
<sessionId>`; no launcher-given id, no mapping file, no lock. The design is
`docs/design/CHD-492.md`; the drafts of the first of three superseded
designs are in `docs/design/evidence/CHD-492/drafts/`.

- **The carrier, tried first in OSC 7501.** The Program Status spec
  (revision 0.4) has no key for it but lets unknown `[a-z]+` keys extend
  it; OpenTUI 0.6.6's `setProgramStatus` encodes only its seven fields and
  drops others; the record `id` is a path (a UUID is over its 32-byte
  segment), `title` and `msg` are for a person, and a report of chord's own
  beside OpenTUI's would erase it. Options put to the owner (Q124): ask
  OpenTUI for extension keys, ask the spec for a key, write every report
  ourselves, another channel. **Choice: another channel** (owner).
- **The sequence.** iTerm2's `ESC ] 1337 ; SetUserVar=chord_session=<base64>
  BEL`, which WezTerm also takes; empty value for nothing to resume.
  OpenTUI has no call for it or for bytes of chord's own, so it goes through
  `useStdout` between frames, as OSC 9 and 777 do, and inside tmux through
  `throughTmux`'s DCS passthrough, which needs `allow-passthrough`. Sent in
  every terminal: one that does not know OSC 1337 ignores it, as it does
  OSC 9, 777 and 7501.
- **When.** Empty at a new session's start; the id once the first prompt is
  sent and flushed to the session record (a failed append does not hold it
  back, as `--resume` still reaches the agent); a resumed or `/resume`-picked
  session's id once open; empty on `/clear` until the new first prompt;
  until CHD-493, the front tab's. **Not cleared on exit**, signal or crash:
  reopening after the pane ends is the point. Children are not reported.
- **What Chorded does.** Keeps the last decoded value per pane and, when the
  pane ends, reopens with its own start command plus `--resume
  <sessionId>`, the same agent, as `--resume` refuses an id recorded for
  another; empty or none, starts chord again.
- **Consequences.** A session whose record is gone resumes as today: the id
  goes to the agent, which reopens it from its replay or chord draws `it
  cannot resume session <id>: …`. Several chords in one tmux share the
  outer terminal's variable, the last write winning. Nothing on screen
  changes; no key is added; no dependency.

## 2026-10-22 — CHD-487: a detail's log in OpenTUI's scrollbox, scrolled after layout

The agent's or task's log in its background detail sits in OpenTUI's
`scrollbox` with `stickyScroll` and `stickyStart: 'bottom'`, which follows
the log's end as work comes, leaves it when the person pages up, and
follows again once scrolled back to the end: the owner's Q140, as the
scrollbox does it, not as chord counts it.

A finding worth keeping: an imperative `scrollTo` issued at React's commit
is clamped against the scrollbox's layout of the frame before, and is not
applied again once the new content is laid out. Plain OpenTUI shows it
(a one-row scrollbox over growing lines, `scrollTo(last)` in an effect,
stays on the old last line); the same call from `renderAfter`, or on a
key, when the frame is laid out, lands. A first try (823babbe) read that as
the scrollbox not fitting and drew the log in a clipped box of chord's own;
it was chord's timing, and the scrollbox stays. Scroll it on the key, or
let `stickyScroll` follow, never from an effect.

**The margin trap (opentui#1739, the owner's Q141 and Q142).** In
OpenTUI 0.6.6 a `scrollbox` one row tall leaves out of its `scrollHeight` a
child's `marginTop`, and `paddingTop` too once the padded box holds a box
rather than bare text; at two rows and more it counts them. The lines past
what it counts cannot be scrolled to. chord's transcript blocks are boxes
spaced by a row of margin over a box of their own, so a detail one row tall
could not page to its log's last lines. The owner had it reported upstream
(https://github.com/anomalyco/opentui/issues/1739) and, meanwhile, the
blocks drawn inside the detail's scrollbox alone with their row of space as
an empty box of its own before each, which the scrollbox counts at every
height: `BlockGap` (`src/ui/transcript/gap.ts`), which the transcript leaves
at margins. `tests/ui/transcript/gap_test.tsx` pins OpenTUI's behaviour;
once a pinned OpenTUI counts the margin, that test fails, and `BlockGap`
and its provider go.

## 2026-10-23 — CHD-493: one main session per chord process; tabs go (owner)

The owner's call of 2026-10-21: chord drops tabs. A chord process runs one
main session with its children (long-lived agents, team members, tasks,
subagents, monitors) as today; sessions side by side are the terminal's
panes. The design is `docs/design/CHD-493.md`; the architects' drafts are in
`docs/design/evidence/CHD-493/drafts/`.

- **Options considered.** Keep tabs (the owner's call removes them); keep
  the session layer's tab list with a cap of one (dead code that every
  feature would still have to fold over); collapse the state to one main
  session and its children. **Choice: collapse.** The window becomes what
  chord with one tab already is: the strip, `ctrl+x c n p 1–9 w k`, the
  sessions picker, `/new` as a tab, the tenth-session refusal, `ctrl+x k`'s
  and ctrl+d's arming over tabs, `/status`'s `Sessions` row, the tab level
  of `/cost`, tab words in notices and notifications, `list_sessions`'
  `tab`, window records and `--resume` of several ids go.
- **The main conversation is never replaced.** `/clear` and a `/resume`
  pick already replace the session inside one `Conversation` (`clear()`),
  dropping a let-go session's late updates and handing the record over;
  the main session keeps one key for the process. `tabs.ts` splits into
  `waits.ts` (the per-agent wait fold) and `window_agents.ts` (main and
  children, picking, attention); `open_sessions.ts` becomes
  `open_agents.ts`. Keys, not places, still name an agent.
- **What holds.** `ctrl+x a` (`session:attention`), now over main and its
  children, with its walk, its remembered place and its key; the agents
  list and its keys; `/resume` never loading a session twice (a session
  open as a child is marked `open now` and picked); OSC 7501's fold over
  main and children, byte for byte today's one-tab record; `chord_session`
  as the main session's id; `startupOf` for children's runtimes.
- **Consequences.** Several sessions are several processes, so nothing
  stops two panes opening one session (Q156; documented, on the
  recommended option). A codex session from a window started as `chord
  claude` is reached from `chord codex`'s `/resume` or its command. Session
  records are unchanged; no format changes.
- **Libraries.** None added or dropped: everything removed was chord's
  own, and nothing new is drawn.

This overturns, in whole or in the parts named in the design: 2026-10-06
"Several sessions in one window are chord's to build"; "Several sessions: a
tab list of chord's own, each tab its own `Conversation`"; "Several
sessions: the strip, the leader line and the `session:` keys"; "Several
sessions: a session behind that needs the person"; 2026-10-07 "Several
sessions: closing one, and quitting with several open"; "M4: agents start
agents through an MCP server chord serves" (its tab-labelled senders and
behind marks); 2026-10-08 "The sessions picker, and `/resume` knowing the
open sessions"; "`/new <agent>`, each agent's starting values, and
`/status`'s sessions"; "`-r <id> -r <id> …`: a tab each, each in its own
place"; "Long-lived agents: a list under the prompt, picked as a tab is"
(only its comparison to a tab); "chord's MCP server: @modelcontextprotocol/sdk
1.32.1 on `Deno.serve`, a token per session, tools by role" (a token names
the session, not a tab); "A window record, and `--resume w-…`"; "Windows in
`/resume`, and `--resume` with no id" (the window rows; `[id:string]` and its
accepted Cliffy limit hold); 2026-10-09 "`/team`: the picker, show, run and
stop" ("the front tab's `main`" reads `main`); 2026-10-13 "CHD-355: the
person's own sessions start on an effort from the files or `--effort`" ("each
`/new`" reads main, each `/clear`, `-p`); 2026-10-21 "CHD-492: chord tells
the terminal the session id to resume, in a user variable (owner, Q124)"
(the clause "until CHD-493, the front tab's"). What holds of each is in the
design and the drafts.

## 2026-10-23 — CHD-493: `/new` is `/clear`'s alias (pending the owner, Q153)

- **Options considered.** `/new` as `/clear`'s alias, `/new <agent>`
  refused (Claude Code 2.1.307's menu lists `/clear (new)`); remove `/new`,
  which lets an agent's own advertised `/new` through to the agent;
  `/new <agent>` switching the main agent in place, which would replace the
  main conversation and make header, `/resume`'s list, the quit's command,
  OSC 7501 and the token follow a changing agent.
- **Choice, pending Q153: the alias.** `/clear`'s entry gets one `alias`,
  which takes a chord command name everywhere a name does: the collision
  set (an agent's `new` stays out of the menu), fzf's filter (a second
  selector key), Tab completion and dispatch. `/new codex` is refused
  without clearing: `/new starts a new fake session here; for codex, run
  chord codex in another pane`.
- **Consequences.** One meaning, Claude Code's; another agent is another
  pane. Under another answer, U2's `/new` rows change, and under the switch
  U3 keeps a path that replaces the main conversation.

## 2026-10-23 — CHD-493: old window records are read only to refuse, with each session's command (pending the owner, Q154)

People have `windows/w-<id>.json` from 0.54.0–0.57.0 and printed `chord
--resume w-…` commands.

- **Options considered.** Refuse and print each session's command; open the
  recorded front tab's session and list the rest (chord choosing one of
  several, the guess turned down for `-r` before); forget windows (an old
  printed command then means nothing).
- **Choice, pending Q154: refuse.** `windowGone(record)` prints, before the
  screen, `w-… was a window of N sessions; chord opens one session per run
  now. Resume each with:` and one `chord <agent> --cwd <dir> --resume <id>`
  per tab in order, a tab whose session record is gone included (the agent
  may still have it). The tab's directory goes in `--cwd`, as an id chord
  has no record of otherwise opens where the command is typed;
  `resumeCommand` gains an optional `cwd`, quoted by `shellQuote`.
  `windows.ts` keeps only the reader: id, schema, `parseWindow`,
  `readWindow`, `windowGone`.
- **The files are left alone** under every answer: never written, listed,
  rewritten or deleted again; read only when `--resume` names one.

## 2026-10-23 — CHD-493: `--resume` with several ids is refused in chord's words

- **Options considered.** Drop Cliffy's `collect`, so Cliffy refuses a
  repeated option with its generic error; keep `collect` and refuse what it
  hands over; open the first id (a guess).
- **Choice: keep `collect`, refuse.** Before any terminal or agent:
  `--resume opens one session; it was given N. Open each in a chord of its
  own:` and one line per id with its record's agent and directory, so a
  mixed-agent call gets commands that work; an id chord has no record of
  takes this command's agent and directory and says so. Cliffy is used as
  it is; no argv is rewritten.

## 2026-10-23 — CHD-493: a keybinding of a removed `session:` action is ignored with its own words

- **Options considered.** Today's generic `unknown action "session:new",
  ignored`; words that say why; refusing the file.
- **Choice: its own words.** `bindings.ts` keeps a `REMOVED` list of the
  eleven names (`session:new`, `next`, `previous`, `goto1`–`9`, `list`,
  `close`), read before `isAction`: `session:new went with tabs: chord runs
  one session, ignored`, where keybinding problems are said today. The rest
  of the file applies; nothing in it is rewritten; `null` on a key one of
  them held is no problem.

## 2026-10-23 — CHD-493: `list_sessions` stays, with one row and no `tab`

- **Options considered.** Remove the tool (it changes every session's tool
  set, and old records' answers must still draw); keep it with one row.
- **Choice: keep it.** It answers the caller's main session, its id,
  runtime, model and long-lived agents, which is how an agent finds its
  children again after a compaction and what chord's refusals point to.
  `tab` goes from the answer; the transcript row draws the runtime with
  `(you)` and ignores `tab` in an answer a 0.57.0 record kept.

## 2026-10-23 — CHD-493: a let-go session's MCP calls (pending the owner, Q158)

Found in review, not caused by removing tabs: between `/clear` or a
`/resume` pick and the let-go session's exit, its token stays admitted
under the main key, so a late `open_agent`, `spawn_task`, `send_message`,
`close_agent`, `run_team` or `monitor` acts on the replacement's children
and permission box. Today it happens inside a tab; without tabs these are
the only replacements.

- **Options considered.** Fix it in CHD-493's last unit; leave it as today
  (the owner takes no follow-up tasks).
- **Choice, pending Q158: fix it.** The caller names its session, not only
  the slot: a generation carried in `Caller` when the token is minted,
  checked by `WindowView`, a stale caller refused with `The session that
  called this has been replaced.`; or the token revoked at `clear()`.
  Tested on the fake agent.

## 2026-10-25 — CHD-394: a code box's buttons are texts of their own on its top border (owner)

The design (`docs/design/CHD-394.md` §1) puts `[copy]` and, on `sh` and
`bash` blocks, `[run]` on the right end of a code box's top border, in the
text's colour, the language label staying dim on the left; each button is
a press-and-release target. OpenTUI 0.6.6's `<box>` draws one top `title`
with one `titleAlignment` and one `titleColor`, and a `bottomTitle`: it
cannot hold a label on the left and buttons on the right in another colour,
nor tell which word a press landed on.

- **Options considered.** Each button its own `<text>`, placed absolutely
  on the box's top row and right-aligned, with its own colour and mouse
  handlers, the label staying the box's title, as `Reply.tsx` already
  places a list item's marker; chord drawing the top row itself, the box
  bordered on three sides; changing the design to fit the box (the buttons
  in `bottomTitle`, in one colour, or in the title in place of the label);
  asking OpenTUI for titles in several parts, and waiting.
- **Choice (the owner): texts of their own.** OpenTUI still draws the
  border and the label; each button is an OpenTUI text with its own
  handlers, so a click is OpenTUI's own mouse event on it.
- **Found building it: no blank cell beside a button.** OpenTUI draws a
  space on a transparent background by blending it over the cell below,
  which keeps the border's `─`; chord knows the terminal's background only
  as dark or light, not its colour, so an opaque space would be a patch of
  the wrong colour. Weighed: the `─` kept beside the buttons; an opaque
  space in a theme colour; chord drawing the top row after all; asking
  OpenTUI for an opaque default background. **The owner kept the `─`:**
  `┌─ sh ─[copy]─[run]─┐`, a `─` between the words and before the corner,
  which also makes each least width two cells narrower.

## 2026-10-27 — CHD-533: official resource collectors and per-run team selection (owner, Q251/Q252)

The owner approved option 1 of Q251 and Q252 for package `6461ce56` in
[the CHD-533 design](design/CHD-533.md). Chord collects advisory resource
facts; the launching agent chooses a supported composition for one run.
Saved teams and running work stay unchanged. Q250 remains retired; no
payment-source or paid-fallback framework is authorized. API money
accounting is a separate advisory follow-up, not a subscription-routing gate.

- **Libraries tried and selected.** Official Codex app-server and Claude SDK
  no-prompt trials returned structured usage; unchanged-library host fake
  trials tested compile and lifecycle behavior. Select exact
  `codex-app-server-client@0.1.5` public `StdioTransport`/`AppServerClient`
  exports on existing `spawnGroup`, and official
  `@anthropic-ai/claude-agent-sdk@0.3.311`'s experimental usage getter in a
  same-binary isolated worker. Retain existing ACP/MCP SDKs, Zod and OpenTUI.
  CodexBar's reusable API loses quota-map buckets; cliMeter and the VS Code
  extension have no standalone fitting collector; Roost requires excluded
  credential access. Generic JSON-RPC clients do not fit Codex's framing
  unchanged. The managed Codex close trial failed descendant cleanup;
  the public-stream path passed host fake characterization without a patch.
- **Exact deployment and accepted risks.** Use separately installed,
  unmodified native Codex 0.163.0 and Claude Code 2.1.311 with the current
  user's existing authentication. No provider install, extraction, new login
  or direct credential access. Q251 accepts experimental compatibility and
  routine managed startup/auth/cache/hooks/telemetry effects. Q252 accepts
  Chord-owned stdin/signals/bounded waits and isolated-worker group
  supervision, plus uncapped incomplete-frame buffering. Deadlines do not
  cap memory. Host fixtures establish neither full Chord release fit nor
  cross-target lifecycle, freshness, identity or zero billing.
- **Terms evidence.** The
  [official legal guidance](https://code.claude.com/docs/en/legal-and-compliance)
  expressly allows an end user's own subscription authentication through an
  unmodified Claude Code binary and restricts credential intermediation.
  [SDK plan guidance](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan),
  updated October 7, 2026, retains subscription limits for plan-authenticated
  SDK use. This is no blanket SDK subscription prohibition, telemetry-specific
  provider guarantee or legal certainty.
- **Alternatives and boundary.** Upstream lifecycle/frame bounds, another
  maintained fitting client, or reduced passive/legacy coverage were the
  alternatives; reduced coverage leaves the automatic telemetry goal
  incomplete. Approval covers only the specified public APIs and ownership.
  No parser/input rewrite, tag insertion, SDK patch, custom lifecycle repair,
  scheduler, migration or saved-team rewrite is authorized. A new library
  mismatch returns to the owner with options; these trials and approvals
  are not consent to future workarounds.

## 2026-10-27 — CHD-533: the official Codex npm launcher is supported (owner)

The owner approves the installed, unmodified official PATH Codex npm launcher
or native binary for the resource collector. The successful live Codex trial
invoked the PATH npm launcher, not a directly verified native binary; the
previous native-only deployment description was incorrect. Existing Node is
required only for official npm launcher installs. Claude remains an external
native executable. The prior live trial is sufficient; no repeat is required.

This corrects the earlier CHD-533 deployment decision without authorizing a
private vendor-layout resolver, launcher patch, installation or authentication
change. Keep the public-stream API, process-group ownership, experimental
Claude API and uncapped-frame-buffer risk as approved. Deadlines do not cap
memory. Existing trial, freshness, identity, billing and cross-target evidence
limits remain unchanged.

## 2026-10-27 — CHD-533: MCP-first selection; remove the unrequested choose surface (owner)

The owner removes `/team choose` completely. It was unnecessary for the
MCP-first goal: the launching agent reads existing team instructions, reads
resource facts when relevant, and calls normal `run_team` with supported
per-run overrides. Without such instructions, selection is not required;
human direct runs and picker Enter keep saved composition with no extra
main turn. No replacement command, flag, hidden prompt, opt-in or team schema.

The bounded audit found that optional MCP selection already worked, but
`list_teams` omitted shared body, lead/member instructions and effort, and
`run_team` help/schema descriptions omitted selection semantics. Expose those
stored fields additively through the existing tool and describe inheritance
and runtime switches there, without interpreting or enforcing prose.

Add optional `agents: string[]` to existing `get_budgets`, using existing
runtime IDs (at most 128, each 1–128 characters). Omission preserves current
facts; an explicit empty list adds no interest and returns empty runtime-scoped
facts, never all providers. The launching agent discovers saved
composition/instructions, extracts runtimes and requests facts. No team-name
argument, team-keyed lease or team-budget API. Explicit filters return matching
runtime observations, unavailable entries and active work while preserving
shared-pool identity, global preferences and coverage truth. Never duplicate
percentages or guess identity. Unknown/unsupported IDs are advisory unavailable,
without probing or installation; facts retain account/pool scope.

A unique sorted runtime filter has one temporary caller-generation owner,
with a 30-second absolute admission deadline. Repeats do not extend, re-retain
or restart it; replacement releases the prior owner. Expiry, request
cancellation, actual turn terminal state when available, clear, close,
disconnect and caller
replacement release once, preserving independent main/run owners. Without an
active turn, bounded refresh still works; invent no turn ID. Return cached or
pending facts without provider wait; later explicit reads may see completed
facts without redating them. Missing capacity stays advisory unknown. No
list/discovery fanout, mandatory read, automatic routing, new payment policy
or redundant team/configuration schema.

The earlier choose specification and U5 captures are superseded. Their
historical provenance and approved collector trials remain intact; they prove
no corrected UI behavior. Existing Resources, selected receipts/reinspection,
receipt-only Resume and historical unlinked receipt layouts remain. PR #145
remains open and unmerged under the owner's hold.

## 2026-10-27 — CHD-534: the fx regression uses standard ACP content (owner)

The existing `@agentclientprotocol/sdk` fixture successfully played completed
tools, an explanatory assistant chunk and a terminal `RequestError`. Its
`ToolCallUpdate` type does not include fx's top-level `command_result`
extension: static checking rejected that field with TS2353.

- **Options considered.** Add a local type assertion or intersection for the
  extension; omit it and keep standard ACP text content; wait for upstream
  SDK support.
- **Choice (the owner): standard content only.** Keep safe synthetic clipped
  JSON as ordinary tool content, seven completed calls, the explanation and
  the terminal error. No assertion, intersection, parser or SDK patch is
  needed. The fixture covers client ordering, distinct failures and session
  reuse, not exact historical extension replay, model language acceptance
  or the original mismatch's cause. The original private evidence stays
  unchanged; no production behavior changes.


## 2026-10-28 — CHD-524: public Note editor and existing paste policy

The non-secret Note beside question choices uses the existing OpenTUI 0.6.6
`TextArea` wrapper and its public edit buffer, cursor offsets, word actions
and visual-line actions. Modified arrows belong to this focused Note; bare
arrows and Tab keep question navigation. Other text fields remain unchanged.
The request's existing saved answer state also keeps each Note cursor, so
question and agent focus changes do not reset it.

A fixture-only public-widget trial pasted `A\nB\r\nC\tD\x01E` into a
character-wrapped textarea. The widget retained newlines (CRLF became LF),
tab and the control character. The existing question `askPaste` instead
converts CR, LF and CRLF to spaces. The public `Input` API was also inspected:
it fixes height to one, disables wrapping and strips newlines, so it cannot
provide the required wrapped visual-line behavior unchanged.

The measured paste mismatch was escalated with three options: preserve the
existing normalization before public insertion; accept native multiline
pastes; or defer until a fitting public API exists. Main selected the first
under the owner's delegated authority to implement reviewed recommendations;
this is not a separately recorded individual owner answer to that option.
The scope is exactly the unchanged `askPaste` value policy followed by public
`insertText` at the Note cursor. There is no new sanitizer, parser, editor
engine, library patch, dependency or multiline-answer policy. New library
mismatches still require escalation.

Harness checks cover modified moves, wrapped-line edges, in-place repairs,
choice retention, paste controls, Unicode, navigation and cursor restoration.
The isolated trial and harness checks alone establish no physical macOS key
delivery, native clipboard behavior or compiled-binary result.


## 2026-10-28 — CHD-532: fixture CLI exit receipts

The startup picker keeps tmux for terminal input and frames. Its first CI
run showed the expected refused/missing diagnostics but an empty public
`pane_dead_status` after `pane_dead` became one. A bounded atomic
`pane_dead|pane_dead_status|pane_dead_signal` readiness check still observed
`1||` for ten seconds in the next CI run. These observations do not establish
the target CLI's eventual exit, the runner's tmux version or the cause.
Local source checks did not reproduce the CI failure.

Main approved a bounded fixture-only alternative under delegated authority:
a tiny Bun-run controller uses standard `node:child_process.spawn` to own the
exact CLI executable and arguments with inherited stdio, cwd and environment.
Only that target child's public `exit` event writes an atomic receipt with
its PID, exit code, signal and any recorded spawn error. The test requires a
complete receipt, verifies the distinct target/controller ownership and
asserts exact cancel zero or refusal one, with no signal or error. Missing
receipts fail. tmux formats, version and pane text remain separate diagnostics.
The controller reaps its owned child; bounded cleanup also stops owned
controller and fake-agent processes. No production behavior, timeout increase,
status fallback, global harness or dependency change is involved.

The public child-process API fits this fixture boundary under Bun. Source and
the existing compiled binary exercise the same target argv; the controller
itself is test infrastructure and is not embedded in the application. Local
passes do not establish a green remote CI run or identify a tmux defect.

A subsequent CI run passed the direct-target refusal receipts but timed out
checking controller disappearance on cancel and explicit starts. That check
used PID existence before releasing tmux, although tmux, not the test, owns
and reaps the pane controller. The CI process state was not captured, so a
zombie, running process or cause is not established by those failures.

A bounded disposable Linux arm64 trial used official Bun 1.4.4, tmux 3.4,
the unchanged controller fixture and minimal targets exiting zero and one.
Public PID/PPID/STAT observations confirmed server → controller → target
parentage, exact target receipts and all owned PIDs absent after teardown.
It did not reproduce the CI hang: both controllers were already reaped
before teardown. The trial used no application dependencies or actual CLI
routes and establishes neither the CI cause nor remote acceptance.

The approved fixture correction separates parents: a controller spawned by
the test is awaited through its public ChildProcess exit promise; a tmux
controller first reaps its target, then the test releases the owned tmux
parent before bounded verification that target, controller and server PIDs
are absent. PID/PPID/STAT, receipt and pane snapshots diagnose failures;
a zombie is not accepted as cleanup success. Primary assertion failures and
cleanup failures are retained separately in an AggregateError when both
occur. No application behavior or timeout increase is involved.


## 2026-10-28 — CHD-525: public transient viewport and true zero room

The existing OpenTUI 0.6.6 ScrollBox, Box sizing and the approved Clip
composition were tried before changing prompt layout. A native trial with
nested rows showed public scrollChildIntoView revealing a selected row in
three available rows while pinned content stayed fixed. Hidden scrollbar
options with explicit zero width/height preserved the full viewport width.
At one row, scrollChildIntoView did not reveal the equal-height selected row;
public scrollTo with its existing visible-list index did, using native
clamping. Completion arrays, ranking, highlight and existing visibleRange
remain unchanged; there is no nearest-scroll engine or library patch.

A reachable fake-agent 80-by-24 window combined eight draft content rows,
a running plan, four queued prompts and permanent agents. Public layout
observations measured one completion row with one child, and zero with the
larger fixture roster. At zero, OpenTUI still painted a row while the selected
item was hidden. This is the existing documented zero-layout paint boundary,
not evidence that a usable row is available. Permanent partial agents rows
and both prompt borders stayed fixed in equal-draft comparisons.

Main selected the scoped true-zero policy under delegated authority; this is
not an individual owner answer and does not select pressure-induced folding.
The existing Clip suppresses zero-height completion paint. Measured zero room
also disables completion acceptance and navigation, including pending match
application, while preserving the draft and ordinary prompt submission.
Positive room restores the list and public scrolling normally. The existing
status hint may say `not enough space`; its row and higher-priority status
semantics stay unchanged. No new panel, minimum-height displacement, queue
or plan budget, key binding, renderer, parser or dependency was introduced.

### Subsequent owner disposition: a bounded pressure exception

The actual owner was shown the saved 80-by-25 open/closed real-terminal
pair from `66290d2a` and accepted leaving that demonstrated behavior for
now. Starting at 80-by-24, the fixture runs nine fake processes, a running
plan, four queued prompts and the same eight-line draft ending in `@`.
After resizing to 80-by-25 and selecting file 5, Escape moves prompt borders
from rows 12/21 to 11/20 (one-based), while permanent agents grow from three
physical rows to four. Draft and cursor remain unchanged. The owner accepts
this specific tight-window resize/close transition; this is not permission
for arbitrary prompt movement or a blanket pressure-folding policy.

The original implementation is retained. Ordinary same-draft comparisons at
120-by-40 and 80-by-24 still require fixed prompt borders, with existing
help paging, key priority and the delegated zero-visible-item safety rule
unchanged. The exact resize/close regression records the accepted movement
and agents growth rather than asserting fixed geometry for that exception.
The [design](design/CHD-525.md) records the superseding contract; its
[investigation](design/evidence/CHD-525/investigation/README.md) preserves
the original captures and historical failure against the earlier contract.

A subsequent uncommitted native closed-baseline measurement trial failed
three of nine reached checks: resize/permanent-content equality and two
existing help-paging cases. It was stopped and saved separately, not
integrated. A later native-column proposal was rejected by source inspection
before any runtime trial. Neither finding proves public API exhaustion.
The limited owner acceptance supersedes the need to resolve this particular
demonstrated shift; it does not approve either investigation's code, a
custom baseline measurement path, sticky height policy or layout engine.
No new library or production layout change accompanies this disposition.

## 2026-10-28 — CHD-546: resource collectors read any provider version (owner)

The owner drops the exact-version gate for the Claude Code and Codex resource
collectors. Chord always tries to read: it still runs the provider's
`--version` and takes the version from `codex-cli <version>` or
`<version> (Claude Code)`. A successful read is reported as read; empty,
failed or unrecognised output is unavailable with its reason. Zod validation
of the provider's answer stays the guard against a changed format. The
version read from `--version` is the Codex source version; Claude's source
stays the bundled `claude-agent-sdk` version.

This supersedes only the exact Codex 0.163.0 and Claude Code 2.1.311 part of
the 2026-10-27 CHD-533 "Exact deployment and accepted risks" entry. The
custom-command, platform, PATH, native-binary and npm-launcher checks, the
approved public APIs, ownership and accepted risks are unchanged.

## 2026-10-28 — CHD-547: a new version waits for the last one on npm (owner)

A publishing run commits and pushes its version before any stage, so a
release stopped before publish leaves origin at a version npm does not have.
Rerunning with a bump bumped past it: one release became v0.61.0, v0.62.0 and
v0.63.0, of which only 0.63.0 reached npm.

The owner decided that a run naming a version or bump other than
package.json's stops in preflight while `@chorded/chord` at package.json's
version is not on npm, before authentication and any release work, dry runs
included. It says that version is not published yet and that
`bun dev release` without a version finishes it. A run without a version and
the existing resume path are unchanged.

## 2026-10-28 — CHD-548: get_budgets just reads the limits (owner)

The owner replaces the CHD-533 resource snapshot with a read per call.
`get_budgets` reads Claude Code and Codex in parallel, waiting up to 10 seconds
per provider. Optional `agents` filters runtime IDs; omission reads both, `[]`
reads none, and a runtime without a reader returns unavailable. The answer is
`{readAt, providers}`, each provider carrying `agent` and either `windows` or
an `unavailable` reason. Windows carry `name`, nullable `usedPercent`,
`windowSeconds`, `resetsAt` and `models`. Preferences are not in the answer.

This supersedes the CHD-533 shared cache and 24-hour fold, freshness states,
`activeRuns`, background collectors and 15-second heartbeat, 30-second filter
retention, and `run_team` decision read and budget warnings. Old resource cache
files are left on disk, neither read nor written. Historical receipts retain
their recorded reads and warnings; receipts without a read show no Read line.
Older `get_budgets` answers show only `Recorded in an older format; not shown.`
in the interface, with their JSON preserved in the session record.

Keep the approved Codex app-server client, Claude SDK usage getter in the
isolated worker, executable resolution and fixture isolation, with their
existing compatibility and lifecycle risks. Readers send no inference prompt;
a timeout does not cap buffering or prove cleanup. Window exit waits for
reader cleanup and reports failures. TeamSelection settings and per-run
`run_team` overrides remain; saved teams and running work stay unchanged.
The historical CHD-533 design and collector trials remain as evidence, not
the current resource contract.
