# S7 designer acceptance

Final implementation: `a6c57333a2e49d29ee4e9160d18b20bf426378fc`.
Base visual/API handoff: `d06136684d2211ef21c239244f9dd2e618b13b43`.
Original: `577b58167672e12c999aeaf4eed2a1a988513dc2`.
The full base matrix used the clean held d061366 implementation. The scoped
repair look below used the separate signed final handoff. Designer API/screen
acceptance is PASS; hand S7 directly to reviewer. Code review and tester gates
remain required. Public selection API is unchanged; the demo uses public
exports without private diagnostic or clipboard access.

## Findings raised from the base look

1. Direct measured scene/range composition deltas are absent from the handed
   benchmark. Zero delegate source resolutions/parses and stable structural
   range counts are measured; they do not prove zero range recomposition.
   Developer confirmed the gap and added the approved internal numeric
   collect/publish counters and reporter assertions. Do not label that delta
   proven from the older JSONL. The signed numeric completion below now closes
   this gap with direct measured counters.
2. At all six theme/origin-size combinations, pick-before-narrow has an active
   pick in both products. Resize to20x24: original keeps `↑ ↓ block`, port
   replaces it with the older `sent 5 chars to` note. This violated the design's
   compact pick-hint behavior for a still-current block. Before/failure plain
   and ANSI pairs are retained as pick-before-narrow/narrow20. Developer received
   the finding and handed back the separate signed fix below; no WIP was inspected.
3. The signed-fix look adds the small empty-catalog ctrl+x b notice check at
   both sizes/all themes. The main matrix captures an empty initial catalog but
   did not invoke that action there. The additional scene closes this look gap.
   Empty block copying remains the separately
   reviewed port no-op, not an empty-catalog notice.

## Actual matched setup

capture_matched.py runs24 original/port cases:120x40 and80x24 × dark/light/plain
× auto/manual/failure/timeout. Both sides run the same original scripted fake.
The port_recording.dart.txt bootstrap adapts the handed public compiled fixture:
real StartConnection.start, production TranscriptWindow and recording Copy.
It does not seed a transcript or use private framework diagnostics. The source
is retained as text outside package analysis, run with the port package config.
Original_recording.ts uses production CLI/App, the original fake command and the
S5b-approved recording copier factory. No original file is edited.

The lead approved original public App.home='capture-home' as a presentation
input and a relative task-owned project directory. Both render and its immediate
rerender receive that input. HOME is unchanged. The captured directory label is
not default directory-line parity. Both launchers isolate records/config/state
under build. All visual adapters only record, and cannot call host clipboard or
OSC services; a write event means simulated adapter acceptance.

Every run explicitly unsets inherited NO_COLOR, sets TERM=xterm-256color and
COLORTERM=truecolor. The plain flag deliberately selects NO_COLOR behavior.
Literal text uses send-keys -l; Enter is its own call. Ctrl+x b/c sequences use
literal Ctrl-X followed by the letters, not an ambiguous numeric escape.
SGR mouse bytes prove routing, never physical pointer or native selection.
Both normal quits and pending-copy quits are retained; native exit timing is
separate handed evidence, not inferred from visual capture duration.

## Matrix results and screen differences

Index.md links228 actual paired scenes, original left, port right. Every scene
also has individual plain/ANSI captures and virtual cursor coordinates. The
six auto cases each traverse the whole interaction sequence; the other modes
exercise their feedback contrast and retry behavior at every size/theme.

