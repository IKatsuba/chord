# S5a designer acceptance

Exact clean implementation: `101826632dc3a6573405fd362ec73be66703ecd5`.
Repair parent: `f7727620475a9e0f3ece5e765c5a99093632769e`.
Original reference: `577b58167672e12c999aeaf4eed2a1a988513dc2`.
Developer held this shared-tree runtime window; no S5b implementation was read.
No product/API finding; direct handoff is to reviewer.

Focus/FocusNode capture callbacks and FocusManager.matchKey read like the
approved design. The exact/prefix/dropped/none enum, immutable binding preview
and one-use dispatch shape match it. Binding registrations are read-only
snapshots, with the approved existing setter path. This is an API/design look,
not a code audit or independent rerun of developer's test results.

## Framework fixture

Command: `dart run test/fixtures/key_capture.dart` from the assigned task tree.
Owned socket ctui48-designer; designer-s5a-key-120 (120x40) and
designer-s5a-key-80 (80x24). Each retained state has capture-pane -p .txt and
-p -e .ansi output. Literal vcxvz produces actions1 and draft x: vc dispatches
before editing, x edits, and vz drops the missed chord. F2 then literal vc
edits normally; bracketed paste P and empty bracketed paste both reach capture,
ending with actions1, pastes2, draft xvcP. Both fixtures quit normally with C-q.

## Paired prompt repair checks

Port command: `dart run example/chord/tool/wheel.dart` from the assigned tree.
Original command from the read-only original checkout, canonically ../chord:
`bun dev chord --fake --qa ctui48-designer-s5a-120` (or suffix80).
The original checkout was resolved explicitly; no original files were edited.
Owned sessions designer-s5a-port-120/original-120 and port-80/original-80 used
120x40/80x24. Remain-on-exit retained exit status for the final probes.

The port's seeded unsubmitted draft was cleared first. The original fake ran
long to completion so its private-free transcript, rather than its header,
filled the view. These fixture transcripts intentionally differ: seeded user
rows in the port versus the fake's numbered reply and model/context facts in
the original. The same prompt/completion states are paired; this is local
prompt-geometry acceptance, not a whole-window port parity claim. S7 still
requires matched fake scenarios for final product evidence.

| State (both sizes) | Original / port files | Observation |
| --- | --- | --- |
| One row | original-prompt-one / port-prompt-one | Same one-row box and editable inset. |
| Two rows | original-prompt-two / port-prompt-two | one, then two; matching gutter/border cells and virtual caret. |
| Cleared 2→1 | original-prompt-cleared / port-prompt-cleared | One empty row; marker and caret column4 retained. |
| Grown 1→3 | original-prompt-grown / port-prompt-grown | one/two/three; same full prompt cells and caret column9. |
| /sta | original-sta-completion / port-sta-completion | Complete /sta retained; same /status label and description. |
| Tab acceptance | original-status-accepted / port-status-accepted | /status inserted normally. |
| Before batch quit | original-before-batch-quit-two / port-before-batch-quit-two | Matching two-row drafts before contiguous Ctrl-C bytes. |

Every listed state has plain and ANSI captures. Extracted whole prompt boxes
match exactly between original and port for every paired state at both sizes.
The surrounding fixture transcript and original's additional status facts are
explained above. cursor-and-exit.jsonl records virtual tmux caret coordinates;
these do not prove a physical cursor's focused/unfocused appearance.

A named tmux S-Enter did not transmit the intended modifier: it submitted one
in the original and inserted no newline in the port. setup-named-shift-enter
captures/records retain that setup miss, not a product failure. The rerun used
the original test suite's explicit Shift+Enter sequence ESC[13;2u. The initial
rerun used one literal protocol packet; the final two-row quit setup sends text
and encoded Enter separately through send-keys calls.
The earlier setup caused one harmless fake reply, so later original transcript
cells differ, while the accepted prompt states remain matched.

Port-only low-room check: clear, type /sta, resize to80x5, Tab. Both origin-size
runs preserve /sta with not enough space; port-sta-denied-height5-from-* retains
that state. Restore120x40/80x24, Tab accepts /status; port-status-restored-*.
No original low-room parity is claimed by this port-only guard check.

Same-batch checks at each required size and in both implementations:

1. From one/two, one literal send-keys call emits Ctrl-C three times: clear,
   arm quit, quit. Every pane exited normally with status0.
2. Fresh fixtures start with draft one. One literal input packet contains
   bracketed paste of LF+two+LF+three, followed immediately by three Ctrl-C
   bytes. Every pane again exits status0. Prior grown captures show the paste's
   three-row appearance; no intermediate frame is claimed inside the final
   same-batch exit packet. Exact per-event reducer state remains test evidence.

## Provenance, limits and cleanup

failure-fix.md and sanitized-failure-fix-excerpts.txt distinguish the proven
baseline /sta failure from the uncommitted Ctrl-C repair-chain failure, and
retain handed final results. No old runtime was reconstructed by designer.
Generic settlement-exhaustion input guarantees remain a separate main task.
No clipboard action, real model/agent, compile, full suite, soak or physical
pointer check was performed. The only agent was the original scripted fake.

All final panes were dead with exit0. The first process scan mistook the owned
tmux server's command label for a fixture; checking its process type identified
it correctly. No owned fixture or QA fake child remained. The owned server,
QA directories and isolated state were removed; cleanup.json records checks.
Capture privacy checks found no home/private path. Raw diagnostic stack paths
were excluded. Only this assigned evidence directory was written in the tree.
