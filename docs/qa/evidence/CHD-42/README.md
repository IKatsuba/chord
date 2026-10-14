# CHD-81 — M2 day-driver evidence

2026-10-05. Product tree: main at 8d9aede. QA only; no product change.

## Commands run

- Read CLAUDE.md, README.md, docs/FEATURES.md, docs/decisions.md, and quarry's chord-tui and quarry skills.
- Ran deno task check with process access: types, lint, formatting, 444 tests (20 steps) passed, 0 failed. The restricted first attempt could not spawn /bin/ps (Operation not permitted); the unchanged command passed with access.
- Ran deno task compile: dist/aarch64-apple-darwin/chord was produced and started successfully in both terminal sizes.
- Ran four complete keyboard day-driver sequences: source (deno run --quiet --allow-all --config <repo>/deno.json <repo>/src/main.tsx, equivalent to deno task chord) and binary, each at 120×40 and 80×24.
- Ran separate headless text and JSON invocations for each source/binary/size combination, plus explicit per-exit terminal checks.
- Read text and ANSI tmux captures; checked stty -g, tmux alternate_on/cursor_flag, raw alternate-screen escapes and ps process output.
- Scanned new evidence for private home paths and ran 168 capture/terminal assertions: all passed.

## Isolation and keyboard sequence

Each complete run had its own /tmp directory, HOME, XDG_CONFIG_HOME, XDG_STATE_HOME, working directory and tmux socket. Deno's existing dependency cache was reused. A temporary public-path symlink named the fixture command so quit captures contain no private paths. No owner agent settings were changed and no live agent was started. The settings file contained agent=fake and agents.fake.command pointing at tests/fixtures/fake_agent.ts, with permissionMode=plan. The cwd held src/day.ts and an ignored file.

Text was sent literally; Enter was a separate key call after a pause. All in-app actions used keys. Each source/binary/size run kept one tmux session through the working day, then quit/reopened chord for --continue and --resume. /clear created a new record before /resume selected the original. Separate headless invocations followed. The two widths were also exchanged live and restored.

The steps were: settings start; three shift+tab presses; slash menu and agent completion; /help, /status, /cost, /context; /config; /model; @day; bash printf then text; slow plus a queued draft and Esc; thought and two ctrl+o presses; ctrl+r search and older match, Esc; markdown and PageUp/End; edit; error; resize and restore; quit; --continue and /status; quit; --resume id; /clear, text, /resume; /exit; headless text and JSON.

An initial QA key sequence accepted the older bash-history match and left bash mode enabled; those runs and captures were discarded and all four complete sequences were repeated with the corrected keys. They do not contribute to the results below.

## M2 results

Each PASS links to a representative capture. Matching .ansi files preserve colours. Other captures with the same run prefix show intermediate choices and before/after states.

