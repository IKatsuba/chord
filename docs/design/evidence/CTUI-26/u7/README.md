# U7: live resume overlay and command states

Visual acceptance at b9d8d59b3096cb343ae6c1c956709152b4f808be, the width fix
on handed 19bae9ae661b67a1b1e1cdaf7781d48e1d244296 (implementation 10d99c72).
Original source: 577b58167672e12c999aeaf4eed2a1a988513dc2.
No blocking screen finding remains. The approved failed-start limit is now
explicit in the binding CTUI-26 design.

## Runs and reproduction

All port runs used exact archives under ignored build/, with root/port local
package resolution into the archive. port-* is the initial handoff;
port-fix-* is exact b9d8d59. No observation is relabeled as a newer run.
Owned designer tmux, XDG_STATE_HOME and controlled TMPDIR isolated every run.
NO_COLOR unset, COLORTERM=truecolor, FORCE_COLOR=3; --plain deliberately
removes colors. CHORD_SOURCE resolved the read-only original checkout.
No real model/agent or owner state was used. Literal text was submitted with
send-keys -l and Enter separately, except the explicitly handed same-batch
permission/reopen sequence.

Base command: dart run example/chord/tool/record_history.dart. --many gives
24 local records plus remote; type /resume, Enter. Capture 120x40/80x24;
Escape closes, Ctrl+A changes scope, arrows/j/k navigate. The fixture starts
with a supported past and resumed header. The real opaque overlay appears
above the unchanged prompt/status. --remote-only --light starts local-empty;
Ctrl+A lists the remote record and Enter closes the picker with a report
and quoted reopen command, retaining the current session. Captures retain
local/all/empty/refusal states.

--ask-while-picking starts a fake permission after the picker appears.
Permission UI takes priority; Ctrl+X A focuses it, digit 1 answers and the
retained picker reappears. Suspended permission at 80x24 and reappearance at
120x40/80x24 are retained. Initial selection was first; a noninitial highlight
was not induced before the one-second timer. --queue-return starts a
between-turn permission and queues two drafts. Open /resume; wait for that
state, Ctrl+X A, then send 1 and Enter in the same tmux send-keys call.
The selected session reopens, with queued request one/two restored as two
lines in the draft. The 80x24 result is retained.

--stream-while-picking --plain starts slow output behind the retained picker.
The initial default-speed attempt completed before acceptance, so its
port-plain-stream-accept capture shows a valid completed-turn reopen and is
not busy-refusal proof. The exact-fix rerun set CHORD_FAKE_STEP_MS=100, captured
the retained picker, then Enter while the turn was active. The picker closes
with A turn is running... then /resume., while live dots and working line
continue. This establishes the observed busy acceptance refusal, not an RPC
or generation-race proof.

On exact fix, --remote-only --light at 32x10 has a frame/scope hint but no
visible row or Enter hint. Enter followed by resize to 80x24 keeps the same
all-directory picker and original session; it does not defer a hidden
acceptance. port-fix-zero-before/enter/room-return retain that sequence.
With CHORD_FAKE_REFUSE_LOAD=1, the fake-only fixture draws the existing
startup/protocol error at both standard sizes, without prompt/anchor or a
successful-resume header. This is the owner-approved failed-start boundary;
/resume after failed startup is separately deferred.

Original paired runs use source via Bun production define, fake named agent,
explicit original fake command (--scenario text), isolated state/config/cache
and synthetic cwd. Seed 24 compact v1 local records and one remote with the
fixture's title texts/ages; /resume reaches matching overflow at both sizes.
Remove only those owned local seeds, close/reopen /resume for local-empty.
The original stays fullwidth. A mainbetween prompt reaches its held main
permission; /resume there reports busy. The retained original permission
capture is a different fake proposal/state from the port ask-while-picking
scenario; it is a reference, not identical combined-state parity proof.
A synthetic local record was restored for original 32x10 zero-body evidence.

## Finding and fix

The initial live empty frame shrank to 46 columns at both standard sizes.
Original empty /resume is fullwidth, as the design requires. Developer
accepted the finding; b9d8d59 fills actual available width only for live
composition, preserving startup sizing. Exact-fix empty frames at 120x40 and
80x24 now match original width/anchor, retain scope keys and omit acceptance.
Before/fix and original/fix comparisons are retained. Nonempty many frames
already matched original geometry and hidden-row counts.

## Evidence, approved differences and limits

Each pane txt has matching ansi. comparison-many and comparison-empty pair
both standard sizes. comparison-empty-fix retains the defect. Prompt/status
rows remain stable as the overlay appears; streaming output is painted behind
it. Scope/close/navigation descriptions are visible in the staged shortcuts
capture. Dark many/permission/queue, light empty/all and plain streaming were
observed. No new original light/plain combined palette parity is claimed.

Original version, synthetic directory and staged /help differ as previously
approved. The port fixture has existing resumed past; original starts fresh.
Original and port synthetic paths/age reference differ, so directory-column
widths are not an identical-input oracle. At 32x10 original OpenTUI paints
Esc to close across its bottom border; the port safely clips that text.
The original border overpaint is retained as an observed renderer difference,
not copied or called an acceptance/input difference. Both have no visible
choice. Scope differs in the paired narrow frame because the port is all-
directory while the original is local; no claim of identical wording is made.

As approved by main, existing failed startup/protocol error has no prompt or
resume anchor in this port. Original permits a command after failed startup;
that behavior is a separate follow-up. CTUI-26 does not add it through U7.

The injected fixture owns the asynchronous permission/stream trigger; these
captures show screen reaction, not a user submitting through an open picker.
Queued-input return and suspension were observed, but noninitial highlight
retention, scan errors/delays, wheel consumption, every chord/digit, same-batch
clear/resize, and reentrant/generation ownership were not independently proved
by this screen look. Reviewer/tester retain those checks; U8 keeps integrated
CLI, paired combined-state, compiled/interchange and native proof gates.
The source fake has canned history; this is not real persistent-agent history.

## Sanitization and cleanup

Synthetic temporary roots became equal-length ASCII fixture-root labels with
underscore padding; truncated synthetic root segments became same-length
fixture-label text. Source/fake command rows containing absolute private paths
and their continuations were redacted; those rows are not width or quoting
proof. No home path is retained. Timers vary; they are not performance data.

The live round paused for U8a only after all apps/fakes exited and tmux was
closed. It resumed after lead's explicit release. Final exact-fix panes all
exited 0 with Ctrl+Q; original closed picker with Escape then Ctrl+D.
Owned process checks found no app/fake remaining, controlled TMPDIR had zero
entries and fixture roots were absent. The owned tmux server, source archive,
state/config/cache/projects and temporary capture root were removed afterward.
No suite, compile or implementation edit was performed by designer.
