# CHD-622 — runtime draft

The runtime architect's answers to R1–R7 of the brief: where the package
lives, how it is built, released and pinned, its keyring, how its process
behaves, and how it is tested. Each answer gives the options, the choice and
why. `CROSS:` marks an item the protocol or interface draft must agree with;
`OWNER:` marks a decision that is the owner's, with a recommendation.

## What was tried

Everything below ran on darwin arm64 (Node 24.13.0 and Node 22.13.0 fetched
with `npx -p node@22.13.0`), each download in a new empty directory under
`/tmp`, scripts in a separate directory, nothing from the Cursor tarball run.
No Cursor key was used and Cursor's service was not reached; the keychain
trials wrote and deleted one dummy entry (`chord-keyring-trial`/`dummy`), and
`security find-generic-password` confirmed it gone afterwards.

- **`@cursor/sdk` 1.3.1, types only** (`npm pack`, `.d.ts` read):
  - `engines.node >=22.13`, ESM with a `bun` export condition; five
    exact-pinned optional native packages `@cursor/sdk-<os>-<arch>`
    (darwin arm64/x64, linux arm64/x64, win32 x64; 10–15 MB unpacked each,
    the main package 20 MB). Peer dependency `zod ^3.25 || ^4`.
  - `SdkCredentialStore` is `{ load(): Promise<StoredSdkCredentials |
    undefined>; save(c): Promise<void>; clear(): Promise<void> }`.
    `StoredSdkCredentials` is `{ version: 1, backendUrl, apiKey,
    apiKeyExpiresAtMs?, email?, createdAtMs }`; keys are paired with the
    backend they were minted against.
  - **The store plugs into `Cursor.auth.login/logout/status` only**
    (`SdkLoginOptions.store`, `SdkAuthStatusOptions.store`,
    `SdkLogoutOptions.store`). Every other call resolves its key as explicit
    `apiKey`, then `CURSOR_API_KEY`, then the *default file store*
    (`~/.cursor/sdk/auth.json`, through `getStoredLoginApiKey()`). A
    keyring store therefore does not reach `Agent.create` by itself: the
    adapter loads the key from the keyring and passes it as `apiKey`, which
    is the documented option, not a workaround.
  - `Run` has `stream(): AsyncGenerator<SDKMessage>`, `wait()`, `cancel()`,
    optional `steer?()`, `status` (`running | finished | error |
    cancelled`) and `onDidChangeStatus`. `Agent.getRun(runId)` and
    `Agent.cancelRun(runId)` reach a run without a handle. Stream messages
    carry `agent_id` and `run_id`, `tool_call` a `call_id`, `request` a
    `request_id`; no per-event sequence id, so a re-attached stream cannot be
    de-duplicated against what was already sent.
  - Errors: `AuthenticationError` (401), `RateLimitError` (429),
    `ConfigurationError`, `AgentBusyError`, `IntegrationNotConnectedError`,
    `NetworkError`, `AgentNotFoundError`, `UnknownAgentError`, all
    `CursorSdkError` with `isRetryable`, `code`, `status`.
  - `Cursor.auth.login` writes the login URL to stderr when it opens no
    browser and has no `onLoginUrl`; it accepts an `AbortSignal`.
- **Keyring libraries**, each installed into its own empty directory and
  driven by a script that set, read and deleted the dummy entry, under Node
  24.13.0 and Node 22.13.0:

  | library | version | licence | maintained | prebuilt natives | trial |
  |---|---|---|---|---|---|
  | `@napi-rs/keyring` | 2.1.2 | MIT | pushed 2026-11-10, not archived | darwin arm64/x64, linux arm64/x64 gnu and musl, win32, freebsd, riscv; no install script | set/get/delete passed on both Nodes |
  | `keytar` | 7.9.0 | MIT | **archived** (atom/node-keytar) | `prebuild-install`, falls back to a node-gyp build | passed on both Nodes |
  | `cross-keychain` | 2.0.0 | MIT | pushed 2026-11-08, 17 stars | its native backend is `@napi-rs/keyring` as an optional dependency; also pulls `meow` and `@inquirer/prompts` for its CLI | passed; lists backends native-macos, macos CLI, **"Encrypted file storage" and a null keyring** that it falls to on its own |
  | `@zowe/secrets-for-zowe-sdk` | 8.39.1 | EPL-2.0 | active | builds on install when no prebuild matches | not installed: licence and install script ruled it out |

  `@napi-rs/keyring` on Linux (its README, not run here: no Linux host was
  used): tries the Secret Service first and **silently falls back to the
  kernel keyutils keyring**, which is in memory and lost at reboot, unless
  the entry is pinned with `{ linux: { store: 'secret-service' } }`, in
  which case the constructor throws when no Secret Service is there.
  `AsyncEntry` takes an `AbortSignal` on every call.
