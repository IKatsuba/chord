# Test rules

- UI tests draw through `ui/harness.tsx`, on OpenTUI's test renderer.
  Set the terminal up before the first render; use stdout buffering with a
  10 s NativeSession close timeout.
  The production-build boundary fixture uses OpenTUI's test renderer directly
  with `scripts/dev/compile.ts`'s build options, exercised by
  `scripts/dev/compile_test.ts`.
- Window tests go through `ui/app/render.tsx`'s `withWindow`, which checks
  every agent the window started is gone. After unmount, it waits up to
  10 s for pending starts to settle and fails on a failed stop, including
  one from a start that already failed.
- Bun's `expect` narrows no type; use `node:assert`'s `assert` where a later line needs it.
- Start chord or the fake agent under `process.execPath`, the Bun running the test.
- Helpers sit beside the tests that share them.
- Add a new test to `tsconfig.json`'s `files` when its path differs from
  another file only by case, so tsc checks both on a case-blind file system.
- Never reach a real model or a real agent.
