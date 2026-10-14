# CHD-31 — The wheel scrolls the transcript

On the alternate screen, iTerm2 and Terminal.app turn a wheel or trackpad step
into ↑/↓ (alternate scroll mode, DECSET 1007) unless the program captures the
mouse. chord captures nothing, so the wheel walks prompt history and replaces
the draft. The owner settled the direction: chord captures the mouse as Claude
Code does. The wheel scrolls the transcript through CHD-12's scroll state, and
↑/↓ keep walking history. This design settles the open questions: selection,
a way to turn capture off, what the panel says, and how far one step moves.

The reference was Claude Code 2.1.292, opened in a 120×40 tmux pane in an
empty temporary directory with no prompt sent, and its bundled source:

- **Mouse modes.** tmux reports `alternate_on=1`, `mouse_any_flag=1`,
  `mouse_all_flag=1` (1003) and `mouse_sgr_flag=1` (1006). tmux's
  `mouse_any_flag` only says some mouse mode is on.
- **Selection.** Claude Code draws its own selection. A drag sent as SGR
  reports paints the cells on a slate background (`48;5;66`). On release it
  copies, and the status row says
  `copied 59 chars to clipboard · disable auto-copy in /config`. The
  `copyOnSelect` setting (on by default) turns auto-copy off, and then
  ctrl+shift+c or cmd+c copies. In some terminals its footer names the
  bypass: `option+click to native select` on macOS, `shift+click` elsewhere.
- **Turning capture off.** There is no key and no `settings.json` key. Two
  environment variables do it: `CLAUDE_CODE_DISABLE_MOUSE` (no mouse at all)
  and `CLAUDE_CODE_DISABLE_MOUSE_CLICKS` (the wheel only).
- **The `?` panel** says nothing about the mouse or selection.
- **The wheel** is bound to `scroll:lineUp` / `scroll:lineDown`. In native
  terminals (iTerm2, Terminal.app) one event moves **1 row**, and a fast
  burst of events speeds it up. In xterm.js terminals the base is 3 rows.
  `CLAUDE_CODE_SCROLL_SPEED` overrides it.
- **tmux with its mouse off.** Claude Code shows a one-time hint:
  `tmux detected · scroll with PgUp/PgDn · or add 'set -g mouse on' to
  ~/.tmux.conf for wheel scroll`.

## The decisions, in short

| Question | Answer |
| --- | --- |
| Mouse modes | **1000 + 1006** (button tracking, SGR reports). This is less than Claude Code's 1003, on purpose. |
| Selecting and copying | **The terminal's bypass modifier** for now: option-drag in iTerm2, fn-drag in Terminal.app, shift-drag elsewhere. chord's own selection is a separate task (below). |
| Turning capture off | **`"mouse": false`** in the user's settings file. No key. |
| What tells the person | The panel's scroll line becomes `pgup pgdn or wheel to scroll`. A drag shows `option + drag to select text` (with the terminal's modifier) in the status line for 3 s. The README gets a paragraph and a settings row. |
| One wheel step | **One row**, exactly what `scroll:lineDown` / `scroll:lineUp` do. A step down that reaches the bottom follows again, as the keys do. |

## Mouse modes: 1000 and 1006, not 1003

The wheel is reported in plain button tracking (1000). Any-event tracking
(1003) also reports a motion event for every cell the pointer crosses, even
with no button held. Clicks do nothing in chord yet, so every one of those
reports would be read and thrown away. The selection task moves to 1002
(drags) when it needs them.

- chord writes `ESC[?1000h ESC[?1006h` after it enters the alternate screen.
- It writes `ESC[?1000l ESC[?1006l` before it leaves the alternate screen:
  on quit, after ctrl+c twice, after ctrl+d twice, and on a crash or a
  signal exit. It also writes them before ctrl+g hands the terminal to the
  editor, and turns both back on once the editor exits. The same goes for
  anything else that ever hands the terminal over.
- `chord -p` never turns them on.
- chord does not touch 1007. While chord reports the mouse, iTerm2 and
  Terminal.app send wheel reports instead of arrows, so 1007 no longer
  matters. Writing it would also change a setting chord cannot read back to
  restore.

## What each mouse event does