- **Build**: `bun build src/main.ts --target=node --packages=external`
  on a two-file sample importing `@napi-rs/keyring` and `node:fs/promises`
  gave one ESM file with the shebang kept and the packages left as imports;
  it ran under Node 22.13.0.
- **Type check of a second project**: `bun check -p <dir> --listFilesOnly`
  lists that project's files; project `references` from the root need
  `composite` and emitted declarations (`TS6310` otherwise), so they do not
  fit a `noEmit` root.
- Node 22.13.0 prints `ExperimentalWarning: SQLite is an experimental
  feature` on stderr when `node:sqlite` loads.

## R1 — Layout and chord's tooling

**Options.** (a) `packages/cursor-cloud-acp/` as a Bun workspace of the root
package, one `bun.lock`; (b) the same folder outside the workspace with its
own npm lockfile and install; (c) a separate repository (ruled out by the
owner's decision 1).

**Choice: (a).** One `bun install` gives the root's tests and type checks
the package's dependencies (`@cursor/sdk`'s types are needed to check
`main.ts`), CI stays one install, and the lockfile stays one file. (b) would
bring npm into CI and a second lockfile for no gain. Installing
`@cursor/sdk` at the root is not bundling it: chord's binary takes only
what `src/` imports, and a guard says so (below).

```
packages/cursor-cloud-acp/
  package.json          name, version (own), bin, files, engines, deps
  tsconfig.json         Node's types, no Bun's
  README.md  LICENSE
  src/
    bin.ts              Node version check, then dynamic import of main.ts
    main.ts             the real wiring: @cursor/sdk, keyring, git, stdio
    login.ts            the `login` (and `logout`, `status`) command
    serve.ts            ACP agent over a Port; no SDK import
    port.ts             the seam: types the adapter owns over the SDK
    cursor.ts           Port over @cursor/sdk (the only SDK import beside main)
    keyring.ts          SdkCredentialStore over @napi-rs/keyring
    credentials.ts      key resolution: env, keyring; expiry, backend pairing
    repo.ts             cwd → remote, branch, pushed; over a Git runner
    stream.ts           SDK message → ACP session/update (pure)
    errors.ts           SDK error → ACP error or transcript text (pure)
    turn.ts             one prompt's run: cancel, end, stream loss (state machine)
tests/packages/cursor-cloud-acp/   mirrors src/ (serve_test.ts, …)
tests/fixtures/cursor_cloud/
  main.ts               the adapter's serve.ts on Bun with the fake Port
  port.ts               the scripted fake Port
  scenarios.ts          scenario table, chosen by the prompt's first word
```

What chord's tooling does with it:

- **`package.json` (root)**: `"workspaces": ["packages/*"]`; root stays
  `private`. Nothing else moves.
- **`bun.lock`**: gains the workspace and its dependencies. The package's
  version line in it changes with each package release.
