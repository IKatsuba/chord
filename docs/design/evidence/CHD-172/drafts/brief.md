# CHD-172 — brief

The lead's brief for the architects. The task is on the board (`board show
CHD-172`, with main's comment #8105 carrying the owner's words). This folder
also holds evidence of an older task once numbered CHD-172 in quarry
(`build/`, `design/`, `qa/`, `return3/`); it is not this task's and is left
alone. This task's drafts are in `drafts/` only.

## The problem

Since CHD-31 chord reads the mouse so the wheel scrolls the transcript. A
plain drag therefore selects nothing in the terminal, and chord draws nothing
either: every `<text>` is `selectable: false` (`src/ui/theme/text.ts`) and
the textarea too, so OpenTUI's own selection never shows. The only thing a
person gets is the status line's `shift + drag to select text`
(`src/ui/app/drag.ts`'s `selectHint`, 3 s, `src/ui/app/timers.ts`). The
owner, trying it on the OpenTUI build, found that nothing looks selected and
the hint reads as very strange (comment #8105).

## What the person should see and press (the reference)

Claude Code 2.1.292, as recorded in `docs/design/CHD-31.md`:

- A left drag paints the cells it covers on a slate background
  (`48;5;66`), as the pointer moves.
- On release the selection is copied to the clipboard and the status row
  says `copied 59 chars to clipboard · disable auto-copy in /config`.
- `copyOnSelect` (on by default) turns auto-copy off; then a copy key
  (Claude Code: ctrl+shift+c or cmd+c) copies the selection.
- The terminal's bypass modifier (option in iTerm2, fn in Terminal.app,
  shift elsewhere) still gives the terminal's own selection.

Done, as the task says: a drag over the transcript highlights what it
covers; release copies it (OSC 52, pbcopy where OSC 52 is refused); the
status line says how many characters; a `copyOnSelect` setting and a copy
key exist and the shortcuts panel lists the key; the bypass modifier still
works; CHD-31's drag hint gives way to the copied note.

## Constraints

- **The one rule.** OpenTUI 0.6.0 has a selection of its own: the
  renderer's `startSelection` / `updateSelection` / `getSelection` /
  `clearSelection` / `hasSelection` (`@opentui/core` `renderer.d.ts`), the
  `Selection` class with `getSelectedText()` (`lib/selection.d.ts`), a
  `selectable` prop on text and textarea, `copyToClipboardOSC52` and
  `isOsc52Supported`, and a host clipboard (`lib/clipboard.d.ts`,
  `lib/host-clipboard.*`). It is to be tried first, **in a spike that
  runs**, and what was tried goes into `docs/decisions.md`. Where it does
  not do what the task asks, nobody writes around it: the question goes to
  the owner with options.
- **Mouse modes.** CHD-31 chose 1000 + 1006 on Ink; OpenTUI now sets the
  modes itself (`useMouse`, `enableMouseMovement` in `renderer.tsx`'s
  `openTerminal`). Find out which modes it writes today and whether a drag
  already reports motion.
- **What draws is what is mounted.** The transcript mounts only its tail
  (CHD-327 D) and the native scene culls what is off screen (CHD-327 A).
  Entries are `React.memo`'d. A selection must not unmount what it covers
  while it is held (opencode keeps its window while text is selected; chord
  noted that in CHD-327 D).
- **Every action has a key** (CLAUDE.md). The copy key is an action in
  `src/ui/shortcuts/bindings.ts`, listed in `keys.ts`, checked by
  `tests/ui/shortcuts/keys_test.tsx`.
- **Settings.** `mouse`, `theme` and `editorMode` are the user's file only.
  `"mouse": false` must still leave the mouse to the terminal entirely.
- **Tests never reach a real terminal clipboard.** The copy goes through
  something injectable; `harness.tsx`'s `Logged` terminal can see OSC 52
  bytes.
- `chord -p` draws nothing and is untouched.

## Non-goals

- Keyboard selection (shift+arrows in the transcript), word or line
  selection by double or triple click, unless OpenTUI gives it for nothing
  and it does no harm — say so if it does.
- Clicks doing anything else (no click to pick a row, open a link, focus).
- Following the terminal's theme live.
- Windows.

## Open questions, by architect

### protocol (session side, records, settings, chord's MCP)

1. Does anything reach the agent or the session record? (Expected: nothing.
   Say so and why, and whether a copy is worth a record line — expected no.)
2. The setting: its zod shape in `src/settings.ts`, user's file only or
   both, read at start or live, how `/config` relates to it. Claude Code's
   note says "disable auto-copy in /config"; chord's `/config` lists the
   **agent's** config options, not chord's. What should chord's note say,
   and is there any honest place for the toggle besides the settings file?
   Bring the options; the name and default are the owner's.
3. The clipboard path: OSC 52 (`renderer.copyToClipboardOSC52`), OpenTUI's
   host clipboard, `@mariozechner/clipboard` (already a dependency for
   ctrl+v images: does it write text?), pbcopy. Which goes first, how
   "OSC 52 is refused" is known (it usually cannot be: a terminal that
   drops OSC 52 says nothing), and inside tmux (`set-clipboard`,
   passthrough). Try each that can be tried here.

### interface (screen, states, keys, slices)

1. Spike OpenTUI's selection with `selectable` turned on in a scratch
   build (do not commit code): its highlight colour and whether
   `48;5;66`-like slate can be set (`selectionBg` / `selectionFg` props?),
   the text it yields across a reply wrapped at words, a reply with markdown
   spans, a diff with its gutter and line numbers, folded tool output
   (`⎿` lines, the `… +N lines` marker), the header's mark, the border of the
   prompt box, the status line and the agents list. What should be
   selectable and what not, and does OpenTUI let chord say so per text?
2. The prompt box: should a drag inside the textarea select its text
   (OpenTUI's textarea selection) and is that the same copy? What does a
   drag that starts in the transcript and ends in the prompt do?
3. The status line: the copied note's words, its place against the armed
   lines, failures and vim's mode, how long it stays, 80×24. What replaces
   `selectHint`: nothing, the note only, or a bypass hint somewhere when
   `copyOnSelect` is off?
4. When does the highlight go away: on copy, on the next press, on a key,
   on Esc, on new output, on a tab switch, on ctrl+o? Does Esc with a
   selection clear it before it interrupts?
5. The copy key: candidates and what each terminal delivers (ctrl+shift+c
   needs the kitty protocol to be told from ctrl+c; cmd+c never reaches a
   program in iTerm2/Terminal.app; ctrl+c is chord's clear/quit). Bring
   the options with what each costs; the choice is the owner's.
6. Screens at 120×40 and 80×24: a drag in progress, after release with the
   note, `copyOnSelect` off with a selection waiting for the key, and the
   shortcuts panel with the key (80×24 has no spare row, CHD-31).

### runtime (processes, concurrency, failure, tests)

1. Which mouse modes OpenTUI writes now (read `enableMouse` and capture the
   bytes), whether 1002 is already on, and what CHD-31's "1002 in place of
   1000" means today.
2. A scroll during a drag: the wheel while the button is held, and a drag
   past the transcript's top or bottom edge — does OpenTUI's selection
   follow content (anchored to renderables) or screen cells? What happens
   when the held entry unmounts (tail-first mounting moves when following,
   new output streams in, the native scene culls it)? Does the selection
   survive the view moving, or must the view hold still while selecting?
3. Streaming under a selection: an entry the reducer replaces (a chunk
   grows the reply) is a new React element; does the selection on it
   survive, move, or vanish?
4. The copy's failure modes: pbcopy missing (Linux), the native clipboard
   addon failing to load in the binary, OSC 52 over ssh and tmux, a very
   large selection (OSC 52 size limits), and what the status line says for
   each. Timeouts, and never blocking a frame.
5. Testability: how `harness.tsx` drives a drag (SGR press, motion,
   release bytes through `testRender`'s mock mouse?), reads the highlight
   in the frame, and sees the copy without a real clipboard.
6. Cost: does turning `selectable` on for every text cost anything per
   frame at 10,000 rows (CHD-327's numbers), and does 1002/1003 motion
   reporting cost anything at rest?

## How the drafts are written

Each architect writes only its own draft in this folder
(`protocol.md`, `interface.md`, `runtime.md`), answers its questions above
with what it actually ran (commands, captures, short excerpts; captures may
go beside the drafts as `spike-*.txt`), and ends with **Owner questions**:
each with the options and a recommendation, never decided. No code under
`src/`, `tests/`, `scripts/` or `lint/` is changed or committed; a spike
lives in a scratch file outside the tree or is reverted before the draft is
done (`git status` clean but for the drafts).
