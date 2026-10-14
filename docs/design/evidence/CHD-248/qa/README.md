# CHD-248 independent QA

Checked on main at 3a1b084, including cdbaf29. Appearance was already passed
by the designer; this pass proves behavior.

Ran `deno task check`, `deno task compile`, then source (`deno task chord:fake`)
and the compiled binary against `tests/fixtures/fake_agent/main.ts`, in an
isolated tmux server with scratch working directory, config and state.
All interaction was by keys, with text and Enter sent separately.

- `mcpask` at 120x40 and 80x24 shows the command, description and timeout
  before approval. Resizing a pending request preserves the choices and input.
- At 50x24 the command wraps with its continuation at the key's indent.
  Ink's native wrapping is exercised directly; nested formatting uses the
  tested `JSON.stringify` helper. No library or implementation was added.
- Source: Down/Enter selects `always`, 1 selects `allow`, Esc selects `deny`.
  Compiled: 3 selects `deny`; Down/Up/Enter selects `allow`; Esc rejects.
  The agent's reply reports the selected option id, and denial leaves a
  failed tool and a Rejected line.
- `permission`, with diff content and rawInput, retains the prior title,
  question and choices at both sizes, without argument lines.
- `error` displays `The fake agent failed on purpose.` in both builds.
  `slow`, then Esc, displays `Interrupted by user` and returns to the prompt.
- Source ctrl+d after the interrupt, and compiled ctrl+d while an MCP request
  remained unanswered, both return to a usable shell. tmux reports
  `alternate=0 cursor=1`; `stty -a` reports `icanon` and `echo`.
  `ps` confirms all identified client and fixture PIDs gone, then the owned
  tmux server is removed.

Captures are independent QA observations; the original mock-7 and unchanged
content acceptance captures remain in the parent directory. Cleanup captures
stay outside the repository because the shell prints the local launch command.
No live agent/model was run, no agent configuration was edited, and nothing
was pushed or published. The previously filed argument-height issue remains
CHD-251; no new finding was filed.

Validation completed: `deno task check` passed types, lint, formatting and
1,347 tests (20 steps), zero failures, in 7m40s. `deno task compile` produced
the native binary exercised above. The staged evidence privacy check passed
all seven tests after rerunning with the test task's required Deno permissions;
the first narrow invocation omitted write/env permissions. Final `ps` found
no check process or fake-agent fixture left. `git diff --cached --check` passed.
