# Source rules

- `registry.ts` (`bun dev registry`) and `ui/header/mark.ts`
  (`bun dev mark`) are generated; never edit them.
- Write settings only through `saveTheme`, `saveEditorMode` or `saveSettingAt`:
  writes are atomic and keep the file's other keys.
- `.mcp.json` and the MCP configuration are read only.
- Read team files on request, never at start; write only through
  `propose_team`'s save. Selected runs freeze composition and instructions;
  later member admission rereads policy, never the saved team.
- Read a file that may be absent through `not_found.ts`; absent means none.
- No console calls in `session/`, `acp/`, `server/` or `riff/`: stdout may
  carry ACP.
- `riff/` serves one ACP session per process on the hidden `--riff-agent`
  flag; its tools are read, list and search. It is listed only with nonempty
  `CHORD_RIFF_FAKE_PROVIDER`, which `bun dev chord --fake` and `--qa` set for
  development; production stays hidden until sign-in lands.
  Sessions use libfx's `local()` store under chord's state directory, with
  a sidecar per session; chord's record remains what was shown.