- **`tsconfig.json` (root)**: unchanged `include`; the package's tests under
  `tests/` import its `src/`, so the root pass sees it too, with Bun's
  types. The package's own `tsconfig.json` (`types: ["node"]`, `lib:
  ["ES2023"]`, the root's strict flags) is what keeps Bun's globals out of
  its source: `Bun` does not exist there.
- **`bun check`**: `bun quality` runs it a second time as
  `bun check -p packages/cursor-cloud-acp`. Project references were tried
  and do not fit a `noEmit` root.
- **`scripts/dev/covered.ts`**: the listed set becomes the union of the
  root's `--listFilesOnly` and each workspace's
  (`-p packages/<name> --listFilesOnly`), read from the root's
  `workspaces`; its test gains that case.
- **`eslint.config.ts`**: lints the folder as it lints the rest (no ignore).
  One added block for `packages/*/src/**`: `no-restricted-globals` on `Bun`
  and `no-restricted-imports` on `bun` and `bun:*`, with snippets in
  `lint/config_test.ts` as AGENTS.md asks. A second block for `src/**`:
  `no-restricted-imports` on `@cursor/sdk`, `@napi-rs/keyring` and
  `**/packages/*/src/**`, so chord's binary cannot take either.
  `src/platform/`'s rule is untouched: the package calls no Bun API at all.
- **`bun fmt`**: formats the folder like the rest; nothing to add.
- **`tests/privacy_test.ts`**: covers every tracked file already.
- **`tests/timings.json`**: unlisted files take the median; nothing to do.
- **CI**: `static` and the three `tests` shards cover the package with the
  changes above (its tests are under `tests/`, which `bun dev test` runs).
  `compile` is unaffected. **A new job, `node`**, guarantees Node:
  `actions/setup-node` at `22.13.0` (the floor) and at the current LTS,
  `bun install --frozen-lockfile`, build the package, `npm pack`, install
  the tarball into a scratch directory with that Node's npm, and run the
  smoke test (R7) on it. `check` adds `node` to its `needs`.

**Its tests run on Bun's test runner**, against source that uses only
`node:` APIs; the `node` job is what proves Node. Running the unit tests a
second time under `node --test` was considered and rejected: it doubles the
suite's tooling for what the built-tarball smoke already shows (that the
code Node loads works), and AGENTS.md's tests use `bun:test`.

CROSS (protocol): `serve.ts` imports only `port.ts`; every SDK type the
protocol draft maps from must be re-declared in `port.ts` as the adapter
reads it, so the fake and the real `cursor.ts` share one contract.

## R2 — Build and package.json

**Options.** (a) `bun build --target=node --packages=external`, one file per
entry (`bin`); (b) `tsc` emitting a `dist/` tree (needs a separate emit
config, since the root's is `noEmit` with `.ts` import extensions, which TS
rewrites only with `rewriteRelativeImportExtensions`); (c) tsdown or tsup, a
new dev dependency for what (a) does.

**Choice: (a).** Bun is already the toolchain, no dependency is added, and
it was tried: the output keeps the shebang, keeps packages as imports and
runs on Node 22.13. Node 22.13 cannot run TypeScript itself (type stripping
is unflagged only from 22.18), so JavaScript is shipped. Declarations are
not needed: the package is a command, not a library.

`packages/cursor-cloud-acp/package.json`:

- `"type": "module"`, `"bin": { "cursor-cloud-acp": "dist/bin.js" }` (one
  bin, so `npx @chorded/cursor-cloud-acp` and `… login` find it),
  `"files": ["dist", "README.md", "LICENSE"]`, `"engines": { "node":
  ">=22.13" }`, `"license": "MIT"`, `"repository"` with `"directory"`,
  `"publishConfig": { "access": "public" }`.
- `dependencies`: `@cursor/sdk` **exact** (`1.3.1`: proprietary,
  fast-moving, `tool_call` shapes marked unstable; bun.lock does not reach a
  person's npx install, so only an exact range holds what was tested);
  `@agentclientprotocol/sdk` and `@napi-rs/keyring` with carets, as
  AGENTS.md's rule for 1.x packages; `zod` with the range both the ACP SDK
  and `@cursor/sdk`'s peer accept.
- The build script is `bun dev` code (R3's build stage), not a package.json
  script, as CHD-411 keeps package.json scripts to `dev`.

The build stage checks its own output: Bun's metafile must list only files
under `packages/cursor-cloud-acp/src/` as inputs, so neither the SDK nor the
keyring is ever bundled (owner's decision 2).

## R3 — Release beside `bun dev release`

**Options.** (a) `bun dev release --package cursor-cloud-acp`: the existing
command, but `natives`, `compile`, `sign`, `notarise`, `selftest`, `pack`
and the draft GitHub release do not apply, and `--package` already means
"publish only this platform package"; (b) its own command,
`bun dev release-acp cursor-cloud-acp [version|bump] [--channel <name>]`,
sharing the release modules; (c) publish from CI on a tag (gives npm
provenance, but moves publishing off the owner's Mac, against the current
release decision).

**Choice: (b)**, reusing `release/version.ts` (bump, channel rules of
CHD-577), `release/authenticate.ts` (npm whoami/login), `release/lib.ts`
(npm on the real node, CHD-395) and `release/select.ts` (`--skip`, `--only`,
`--from`, `--to`). Stages:

1. `preflight` — clean tree, main (or the channel's branch) level with
   origin, `gh` not needed; CHD-547's rule applied to this package: a new
   version is refused while package.json's is not on npm.
2. `check` — `bun check -p packages/cursor-cloud-acp` and the package's
   tests (`bun dev test tests/packages/cursor-cloud-acp/`).
3. `build` — R2.
4. `smoke` — R7's Node smoke on the packed tarball, with the Node on PATH
   past Bun's (as CHD-395's helper finds it), refusing one below 22.13.
5. `publish` — the version commit `chore: cursor-cloud-acp v<version>`
   (package.json and bun.lock), pushed; `npm publish` of the tarball the
   smoke checked, with `--tag <channel>` on a channel; tag
   `cursor-cloud-acp-v<version>` pushed.

- **Tag form** `cursor-cloud-acp-v<version>`: cannot collide with chord's
  `v<version>`.
- **No GitHub release**: there is nothing to attach, and a release would
  compete with chord's for the repository's "latest". The changelog lives
  in the package's README or the tag message.
- **No code signing**: plain JavaScript; npm signs the registry tarball.
- **No provenance**: npm provenance needs a supported CI's OIDC; publishing
  from the owner's Mac cannot give it, as chord's own packages have none.
- **Channels** as CHD-577: same name rules, `--tag <channel>`, branch named
  after the channel.

OWNER: the release shape — (b) a separate `bun dev release-acp` run by the
owner (recommended), (a) folded into `bun dev release`, or (c) CI publishing
with provenance. Also whether a draft GitHub release is wanted (recommended:
no).

## R4 — chord's pin, how a release reaches chord, and `--fake`

**The pin. Options.** (a) a hand-kept table `src/chorded.ts` of
registry-shaped entries (`{ id, name, package, version, args, env }`) that
`src/agents.ts` merges beside `REGISTRY_AGENTS` (not `src/registry.ts`
itself, which `bun dev registry` rewrites); (b) the same table with the
version read from `packages/cursor-cloud-acp/package.json` by a JSON import,
so the pin has one source.

**Choice: (b).** The package's version changes only in its release commit,
so main always pins the last version released (or being released). The
start is `['npx', '-y', '@chorded/cursor-cloud-acp@<version>']`, `runner:
'npx'`, `pinned` set, exactly as registry agents start; `missingCommand`
already refuses a missing npx. A JSON import is bundled by
`bun build --compile` like any import.

**How a release reaches chord.** A package release changes the pin on main
by itself; chord's next release ships it. chord's `bun dev release`
preflight gains one check: each `src/chorded.ts` pin answers `npm view` at
its version, so a stopped package release cannot ship in chord. 0.70.0's
order is therefore: package 0.1.0 released, then chord 0.70.0.

**`--fake` and tests. Options.** (a) `tests/fixtures/cursor_cloud/main.ts`
runs the adapter's `serve.ts` on Bun with the fake Port, started through
`--agent-command` (tests) or a QA line in the guide
(`bun dev chord --fake --qa <name> --agent-command "bun
tests/fixtures/cursor_cloud/main.ts" cursor-cloud`); (b) a new
`bun dev chord --fake-cursor-cloud` option that adds that `--agent-command`
for the person; (c) a scenario in `tests/fixtures/fake_agent/` that plays
the adapter's output without the adapter.

**Choice: (a)**, with (c) only if the interface draft needs chord-side
frames independent of the adapter. (a) exercises the real adapter code
path end to end with no npx and no network; `--fake`'s own `fake
--agent-command` stays as it is. For a local run of the real build, a
developer passes `--agent-command "node packages/cursor-cloud-acp/dist/bin.js"`.

CROSS (interface): the command-line name (`cursor-cloud` assumed above) and
title come from the interface draft; the table only carries them.
CROSS (protocol): `npx @chorded/cursor-cloud-acp login` in `authMethods` is
unversioned and may run a newer package than chord's pin, so the keyring
entry's service and account names and the stored JSON are a format that
stays readable across versions (version field checked, unknown shape read
as signed out).

## R5 — The keyring library, and where none exists

**Choice: `@napi-rs/keyring`**, `AsyncEntry`, pinned to the Secret Service
on Linux. It is the only maintained candidate with prebuilt binaries for all
four targets and no install script; `keytar` is archived and builds from
source when a prebuild is missing; `cross-keychain` wraps the same native
library under a CLI's dependencies and, by default, falls through to an
encrypted file or a null store on its own, which would decide the owner's
question below silently; Zowe's is EPL-2.0 and builds on install.

`keyring.ts` implements `SdkCredentialStore`: one entry, service
`@chorded/cursor-cloud-acp`, account `cursor-api-key` (CROSS: names final
with protocol), the password the JSON of `StoredSdkCredentials`. `load` reads
and validates (unknown shape → `undefined`), `save` writes, `clear`
deletes. It is passed as `store` to `Cursor.auth.login/logout/status`.
`credentials.ts` resolves the key for every other call: `CURSOR_API_KEY`,
else the keyring entry if unexpired and minted for the backend in use; the
result is always passed as `apiKey`, so the SDK's own fallback to
`~/.cursor/sdk/auth.json` never runs.

Each keyring call has a 10 s bound (`AbortSignal.timeout`): macOS shows a
GUI dialog when a different `node` binary (after a Node upgrade) reads an
item another one wrote, and the call blocks until answered. A bound that
passes ends the start with a message naming the keychain, not a hang.

Without the pin, `@napi-rs/keyring` on Linux stores the key in keyutils
when no Secret Service exists, and it is gone at the next reboot with no
word said. Pinning makes that case an error instead, which is the case the
owner decides:

OWNER: where no keychain is available (Linux without a Secret Service, a
headless or SSH-only box, a locked keychain that cannot be unlocked):

- **(a) `login` refuses**, naming the keychain error and saying to set
  `CURSOR_API_KEY` instead; the adapter's `authMethods` text says the same.
  No key is ever on disk. **Recommended**: it keeps the owner's "the key
  goes into the OS keychain" true everywhere, and `CURSOR_API_KEY` is the
  SDK's own documented path.
- (b) fall back to the SDK's `FileCredentialStore`
  (`~/.cursor/sdk/auth.json`, 0600), with a warning on stderr. Works
  everywhere, but the key sits in a plain file, and the same file other
  SDK hosts share.
- (c) an opt-in `login --file`, (b) only when asked.
- (d) the kernel keyutils keyring (the library's own fallback): rejected,
  lost at reboot.

OWNER (smaller): whether a key already in `~/.cursor/sdk/auth.json` (from
another SDK host's `Cursor.auth.login()`) is used. Recommended: no; the
adapter always passes `apiKey`, so only `CURSOR_API_KEY` and its own keyring
entry count, and the person can tell which key is billed.

## R6 — Process and failure

The adapter is one Node process per chord agent start, under `npx` in the
process group chord made for it; it may serve several ACP sessions. chord
stops it as `src/acp/process.ts` does: stdin ends, 2 s, SIGTERM to the
group, 2 s, SIGKILL.

| scenario | expected outcome |
|---|---|
| Node below 22.13 (npm only warns on `engines`) | `bin.ts`, written so old Node parses it, writes `cursor-cloud-acp needs Node.js 22.13 or newer; this is <version>.` to stderr and exits 1 before importing anything; chord shows the start failure with stderr's tail. |
| First `npx` start (≈45 MB with one native SDK package) | No ACP until npm is done; chord's splash shows its slow line from 5 s. Nothing in the adapter. |
| stdin ends (chord closes the session or quits) | Stop reading; for each session, stop forwarding its stream, `agent.close()`, **no `run.cancel()`**: the cloud agent goes on in Cursor's VM, as the owner's design has it. Exit 0 within 1.5 s whatever `close()` does, inside chord's 2 s. |
| SIGTERM, SIGINT, SIGHUP | Same as stdin's end, at once. |
| A run going on when chord quits | The cloud agent keeps working and pushing. CROSS (protocol, interface): the person learns it from the first message, which should say so beside the link (e.g. "it keeps working in Cursor's cloud after chord closes; Esc stops a turn"). There is no later chance: the window is closing. |
| `session/cancel` while `agent.send()` has not yet returned a `Run` | Cancel is remembered; when the `Run` arrives it is cancelled at once and the prompt answers `cancelled`. |
| `session/cancel` during a run | Forwarding stops at once; `run.cancel()` with a 10 s bound; the prompt answers `cancelled` (ACP requires it). If `run.cancel()` fails or times out, a text update says Cursor did not confirm the stop and the run may still be going, with the link. |
| `session/cancel` after the run ended, or twice | No-op; the prompt already answered or answers once. |
| A second `session/prompt` while one runs | chord queues prompts itself; if one arrives, the SDK's `AgentBusyError` is answered as an ACP error, not queued in the adapter. CROSS (protocol): `run.steer` and chord's Tab-into-turn. |
| Stream lost mid-run (`NetworkError`, the generator throws) | No silent re-attach: a re-attached stream has no event ids to skip what was sent, and the SDK's types do not say what it replays. The adapter says in a text update that the live view was lost, then `Agent.getRun(runId)` + `wait()` with a bound (CROSS: protocol's P4 picks the bound and words) and sends the run's final `result`, ending the turn by its status. If that fails too, the turn ends with the error and the link. |
| Run ends `error` or `finished` with nobody watching (resume later) | Protocol's (P4). Runtime: nothing is held in the adapter between processes; Cursor's records are the state. |
| Flood: a run emits events faster than chord reads | Each event is awaited through the ACP connection before the next is taken from `run.stream()`, so the generator, not an adapter queue, absorbs the difference. A fake scenario of 10 000 events checks order and completion (not memory). |
| `git` for repo/branch detection | `node:child_process` `execFile` with `stdin: 'ignore'` (stdin is the ACP pipe), `GIT_TERMINAL_PROMPT=0` (git's own switch), a 10 s bound each, `cwd` the session's. chord's agent group is detached from the terminal, so an SSH passphrase prompt cannot open `/dev/tty` and fails instead of drawing over the window. CROSS (protocol): whether "pushed" is the local tracking ref (no network) or `git ls-remote` (network, credentials); runtime asks for the tracking ref unless the protocol draft needs the remote's truth. |
| Keyring hangs (macOS dialog) | 10 s bound, then the start fails naming the keychain (R5). |
| Signed in while chord is open | The key is read per `session/new`, not cached at process start, so the next session works without restarting chord. |
| Key revoked or expired mid-session | The SDK's `AuthenticationError` ends the turn as an ACP error with the authRequired code and the login line (CROSS: protocol P4). |
| `login` run while not in a terminal (no browser, SSH) | `Cursor.auth.login` prints the URL to stderr, the package's own terminal: fine. `login` is a person's command, never started by chord. Ctrl-C aborts the poll through its `AbortSignal`. |

**stdout discipline.** Only the ACP connection writes stdout. The adapter
writes its own diagnostics to stderr. The SDK documents its own stderr use
(the login URL); Node 22's `node:sqlite` warning goes to stderr. Nothing in
the types says the SDK logs to stdout, so no `console` is redirected: that
would patch the library's behaviour. The fake ACP tests and the Node smoke
fail on any stdout line that is not JSON-RPC; if the real SDK is ever seen
writing stdout, that is a question for the owner with options, not a fix.

**Timers.** Every bound above (shutdown 1.5 s, keyring 10 s, git 10 s,
cancel 10 s, final-result wait) is a named constant in its module, measured
on the monotonic clock, and injectable for tests.

## R7 — Test plan

No test reaches Cursor's service, a real keychain, `npx` or the network.

**The seam.** `port.ts` declares what the adapter uses: `Port { create,
resume, list, getRun, models, me, login, logout, status }`, `AgentHandle {
id, send, close }`, `RunHandle { id, stream, cancel, wait, status }`,
`CredentialStore` (the SDK's `SdkCredentialStore` shape), and `Git` (`run(args,
cwd)`). `cursor.ts` and `keyring.ts` are the only real implementations and
are imported by `main.ts` alone; `main.ts` and `login.ts` are reached only
by the Node smoke. A lint test checks `serve.ts` and everything it imports
never import `@cursor/sdk` or `@napi-rs/keyring`.

**Pure modules, tested directly** (`tests/packages/cursor-cloud-acp/`):

- `stream_test.ts` — every SDK message type to its `session/update`s,
  `tool_call` with unknown `args`/`result` shapes, `request` as text, the
  first message.
- `errors_test.ts` — every SDK error class to its ACP error or text.
- `credentials_test.ts` — env over keyring; expired key; key minted for
  another backend; unknown stored shape; keyring timeout; `apiKey` always
  set on what reaches the Port.
- `repo_test.ts` — real `git` in temporary repositories: no remote; remote
  with a GitHub URL (`https://`, `git@`, `ssh://`) set with
  `git remote add` and its tracking ref made with `git update-ref`, so no
  network; branch not pushed; branch behind/ahead of its tracking ref;
  detached HEAD; not a repository. If the protocol draft chooses
  `ls-remote`, a local bare repository stands in through git's own
  `url.<base>.insteadOf`.
- `turn_test.ts` — the run state machine on fake timers: cancel before the
  Run, during, after, twice; `run.cancel()` throwing and timing out; stream
  loss then final result; stream loss then failure.
- `keyring_test.ts` — `keyring.ts` against an injected fake entry
  constructor: save/load/clear round trip, foreign JSON, the Linux pin
  passed. The real `@napi-rs/keyring` is never constructed in tests.

**ACP level** (`serve_test.ts`): a `ClientSideConnection` of
`@agentclientprotocol/sdk` against `serve()` over in-memory streams, with the
fake Port: initialize (capabilities, `authMethods`, `agentInfo`), new
(refused: no remote, not pushed, not signed in), prompt streaming, cancel,
list, load/resume, modes and models, flood ordering, shutdown on end of
input with runs left running (the fake records no cancel). One test starts
`tests/fixtures/cursor_cloud/main.ts` under `process.execPath` over real
pipes and checks stdout carries only JSON-RPC and that the process exits
within the shutdown bound after stdin ends.

**The fake Port** (`tests/fixtures/cursor_cloud/`): scripted per scenario,
chosen by the prompt's first word as riff's fake is (`text`, `think`,
`tools`, `unknowntool`, `request`, `plan`, `usage`, `long`, `hang`, `fail`,
`streamlost`, `cancelfails`, `flood`, `busy`, `authexpired`), plus start
states through its environment (`signedout`, `listed:<n>`, `finished`,
`errored`) for `--qa` runs. It records every call so tests assert what was
sent (model, mode, apiKey present, no cancel on shutdown).

**chord side** (`tests/`):

- `agents_test.ts` — the `cursor-cloud` entry: argv
  `npx -y @chorded/cursor-cloud-acp@<version from package.json>`, `runner`,
  `pinned`, `chord agents` and `--json` rows.
- A window test through `tests/ui/harness.tsx` / `withWindow`, starting the
  fixture with `--agent-command`: first message, a streamed turn, `request`
  as text, Esc cancel, the refused start's block. The interface draft names
  the frames.
- `lint/config_test.ts` — the two new ESLint blocks.
- `scripts/dev/covered.ts`'s test — the workspace union.
- `scripts/dev/compile_test.ts` — the binary's inputs include no
  `@cursor/sdk` or `@napi-rs/keyring` file.
- The release: `tests/scripts/` tests of `release-acp`'s stage selection,
  version and channel rules, with npm faked on PATH as the existing release
  tests do.

**Node smoke** (CI's `node` job and the release's `smoke` stage): install
the packed tarball with Node's npm into an empty directory (proves `files`,
`bin`, dependencies and the native optional package resolve), then: `node
…/bin.js` with Node below the floor refused (CI only, a second setup-node);
`initialize` answered with the expected capabilities; `session/new` in a
non-git directory refused with protocol's words; stdout only JSON-RPC.
`CURSOR_API_KEY` is unset and no keychain is read on these paths (CROSS:
protocol orders the repository check before the credential check, or the
smoke stops at `initialize`).

## Open questions

- OWNER: R5's no-keychain fallback (recommended: refuse `login`, point to
  `CURSOR_API_KEY`).
- OWNER: whether `~/.cursor/sdk/auth.json` from other SDK hosts counts
  (recommended: no).
- OWNER: R3's release shape (recommended: `bun dev release-acp`, no GitHub
  release, no provenance).
- OWNER: a `node` CI job required by `check` (recommended: yes, Node 22.13
  and current LTS).
- CROSS (protocol): `port.ts` as the one contract; keyring entry names and
  format stable across versions; "pushed" by tracking ref or `ls-remote`;
  stream-loss words and bound; authRequired mid-session; repository check
  before credentials; `run.steer`.
- CROSS (interface): the command-line name and title; whether chord-side
  frames need a `fake_agent` scenario besides the adapter fixture; the
  first message saying the agent keeps running after chord closes.
- The SDK's behaviour on stdout and on stream re-attachment is not in its
  types; both are held to what the types promise and checked by the smoke,
  not guessed.
