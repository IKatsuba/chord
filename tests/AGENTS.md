# Test rules

- UI tests draw through `ui/harness.tsx`, on OpenTUI's test renderer.
  Set the terminal up before the first render; use stdout buffering with a
  10 s NativeSession close timeout.
- Window tests go through `ui/app/render.tsx`'s `withWindow`, which proves every process started is gone.
- Bun's `expect` narrows no type; use `node:assert`'s `assert` where a later line needs it.
- Start chord or the fake agent under `process.execPath`, the Bun running the test.
- Helpers sit beside the tests that share them.
- Add a new test to `tsconfig.json`'s `files` when its path differs from
  another file only by case, so tsc checks both on a case-blind file system.
- Never reach a real model or a real agent.
