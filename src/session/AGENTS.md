# Session and ACP rules

These rules also cover `src/acp/`.

- Every session's traffic runs through the enricher chain (`enrich.ts`, `enrichers.ts`) on the transport's relay; state, record, window, `-p` and `acp` read only what it leaves.
- Enrichers are pure, with ACP's shape on both sides; name what chord filled under `_meta`'s `chord/filled`.
- `transcript/` is a pure reducer, one module per kind of update.
- Session records (`record.ts`) are a stored format: older records must still
  read back. Embedded resources retain only `uri` and `mimeType`, never
  content. Legacy `windows/` files are ignored and left untouched.
- MCP servers go through `servers.ts` on new, fork, load and resume: stdio always,
  HTTP, SSE and ACP only when advertised. The agent's `mcpServers: false`
  setting holds every server back, chord's own included; its setting of
  `true` overrides a default of none. `--no-mcp-servers` beats the files for
  the startup agent by name, including children and team members of that
  agent. Never record it; resume needs it again. Held-back lines name the
  flag when it caused the suppression. Keep the held-back names and reasons.
- Forks use ACP `session/fork` in their own agent process, as resume does.
  Route the answer to the new session ID, not the source. Record the divider
  and subsequent work; the copied source transcript stays out of the record.
- Clear replaces the agent session, not the child's identity. Old calls and
  task reports lose delivery authority immediately. The next surviving prompt
  carries any team part exactly once; a withdrawn prompt does not spend it.
- The window's and `acp`'s sessions are recorded; `-p`'s are not.
- `acp` accepts embedded resources only when the agent advertises
  `embeddedContext`; otherwise refuse the whole prompt before sending it.
  Ordinary, queued and steered prompts preserve resource blocks after images
  and before links. The window's file mentions remain `resource_link` blocks.
- `_meta["chord/permission"]` carries optional review outcome/reason and
  `deadlineAt` for any agent; ignore invalid fields. Preserve it through
  transcript reduction and ACP forwarding. `-p` denies reviewed asks even
  with `--dangerously-skip-permissions`; the requesting agent owns timeout.
- Nothing here or in `src/acp/` imports from `src/ui/` or React.
  `agents_host.ts` owns main, children, teams and their MCP view; it imports
  `src/server/` for runtime probes, MCP types and the settings-box claim.
  Window effects and state reads go through its synchronous port callbacks.
- `get_budgets` returns per-call provider windows or unavailable reasons;
  missing values stay null. `readAt` is the call time, not provider freshness.
  Omitted runtime filters read Claude and Codex; empty filters read none.
  Never infer account identity or combine independent windows.
- `run_team` records no budget read or budget warnings. Preserve reads and
  warnings in historical receipts; never manufacture missing provenance.
- Selection allowlists apply only to selected runs, across every effective
  role. Freeze composition; check current policy and observed startup before
  each first job. Confirm runtime and requested model/mode; omitted defaults
  stay unknown until observed. Effort stays soft.
- Persist actual admitted receipts in existing records, including refused
  attempts in the caller's record. Never invent provider IDs, ACP events or
  prompts to make a receipt replay. Historical missing values stay unknown.