| State group | Live evidence |
| --- | --- |
| Empty/header/draft | Real connected fake facts, exposed selected header text, focused draft, forward/reverse draft selection. |
| Auto copy | Sent note, retained highlight after3000ms, explicit copy clears highlight. |
| Manual | Release says ctrl+c to copy without a write; explicit copy records/clears. |
| Failure/timeout | Persistent selection error and retry;1200ms timeout then pending retry/quit. |
| markdowncode | Real nested/wrapped/blank source, newest/previous/first code copies; prose selected forward and reverse. |
| Stream open/held/mutated/release/closed | Same original markdown scenario,10ms steps. Hold const while the open source gains its actual closer, then release current text; End exposes final closed source/code copy. |
| Quote/table | Real quoted paragraph and session.ts table cell selections, exact copied text. |
| Permission/diff | Actual Allow modal, eligible notes diff letters selected, explicit Ctrl+C copies without rejecting; Esc subsequently rejects normally. |
| Narrow | Current actual20-column resize exposes the open pick-retention finding above. |

Clipboard-comparisons.json proves all24 attempt/write event lists are identical.
Each auto case has22 writes, including `chord`, `draft`, prose in both
directions, full code with its hard blank LF, `const` after held mutation,
quoted words, table text and permission diff `notes`. Manual has one write;
failure/timeout each have two attempts and no writes. Original cancellation
notifications are retained in journals but excluded from attempt/write matching,
since the two recording adapters expose cancellation differently.

Highlight ANSI uses slate66 dark and152 light in both products. Port plain
uses inverse without foreground/background SGR; original's slate exception is
the explicitly approved difference. The code control/body geometry consumes
accepted S6a behavior; this is not a claim of full pixel identity.

The lead explicitly retained these existing boundaries: original version and
/help header, its disabled-MCP warning, later [run]/r controls, and the port's
existing code inset/wrapping. Exact references: CTUI-48 scope excludes run
until CTUI-25; Code buttons and mode preserves current code inset/wrapping;
original main.tsx/App.tsx and ui/header/Header.tsx supply the extra header/MCP
facts; original Markdown code frames have their own retained rendering shape.
Different table/code widths and line breaks remain visible in actual pairs,
not hidden by substituting a seeded transcript. Permission/prose/code payload
comparisons above are exact even where retained renderer furniture differs.
The original fake markdowncode text literally contains a screen-capture path
inside its unexecuted shell-code example; no such command/path was executed.

## Public framework demo

capture_demo.py runs example/selection.dart at120x40 and80x24, cycling all three
themes. Held header selection sets held and stops following; F2 appends without
moving the held view; release/snapshot reads Selection. Known overlay, unknown
coverage suppression (Snapshot unresolved), recovery, source code inspection
and public reveal are captured. The focused editor remains present. No clipboard
or private diagnostic import is used by the public example. Historical fixture
alias remains a developer-tested entry point, not an additional designer run.

## Handed native/performance proof, not reruns

handed-evidence-manifest.json lists22 explicitly handed artifacts retained under
handed/, with private paths sanitized and that fact recorded. ANSI control bytes
and payloads remain evidence, but path sanitization means these are not untouched
raw-screen geometry comparisons. Originals remain in the ignored named build
artifacts. Designer ran no compile, benchmark or native suite.

The developer's current-source native run has six passes: public demo, production
binary OSC mouse/code path and recording pending-copy exit at each size. Tests
assert exact terminal restoration,1002 cleanup and bounded pending exit. The
retained native OSC check decodes one bun dev check and two draft transmissions
at each size; there was no host clipboard forwarding. These native byte captures
are not physical pointer/cursor appearance proof.

Retained setup failures are explicit: differential ANSI readiness assumptions,
Tcl hex18bc versus octal030bc encoding, journal polling without PTY drain, then
the corrected full-redraw/frame-end/draining run. The actual preserved old
setup24423 ANSI is included. Developer corrected an earlier cleanup omission:
three binaries in an old failed fail-fast directory were preserved as ANSI then
removed; do not repeat the earlier incomplete cleanup claim.

