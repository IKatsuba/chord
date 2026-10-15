# Test rules

- `ui/harness.tsx` is the only module that draws on OpenTUI's `testRender`.
- Window tests go through `ui/app/render.tsx`'s `withWindow`, which proves every process started is gone.
- Bun's `expect` narrows no type; use `node:assert`'s `assert` where a later line needs it.
- Start chord or the fake agent under `process.execPath`, the Bun running the test.
- Helpers sit beside the tests that share them.
- Never reach a real model or a real agent.
