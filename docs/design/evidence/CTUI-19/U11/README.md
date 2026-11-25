# U11 status and working visual check

Implementation 0c0a64d, fixture key fix dc167ce. Original 577b58167.
Designer result: pass after fixture fix, handed to reviewer.
Before each app launch, lib/ and example/ were checked clean; startup was
visually confirmed before input. No tests, compile or other heavy run.

Commands:

- Integrated port: `dart run example/chord/tool/dev.dart chord --fake`.
- Original: `(cd ../chord && bun dev chord --fake --qa designer-ctui19-u11)`.
- Dark fixture: `(cd example/chord && env -u NO_COLOR dart run tool/status.dart)`.
- Light: same fixture command with `--light`.
- Explicit plain precedence: same fixture command with `--light --plain`.

Directory labels are redacted in full panes. `.txt` records text, `.ansi`
records styles, side-by-side files select the relevant working/status region.
Fixture mode tour uses Ctrl+G; Ctrl+T cycles working states; Ctrl+Q quits.
The initial fixture's Ctrl+M was indistinguishable from Enter in ordinary
terminal input: developer fixed it in dc167ce, and Ctrl+G was verified live.

Integrated observations at 120x40 and 80x24:

- Reported model/effort and 1% context appear after a prompt. Original's
  `status` scenario reports plan mode; the 80-column status matches exactly.
- `readsheld` keeps Working visible with a queued prompt. Working/Queue/
  Prompt/Status order and selected text match at both sizes. An initial
  immediate-input attempt missed the original's queued draft; the saved
  final queue captures were repeated with separate tool turns between
  literal text and Enter, and match. No product cause is assigned to the
  missed original input.
- `ignorescancel`, Esc and immediate capture retain Interrupting at both
  sizes, identical elapsed text (0s narrow, 1s wide). The fake times out at
  30s, so delayed captures were replaced with the observed persistent state.
- `permission` shows `Waiting for permission… (0s)` at both sizes. Original
  additionally draws its permission dialog (CTUI-18); this slice does not.
- Combined plan+queue capture at 120x40 shows Working, three checklist rows,
  queued prompt, blank prompt margin, rounded Prompt and Status in matching
  order/columns. The original adds its mode-change key hint; port status is
  read-only in this slice, so that M2 action is not advertised.
- Fixture Ctrl+T displays Interrupting, Waiting for permission and idle;
  idle removes the working row. No clock-rate accuracy is claimed visually.

Palette observations, both fixture sizes:

- Dark/light tours cover plan, accept edits, auto, bypass, read-only and
  default. Mode hues match the original palette source. Status adapts to
  width by dropping less important right-side detail, keeping one row.
- Dark plan/edit/auto use RGB 72/150/140, 175/135/255, 255/215/0.
  Light uses 0/107/102, 122/63/214, 138/97/0. Bypass uses base error.
  Read-only is dim terminal text. Bash is outside this screen slice and
  remains a developer palette-value test, not a live visual claim.
- Spinner ANSI shows three `›`, a bright mark moving among darker marks
  and a rest. Dark uses #d2ffe4/#0a7470; light #1e9a5e/#0a5e57. Working
  text uses the base accent. Palette tours show the same layout/text.
- The inherited shell environment had NO_COLOR=1, discovered during the
  initial tour. Dark/light color runs explicitly removed it. Explicit
  --light --plain captures prove precedence: no explicit foreground or
  background colors in any mode. Plain spinner samples retain a moving
  undimmed mark and all-dim rest. Sampling can skip a timer step; exact
  140ms/250ms timing and timer teardown remain developer-test coverage.

Existing header and empty-prompt `?` hint differ by earlier slice boundaries;
no new difference is authorized. No model or real agent was contacted.
Cleanup: drafts cleared, integrated apps quit with Ctrl+D, fixture Ctrl+Q;
all three owned sessions and all tracked fake/runner descendants checked gone.
