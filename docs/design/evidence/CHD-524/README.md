# CHD-524: question Note screen acceptance

Designer inspected the handed screen unit `cda2af72c1cd374bfa81229db31a1b5904636dec`
on branch `CHD-524`, using only the fake agent. No implementation changes
occurred during the look. The source and host compiled smoke pass the screen
look; no blocking visual finding remains. This is screen acceptance, not code
review or the tester's acceptance.

## Provenance

Source sessions `chd524-designer-wide` and `chd524-designer-narrow` ran
`env -u NO_COLOR bun dev chord --fake --qa <session-name>`, at 120×40 and
80×24 respectively, in the wrapper's fixed `/tmp/chord-qa.<session-name>`.
The final replay waited for the startup hint and question heading before
sending further inputs. All text was sent with `tmux send-keys -l`; Enter
was a separate command. The viewport sizes were specified to tmux; the wide
source pane was also read back with `list-panes` as 120×40.

Compiled binary: `dist/bun-darwin-arm64/chord`, SHA-256
`888b74443d2ce40e49694d5fc19882342c39c935704114c6dff268a74f23d0d7`.
Developer built it from the final source before committing, with no later
code change. Its hash was independently checked here. It ran in owned
session `chd524-designer-binary`, initially 80×24, then resized to 120×40;
the latter size was read back with `list-panes`. The supported route was:

```text
env -u NO_COLOR XDG_STATE_HOME=/tmp/chord-qa.chd524-binary/state
  XDG_CONFIG_HOME=/tmp/chord-qa.chd524-binary/config
  CHORD_RESOURCE_FIXTURE=true <binary> fake
  --agent-command "<absolute Bun executable> <checkout>/tests/fixtures/fake_agent/main.ts"
  -C /tmp/chord-qa.chd524-binary/project
```

The line breaks above are explanatory. Config/state/project were fresh,
fixed scratch directories. Official resource readers were disabled. An
initial compiled invocation using `--qa` was rejected: that flag belongs to
the source dev wrapper. It exercised no Note behavior. The successful smoke
used the existing selftest's explicit fake-command route instead.

Every file in [screen/](screen/) is a whole-window tmux capture: `.txt`
from `capture-pane -p`, `.ansi` from `capture-pane -p -e`, and `.png` rendered
from the corresponding ANSI with existing AnsiUp/Puppeteer dependencies.
The PNGs use Menlo, 13px/18px, foreground `#e4e4e4` and background `#16171b`.
Every final PNG was opened and inspected. These are terminal-cell evidence,
not native terminal screenshots: tmux's separate hardware cursor is not
painted into them. Insertion markers demonstrate cursor location instead.

## Inputs and observed screens

For each source size, send `askcodex`, then Enter; type `2` to choose
Review existing work; `Shift+Tab`, Down, Down focus the first question's Note.
The empty capture keeps its placeholder and selected choice readable.

Type `Please use teh parser`; inject Option-left (`ESC[1;3D`), press
Backspace four times, then type `the `. The repaired capture reads
`Please use the parser`, with choice 2 still checked. At 120×40, bare Right
then Left navigate away/back; at 80×24, Tab then Shift+Tab do so. Down twice
refocuses the Note; inserting `X` produces `Please use the Xparser`, proving
the saved cursor survived the question round trip. Remove `X` with Backspace.

Inject Cmd-left (`ESC[1;9D`), then bracketed paste
`ESC[200~A\rB\nC\r\nDESC[201~`. Both paste captures read
`A B C DPlease use the parser`: existing normalization flattened CR/LF,
and insertion occurred at the cursor. No clipboard was read or written.

Ctrl+U clears the Note; type `alpha beta gamma ` fourteen times. Cmd-left,
`HOME`, Cmd-right (`ESC[1;9C`), `END` insert markers at the last displayed
line's edges, rather than at the whole Note's beginning. Wide wraps across
three editor rows; narrow across four, retaining indentation, the focused
Note and actions. Narrow pressure shows the existing `↑ 2 more` indicator.
The question/options region yields while the focused editor remains visible.
Escape cancels; `?` opens shortcuts. The wide panel fits; the narrow top/end
captures retain word/line entries and truthful above/below scrolling rules.

The compiled smoke repeats the selection/Note route, types `alpha beta gamma`,
uses Option-left, inserts `X`, uses Option-right (`ESC[1;3C`), Cmd-left, and
the same injected paste. The capture reads `A B C Dalpha beta Xgamma` at both
sizes. Tab reaches Token; synthetic text `fixture`, Tab, Enter submit. The
summary retains choice and Note; the fake reply confirms both exact values.
The token here is synthetic fixture input, not a credential.

## Color, cleanup and limits

Permission border/title/marker/Note use dark `permission` RGB `177;185;249`;
required marks use `warning` RGB `255;193;7`. Ordinary Note text stays readable
against the terminal background; descriptions/hints are dim. Initial images
inherited `NO_COLOR=1`; these were replaced with final color captures. A
premature source replay sent input before startup was ready; those frames
were discarded and replaced after explicit readiness waits. Neither setup
mistake is an application finding.

All owned tmux sessions were killed. Process inspection after exit found no
owned source/binary QA process; owned fixed QA directories and temporary
capture/render helpers were removed. No installed settings, real provider,
real clipboard, physical macOS gesture or model was used. Injected sequences
prove byte handling only. No light theme, Unicode/agent-switch/request-reset
matrix, live streaming timing or cross-target binary was checked in this
screen look; developer/tester checks cover their own stated scope. No full
application suite or static suite was repeated by designer.

Before committing captures, the reserved
`nice -n 19 bun test --isolate --timeout=60000 ./tests/privacy_test.ts`
passed: 8 tests, 0 failures, 36 expectations, 4.13 seconds. Changed-file
formatting and diff whitespace checks also passed.
