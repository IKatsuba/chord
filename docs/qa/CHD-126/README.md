# CHD-126 — live Codex and fx checks

Date: 2026-10-06. Source tree: `ed4f1d7`, on `main`. Live agents were used.
Prompts were short and edits were confined to temporary scratch directories.
No owner configuration was edited. No push, publication or PR was made.

## What ran

- Read `CLAUDE.md`, `README.md`, `docs/FEATURES.md`, `docs/decisions.md`,
  `quarry skill show chord-tui` and `quarry skill show quarry`.
- `deno task check`: the initial sandboxed attempt could not run the fake
  processes correctly; the unchanged run with process access passed types,
  lint, formatting and **778 tests (20 steps), zero failures**.
- `deno task compile`: produced the host binary. Started it in tmux against
  `tests/fixtures/fake_agent.ts`, sent `error`, resized to 80×24 and quit.
- Started source with `deno task chord codex -C <scratch>` and
  `deno task chord fx -C <scratch>`, in a dedicated tmux server. Used only
  `send-keys` to operate chord, with text and Enter separated in time.
  Checked 120×40 and 80×24 and captured the panes as text.
- Codex prompts: `Reply with: ok`, `Read note.txt; replace old with new.`,
  `Replace new with next in note.txt.`, `Write ok to ../permission.txt.`,
  `Write ok to ../permission2.txt.`, `Reply with: resumed`,
  `Run sleep 10 then say ok.` and `Run sleep 10.`. The sibling files were
  also inside the scratch root. No project work was requested.
- Ran source `--continue`, `--resume <recorded-id>`, and `-p 'Reply with: ok'`
  with and without the agent's `--permission-mode`.
- Used the existing maintained ACP SDK in temporary, uncommitted scripts to
  inspect fx configuration responses without a model prompt. A later
  initialization attempt with that SDK also stalled. A further attempted
  tiny SDK prompt never reached initialization and was stopped.
- Read process tables before and after the checks. Stalled owned fx processes
  were identified by PID and parent before SIGTERM. Existing and unrelated
  agents were left alone.

No product component, parser, renderer or protocol helper was written. The
attribution probes used `@agentclientprotocol/sdk`, already in the repository;
the product continues to use `acpx/runtime` and Ink.

## What was observed

**Result: FAIL.** Codex's principal flows work, but its permission-mode display
is stale and a starting mode is lost on a reopened record. fx was unreachable
because of its own network problem, so its rows are not checked and need a
second pass. Unresponsive fx attempts also exposed an unbounded chord quit.

Each link below is a pane capture or headless output. Home paths in captures
are replaced with `[redacted home]`; trailing blank shell rows are omitted.
Otherwise the captured text is preserved.
The width columns describe the observed terminal behaviour, not separate
automated tests.

### Codex

| Row | 120×40 | 80×24 | Observation |
| --- | --- | --- | --- |
| Start and streamed reply | [PASS](captures/codex-120-reply.txt) | [PASS](captures/codex-80-permission.txt) | `ok`; a later narrow turn was captured with a partial reply and Working line. |
| Tool call and edit with diff | [PASS](captures/codex-120-edit.txt) | [PASS](captures/codex-80-permission.txt) | Read and edit tools appeared; `old → new` and `new → next` were numbered diffs. |
| Permission prompt and answer | [PASS](captures/codex-120-permission.txt) | [PASS](captures/codex-80-permission-prompt.txt) | Fresh `read-only` session requested approval for a sibling scratch write. The open prompt survived resize; `1` allowed it and [recorded the answer](captures/codex-80-permission-answer.txt). |
| Esc interrupt | [PASS](captures/codex-120-interrupt.txt) | [PASS](captures/codex-80-interrupt.txt) | Working changed through Interrupting to Interrupted by user; the prompt remained usable. |
| Shift+Tab modes | [FAIL](captures/codex-120-mode2.txt) | [FAIL](captures/codex-80-interrupt.txt) | Successful change remained displayed as Approve for me until a later turn. CHD-129. |
| `/model` | [PASS](captures/codex-120-model.txt) | [PASS](captures/codex-80-model.txt) | Offered models were shown; choosing 6 Luna [changed the status](captures/codex-120-model-set.txt). |
| `/config` | [PASS](captures/codex-120-config.txt) | [PASS](captures/codex-80-config.txt) | Collaboration mode, reasoning effort and fast mode offered. Setting effort to Low [read back](captures/codex-120-config-set.txt). |
| `/cost` and `/context` | [PASS](captures/codex-120-usage.txt) | [PASS](captures/codex-80-usage.txt) | Token/context figures shown; cost explicitly not reported by Codex. |
| Quit and terminal restoration | [PASS](captures/codex-quit-shell.txt) | [PASS](captures/codex-quit-terminal.txt) | Shell returned; cursor visible and alternate screen off. |
| `--continue` | [PASS](captures/codex-120-continue.txt) | [PASS](captures/codex-80-continue.txt) | Earlier transcript displayed; continued scratch edit completed. Requested starting mode on reused record failed separately: CHD-80. |
| `--resume` | [PASS](captures/codex-120-resume.txt) | [PASS](captures/codex-80-resume-reply.txt) | Recorded session displayed its past and replied `resumed` to the next prompt. Replayed edits lose diffs as already documented. |
| `-p`, no permission mode | [PASS](captures/codex-headless.txt) | [PASS](captures/codex-headless.txt) | One tiny reply, `ok`, exit 0; headless output has no layout to resize. |
| `-p --permission-mode read-only` | [PASS](captures/codex-headless-mode.txt) | [PASS](captures/codex-headless-mode.txt) | One tiny reply, `ok`, exit 0. |