| Event | Does |
| --- | --- |
| Wheel up / down (SGR buttons 64 / 65), anywhere in the window, with or without modifiers | Runs `scroll:lineUp` / `scroll:lineDown`, the action, not a key. It does what shift+↑/↓ do by default, wherever they do it, and nothing where they do nothing. |
| Horizontal wheel (66 / 67) | Nothing. |
| A left press and release on **different cells** (a drag) | Shows the selection hint (below). Nothing else. |
| Any other press, release or click | Nothing. |

**No mouse report ever reaches the draft, a list, a form or the screen.**
Reports are taken out of stdin before Ink reads keys. A report split across
two reads is still one report: half of one must never come out as typed
`[<64;12;7M`. The draft, its cursor and the history position stay as they
were. ↑ after a wheel still recalls the previous prompt.

The wheel scrolls through every state where the scroll keys work: while
streaming, with a permission asked, and with `?` open (CHD-12). At 80×24 the
`?` panel covers the whole transcript, so the wheel moves it out of sight,
exactly as shift+↑ does there.

### One step is one row

One wheel event is one `line_up` / `line_down` in `scroll.ts`, the step
shift+↑/↓ already take. This is Claude Code's own base in iTerm2 and
Terminal.app. Those terminals already send more events for a longer flick
and for trackpad momentum. So:

- The view leaves following on the first step up, and the indicator
  appears: `── ↓ N lines below · end to jump to the bottom ──`.
- A step down that reaches the bottom follows new output again, and the
  indicator goes, exactly as shift+↓ at the bottom does.
- A step down while following does nothing. A step up while the transcript
  fits does nothing.

Claude Code speeds up fast bursts. This task does not. If the by-hand check
finds a physical wheel notch too slow, qa files the burst rule as a follow-up.
That keeps this task's mapping a one-liner that tests can pin.

## Selecting text

With the mouse captured, a plain drag no longer selects in the terminal.
For now the terminal's own bypass is the way to select, and chord says which
modifier it is when someone drags:

| Terminal (from the environment) | Hint |
| --- | --- |
| `TERM_PROGRAM=iTerm.app`, or `LC_TERMINAL=iTerm2` (survives tmux and ssh) | `option + drag to select text` |
| `TERM_PROGRAM=Apple_Terminal` | `fn + drag to select text` |
| anything else (kitty, WezTerm, Ghostty, Alacritty, foot, xterm, VTE, Windows Terminal, VS Code) | `shift + drag to select text` |

`src/notify.ts` already reads `TERM_PROGRAM`. Read the terminal in one
place. If the by-hand check finds that Terminal.app wants option and not fn,
change the hint and the README line to match. Terminal.app's own ⌘R ("Allow
Mouse Reporting") also turns reporting off for the window. The README says so.

**chord drawing its own selection** (a drag highlights, release copies
through OSC 52 / pbcopy, `copied N chars to clipboard`, a `copyOnSelect`
setting) is how Claude Code does it. It is the better end state, but it is
its own piece of work. It is filed as CHD-177 and is not part of
CHD-31.

## Turning capture off

`"mouse": false` in the **user's** settings file turns no mouse mode on.
chord then behaves as it did before this task: the terminal decides what the
wheel does, which in iTerm2 and Terminal.app means ↑/↓ and prompt history.
The default is `true`.

- It is about a person's terminal and hands, not a project, so it is read
  from the user's file only, as `theme` and `editorMode` are. One in a
  project's file is reported and left out, the same way.
- It is read at start. There is no key and no `/` command. Someone who wants
  the terminal's own selection for a moment has the bypass modifier, so a
  live toggle would be a second way to do the same thing.
- Claude Code uses an environment variable for this. chord uses its
  settings file, because that is where chord's other choices live. A
  keybindings file that binds `wheelup` / `wheeldown` is still refused. The
  wheel always scrolls, so the problem now reads:
  `the wheel always scrolls the transcript and cannot be bound`.

## Screens

The header's path is the mktemp directory. Captures were made with the fake
agent's `long` scenario and a draft typed. The scrolled screens were made
with shift+↑ today, and twelve wheel steps up must give exactly these
screens, draft included.

### Scrolled back by the wheel, 120×40

