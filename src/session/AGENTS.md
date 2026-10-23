# Session and ACP rules

These rules also cover `src/acp/`.

- Every session's traffic runs through the enricher chain (`enrich.ts`, `enrichers.ts`) on the transport's relay; state, record, window and `-p` read only what it leaves.
- Enrichers are pure, with ACP's shape on both sides; name what chord filled under `_meta`'s `chord/filled`.
- `transcript/` is a pure reducer, one module per kind of update.
- Session records (`record.ts`) are a stored format: older records must still
  read back. Legacy `windows/` files are ignored and left untouched.
- MCP servers go through `servers.ts` on new, load and resume: stdio always,
  HTTP, SSE and ACP only when advertised. The agent's `mcpServers: false`
  setting holds every server back, chord's own included; its setting of
  `true` overrides a default of none. Keep the held-back names and reasons.
- The window's sessions are recorded; `-p`'s are not.
- This layer is below the interface and shared with `-p`: nothing here or in `src/acp/` imports from `src/ui/`.
