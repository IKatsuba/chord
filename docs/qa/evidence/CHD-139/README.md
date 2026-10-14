# CHD-139 independent QA

Tested `6461cce` on `main`, after the reviewer's Return 1 approval. The designer's appearance remains settled; CHD-143 is separate.

## Commands run

- `deno task check` with process-query access for fixture cleanup tests.
- `deno task compile`.
- Source TUI: `deno run --allow-all src/main.tsx fake --agent-command "deno run --quiet --allow-env --config <checkout>/deno.json <checkout>/tests/fixtures/fake_agent.ts --tokens-only --silent-set-mode --resume-only" -C <scratch>`.
- Compiled TUI: `dist/aarch64-apple-darwin/chord` with the same arguments and `--continue`, then a separate plain fake session.
- An isolated tmux server, scratch working directories, and isolated `XDG_CONFIG_HOME` and `XDG_STATE_HOME`; 120x40, resized to 80x24. Every UI action used keys. Literal text and Enter were sent separately.
- Compiled `-p text --output-format json` for plain and `--tokens-only` fakes; compiled `-p mode --permission-mode plan --output-format json` for `--silent-set-mode`.
- Independent temporary Deno assertions using the full enricher chain: both mode-setting methods, each with an intervening mode notification or changed mode config options, followed by another silent request.
- Independent fake-session assertions: modes confirmed inside prompts, title/kind carried onto tool updates, running cost and window provenance, and closure verified with `ps`.
- `tmux capture-pane`, pane alternate-screen/cursor state, raw terminal escape inspection, `stty -g` before/after, and `ps` before/after. Killed only the two owned tmux sessions and verified the isolated server was gone.
- Private-path scan of these evidence files.

## Observations

- Before a turn, the status line names the model without inventing a context figure.
- At 120x40, one tokens-only turn produces `$0.0047 (chord's estimate)` and `~99% context left`; context is 2,000 of 400,000.
- Silent Shift+Tab reports accept edits before a prompt. The agent's `mode` answer confirms `acceptEdits`.
- At 80x24 after three turns, cost is `$0.0141` and input/output/cache-read totals are 3,000/600/2,400. Context remains the last turn's 2,000 tokens. Tool completion retains `Read(README.md)`.
- The compiled resume reopens those three turns once, at `$0.0141`. One more turn gives `$0.0188` and totals 4,000/800/3,200. The same record holds exact enriched totals 0.01407 and 0.01876, plus carried tool-update title/kind with provenance.
- Plain compiled fake: `$0.0125`, 2,000 of 1,000,000, and `99% context left`, all unmarked.
- Compiled JSON: estimated cost 0.00469 with `cost_estimated: true`; agent cost 0.0125 without that flag. Silent starting mode returns `Mode: plan.`.
- All four independent mode/report race combinations preserve the agent's intervening report. Subsequent silent requests still get readback. Both independent fake-session cases pass.
- The deliberate agent error is displayed. Esc interrupts `slow`, removes the working state, and adds no estimated turn cost. A refused mode change displays the agent's reason and keeps plan mode.
- Quitting source and compiled builds restores the shell, alternate screen off and cursor visible. Raw terminal output confirms exit/show sequences. Terminal settings match except macOS's PENDIN bit, which reflects pending input reprocessing.
- No live agent or model was used. No owner configuration was edited. Existing unrelated processes were left alone.

The dependency exercised by the source and compiled pricing paths is exact-pinned `@pydantic/genai-prices` 0.1.9, whose price/window data ships in the package. Engineering's evaluations of tokenlens, models.dev and LiteLLM remain recorded in `docs/decisions.md`; QA introduced no component, renderer, parser, protocol helper or dependency.