```
 chord                                                                                        fake · /tmp/chord-qa.VnvX
   155. Line 155 of 200, streamed one at a time.
   156. Line 156 of 200, streamed one at a time.
   157. Line 157 of 200, streamed one at a time.
   158. Line 158 of 200, streamed one at a time.
   159. Line 159 of 200, streamed one at a time.
   160. Line 160 of 200, streamed one at a time.
   161. Line 161 of 200, streamed one at a time.
   162. Line 162 of 200, streamed one at a time.
   163. Line 163 of 200, streamed one at a time.
   164. Line 164 of 200, streamed one at a time.
   165. Line 165 of 200, streamed one at a time.
   166. Line 166 of 200, streamed one at a time.
   167. Line 167 of 200, streamed one at a time.
   168. Line 168 of 200, streamed one at a time.
   169. Line 169 of 200, streamed one at a time.
   170. Line 170 of 200, streamed one at a time.
   171. Line 171 of 200, streamed one at a time.
   172. Line 172 of 200, streamed one at a time.
   173. Line 173 of 200, streamed one at a time.
   174. Line 174 of 200, streamed one at a time.
   175. Line 175 of 200, streamed one at a time.
   176. Line 176 of 200, streamed one at a time.
   177. Line 177 of 200, streamed one at a time.
   178. Line 178 of 200, streamed one at a time.
   179. Line 179 of 200, streamed one at a time.
   180. Line 180 of 200, streamed one at a time.
   181. Line 181 of 200, streamed one at a time.
   182. Line 182 of 200, streamed one at a time.
   183. Line 183 of 200, streamed one at a time.
   184. Line 184 of 200, streamed one at a time.
   185. Line 185 of 200, streamed one at a time.
   186. Line 186 of 200, streamed one at a time.
   187. Line 187 of 200, streamed one at a time.
 ── ↓ 13 lines below · end to jump to the bottom ──────────────────────────────────────────────────────────────────────

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ › a draft I am still typing                                                                                          │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
                                                                Fake Large with a 1M context window · 99% context left
```

### Scrolled back by the wheel, 80×24

```
 chord                                                fake · /tmp/chord-qa.VnvX
   171. Line 171 of 200, streamed one at a time.
   172. Line 172 of 200, streamed one at a time.
   173. Line 173 of 200, streamed one at a time.
   174. Line 174 of 200, streamed one at a time.
   175. Line 175 of 200, streamed one at a time.
   176. Line 176 of 200, streamed one at a time.
   177. Line 177 of 200, streamed one at a time.
   178. Line 178 of 200, streamed one at a time.
   179. Line 179 of 200, streamed one at a time.
   180. Line 180 of 200, streamed one at a time.
   181. Line 181 of 200, streamed one at a time.
   182. Line 182 of 200, streamed one at a time.
   183. Line 183 of 200, streamed one at a time.
   184. Line 184 of 200, streamed one at a time.
   185. Line 185 of 200, streamed one at a time.
   186. Line 186 of 200, streamed one at a time.
   187. Line 187 of 200, streamed one at a time.
 ── ↓ 13 lines below · end to jump to the bottom ──────────────────────────────

╭──────────────────────────────────────────────────────────────────────────────╮
│ › a draft I am still typing                                                  │
╰──────────────────────────────────────────────────────────────────────────────╯
                        Fake Large with a 1M context window · 99% context left
```

### The shortcuts panel, 120×40

Only the scroll line changes. Its width (28) stays under the column's widest
line (35), so no column moves and no row is added.

```
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  enter to send                         ↑ ↓ to pick a command                ctrl + x then a key for sessions
  \ + enter for a newline               tab to complete a command            1–9 to pick a choice
  shift + enter for a newline           @ for files                          ↑ ↓ or j k to move between choices
  ctrl + g to edit in $EDITOR           ↑ ↓ to pick a file                   enter to pick the highlighted choice
  ctrl + v to paste an image            tab enter to add a file              esc to reject a permission
  ↑ ↓ for earlier prompts               esc to close commands or files       esc to close a picker
  ctrl + r to search prompts            ! for bash mode                      ctrl + a to show all directories
  tab enter to take a match             backspace to leave bash mode         tab ↑ ↓ space to fill in a form
  esc to cancel a search                esc to interrupt or stop a command   ctrl + c to stop the turn and its form
  pgup pgdn or wheel to scroll          shift + tab to cycle modes           /vim for vim mode
  shift + ↑ ↓ to scroll a line          ctrl + o for verbose output          ? for shortcuts
  home end for the top and the bottom   ctrl + c to clear input              esc to close shortcuts
  / for commands                        ctrl + d or ctrl + c twice to quit
```