The final pre-counter AOT dataset covers600/10000, both sizes,20 steady frames,
and1000 updates coalesced before one selected frame. None/held/shown steady
phases report zero builders/source resolutions/parses; one changed parse for
the burst. At10000, held/shown medians0.050–0.086ms, first layout328.440–329.704ms,
selected updates179.737–200.743ms. These are dataset measurements, not latency
limits or a constant-time changed-history claim. Mounted states13/8 equal
visible mounts; full-history selection holds10002 selected roots/30002 ranges.
Clear reports zero immediate extra references and next-frame visible baseline.
These are structural counts, not heap/RSS/GC proof. This older dataset does not prove direct composition deltas; the signed
numeric completion below supplies them. Old600-resolve and
clear87/92-cache failures and later results are retained, never relabeled as a
proved committed-baseline regression; all diagnostic failures were S7 WIP.

## Setup misses and cleanup

The first approved home override was reset by the original's immediate rerender;
no private capture was retained, and the corrected wrapper covers both calls.
The first permission readiness phrase used fixture Allow once; actual UI said
Allow. That stopped the setup while both apps correctly waited. Before-retry
plain/ANSI/journals and the corrected final run are retained. These are setup
misses, not product findings. The resize mismatch is a separate real finding.

All48 final matched panes, two public-demo panes and initial setup probes
exited0. Owned tmux/fake/fixture processes are gone; isolated runtime records and
fixed journals were removed after retaining every case. Runtime-cleanup.json
records checks. No real model, clipboard, full suite, extra benchmark, physical
pointer or heap measurement was used. The signed fixes and exact recheck below
close the designer findings without relabeling these base captures as new-head
runtime or native proof.


## Signed completion and exact repair look

Numeric commit: `8c15fc9c0ae80e3b705c04ac6be0d33e238a86c1`.
Resize commit/final head: `a6c57333a2e49d29ee4e9160d18b20bf426378fc`.
Both signatures were verified. The numeric change only adds internal integer
work counters at actual collect/publish entry; the behavior repair preserves
valid code-pick identity across resize while still cancelling selection/drag.
No renderer, eligibility, source identity or public API changed.

The handed composition_metrics JSONL now directly measures sceneCollections
and rangeCompositions. All12 no-selection/held/shown steady phases at600/10000
and both sizes are0/0. Changed held is1scene/2range; shown1/1; none1/0. Reads/reset
have handed positive-work/no-effect tests. The AOT reporter self-checks passed
and its binary was removed. Normal tests ran concurrently with that reporter;
its times are not isolated before/after latency evidence. Designer only read
and retained the artifacts, without rerunning native or performance work.

capture_repairs.py runs six actual original/port pairs on the exact final head,
using the same recording/public-home setup as the base matrix. The compact
pick hint survives20x24 resize from both required sizes in every theme, over a
live earlier five-character copy note. c copies the current nested source.
A subsequent first-code target has no button in its genuinely narrow column,
but c still copies x. The recheck uses markdowncode as a minimal equivalent
valid-pick resize reproduction; it is not a same-content pixel comparison with
the longer base failure scene. Before/failure captures remain unchanged.

The added empty-catalog action shows No code block to pick and expires after
3000ms without calling Copy. All six journal pairs are identical, with exactly
chord, chord, bun dev check, x writes. This also proves the narrow copy keys did
not fall through into the draft. The first recheck validated journals in-process
but omitted per-case retention; a same-head rerun saved/asserted each journal.
Both runs' exit records are retained, and journal-retention.txt labels the
recording omission rather than inventing a product defect.

All12 final repair panes and12 first-look panes exited0; owned server, fake
children, fixtures and isolated recording state are gone. repairs/cleanup.json
records checks. Framework1156 and final port1408 reached passes/static checks
are developer-handed evidence, not a designer suite rerun. All source writes
remained held through this look.

The earlier228 paired scenes/48 panes and native six-case proof remain scoped
to d061366 and unchanged appearance/behavior they actually exercised. No new-head
binary rerun is claimed. Direct AOT counter proof is scoped to8c15fc9 framework;
resize proof is exact a6c5733 widget/live evidence. No designer finding remains
open; reviewer and tester must assess the exact final unit before completion.
