# U52c: step-aware words and held Escape/resize finding

Handed source: signed `4a084be881fc9b934d881b2bb2a9ec359ab76fba`.
Required-size wording/row-count checks below pass. Overall designer round 1
is HELD on the persistent Escape/resize observation; no review clearance,
framework attribution, final CTUI-52 parity or fixed claim follows from this note.

Concurrent U52d source was not run or inspected. Designer used an exact
4a084be source archive inside build, redirected only self-package config
roots, and reused resolved external package roots without pub get. Original
head is `577b58167672e12c999aeaf4eed2a1a988513dc2`; original source was never
edited. Both source launchers use Bun's original fake, isolated XDG state/
config and task cwd. No real agent/model/account was used.

## Original words at required sizes

Paired alias startup (`CHORD_FAKE_START_FAILS=alias`) now includes original
`it refused session/new: ` and the agent's words. At 80x24 the two failure
rows match; at 120x40 both have two rows, with the existing break difference
below. Non-ACP (`CHORD_FAKE_START_FAILS=notacp`) matches original
`it does not serve ACP sessions: not an ACP agent, or not at this version.`
at both sizes, including one row at 120x40 and two at 80x24. Ordinary text plus
Enter remains unsent in both failed windows; the draft survives.

A synthetic saved UUID2 plus `CHORD_FAKE_REFUSE_LOAD=1` and CLI --resume
matches original `it refused session/load: Resource not found: <UUID>`.
There is no doubled outer resume message or partial history. Both required
sizes retain the same headline row count and fixed prompt/status geometry.
Typing `/resume` then separate Enter still opens matching saved choices from
the failed-reopen prompt at 80x24.

Lead explicitly retains existing framework plain-Text wrapping; no generic
break-opportunity edit or startup-specific workaround is authorized. At 120
alias, original breaks `[agents.<alias>]` after the period, while port keeps
the token together. At 80 load refusal, original breaks the UUID at a hyphen,
while port moves its complete token to the second row. Same words/row counts
at required sizes do not imply cell-identical line breaks. At 32x10 direct
failure is five original versus four port rows, reflecting that existing
wrapping difference; both keep the prompt. The original narrow resume hint
still overwrites its border, while the port keeps the accepted intact frame.

Text/ANSI pairs and `u52c-comparison-*` retain these observations. Established
version/header-help staging remains. Auth, initialize, session/resume,
closure/exit, cancellation/stale metadata precedence remain scripted
reviewer/tester obligations, not additional designer live claims.

## One bounded Escape/resize reproduction

An initial uninstrumented sequence closed the original resume overlay but
left the port overlay at 32x10. Lead requested exactly one overlap rerun plus
a fresh separated control, with no diagnosis or further repeated overlap.
The exact seed/config/launch is in u52c-repro-corpus.json; command timings
and observed states are in u52c-escape-resize-repro.json. Cwd is labelled
<task-checkout> for reconstruction; exact timestamp/UUID/title are retained.

Start both at 80x24 with one compact type-first version 1 record, load refusal,
and CLI --resume UUID. Literal `/resume`, Enter separately, wait until both
captures show Resume a session. In one sequential command batch send Escape
to original, Escape to port, resize original to32x10, resize port to32x10.
The four subprocesses span about 28 ms, with exact timings retained.

Immediate captures show in-progress rendering and are not settled evidence.
After explicit 1-second sleep and a later tool capture beyond normal parser/
frame settlement, original is closed but port remains the zero-choice picker.
The actual elapsed delays are retained in JSON. A further separate Escape
on that persisted port state also failed to close it. A failed assertion
was followed by a literal `/resume` from the shell: that mismatched sequence
is explicitly contaminated and is not a valid separated control.

Both windows were then closed and restarted fresh at 32x10 with the same
source/corpus. Open `/resume`, verify both overlays, then Escape in its own
call with no resize. This fresh separated control closes both. Retained
before/after text/ANSI proves the differing precondition and result.

This is a persistent observed action failure after the overlap, not an
unmeasured early frame or a wording failure. No claim identifies which
subsystem caused it. CTUI-51 is done on current main; it is not cited as an
existing open failure. Lead routed tester first to already-reviewed61d012c
(+fixture bb3a6d2) to vary only source against this exact corpus, not to
inspect/test unreviewed 4a early. U52c round 1 remains held pending routing.

## Cleanup

All original/port/control sessions exited cooperatively; owned tmux servers
ended. No relevant Dart/Bun/fake process remained. Owned isolated XDG roots
and exact archive were removed after the bounded control. No private path
is retained. Sanitized display cwd labels do not relayout captured cells.
No AOT, heap, physical terminal/display or broad latency claim is made.

## Lead routing update before immutable handoff

Lead reports tester also reproduced the state loss on already-reviewed
U52b61d012c, so it is preexisting to the U52c wording unit. The finding is
not attributed to wording, parser timing or CTUI-51. Lead approved a separate
U52e port-only cancel-focus correction; its exact fix and recheck are still
pending. These raw before/immediate/settled/control captures remain unchanged.
Terminal blank rows at EOF are preserved; the scoped whitespace check omits
only blank-at-EOF for raw captures.
