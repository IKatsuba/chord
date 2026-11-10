# Runtime rules

- Only this folder calls `Bun.*`; everything else in `src/` calls `node:` built-ins, so moving runtime is this folder's change.
- `secrets.ts` alone calls `Bun.secrets`, through an explicit system/fixture
  choice. Keep one serial queue per process and a 20 s deadline per call.
  A timed-out operation keeps its queue place; await a late write or delete
  before releasing its credential lock. Errors name the platform's store
  and recovery step, never backend details or secret values. No store
  means no sign-in; never fall back to a file, environment or memory.
- riff's list and search use fff in one Worker per session directory, on
  fff's own semantics. Cancelling a call ends the Worker; the next call
  rescans, and unaffected pending calls are sent again. Close the finder
  with its session.
- Resource factories require an explicit official/fixture choice; omitted UI
  access is disabled. Fixture mode never falls back to provider executables.
- Keep collectors on approved public library APIs and owned process groups,
  with bounded acquisition/cleanup. Never patch framing, SDKs or launchers,
  resolve private vendor layouts, or read credentials. A deadline is no cap on
  the Codex client's incomplete-frame buffer.
