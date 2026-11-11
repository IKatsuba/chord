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
- Never reach a real model, agent or resource provider. Inject fixture resource
  access explicitly; omitted access is disabled, never an official fallback.
  `colour.ts` sets `CHORD_RESOURCE_FIXTURE=true` for spawned processes to
  inherit; retain it when supplying a child environment. The system credential
  store refuses every operation under that flag; inject fixture secrets and
  sign-in effects instead.
  Fake/QA launches use fixture collectors even if real provider CLIs exist.
  riff uses the local fake Chat Completions provider in `fixtures/riff/`;
  `CHORD_RIFF_FAKE_PROVIDER` sets its URL, and `CHORD_RIFF_BACKEND=wasm`
  forces WebAssembly. Neither is a setting. Only the start of the prompt
  selects a scenario: `call`, `tool`, `hang`, `long`, `fail` or `think`.
  `call <tool> <json>` exercises a tool; words later in a prompt never
  select a scenario. The riff team fixture is `fixtures/teams/fake/riff.md`.
  In the pending action only, `[review:clear]` selects clear and
  `[review:failed]` selects a failed review; other review calls return caution.
  These markers in requests or prior results never select the verdict. `fixtures/riff/tree.ts` supplies
  fff's git and non-git file-set cases. Credential tests inject `Secrets`
  and fake plan fetches; never call `Bun.secrets`. QA credential states use
  `CHORD_RIFF_QA=1` with a fake provider URL and `CHORD_RIFF_QA_STATE`;
  provider and store-name overrides are documented in the guide.
