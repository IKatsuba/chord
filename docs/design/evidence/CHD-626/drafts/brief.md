# CHD-626 brief: model parameters in place; `/effort` and fast

## The problem

The owner, 2026-11-13, after a live run of `cursor-cloud` (CHD-622): choosing
a model's effort and other parameters in chord is bad UX, for every agent.
`/model` lists models only. Effort, fast and context live in `/config` as
separate options, one Enter-list per option. On cursor-cloud's "Cursor's
default" (Auto), `/config` said "cursor-cloud has no settings other than its
model and mode": nothing to change at all. The task is `board show CHD-626`.

## The owner's direction (from the task)

- Claude Code, the one the owner finds most convenient: `/model` lists models
  with one line under them, "◐ Medium effort (default) ←/→ to adjust"; ←/→
  changes the highlighted model's effort in place; Enter sets model and
  effort. `/effort` opens its own slider (low · medium · high · xhigh · max,
  "Faster ↔ Smarter", ←/→, Enter). `/fast` toggles fast mode.
- Cursor's CLI: each model's current parameters beside it ("256K High
  Fast"); Tab on a model opens "Edit Parameters" with every parameter
  (Context, Effort, Fast) as radio groups.
- Codex: after a model is chosen, its effort choice opens.
- Wanted: effort changeable in the model picker (Claude-style), a separate
  `/effort`, a separate way to toggle fast, and the context window reachable
  somewhere (e.g. `/config`).

## What chord has today (read the code, do not take this as complete)

- `/model`: `src/ui/pickers/` (state.ts, picker.ts, Pickers.tsx); models from
  the `model` config option or the legacy `models` field
  (`src/session/models.ts`), set by `session/set_config_option` or
  `session/set_model`.
- Effort: `src/session/efforts.ts`, the select option of category
  `thought_level` only, never by id or name. The status line shows it.
  `--effort` for headless runs.
- `/config`: `src/session/config.ts`, every select option but mode and
  model, one list per option.
- ACP SDK 2.2.0 (`SessionConfigOptionCategory`): reserved categories `mode`,
  `model`, `model_config`, `thought_level`; names beginning with `_` are free
  for custom use; categories "MUST NOT be required for correctness" and
  unknown ones are handled gracefully. Config options may be `select` or
  `boolean` (`SessionConfigBoolean`). chord's `/config` lists selects only.
- What agents send: `docs/agent-capabilities.md` (per agent). Known: Claude's
  adapter `effort` (`thought_level`); Codex's `reasoning_effort`
  (`thought_level`); fx sends `fast` and `ultrafast` as category `model`
  (fx9), which chord today may take for its model option; cursor-cloud
  (`packages/cursor-cloud-acp/src/config.ts`, ours) sends each model's
  Cursor parameters as selects with no category on purpose ("the ids Cursor
  gives are not recorded yet"), and none for Cursor's default.
- Option sets change with the model: adapters resend options on a model
  change (`config_option_update` or the `set_config_option` answer).

## What a person sees and presses (to be designed)

`/model` with the highlighted model's parameters in place; `/effort`; a way to
toggle fast; context reachable; every action with a key, listed in the
shortcuts panel (`?`), rebindable ones in `src/ui/shortcuts/bindings.ts`.

## Constraints

- AGENTS.md is binding: the one rule (OpenTUI's components before ours; no
  workaround around a library on our own call), every action has a key,
  logic in pure tested modules, tests with fake ACP fixtures only.
- **Never guess a parameter's meaning from free text** (an id or name like
  "fast" or "context"). If ACP gives no way to recognise fast or context,
  say so and give the owner options; do not decide it.
- Works for every agent chord runs, including ones that send no such
  options, or send effort as a plain uncategorised select.
- Parameters are per model and arrive only after the model is set: the
  agent tells chord a model's options when it is on that model. Any
  "change the highlighted model's effort before choosing it" must say how
  that is possible over ACP, or what it does instead.
- No tabs (CHD-493). Output text is English, no private paths.

## Non-goals

- No change to what Claude's or Codex's adapters send (upstream).
- No settings-file default effort per model beyond what exists, unless a
  draft shows it is needed (then it is an owner question).
- The status line's layout beyond showing what it shows now.

## Open questions

The task's four, each answered with options and a recommendation:

1. `/model`'s layout and keys for effort and other parameters, for agents
   that report them as config options and for those that do not.
2. `/effort` and how fast is toggled: names, what they show, what they do for
   an agent without such options.
3. Which parameters stay in `/config`; how an option is recognised as effort,
   fast or context when it has no ACP category (`model_config`, `_`-custom
   categories, `_meta`, our own cursor-cloud package setting categories,
   upstream asks).
4. What a model with no parameters (Cursor's Auto) shows.

Per architect:

- **protocol**: what every agent chord runs actually sends (ids, categories,
  select vs boolean, per model, when resent), from
  `docs/agent-capabilities.md` and the adapters; how chord recognises
  effort, fast and context without guessing (Q3) with options; what
  cursor-cloud-acp should send (it is ours); how a parameter for a model not
  yet chosen can be set (order of `set_config_option` calls, the race with
  the resent option set, failures); fx's `fast` under category `model`;
  boolean options in `/config`.
- **interface**: the screens of `/model`, `/effort`, fast, `/config` and the
  no-parameter model, at 120x40 and 80x24, with states (loading, setting,
  failed, agent without options, Auto); keys and their shortcuts-panel
  entries; how the state slices in `src/ui/pickers/state.ts` change; Q1, Q2,
  Q4 with options and a recommendation.
- **runtime**: the sequence of ACP calls when model and parameters change
  together, concurrency with a running turn and with resent option sets,
  failure and partial success (model set, effort refused), what is pure and
  how each piece is tested with fake ACP fixtures (`tests/fixtures/`), the
  headless `--effort` path, and whether a `--fast`/settings counterpart is
  needed (owner's if so).
