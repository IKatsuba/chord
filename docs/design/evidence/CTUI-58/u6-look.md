# U6 (CTUI-58): a request held inside an agent's own cycle, looked at

Handed source: `60da2f1`, then the fix `179c078`. Both programs were started with the same `--agent-command 'bun ../chord/tests/fixtures/fake_agent/main.ts --adapter claude --no-usage'`, isolated `XDG_CONFIG_HOME` and `XDG_STATE_HOME`, working directory `/tmp/ctui58-u6/wd`. The original was v0.71.0, run from `../chord/src/main.tsx`. Steps: `claudecycleask`, Enter, wait for the cycle's request (`held`), `/cost` (`cost`), ctrl+x a (`ask`), `1` (`allowed`), then the cycle's end (`ended`).

The look passes at `179c078`.

- `held`: `⏺ Write(notes/build.md)` / `⎿  Waiting…`, the working line `››› Waiting for permission…`, and the `main asks · between turns` box with `ctrl+x a to answer`, as the original's at both sizes. At `60da2f1` the `⎿  Waiting…` row was missing; `179c078` passes the original's `ended && !asks` (Transcript.tsx:232).
- `cost`: `/cost` shows the running turn's row, `counted when it ends`, as the original's. Only the session time differs.
- `ask`, `allowed`, `ended`: the answer box, the working line resuming from the cycle's start, and the cycle's end as a turn's end match the original's.

Old, not this unit, taken to the lead: at 120x40, while a request is held between turns, the port's status line drops `· ? for shortcuts` and keeps `· medium effort`, where the original keeps the hint and drops the effort (`! heldBack(app)` in `window.dart`, since `d83648e`, CTUI-21). It matches at 80x24. Also old: the version and the header's `· /help`.

## U6b: the shortcuts hint while a request is held

Handed source: `ef9d048`, same setup, `held` state. `u6b-held-p-{120x40,80x24}` beside `u6-held-o-*`: the status line now reads `● permission asked between turns · ctrl+x a to answer · ? for shortcuts` with `Fake Large with a 1M context window` on the right, the effort giving way as in the original. Identical at both sizes but for the version and the header's `· /help`.