| M2 row | Source 120×40 | Source 80×24 | Binary 120×40 | Binary 80×24 | Observed behaviour |
| --- | --- | --- | --- | --- | --- |
| Permission modes, cycled | [PASS](source-120x40-02-mode-edits.txt) | [PASS](source-80x24-02-mode-edits.txt) | [PASS](binary-120x40-02-mode-edits.txt) | [PASS](binary-80x24-02-mode-edits.txt) | Plan from settings; shift+tab → default → accept edits → plan. |
| Model picker | [PASS](source-120x40-05-model-set.txt) | [PASS](source-80x24-05-model-set.txt) | [PASS](binary-120x40-05-model-set.txt) | [PASS](binary-80x24-05-model-set.txt) | /model, Down, Enter selects Fake Small; status reads it back. |
| Agent slash commands with completion | [PASS](source-120x40-03-agent-command.txt) | [PASS](source-80x24-03-agent-command.txt) | [PASS](binary-120x40-03-agent-command.txt) | [PASS](binary-80x24-03-agent-command.txt) | / opens the list; /gr filters /greet; Tab completes; /greet day answers. |
| Client slash commands | [PASS](source-120x40-04-status.txt) | [PASS](source-80x24-04-status.txt) | [PASS](binary-120x40-04-status.txt) | [PASS](binary-80x24-04-status.txt) | /help opens shortcuts; Esc closes; /status reports; /clear opens an empty new session; /resume and /exit work. |
| @ file mentions with fuzzy finder | [PASS](source-120x40-06-mention-picked.txt) | [PASS](source-80x24-06-mention-picked.txt) | [PASS](binary-120x40-06-mention-picked.txt) | [PASS](binary-80x24-06-mention-picked.txt) | @day finds src/day.ts; Tab inserts @src/day.ts; Enter sends it. Text delivery is the CHD-60 owner decision. |
| Bash mode | [PASS](source-120x40-07-bash-context.txt) | [PASS](source-80x24-07-bash-context.txt) | [PASS](binary-120x40-07-bash-context.txt) | [PASS](binary-80x24-07-bash-context.txt) | !printf runs in the isolated cwd; the next text prompt receives day-context. |
| Resume a session | [PASS](source-120x40-11-resume-in-place.txt) | [PASS](source-80x24-11-resume-in-place.txt) | [PASS](binary-120x40-11-resume-in-place.txt) | [PASS](binary-80x24-11-resume-in-place.txt) | Quit; --continue; quit; --resume <printed id>; /clear; /resume selects the original session in place. |
| Queue a prompt while a turn runs | [PASS](source-120x40-08-returned.txt) | [PASS](source-80x24-08-returned.txt) | [PASS](binary-120x40-08-returned.txt) | [PASS](binary-80x24-08-returned.txt) | slow runs; queued day draft + Enter queues; Esc interrupts and restores the complete editable draft. |
| Transcript / verbose view | [PASS](source-120x40-09-verbose.txt) | [PASS](source-80x24-09-verbose.txt) | [PASS](binary-120x40-09-verbose.txt) | [PASS](binary-80x24-09-verbose.txt) | thought; ctrl+o expands Considering the question.; ctrl+o folds it again. |
| Reverse history search | [PASS](source-120x40-10-history-search.txt) | [PASS](source-80x24-10-history-search.txt) | [PASS](binary-120x40-10-history-search.txt) | [PASS](binary-80x24-10-history-search.txt) | ctrl+r + text finds the last text prompt; another ctrl+r finds the earlier bash command containing text; Esc restores the draft. |
| Headless one-shot | [PASS](source-120x40-headless-json.txt) | [PASS](source-80x24-headless-json.txt) | [PASS](binary-120x40-headless-json.txt) | [PASS](binary-80x24-headless-json.txt) | Separate -p text and -p text --output-format json exit 0; JSON reports result, session id, end_turn, usage and cost. |
| Syntax highlighting in code and diffs | [PASS](source-120x40-12-diff.txt) | [PASS](source-80x24-12-diff.txt) | [PASS](binary-120x40-12-diff.txt) | [PASS](binary-80x24-12-diff.txt) | markdown draws fenced ts/sh code; PageUp/End scroll; edit draws numbered additions/removal with token colours and row tints. |
| Session config options (effort, etc.) | [PASS](source-120x40-13-config-set.txt) | [PASS](source-80x24-13-config-set.txt) | [PASS](binary-120x40-13-config-set.txt) | [PASS](binary-80x24-13-config-set.txt) | /config opens Effort; Enter opens values; Down/Enter sets High and records readback. |
| Usage and cost | [PASS](source-120x40-14-cost.txt) | [PASS](source-80x24-14-cost.txt) | [PASS](binary-120x40-14-cost.txt) | [PASS](binary-80x24-14-cost.txt) | /cost reports $0.0125, 1,000 input, 200 output, 800 cache-read tokens; /context reports 2,000/1,000,000 and 99% free. |
| Settings files | [PASS](source-120x40-01-settings.txt) | [PASS](source-80x24-01-settings.txt) | [PASS](binary-120x40-01-settings.txt) | [PASS](binary-80x24-01-settings.txt) | The isolated XDG config file selects fake, its command, and starting plan mode without agent/mode CLI flags. |

## Terminal and process results

Every original, --continue, --resume, headless-text and headless-json exit has a *-terminal.txt file containing before/after stty values and alternate=0 cursor=1. All 20 pairs have identical settings after masking only macOS PENDIN (0x20000000), the pending-input bookkeeping bit; canonical input, echo, signals and control characters match. The shell is visible and responsive after exit.

Each full-run escape-summary.json has three alternate-screen enters and three leaves, for original/continue/resume. Headless invocations added no alternate-screen entry. Cursor-show escapes were present, and tmux reports cursor=1 after each exit.

All owned tmux servers were killed. A final ps -axo pid,ppid,command inspection found no QA fake-agent process, no QA driver and no tmux server using any CHD-81 socket. Other users' sessions/processes were left alone.

[verification.json](verification.json) records the 168 capture and terminal checks. [session-proof.json](session-proof.json) shows that the cancelled queued draft is absent from all four original records, /clear created a different session id, and the stored prompts retain bash context and file-mention text. The original and --continue /status captures also report the same id in all four runs. [cleanup.txt](cleanup.txt) records the final process/socket check.

## Findings and limits

No new product defect was found. CHD-80's starting mode loss on an already reopened record was observed and excluded as instructed. CHD-79, CHD-60 and CHD-72 remain the existing flake/owner decisions; they were not reopened. Resumed edits lose their diffs because acpx stores less detail than the live turn, as documented in decisions.md; the stored prompt/reply/tool transcript replayed.

The repository-wide privacy scan found private headers only in pre-existing untracked CHD-32 design captures. This is already filed as CHD-52, with reproduction; no duplicate task was created. CHD-32 and CHD-76 untracked design evidence is deliberately outside this commit. The new CHD-42 evidence scan is clean.

The scope is fake-agent behaviour, not a claim about every ACP agent. No live model was used. No components, renderers, parsers or protocol helpers were written, so no new library trial was needed; this proof exercised the existing acpx/Ink stack and the existing fixture with tmux.
