# S6b designer acceptance

Implementation: `bca820ed79c58fa65645625b1b88100c2735a05e`.
Runtime docs head: `46ec1a820ed0096a900f65dd78f253ae75aaf4d9`.
Original: `577b58167672e12c999aeaf4eed2a1a988513dc2`.
Only the approved design/decision notes differ between the handed code and
runtime head. Developer held all writes. No screen finding; hand to reviewer.

## Setup

Run the retained Python drivers from repository root. The port driver serializes
`dart run example/chord/tool/selection.dart --pick --manual` with --light,
--plain, --many, --failure or --timeout as named. It also runs the existing
wheel --help --tall-draft fixture, with and without --closing. Every case uses
an owned tmux session at120x40 or80x24, explicit unset NO_COLOR,
TERM=xterm-256color and COLORTERM=truecolor. --plain deliberately restores
NO_COLOR in the production fixture. Plain/ANSI captures and virtual cursor
coordinates are retained for every state.

The fixed build/ctui48_selection_record.jsonl is saved before the next port
fixture starts. The injected Copy only records attempts/writes; it cannot call
a host service. Successful journals contain the exact ordinary payload
`\tcopy body\n\ntail` and quoted body, without borders or a structural final LF.
A write event means simulated adapter acceptance, not an OS write or OSC receipt.

Original-recording.ts retains the S5b-approved factory seam: import read-only
original main.tsx, replace startServices.copier before cli.parse, then run its
scripted fake with isolated config/state/project directories and no MCP servers.
The factory never constructs a host or terminal clipboard adapter. The original
fake markdown scenario supplies real closed/nested code. Original source is not
edited. Literal text uses send-keys -l, Enter its own call. Same-batch ctrl+x b
is one literal packet, ESC-free Ctrl-X byte followed by b. SGR reports are
synthetic protocol evidence, never physical pointer proof.

## Live screen result

Six normal port runs cover dark/light/plain at both required sizes. Other
port cases below cover both sizes in dark. Individual filenames follow
`port-<theme>-<size>-<state>` or `port-<mode>-<size>-<state>`.

| Captured states | Result |
| --- | --- |
| initial / pending / picked-quote | One ordinary button, quote no button, final open Dart no target; live leader includes b and real pick hint appears. |
| samebatch-picked / picked-ordinary | One-batch ctrl+x b picks the newest eligible quote; Up emphasizes ordinary TS; the open fence is skipped. |
| ordinary-copied / quote-copied / button-copied | c and real button use the shared recorder; exact tab/blank payload and quoted body are retained; pick ends and sent note counts16 or11. |
| selection / selection-then-pick / typed | Real body selection yields to code pick; Esc ends pick; x enters the still-focused draft. |
| sta / status-completed | Whole /sta survives one text packet and Tab inserts /status at both sizes and all themes. |
| many picked / ordinary-revealed | Code begins offscreen behind100 history entries; newest quoted container is revealed at the top, then ordinary TS is reachable by Up without visiting each intervening row. |
| failure copy / expired | Code-origin error has no selection retry clause; note disappears after3000ms. |
| timeout copy / bounded / retry-pending | Pending code copy reaches1200ms bound with the correct error; fresh pick/c retries, then empty-draft exit completes without waiting on that pending adapter. |

Picked dark/light frame/label/button use the current framework accent; button
is bold. Quoted outer bar stays dim. Plain uses terminal foreground and bold
picked button; every retained port plain screen has no foreground/background
SGR. These consume the already accepted S6a control/inset/wrapping geometry.

## Original comparison and status placement

The paired files put original left and port right for pick, /sta and completion
at both sizes and all themes. Prompt-cursor-comparisons.json proves all18
paired prompt boxes, row positions and virtual cursor coordinates are identical.
Six initial prompt boxes also match the earlier S5b captures exactly, preserving
the pre-relocation connected prompt cells/width/order/height.

