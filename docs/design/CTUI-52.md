# CTUI-52: client commands after failed startup

The original is the specification: `../chord/src/ui/app/App.tsx`,
`state.ts`, `keys.ts`, `commands.ts` and the existing resume design CTUI-26.
This ends CTUI-26's explicitly deferred failed-start prompt boundary.
No new framework API or subsystem is proposed.

## Screen and ownership

Keep the original compact header and startup failure in the scrollable
transcript. Draw the ordinary bottom prompt, its gap/status rows and the
existing overlay anchor. Do not introduce a separate error-card layout,
retry button or successful-resume header. Initial startup and failed reopen
use the same command-capable failure surface; pending/closing input guards
remain. Failure detail and stderr wording retain existing port rules.

The prompt edits normally, but uninitialized failure cannot send ordinary
text to an agent or enqueue a turn. Existing supported client commands are
recognized before that send guard, as the original does. Preserve command
completion/arguments and reserved ownership; unavailable M3+ commands remain
staged out. `/resume` uses the existing local/all picker, room/focus guards,
async opening identity and stale-result rules. A failed replacement must
not publish partial prepared history. Do not create a parallel command path.

## Original beside the planned port

Original head `577b58167672e12c999aeaf4eed2a1a988513dc2`, fake only.
These sanitized references are observations, not port-parity evidence:

| Size/state | Original reference | Planned port |
| --- | --- | --- |
| 120x40 failed session/new | [failure](evidence/CTUI-52/original-failed-120x40.txt) | Same compact header, failure, blank prompt and bottom shortcut hint |
| 80x24 same failure | [failure](evidence/CTUI-52/original-failed-80x24.txt) | Same wrapped failure and ordinary bottom prompt |
| 120x40 `/resume`, no records | [command result](evidence/CTUI-52/original-resume-empty-120x40.txt) | Same prompt echo and original no-earlier-session sentence |
| 80x24 same command | [command result](evidence/CTUI-52/original-resume-empty-80x24.txt) | Same result with original wrapping |

Every reference has matching `.ansi` evidence. Version differs by the
port's established version policy. The retained source failure names the
fake's missing agentAlias, with no private command/path in the capture.
Port comparison captures must be added after exact developer handoff.

## States, keys and checks

Enter dispatches a recognized supported client command; ordinary text on
failed startup remains unsent. `/resume` followed by Enter opens existing
choices or reports original empty wording. Picker arrows/j/k, digits/Enter,
Ctrl+A scope and Esc keep CTUI-26 behavior. Esc closes an overlay without
inventing a retry. Existing clear/cancel/quit priority and described Actions
remain; help lists only live actions. No new pointer-only action.

Check initial failure and failed reopen at 120x40/80x24; command-only send
guard, `/resume` local/all/empty, cancel, accepted replacement, replacement
failure, repeated invocation and stale read/open completion. Inspect narrow
zero-room and light/plain states where prompt/overlay roles are affected.
A real original failed-start picker comparison needs isolated seeded version-1
records; the initial empty-state captures do not prove that case.

Reproduction: from original run `CHORD_FAKE_START_FAILS=alias bun dev chord
--fake --qa designer-ctui52`, type `/resume` literally, then Enter separately.
Start at 120x40 and resize to 80x24. QA state is synthetic and fresh.
Captures replace only the displayed synthetic QA directory with
`fixture-project`; that label is not an exact width oracle. No original
file was edited. Owned tmux sessions were closed cooperatively.


## U52c: step-aware startup failure words

Main chose this as a separate unit after the U52b live pair exposed the
missing `it refused session/new: ` wrapper. It supersedes this design's
preserve-existing-error-words boundary only for this explicit original
startup-failure projection. Keep the pre-fix u52b failure captures; this is
not an accepted wording difference or an intro/cache geometry regression.

Read `../chord/src/session/start_failure.ts` (StartFailure/startFailed/
stepWords), `src/session/session.ts` (initialize and session-step catches),
`src/ui/app/App.tsx` and its StartFailure/SignIn context. Capture structural
facts at the failing supported step: initialize, session/new, session/load
or session/resume. Fork stays staged out. Preserve the originating error's
words/cause and actual JSON-RPC refusal code, agent connection-closed/exit
facts and existing stderr data. Do not classify by matching message text.
Keep existing wire numeric types and current ownership/cancellation guards.

The headline remains `<agent> did not start: <step words>`, in the same
excluded intro item and ordinary scroll/prompt/overlay geometry. Apply the
original precedence in order:

| Facts | Step words |
| --- | --- |
| No structured failure | Original message |
| Connection closed before step, no exit observed | `it closed its connection before answering <step>.` |
| Exit observed, no signal | `it exited with code <code> before answering <step>.` |
| Exit observed with signal | `it was stopped by <signal> before answering <step>.` |
| No refusal code, or auth-required -32000 | Original message, retaining existing auth wording |
| Method-not-found -32601 after initialize | `it does not serve ACP sessions: not an ACP agent, or not at this version.` |
| Other refusal, including initialize method-not-found | `it refused <step>: <agent refusal words or original message>` |

Cancellation/superseded opening must not become a visible structured startup
failure; original initialize explicitly bypasses wrapping on aborted signal.
An auth failure must retain its existing sign-in-aware message precedence.
Retain process failure facts through cleanup without turning a refused RPC
into a later process-exit headline. Do not fabricate an exit code/signal or
parse it from stderr. Successful replacement drops the failed intro normally;
late old-step failures cannot replace current state.

This unit adds no generic framework API, persistence/replay error entry,
retry action, sign-in subsystem, pin registry or command surface. Existing
failure-detail/stderr/auth block staging and printable control sanitation
remain unchanged. The approved tall fixture uses space-separated synthetic
sentences for legible wrap/scroll stress; control rejection remains tested
separately. A follow-up need for an unavailable original subsystem goes to
the lead before expanding.

At 120x40 the fake alias refusal must reproduce the original two-row headline;
at 80x24 both draw the same two wrapped rows. The seeded resume picker still
floats above an unchanged prompt/status. U52c needs paired exact-fix captures
at both sizes, replacing the U52b reason mismatch while preserving its raw
failure evidence. Reach pure precedence cases plus supported live initial/
reopen failures, cancellation, closure/exit ordering and stale replacement.
Use scripted children/original fake only, isolated state, no model. All
existing keys/help clauses remain unchanged by wording.
