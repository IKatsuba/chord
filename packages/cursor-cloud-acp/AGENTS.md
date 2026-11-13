# Cursor cloud ACP rules

- This is a Node 22.13+ ACP agent, separate from chord's binary. Source
  uses `node:` built-ins, never `Bun` or `bun:*`. Tooling runs on Bun.
- `@cursor/sdk` is exact-pinned at 1.3.1 by the owner. Build leaves all
  packages external; its metafile must contain only this package's source.
- `main.ts` wires the real Cursor and keychain. `serve.ts` and its imports
  use SDK types only; tests inject the Port, git and credentials. Never
  reach Cursor, a real keychain or the network in tests.
- Check git before credentials. A new session needs a work tree, attached
  branch, push remote and a local remote-tracking ref containing HEAD.
  Never fetch to decide whether it is pushed. Strip URL user and password
  before a push URL reaches Cursor or the screen.
- Resolve credentials for each session: nonempty `CURSOR_API_KEY`, else
  an unexpired keychain entry, else signed out. Never use the SDK's login
  file. Keychain calls are bounded at 10 seconds; no file fallback.
- Only ACP writes stdout while serving. SDK errors keep their message as
  one plain line; class, code and request id belong in error data. No
  parsing error words, guessed event shapes or answered Cursor requests.
- Models have one option each and separate parameter options. Start a
  chosen model outside max mode when possible; offer only combinations
  the SDK's variants contain. Mark `reasoning_effort` as `thought_level`,
  and `context` and `fast` as `model_config` with
  `_meta["chord/parameter"]` set to `"context"` and `"fast"` respectively.
  Other parameters stay uncategorised; Cursor's default offers none.
  Mode and model changes apply next turn.
- Cancel is bounded at 10 seconds. Drop late updates after the turn ends.
  Closing a session or process closes handles without cancelling cloud
  runs. A resumed run still going is reported, never followed live.
- Tests mirror `src/` under `tests/`; fixture entry is
  `tests/fixtures/main.ts`. Its QA argv and scenarios are in the guide.
  Run `bun dev quality cursor-cloud-acp` from the repository root;
  `--static` leaves out tests, build and packed Node smoke. Smoke installs
  dependencies, then refuses a session outside git without Cursor or
  keychain access. chord's checks exclude this package except privacy.
- The owner's `bun dev release cursor-cloud-acp` runs install, quality,
  build, pack and publish. Build is required for a new version; publish
  tags `cursor-cloud-acp-v<version>` and creates no GitHub release.
