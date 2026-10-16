# CHD-160: the four subagent states, on the fake agent

Captures of chord from source on the fake agent's `subagentstates` scenario
(commit 2e000eab), in tmux at 120×40 and 80×24, named after the CHD-149 mocks
they are compared with (`docs/design/evidence/CHD-149/mock/`):

- `plan` and `one-running`: the parent's plan above the prompt beside a lone
  `Agent(Find the session layer)`. The scenario reaches both in one moment,
  so the two captures are the same screen.
- `codex-wait`: the `Running 2 agents…` group under the parent's
  `Wait(explorer, worker)`.
- `finished`: `2 agents finished`, both children done, then the answer.

`plan`, `one-running` and `codex-wait` were taken with
`CHORD_FAKE_STEP_MS=150`, `finished` with `CHORD_FAKE_STEP_MS=40`.

## What was changed

chord ran in a scratch directory from `mktemp -d`, whose path the header
prints. That path is replaced by `~/src/app`, the mocks' directory, in the
third row of each capture that shows the header; nothing else in the
captures was edited.