The installed Codex adapter's legacy `session/set_mode` changes its internal
mode and returns `{}` without a config update. That agent difference explains
why acpx's recorded config remains old; chord still needs an accurate
security-relevant status. Its advertised `mode` config option and the existing
`setConfigOption` library API provide a response with updated configuration.

### fx — original environment

The owner confirmed during the check that fx itself had a network problem on
2026-10-06: plain fx outside chord did not answer either. By the owner's call,
fx's failures to answer are not counted against chord, and every row that
needs a live fx turn is **not checked (fx unreachable)**. The captures show
what was attempted. The final serial launch used exactly
`deno task chord fx -C <scratch>`, with the owner's original environment, and
remained at Starting fx; a launch that kept chord's state isolated but
restored fx's original XDG environment also stalled.

The quit row stands on its own: quit must not hang on an agent that stops
answering, whatever the reason, so it is a chord FAIL (CHD-128).

**fx needs a second pass** of this whole matrix once its network works
(CHD-130).

| Row | 120×40 | 80×24 | Observation |
| --- | --- | --- | --- |
| Start and streamed reply | [not checked (fx unreachable)](captures/fx-registry-120-start.txt) | [not checked (fx unreachable)](captures/fx-registry-80-start.txt) | Original-environment initialization did not finish. |
| Tool call and edit with diff | [not checked (fx unreachable)](captures/fx-registry-120-start.txt) | [not checked (fx unreachable)](captures/fx-registry-80-start.txt) | Could not send the scratch edit after initialization. |
| Permission prompt | [not checked (fx unreachable)](captures/fx-registry-120-start.txt) | [not checked (fx unreachable)](captures/fx-registry-80-start.txt) | No original-environment turn reached a permission request. |
| Esc interrupt | [not checked (fx unreachable)](captures/fx-original-120-start.txt) | [not checked (fx unreachable)](captures/fx-registry-80-start.txt) | No initialized turn available in the final check. |
| Shift+Tab modes | [not checked (fx unreachable)](captures/fx-registry-120-start.txt) | [not checked (fx unreachable)](captures/fx-registry-80-start.txt) | Could not verify a mode change after original-environment initialization. |
| `/model` | [not checked (fx unreachable)](captures/fx-registry-120-start.txt) | [not checked (fx unreachable)](captures/fx-registry-80-start.txt) | Could not verify original-environment selection. |
| `/config` | [not checked (fx unreachable)](captures/fx-registry-120-start.txt) | [not checked (fx unreachable)](captures/fx-registry-80-start.txt) | Could not verify original-environment selection. |
| `/cost` and `/context` | [not checked (fx unreachable)](captures/fx-registry-120-start.txt) | [not checked (fx unreachable)](captures/fx-registry-80-start.txt) | No initialized session to report. |
| Quit and terminal restoration | [FAIL](captures/fx-120-quit-stuck.txt) | [FAIL](captures/fx-registry-80-quit.txt) | Quit required external termination of the owned adapter. CHD-128. The wide capture is from the earlier exploratory environment. |
| `--continue` | [not checked (fx unreachable)](captures/fx-120-continue.txt) | [not checked (fx unreachable)](captures/fx-80-continue.txt) | Exploratory replay eventually appeared, but original-environment continuation could not be certified. |
| `--resume` | [not checked (fx unreachable)](captures/fx-120-resume-working.txt) | [not checked (fx unreachable)](captures/fx-80-resume.txt) | Exploratory replay appeared; no accepted original-environment resumed turn. |
| `-p`, no permission mode | [not checked (fx unreachable)](captures/fx-registry-headless.txt) | [not checked (fx unreachable)](captures/fx-registry-headless.txt) | Serial original-environment attempt did not initialize. After external SIGTERM, chord reported the startup error and exited 1. Headless output has no width-dependent layout. |
| `-p --permission-mode code` | [not checked (fx unreachable)](captures/fx-registry-headless-mode.txt) | [not checked (fx unreachable)](captures/fx-registry-headless-mode.txt) | Serial original-environment attempt also did not initialize; external SIGTERM produced a visible startup error and exit 1. |

