# CHD-196 independent QA

Tested `797e6a9` on top of `6a6820a`, on main. No real agent or model was used.

## What ran

- `deno task check`, with process-query access: types, lint, formatting and
  fake-agent tests; 1051 passed, 20 steps, zero failures, 5m21s.
- `deno task compile`: produced the host binary, which started in an isolated
  tmux pane and completed the fake shell scenario.
- Six fresh source sessions: shell, shellcut and bash at 120x40 and 80x24.
  Literal scenario text and Enter were sent separately. Each was captured
  folded and after ctrl+o, then quit with ctrl+d.
- Source session: shell, capture after its third delta (inside a split CSI),
  resize 120x40 to 80x24, Esc, shellcut, ctrl+o, error, bash, resize back to
  120x40, and ctrl+c twice to quit.
- Compiled session: shell at 80x24, ctrl+o, resize to 120x40, ctrl+d to quit.
- `-p` text and JSON against the fake agent, comparing pre-change main
  `6b27797`, current source and the compiled binary: shell, shellcut, bash,
  error, and `/echo tiny prompt` with `piped input` on stdin. Compared stdout,
  stderr and exit status; JSON comparison excludes only generated session_id.
- Read all six fresh session records and compared terminal updates with
  SHELL_OUTPUT, CUT_OUTPUT and BASH_OUTPUT byte-for-byte.
- After quitting: tmux alternate_on/cursor_flag, stty before/after, shell
  keyboard input, owned-process checks with ps, and isolated-server cleanup.

Every UI action was driven by keys in an isolated tmux server. Each session
used a neutral scratch directory and isolated XDG_CONFIG_HOME/XDG_STATE_HOME.
The launch was equivalent to `deno task chord:fake -C "$WORK"`; the compiled
run used `dist/aarch64-apple-darwin/chord fake --agent-command "$FAKE" -C "$WORK"`,
where FAKE runs tests/fixtures/fake_agent.ts through Deno with repository config.

## What was observed

All twelve fresh scenario captures match the engineer's after-captures below
row one. The isolated scratch path is longer, so row one's directory and its
preceding spaces differ; comparison.txt documents that exclusion. All other
rows, including whitespace, match exactly. Shell and bash retain the original
baseline output. Shellcut retains exactly the lead's accepted correction:
both real lines survive and the invisible OSC URL causes no cut marker.

Progress rewrites drew 3/3 without escape debris. Esc during a split escape
showed Interrupted by user. The resized session then completed shellcut,
showed Exit code 1 and the failed test text, displayed The fake agent failed
on purpose for an agent request error, and completed a subsequent bash prompt.
The compiled binary drew the same shell output at both sizes.

All headless comparisons matched, including error exit 1 and successful exit
0. No alternate-screen or cursor-mode controls appeared in headless output.
Every recorded terminal update remained whole, escapes and the long OSC URL
included. The full suite also passed split invariance, bounded parser/cursor
state, whole-grapheme cuts, replacement output, live/agent/record replay equality
and whole-record assertions.

Every one of the eight TUI sessions quit with alternate_on=0, cursor_flag=1,
identical stty state and exit 0. The shell accepted keyboard input afterwards.
Final ps found no owned QA/check process or fake-agent child. The isolated tmux
server had no remaining session and exited. The pre-existing orphan PID 78189,
started at 07:00:36 and already tracked by CHD-158, was left untouched.

No product code changed during QA. Library findings were read in decisions.md,
not independently reprobed: xterm/headless was rejected after Deno run/compile
probes; ansi-tools/parser was rejected for stateless chunk parsing; the other
candidates were unsuitable. Bash mode CHD-197 and transcript split CHD-187 were
left alone. Repros covered by the passing suite: CHD-155, CHD-157, CHD-178,
CHD-190 and CHD-195; their closure remains with the lead.