The original uses its full fake markdown reply and reported model facts; the
port uses the handed seeded reply and fixture launch/header. Different code
payloads, block sizes, transcript rows and notice counts are setup differences,
not matched-content evidence. Original has later [run] buttons and r in its
pick hint; the port intentionally omits them until CTUI-25, as approved.
The port hint is exactly `↑ ↓ another block · c copy · esc done`.
This is not a full matched fake-session/renderer parity claim; S7 retains that
integration obligation.

For startup/non-send/failure, status_phases.dart.txt is a capture-only public
state launcher: StartConnection is never opened, no agent/model starts, and one
stable TranscriptWindow key survives starting→failed→idle→connected→gone→closing.
The source is retained as text outside package analysis; the exact runnable
command uses `dart --packages=example/chord/.dart_tool/package_config.json`.
Phase captures show one status row with its existing two-cell inset. Starting,
failed and idle have no prompt; connected/gone/closing keep the same prompt.
Phase-cursor-visibility.json records hidden virtual cursor for non-send states
and the same visible editor cursor at4,37 or4,21 for the send-capable states.
No physical cursor appearance claim follows from tmux flags. No earlier
startup runtime was reconstructed; these are explicit fixture states, with
historical connected-cell comparison separately recorded above.

An auxiliary cursor probe initially checked exit after a fixed200ms delay,
before that pane had finished exiting. It later reported exit0; the retained
rerun uses readiness and bounded exit polling. auxiliary-cursor-setup.txt keeps
this setup miss distinct from a product failure.

## Help geometry and failure provenance

Existing wheel --help --tall-draft at80x24 shows the two genuine new help rows
and `↓ 2 lines below`:12 action rows, room11. Wheel reveals an above rule while
retaining the complete seven-row draft, cursor and focus behavior. With
--closing, the panel does not move. At120x40 the actual catalog fits and wheel
has no panel overflow to consume. Four exact prompt/cursor comparisons confirm
no draft/geometry movement. Earlier CTUI-47 M1 fitting evidence is historical;
no catalog entries or room were manipulated to keep an old fit assertion.

sanitized-failure-fix.txt and diagnostic-pick-before-120x40.txt retain the
explicitly handed WIP diagnostics: pending mirror exhausted usable geometry;
first live-KeyHelp repair passes12 pick cases; existing command cases then lose
/sta→/ta; unconditional keyed status footer repair passes52 reached cases.
The initial reached aggregate's two old tall-help fit expectations are retained
as failures, followed by the approved catalog-derived update and1391 passes.
All red diagnostics are uncommitted S6b WIP based on S6a4eeba4f / later docs444649c,
not a proven committed-baseline defect. Designer did not rerun old code or
claim ANSI before-fix captures where only diagnostic text was handed.

The footer relocation preserves cells and budget; this evidence claims no
matcher/Focus notification change, extra pass, replay or generic exhausted-input
guarantee. CTUI-51 retains that follow-up. Current Plan/PlanRecord/plain Tool
negative descriptors and the full form/permission/pending coexistence matrix
are handed automated coverage, not additional live claims from this fixture.

## Cleanup and limits

All18 primary port panes, three original panes and auxiliary probes exited0.
The owned server, fixtures and fake children are gone. Original isolated state
and the fixed port journal were removed after saving evidence. Privacy scans
found no private paths. cleanup.json records checks.
No real model, clipboard, physical pointer, compile, full suite, performance or
new fake-session integration run was performed by designer. S7 remains pending.


## Post-look source-fidelity correction

Review found original ui/app/terminal.ts:692–695 treats an empty code body as a
port copy no-op before coordinator mutation: no Copy(''), new note, pending
copy cancellation or generation change. Copy-key pick ending and button-press
range clearing remain normal; an empty catalog retains its separate3000ms
No code block to pick notice. Generic framework empty descriptors/callbacks
and the Terminal clipboard service are unchanged. Fix a43928b passed exact
review and tester03bb3ee. Appearance was unchanged; no designer runtime rerun
was requested, and the captures above retain their original implementation head.
