# Source rules

- `registry.ts` (`bun dev registry`) and `ui/header/mark.ts`
  (`bun dev mark`) are generated; never edit them. Recheck `agents.ts`'s
  recorded fast-option ids when their adapters' pins change.
- `chorded.ts` holds chord's own npx agents, merged by name with the
  registry. Pins are literals; bump one only after its package is on npm.
  `cursor-cloud` defaults to `mcpServers: false`: cloud agents cannot reach
  local servers. Nothing in `src/` imports `packages/`, `@cursor/sdk` or
  `@napi-rs/keyring`; neither dependency belongs in chord's binary.
- Write settings only through `saveTheme`, `saveEditorMode` or `saveSettingAt`:
  writes are atomic and keep the file's other keys.
- `.mcp.json` and the MCP configuration are read only.
- Read team files on request, never at start; write only through
  `propose_team`'s save. Selected runs freeze composition and instructions;
  later member admission rereads policy, never the saved team.
- Read a file that may be absent through `not_found.ts`; absent means none.
- No console calls in `session/`, `acp/` or `server/`: stdout may carry ACP.
