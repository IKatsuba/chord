# CHD-485 brief: chord's own built-in agent, its MVP on libfx

The lead's brief to the protocol, interface and runtime architects. Read
`AGENTS.md`, `README.md`, `docs/FEATURES.md`, `docs/decisions.md` (above all
the CHD-573, CHD-575, CHD-580, CHD-581 entries on `chord acp` and the host,
"chord's own ACP layer", CHD-435 on sign-in, and the M4/M5 entries on chord's
MCP server and teams), `docs/design/CHD-573.md`, the task itself
(`board show CHD-485`, comments included) and
`docs/design/evidence/CHD-485/gate.md` before writing.

## The problem

chord drives other people's agents over ACP: Claude Code, Codex, the ACP
Registry's 36, and `fx acp` among them (`src/clis.ts`). The owner wants an
agent of chord's own beside them, so a person with a ChatGPT or Grok plan and
nothing else installed can work in chord. The MVP runs on libfx (npm
`libfx` 0.0.16, Apache-2.0, vercel-labs/fx): the fx engine as a JavaScript
library with a native addon and a Wasm fallback. libfx runs the model loop,
streaming, tool calls, retries, steering, images and journals; the host
gives it the model, the credentials, the instructions and every tool. With
the native backend, fx's own shell and file tools are not turned on: the
tools are chord's to provide.

## Settled, not to reopen

- Sign-in to ChatGPT and Grok plans goes through libfx (`libfx/chatgpt`,
  `libfx/grok`), both in the browser and by device code, for each.
- For the browser way chord listens on the loopback callback address only
  while it waits for the answer, and closes it then. libfx itself listens
  nowhere; chord's listener receives the redirect libfx's sign-in names.
- ChatGPT's redirect is fixed by libfx at `http://localhost:1455/auth/callback`.
  When 1455 is taken, chord says the port is taken and offers device code.
  No workaround around the fixed redirect. Grok's sign-in picks its own
  random loopback port and returns it in `redirectUri`.
- Credentials are kept with Bun.secrets (macOS Keychain, Secret Service,
  Windows Credential Manager). It is Bun's own call, so it lives in
  `src/platform/`. What chord does without a credential store is open (Q4).
- The gate (owner, option A): libfx does not fit `bun build --compile` as it
  is (it names `libfx.node` and `fx-core.wasm` by `new URL(…,
  import.meta.url)`, which Bun does not embed). chord embeds both files with
  Bun's `with { type: 'file' }` imports by their path inside `node_modules`,
  past the packages' `exports` (the owner allows that reach for this), and
  passes them through libfx's documented `nativeAddon` and `wasm` options.
  Verified on all four targets; +9.8 to 11.1 MiB per binary. A libfx layout
  change must fail the build, not the binary: the design names how the build
  checks it. Upstream changes are not part of this design.
- No real model calls, sign-ins or turns against a real provider without the
  owner's go-ahead through main. libfx's custom provider takes
  `http://localhost` Chat Completions servers: the gate ran a whole turn
  with a tool call against a fake one.

## What a person sees and presses

- The built-in agent is in the agent picker and in `chord <name>` like any
  other, under a name the owner picks (Q5).
- With no credential, starting it leads to sign-in: pick ChatGPT or Grok,
  then the browser or a device code. Browser: chord shows the address (and
  may open it), listens on loopback, and goes on when the redirect lands;
  Esc gives up and closes the listener. 1455 taken: the words say so and
  offer device code. Device code: chord shows the code and the address and
  polls until the person enters it, or it expires, or Esc. ChatGPT accounts
  must turn device code on in their security settings first; the failure
  says so.
- Signed in, the session is any session: a streamed reply, thinking, tool
  calls with their status and diffs, chord's permission prompt, Esc cancels,
  a queued prompt, Tab steers, the status line shows the model, effort and
  usage, `/model` picks among the provider's models.
- A way to sign out and to switch account or provider, by key or command.

## Constraints

- AGENTS.md is binding: the one rule (take a library before writing one;
  file, search and shell tools included: say what you tried), logic in pure
  tested modules, components draw and dispatch, every action has a key in
  the shortcuts panel, Bun's runtime calls only in `src/platform/`, tests
  never reach a real model or provider, `--fake`/`--qa` never fall back to
  real readers.
- One main session per process; no tabs (CHD-493).
- `chord acp` exists (CHD-573 to CHD-582) and chord already speaks both
  sides of ACP. chord's own MCP server is offered to every session it opens.
- The ship team builds from this design; the design names the parts in
  order, each testable, and the checks for each.

## Non-goals

- Upstream changes to libfx or fx.
- A model loop, streaming client or provider client of chord's own: libfx's.
- Claude or Anthropic subscription sign-in (libfx has none).
- Windows (chord ships no Windows binary).
- Changing how other agents run.

## The owner's questions

Each is the owner's. The architects bring evidence and options with a
recommendation; the lead takes each to main, one at a time, and the design
follows the answers. Nobody settles them in a draft.

