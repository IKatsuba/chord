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
  It is the catalog's first agent; Claude stays the default. Listing reads
  no credentials. `CHORD_RIFF_FAKE_PROVIDER`, set by `--fake` and `--qa`,
  selects only the development provider.
  Sessions use libfx's `local()` store under chord's state directory, with
  a sidecar per session; chord's record remains what was shown.
- riff's window owns sign-in through libfx; `-p` and `acp` report the
  failure with `run chord riff to sign in`. Plan credentials use
  `platform/secrets.ts` only. Sign-in, refresh and logout share a per-provider
  `proper-lockfile` lock and in-process mutex; reread
  inside the lock and compare before saving a rotation. Recheck the store
  at each prompt; a missing entry or changed account refuses it. A failed
  refresh never clears the stored entry. New sessions prefer the last signed-in
  provider still stored; resume keeps its recorded provider and account.
  `_chord/credentials` notices apply only to the current riff session.
  Fake and QA launches use in-memory secrets and fake providers. `--qa`
  enables `CHORD_RIFF_QA_STATE`, `CHORD_RIFF_QA_PROVIDER` and
  `CHORD_RIFF_QA_STORE` fixtures documented in the guide. Fake/QA sign-in
  uses `CHORD_RIFF_QA_SIGN_IN`; never use the system store or a live provider.
- `/login` opens riff from another agent, or signs in in place on riff;
  success starts a fresh session with the transcript kept. `/logout` belongs
  only to riff: delete locally, cancel this window's riff turns and children,
  and end the session. Revoke Grok's refresh token after deletion and report
  failure; ChatGPT tokens are not revoked.
