# Runtime rules

- Only this folder calls `Bun.*`; everything else in `src/` calls `node:` built-ins, so moving runtime is this folder's change.
- Resource factories require an explicit official/fixture choice; omitted UI
  access is disabled. Fixture mode never falls back to provider executables.
- Keep collectors on approved public library APIs and owned process groups,
  with bounded acquisition/cleanup. Never patch framing, SDKs or launchers,
  resolve private vendor layouts, or read credentials. A deadline is no cap on
  the Codex client's incomplete-frame buffer.
