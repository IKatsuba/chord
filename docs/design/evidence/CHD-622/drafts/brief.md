# CHD-622 brief — `@chorded/cursor-cloud-acp`

The lead's brief for the architects. The task is `board show CHD-622`; its
comments hold the owner's decisions of 2026-11-12, restated below. They are
fixed: design within them. A choice that contradicts one, changes scope, or
needs a library that does not fit as it is goes back to the lead as a
question for the owner, with options; it is not decided in a draft.

## The problem

Cursor's own CLI (`agent acp`, already in chord's agent list as `cursor`)
runs local agents only. Cloud agents — Cursor's agents in its own VM on a
clone of a repository, pushing to a branch — are reachable only through
Cursor's TypeScript SDK, `@cursor/sdk` (1.3.1 today, Node `>=22.13`,
proprietary: "© Anysphere Inc. All rights reserved", used under Cursor's
Terms of Service, which the owner accepted). No ACP adapter over it exists.

chord gets one: a new npm package, `@chorded/cursor-cloud-acp`, in this
repository, that serves Cursor cloud agents as an ACP v1 agent on stdin and
stdout, started with `npx` as chord starts `@agentclientprotocol/claude-agent-acp`
and `codex-acp`, and offered in chord's own agent list as `cursor cloud`.

Sources: the SDK's docs (https://cursor.com/docs/sdk/typescript) and the
`.d.ts` files in the npm tarball of `@cursor/sdk`. Read the types and docs
for what crosses the API — nothing more: no reading, copying or describing
its compiled code. Download the tarball into a new empty directory of its
own under `/tmp`, never into the repository, and run nothing from it.

## The owner's decisions (fixed)

1. The code lives in this repository and ships as an ordinary npm package,
   versioned on its own, apart from chord.
2. Built on `@cursor/sdk`, a plain npm dependency of the package: never
   bundled, vendored or copied into it, nor into chord's binary.
3. Cloud agents only. Local Cursor agents stay on Cursor's `agent acp`.
4. A new session's cloud agent starts from the cwd's current branch when it
   is pushed; otherwise `session/new` is refused with a message saying to
   push the branch. A cwd with no remote is refused. Uncommitted or unpushed
   work gets no other handling.
5. The adapter's first message in a session names the repository, the
   branch and the agent's link on cursor.com/agents, so the person can tell
   the session is remote. No change in chord for that.
6. No permission requests: the agent runs in Cursor's isolated VM and its
   only result is a branch. SDK `request` events are shown as text in the
   transcript, never answered by guessing.
7. The person decides what happens to the result and tells the agent.
8. Sign-in belongs to the package: `npx @chorded/cursor-cloud-acp login`
   runs `Cursor.auth.login()` in the browser; the key goes into the OS
   keychain through a Node keyring library plugged in as the SDK's
   `SdkCredentialStore`. `CURSOR_API_KEY` keeps working as the SDK reads it.
   chord gets no sign-in code: it shows the package's way in as it shows
   other agents' external sign-in (CHD-435, `docs/design/CHD-435.md`). Not
   chosen: Bun.secrets in chord, ACP `authenticate` in chord's window.
9. Serve whatever ACP methods the SDK supports.
10. Named `cursor cloud` in chord, in chord's own agent list beside `claude`
    and `codex`.

## What a person sees and presses

- `chord` → the picker lists `cursor cloud`; or `chord <name>` on the
  command line (how a name with a space is typed, or what its command-line
  name is, is an open question below).
- Not signed in: the start fails, and CHD-435's block shows the package's
  `authMethods` entry naming `npx @chorded/cursor-cloud-acp login`.
- Signed in, in a pushed branch: the session opens; the first transcript
  message names repo, branch and the cursor.com/agents link. Prompts stream
  as with any agent: text, thinking, tool calls, plan/status, usage. Esc
  cancels the run. `request` events appear as text.
- Not pushed, or no remote: the start fails with the package's message.
- `/resume` and `chord --resume` list and reopen sessions; whether cloud
  agents started elsewhere (cursor.com, another machine) appear is an open
  question below.
- shift+tab and `/model` where the SDK has modes and models.

## Constraints

- AGENTS.md is binding: the one rule (library before own code; no
  workaround around a library without the owner), "Bun runs chord", tests
  never reach a real model or service, every action has a key, the
  repository names no private path, commits signed with no trailers.
- The package runs on Node 22.13+ under `npx`, not on Bun and not inside
  chord's binary. chord's tooling today assumes one Bun package at the root:
  `bun.lock`, `tsconfig.json`'s `include`, `scripts/dev/covered.ts` (every
  tracked TS file type-checked), `eslint.config.ts`, `bun fmt`,
  `tests/privacy_test.ts`, `tests/timings.json`, CI's `static`, three test
  shards and `compile`.
- chord's release is `bun dev release` (`scripts/dev/release/`), run on the
  owner's Mac, publishing `@chorded/chord` and four platform packages, with
  channels (CHD-577), npm through the real node (CHD-395), draft GitHub
  release. The new package is versioned apart.
- chord's npx agents come from `src/registry.ts` (frozen ACP Registry,
  `npx -y <package>@<exact version>`); CLI agents from `src/clis.ts`; the
  names map in `src/agents.ts`.
- `--fake` and tests must reach the adapter without `npx` and without the
  network; the SDK is faked at a seam.

## Non-goals

- Local Cursor agents; Cursor's Cloud Agents HTTP API or SDK Bridge as the
  base; listing the package in the ACP Registry (may come later, not here).
- Sign-in UI in chord; ACP `authenticate` handled by chord.
- Pulling the cloud agent's branch, opening PRs or applying its changes
  locally on the person's behalf.
- Permission prompts, approval of `request` events.
- Any code in this design pass.

