# CHD-307 — OpenTUI part 4: the transcript restored

Captured with `tmux capture-pane -p` from source on the fake agent
(`bun run chord:fake`), `main` at 3538862 and the `opentui` branch with
this part, each in a fresh `/tmp/chord-qa.XXXX` (the name masked).

- `scroll-<step>-<tree>-<size>.txt`: `calls`, then `long`, then in order:
  `news` (pgup while `long` streams: the rule says new output below),
  `back` (Esc, still scrolled back), `wheel` (three wheel steps up, SGR
  reports typed into the pane), `ctrlo` and `ctrlo-closed` (ctrl+o twice
  while scrolled back), `resized` (the window resized to 100×30 while
  scrolled back), `bottom` (end). The spinner's frame in `news` is the
  only difference between the trees, at both sizes.
- `diff-<state>-<tree>-<size>.txt`: `rewrite`'s diff folded, opened by
  ctrl+o, and at 80×24 opened and scrolled back a page. Identical.
