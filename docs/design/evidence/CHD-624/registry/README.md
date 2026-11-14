# The registry refresh (U4, commit 78435784b)

`bun dev chord agents` and the picker (`--qa`, no agent picked), CHD-624
beside origin/main. PNGs here, text in `text/`.

- `u4-agents`: the rows D6 names change as designed. claude 0.107.0;
  github-copilot-cli titled GitHub Copilot (1.0.112); kimi is npx
  `@moonshot-ai/kimi-code@2.6.2 acp`; autohand moves from npx to own CLI
  `autohand --acp`; kiro gains `--agent-engine=v3`; the own-CLI kimi row
  is gone. Pins are the registry's on 2026-11-14, newer than the design's
  mock.
- `pick-*` (a open, b and c scrolled down): `kimi · Kimi Code` sits among
  the npx agents, `github-copilot-cli · GitHub Copilot` reads its new title,
  and autohand, not on PATH, is not offered. Columns and frame as on
  origin/main.
- `pick-80x24-end`: at the list's end the row under it still reads
  `… +17 more`, the count of rows below the first page; origin/main draws
  it the same way (`main-pick-*-c`), so it predates this task.
