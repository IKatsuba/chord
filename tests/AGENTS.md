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
- ACP pipe-order tests can pass an `AgentProcess` with held streams to
  `src/acp/connection.ts`'s `connectAgent`, controlling stdout and stderr
  independently.
- Helpers sit beside the tests that share them.
- `tests/timings.json` only places files: Bun balances shards and starts
  each worker's slowest files first by it; unlisted files take the median.
  No refresh is required.
- Use fake-agent gates and observed conditions instead of fixed pauses to
  order events. Waits must be bounded and use a monotonic clock, so fake
  system time cannot stop their deadline. Reuse `until` from
  `ui/app/render.tsx` or `session/conversation_fake.ts` (10 s by default).
- Add a new test to `tsconfig.json`'s `files` when its path differs from
  another file only by case, so `bun check` checks both on a case-blind
  file system.
- Never reach a real model or a real agent.