No row is marked “agent does not offer it”: capabilities were advertised in
the exploratory session and SDK probe, and an unreachable agent cannot prove
their absence.

### Exploratory fx evidence and harness limits

The first fx attempts inherited the XDG variables used to isolate chord.
This also changed fx's environment, so these observations are retained for
diagnosis and **excluded from compatibility acceptance**:

- Started with Ask mode and `gpt-6-astra`; a tiny `ok` eventually arrived.
- Models, modes and Reasoning Effort were advertised. Config responses from
  the SDK returned updated values. Chord's selected model and effort became
  visible after reopening the recorded session.
- `/cost` showed the agent's reported `$0.0000`; this does not establish that
  the owner's subscription spent nothing. `/context` showed a figure on the
  first session and explicitly said no figure was reported after resume.
- An edit turn stayed Working for minutes and never yielded a tool or diff
  before it was stopped. Esc and quit remained pending. Terminating only
  the owned fx PID released chord. No file edit was established for fx.
- fx's skill-discovery warnings were displayed. Their configuration causes
  belong to fx; the owner's skill links were not changed.
- Exploratory `-p --permission-mode code` replied `ok` and exited 0, but its
  modified XDG environment excludes it from original-environment acceptance.
- During an exploratory connecting session, a launch command was accidentally
  appended to an unsent `Reply with:` draft. The agent echoed the combined
  text. That turn is excluded from the tiny-prompt acceptance evidence.

The original-environment SDK initialization also failed to settle in a later
attempt. This matches the owner's report that fx itself could not reach its network;
the stalled startup is not assigned to chord.

## Cleanup and final validation

All five live-check panes returned to a shell with cursor visible and
alternate screen off ([terminal flags](captures/terminal-restoration.txt)).
The shell was back in canonical input with echo
([stty](captures/stty-after.txt)). The dedicated tmux server was removed.
Process snapshots identified 17 owned roots and 56 observed process IDs across
their descendants; [none remained](captures/process-cleanup.txt). Unrelated
agents were not terminated. The compiled fake-agent terminal also restored
[its cursor and normal screen](captures/compiled-quit-terminal.txt).

The required full check was rerun after adding the evidence: **778 tests
(20 steps), zero failures, 6m41s**. Automated session checks and the compiled
smoke check use the fake fixture; automated tests never invoke a live model.
New captures were scanned for private paths before staging. Only this task's
evidence is committed; unrelated pre-existing untracked captures are left in
place.

## Filed findings and handover

- **CHD-128:** unbounded quit with an unresponsive fx adapter, including
  startup and pending control requests. The owned process can stay alive and
  the terminal remain in the alternate screen. Test the boundary with a fake
  agent before returning it to live QA.
- **CHD-129:** Codex's displayed permission mode remains stale after a
  successful change, including a fresh starting mode.
- **CHD-130:** the fx second pass of this matrix, once fx's network works.
- **CHD-80:** existing task; added independent live evidence that a requested
  starting mode is lost on a reused record. No duplicate task was filed.

The matrix is not an end-to-end pass for either agent. Codex's working rows
are proved; fx's rows are not checked (fx unreachable) and wait for CHD-130. Agent
warnings, latency, capabilities and startup attribution are notes rather than
additional chord defects.