### The shortcuts panel, 80×24

At 80×24 the panel already fills every row. That is why the wheel joins an
existing line instead of getting its own, and why the selection hint is not
in the panel.

```
 chord                                                fake · /tmp/chord-qa.VnvX

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  enter to send                         ! for bash mode
  \ + enter for a newline               backspace to leave bash mode
  shift + enter for a newline           esc to interrupt or stop a command
  ctrl + g to edit in $EDITOR           shift + tab to cycle modes
  ctrl + v to paste an image            ctrl + o for verbose output
  ↑ ↓ for earlier prompts               ctrl + c to clear input
  ctrl + r to search prompts            ctrl + d or ctrl + c twice to quit
  tab enter to take a match             ctrl + x then a key for sessions
  esc to cancel a search                1–9 to pick a choice
  pgup pgdn or wheel to scroll          ↑ ↓ or j k to move between choices
  shift + ↑ ↓ to scroll a line          enter to pick the highlighted choice
  home end for the top and the bottom   esc to reject a permission
  / for commands                        esc to close a picker
  ↑ ↓ to pick a command                 ctrl + a to show all directories
  tab to complete a command             tab ↑ ↓ space to fill in a form
  @ for files                           ctrl + c to stop the turn and its form
  ↑ ↓ to pick a file                    /vim for vim mode
  tab enter to add a file               ? for shortcuts
  esc to close commands or files        esc to close shortcuts
```

If `scroll:pageUp` / `pageDown` are rebound, the line names the bound keys as
it does today, and ` or wheel` still follows them. If neither is bound to any
key, the line reads `wheel to scroll`.

### After a drag, 120×40 and 80×24

A drag (left press, release on another cell) shows the hint in the status
line for **3 s**. It is dim, because it is a hint and not a failure. Like an
armed quit, it **stands alone**, so the model and usage give way and nothing
cuts the hint at 80 columns. Another drag restarts the 3 s. A failure or an
armed quit or close wins over it. A draft does not hide it, unlike
`? for shortcuts`.

```
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ › a draft I am still typing                                                                                          │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  option + drag to select text
```

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ › a draft I am still typing                                                  │
╰──────────────────────────────────────────────────────────────────────────────╯
  option + drag to select text
```

Why a hint on a drag and not a panel line: the person needs it exactly when
a drag has just failed to select, and they are looking at that spot. A panel
line would cost a row that 80×24 does not have, and would name one terminal's
modifier to people in another.

## README

Add a settings row after `editorMode`:

```
| `mouse`                        | `false` leaves the mouse to the terminal; user's file only |                     |
```

And this paragraph after the `theme` / `editorMode` paragraph:

> chord reads the mouse, so the wheel and the trackpad scroll the
> transcript, as pgup, pgdn and shift+↑/↓ do, and ↑/↓ stay with your earlier
> prompts. To select text, hold your terminal's modifier while you drag:
> option in iTerm2, fn in Terminal.app (or turn mouse reporting off with
> ⌘R), shift in most others. Inside tmux, the wheel reaches chord only with
> `set -g mouse on`; without it the terminal sends ↑/↓. `"mouse": false`, read
> from the user's file only, leaves the mouse to the terminal, as before.

## States

- **Empty transcript, or one that fits.** The wheel does nothing. Nothing
  moves and no indicator appears.
- **Streaming.** The wheel scrolls back, and the view stays put while output
  arrives (CHD-12's rule). The indicator says `↓ new output`.
- **Permission asked, `?` open, form open.** The wheel scrolls the
  transcript, as the scroll keys do there. It never moves a list's
  highlight.
- **ctrl+g's editor open.** Mouse modes are off, so the editor gets the
  terminal as a plain program would. They come back on when it exits.
- **Quit, ctrl+c twice, crash, signal.** Mouse modes are off, the shell
  prompt is back, and a wheel turn in the shell does what the terminal
  always does there.
- **Narrow.** Nothing changes at 80 columns beyond what is shown above.
- **Light and dark terminals.** Nothing new is coloured. The hint uses the
  status line's dim style.