## Open questions, by owner

### protocol (`drafts/protocol.md`)

P1. The ACP surface over the SDK: `initialize` (capabilities, `authMethods`
    for the login command, `agentInfo`), `session/new` (repo and ref
    detection from cwd: which remote, which URL forms Cursor accepts, how
    "pushed" is checked — local git, `git ls-remote`, or the SDK refusing),
    `session/prompt` (one `agent.send()` per prompt? one cloud agent per
    session?), `session/cancel` (`run.cancel()`), `session/list` and
    `session/load` / `session/resume` over `Agent.list()` / `Agent.resume()`
    — which agents are listed (this repo only? started by this adapter
    only? by anyone on the account?), and what replay `session/load` can
    give from the SDK's history.
P2. The stream mapping: each SDK event (`system`, `user`, `assistant`,
    `thinking`, `tool_call`, `status`, `task`, `request`, `usage`) to ACP
    `session/update`s; the first message (repo, branch, link) — as an
    `agent_message_chunk` or otherwise; `request` as text; how unstable
    `tool_call` `args`/`result` shapes are drawn (a generic title + raw
    content, a few known kinds, `kind`), without guessing.
P3. Modes (`agent`, `plan`) and models (`Cursor.models.list()`): config
    options vs `session/set_mode`/`set_model`; when a model change applies
    to a running cloud agent; artifacts; per-run env vars (served or not).
P4. Errors and refusals: not signed in (`authRequired`, -32000, with the
    words CHD-435 draws), no remote, not pushed, Team Admin key, quota,
    network loss mid-stream, a cloud agent that finished or failed while no
    one watched.
P5. Where the SDK keeps local state (`node:sqlite` store vs
    `JsonlLocalAgentStore`) and whether the adapter needs any; the
    `SdkCredentialStore` interface as the types state it.

### interface (`drafts/interface.md`)

I1. How `cursor cloud` appears: picker row, `chord agents` (and `--json`),
    status line, header; the command-line name (a name with a space cannot
    be one argv word — `cursor-cloud` as the name with `cursor cloud` as
    its title? something else?), settings key `agents.<name>`; how it sits
    beside the existing `cursor` (CLI) entry.
I2. The screens at 120×40 and 80×24: start, not signed in (CHD-435's
    block), refused start (not pushed, no remote), the first message,
    a streaming turn with tool calls of unknown shape, a `request` event as
    text, cancel, resume list with cloud agents, a run that ended remotely.
I3. Keys: confirm no new action is needed (nothing on screen needs a new
    key); if one is, name it and its shortcuts-panel entry.
I4. Whether chord needs any change beyond the agent-list entry (the owner's
    "no change in chord" for the first message); anything chord draws
    differently for this agent is a question for the owner, not a decision.

### runtime (`drafts/runtime.md`)

R1. The package's layout in the repo (e.g. `packages/cursor-cloud-acp/`
    with its own `package.json`; a Bun workspace or not) and what chord's
    tooling does with it: `bun.lock`, `tsconfig.json`, `covered.ts`,
    `eslint.config.ts`, `bun fmt`, `privacy_test.ts`, `timings.json`, CI
    jobs — given "Bun runs chord" while the package runs on Node 22.13+.
    How its own tests run (on Bun's test runner against Node-compatible
    code? on Node too?), and what guarantees it runs on Node.
R2. Its build: ship TypeScript compiled to JS (which tool — library first:
    `tsc`, `bun build --target=node`, tsdown/tsup…), `bin`, `files`,
    `engines`, the SDK and keyring as plain dependencies, no bundling of
    either.
R3. Its release and tag beside `bun dev release`: a `bun dev` command or a
    stage of the existing one; tag form (e.g. `cursor-cloud-acp-v0.1.0`);
    whether a GitHub release is drafted; signing (none needed for JS?);
    npm provenance; channels.
R4. How chord's agent entry pins a published version (a hand-kept entry in
    `src/agents.ts`/a new table, exact version, `npx -y pkg@x.y.z`), how a
    package release reaches chord (a chord change bumping the pin), and how
    tests and `--fake` reach the adapter without npx (run its source on Bun
    with a fake SDK? an `--agent-command`?).
R5. The keyring library under the one rule: candidates that run on Node
    22.13+ under npx with prebuilt binaries for macOS and Linux arm64/x64
    (e.g. `@napi-rs/keyring`, `keytar` (archived), `cross-keychain`, …),
    tried, with findings; and what happens where no keychain exists (Linux
    without Secret Service, a headless box): options — refuse `login` and
    point to `CURSOR_API_KEY`; fall back to the SDK's own file store; other.
    This choice goes to the owner; the draft recommends.
R6. Process and failure: the adapter's lifetime vs a cloud agent's (the
    agent keeps running when chord quits — what the person is told),
    stream reconnects, cancel races, stdout discipline (nothing but ACP on
    stdout; the SDK's logs to stderr), Node version check with a clear
    refusal.
R7. The test plan: the seam where the SDK is faked (an interface the
    adapter owns over `Agent`, `Run`, `Cursor.models`, `Cursor.auth`,
    `SdkCredentialStore`), the ACP-level tests (client ↔ adapter over
    stdio/in-memory streams), git fixtures for repo/branch detection, the
    keyring faked, and the chord-side tests (agent entry, `--fake` path);
    never the real Cursor service or a real keychain.

## How the drafts are written

Each architect writes only its own draft, in English, naming no private
path, and states for each question its options, its choice and why. A
question that needs the other two (P1/R4 on how `--fake` reaches the
adapter, P4/I2 on refusal words) is answered from your side and flagged
`CROSS:` for the lead. A question that is the owner's is flagged `OWNER:`
with the options and a recommendation, not decided.
