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
  flag; its tools are read, list, search, edit, write and shell. Edit and write
  share a real-path session grant and refuse a changed proposal; shell grants
  cover exact commands, with cancellation stopping the process group.
  It is listed only with nonempty `CHORD_RIFF_FAKE_PROVIDER`, which
  `bun dev chord --fake` and `--qa` set for development; production stays
  hidden until sign-in lands.
  Sessions use libfx's `local()` store under chord's state directory, with
  a sidecar per session; chord's record remains what was shown.
- riff's plan credentials use `platform/secrets.ts` only. Refresh and logout
  share a per-provider `proper-lockfile` lock and in-process mutex; reread
  inside the lock and compare before saving a rotation. Recheck the store
  at each prompt; a missing entry or changed account refuses it. A failed
  refresh never clears the stored entry. `_chord/credentials` notices apply
  only to the current riff session.
  Fake and QA launches use in-memory secrets and fake providers. `--qa`
  enables `CHORD_RIFF_QA_STATE`, `CHORD_RIFF_QA_PROVIDER` and
  `CHORD_RIFF_QA_STORE` fixtures documented in the guide; never use the
  system store or a live provider for them.
