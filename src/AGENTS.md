# Source rules

- `registry.ts` (`bun run dev registry`) and `ui/header/mark.ts`
  (`bun run dev mark`) are generated; never edit them.
- Write settings only through `saveTheme` or `saveEditorMode`: writes are atomic and keep the file's other keys.
- `.mcp.json` and the MCP configuration are read only.
- Read team files whenever asked, never at start; write them only through `propose_team`'s save.
- Read a file that may be absent through `not_found.ts`; absent means none.
