# Source rules

- `registry.ts` (`bun dev registry`) and `ui/header/mark.ts`
  (`bun dev mark`) are generated; never edit them.
- Write settings only through `saveTheme` or `saveEditorMode`: writes are atomic and keep the file's other keys.
- `.mcp.json` and the MCP configuration are read only.
- Read team files on request, never at start; write only through
  `propose_team`'s save. Selected runs freeze composition and instructions;
  later member admission rereads policy, never the saved team.
- Read a file that may be absent through `not_found.ts`; absent means none.