- Q1. How the agent reaches the rest of chord: in-process behind the session
  layer, beside the ACP connections; or as an ACP agent chord starts itself
  (a `chord` subcommand on stdio, so the existing ACP client path carries
  it whole).
- Q2. What the MVP covers: which tools (read, edit or write, search, shell;
  terminal output), permissions through chord's permission prompt and which
  calls ask, MCP servers from settings, chord's own MCP tools (children,
  teams, monitors), being a team member or lead.
- Q3. Which providers: ChatGPT and Grok plans (settled to support); also AI
  Gateway by key, a custom Chat Completions server, or none of those.
- Q4. Where credentials live beyond Bun.secrets, and what chord does with no
  credential store: refuse, an explicit 0600 file, environment variables
  only, memory for the process's life.
- Q5. Its name in settings and the picker, and whether it is the default.
- Q6. Resume: libfx's journals and checkpoints (`local()` durability,
  `createFxEngine` persistence or `checkpoint()`) and how they meet chord's
  own session records; what a crash mid-turn does.
- Q7. Cost and usage: what libfx reports (`usage`, plan limits), what the
  status line and `/cost` show for a plan with no price.
- Q8. Tool rendering: how chord's own tools' calls look in the transcript
  (kinds, titles, diffs, terminal output), against Claude's and Codex's.
- Q9. Whether the providers' terms (a third-party client signing in as the
  Codex CLI's OpenAI client or the fx CLI's xAI client) need an answer
  before release.

## What each architect answers

Every draft ends with: the options for each owner question it owns, with
the evidence and a recommendation; what it read in libfx 0.0.16 (file and
line); libraries tried; what it could not check. Read libfx from npm
(`npm pack libfx@0.0.16` into a new empty directory under `/tmp`) and
vercel-labs/fx on GitHub; never from memory.

**protocol** (Q1, Q3, Q6; with runtime on Q1):
- In each Q1 option, the surface: which ACP methods and capabilities the
  agent offers (initialize, auth methods, new, load or resume, prompt,
  cancel, set config option for model and effort, steering), and how libfx's
  events (`text_delta`, thinking, `tool_start`, `tool_end`, usage, errors,
  stop reasons) map onto ACP updates chord's reducer already reads.
- Sign-in in each option: ACP's `authenticate` and auth methods, or chord's
  own screen before the session; how a failure reaches chord (`authRequired`
  is how other agents say it, CHD-435).
- MCP: the session's servers through `libfx/mcp` and an
  `@modelcontextprotocol/sdk` client; whether chord's own MCP server then
  works with no special path, and what that gives (children, teams).
- Records and resume: what chord's session record keeps, what libfx's
  journal keeps, which one is the truth, and what `--continue` does.
- Models: `listModels`, per provider, and `/model` and effort.

**interface** (Q5, Q7, Q8; screens for Q2 and Q4):
- The sign-in screens as text at 120x40 and 80x24, every state: choosing
  the provider, choosing the way, waiting on the browser, port 1455 taken,
  the device code, success, failure, expired, cancelled, no credential store.
- Where sign-in lives: before the session, in the picker, a slash command;
  sign out and switching account or provider. Keys for every action, and
  their shortcuts panel entries.
- The picker entry, the status line and `/cost` for a plan, tool rendering
  of chord's own tools, and the permission prompt for them.
- The state slices and pure modules the screens draw from.

**runtime** (Q2, Q4, Q9 evidence; with protocol on Q1):
- The processes in each Q1 option: what runs where, cancellation, a crash of
  libfx's native code (in-process takes the window down with it), memory,
  quitting bounded as chord's quitting is.
- The build: the embedded assets per target, and the build check that fails
  when libfx moves or renames `libfx.node`, `fx-core.wasm` or the platform
  packages (the owner's condition); `nativeAddon` falling back to Wasm on
  glibc below 2.34 or a `noexec` temporary directory (Bun writes the addon
  to the temporary directory before loading it).
- The tools: whether libfx or fx ships tools a host may turn on (read
  `fx-harness.js`, the native backend's options and fx's own tool code)
  before chord writes any; else which libraries carry file edits, search and
  shell (chord already has `src/shell.ts` and the monitor engine); ordering,
  `idempotent` and `writes` per tool; where the permission prompt sits in a
  call.
- Sign-in: the loopback listener's life, detecting 1455 taken, device code
  polling and expiry, cancellation; Bun.secrets: bounded reads, a lock for
  concurrent writers, a locked keychain or no secret service, refresh tokens
  written back (`onCredentials`).
- Testability: the fake Chat Completions server as the test seam; how
  sign-in is tested with no network (can libfx's OpenAI and xAI endpoints be
  pointed at a fixture, or must the seam sit around libfx's calls); the
  compiled `bun dev selftest`; `--fake` and `--qa` for the built-in agent.
- Q9: what the README, the code and the providers' published terms say,
  quoted, with no legal conclusion.
