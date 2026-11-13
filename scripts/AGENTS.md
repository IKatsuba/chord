# Script rules

- `bun dev <command>` is the Cliffy CLI in `dev.ts`, with modules in
  `dev/`; declare its arguments there, not in each module. Only `quality`,
  `lint` and `release` take a package by its npm name without the scope.
  Each runs that package's root `steps.ts`: checks, lint argv and release
  stages, with publish last. `bun check` and `bun fmt` are native Bun commands.
  chord's checks leave `packages/` out. Local quality checks the host's libfx
  package and every target's metadata; CI's static job installs all platforms
  and sets `CHORD_LIBFX_ALL_TARGETS=1` to check all four packages.
- `bun dev chord --qa [name]` remakes its capture directory and sibling
  `.state` directory together (`/tmp/chord-qa[.<name>]` and that path plus
  `.state`). `--fake` without `--qa` uses `/tmp/chord-fake`, made if missing
  and kept across runs. QA takes precedence. Both set only `XDG_STATE_HOME`,
  never writing records or riff's state into the person's own state; config,
  data and cache stay unchanged. Plain `bun dev chord` keeps the person's
  XDG state. A bare `--fake --qa` opens the fake agent; plain `--qa` shows
  the picker. The cursor-cloud fixture uses `--qa` with its explicit
  `--agent-command`, never `--fake`, which supplies a command of its own.
- `bun dev release <package> [--bump <version|major|minor|patch|fix>]` is
  the owner's (`docs/decisions.md`, "Releasing"); nobody else publishes.
  chord's preflight checks every `src/chorded.ts` pin on npm; release the
  agent package first. cursor-cloud-acp runs install, quality, build, pack
  and publish, tags `cursor-cloud-acp-v<version>` and makes no GitHub release.
  A bare release releases nothing. Use `--bump` instead of editing the version
  by hand. `--channel <name>` makes `<base>-<channel>.<n>`; bumps count from
  npm's latest stable. If package.json holds that base on that channel, its
  number goes up; otherwise it starts at 0. Labelled versions are refused;
  a stable bump from a pre-release needs an exact version. Without `--bump`,
  `--channel` requires package.json already on that channel.
- A new version needs a `versioned` stage (chord's `compile`). Before any
  stage, its package.json is committed alone as `chore: <package> v<version>`.
  Publishing requires the channel's branch, or main for a stable release,
  level with origin, and pushes it there. A run with state keeps the commit
  on a failed push, later failure or signal. A dry run or a run without publish
  that makes a new version keeps no state and drops its commit, on failure,
  SIGINT, SIGTERM or SIGHUP too. SIGKILL may leave it: `git reset --keep HEAD~1`.
- Release stages come from the package's `steps.ts`; `dev/release/` runs them.
  chord's are `install`, `quality`, `natives`, `compile`, `sign`, `selftest`,
  `notarise`, `pack`, `publish`. Select with `--skip`, `--only`, `--from`,
  `--to`; guards always run. `natives`, `sign`, `notarise` need an arm64 Mac.
  A dry run still submits to Apple unless `--skip notarise` is passed.
  chord's publish requires signed-in `gh`, checked with `gh auth status`.
  After the guards, every named release requires npm authentication, even
  dry runs and runs without publish. Successful `npm whoami` needs no terminal.
  On failure, stdin and stdout must be terminals for one plain `npm login`
  and a successful `npm whoami` recheck. Missing terminals, failed or cancelled
  login, signals or a failed recheck stop the release. npm may open a browser
  and save credentials or registry settings even in a dry run.
- chord's `pack` fetches FFmpeg and zlib source with `curl` into
  `dist/release/source/` and checks sums against OpenTUI's `FFMPEG-SOURCE.md`.
  Failed downloads or mismatches stop the release; dry runs need network too.
  Publish rechecks the archives and needs `pack` done in this run or the state.
  It publishes all five npm packages in order. Channel packages use
  `--tag <channel>`, leaving latest unchanged; a channel dry run prints its
  stages and npm publish arguments. After pushing the tag, publish creates a
  draft GitHub release with the archives, marked `--prerelease` for a channel.
  The owner writes its notes and publishes it.
- A publishing run, or one at package.json's version without `--dry-run`,
  records progress in `.release/<package>/state.json`, gitignored. Rerun
  `bun dev release <package>` to continue, including a failed draft. The state
  refuses `--bump` and `--dry-run` while unfinished. Missing or changed output
  names the stage to rerun from (after signing, `--from compile`). Completion
  removes state; abandon it by hand with `rm -r .release/<package>`.
  The checkout-wide lock in git's common directory never goes stale. A lock
  left by SIGKILL, a crash or reboot is refused with its pid and path, to
  remove by hand.
- `dev/compile.ts` uses `Bun.build` with a plugin resolving OpenTUI's
  `react/jsx-dev-runtime` imports to `dev/jsx_dev_runtime.ts` on React's
  production runtime. It installs all target packages, then checks the pinned
  libfx layout for each target it builds with `dev/libfx_assets.ts`; a mismatch
  names the package and version and stops the build. A plugin embeds only the
  target's `libfx.node`. The binary includes fff's Worker and exactly its
  target's fff library (gnu on Linux); the build checks that selection
  and refuses any Cursor SDK or keyring file.
  Its `buildOptions` also builds the boundary test.
- `bun dev selftest <binary>` checks the version, `-p`, ACP stdio, the window
  and clipboard with the fake agent. On native and WebAssembly, riff
  searches with fff, reads `needle.txt`, then answers `done`: three requests
  per backend to a local fake provider through `--riff-agent`.
- `targets.ts` is the one list of release platforms. Resource collector support
  is separately guarded; compiling a target does not enable its collectors.
  Keep the resource worker in the same binary and provider executables external.
- `bun dev memory` is too slow for `bun dev quality chord` (`docs/memory.md`).
- Scripts run on Bun; no `npx`. The release runs npm on node through
  `dev/release/lib.ts` (the owner's exception in `docs/decisions.md`).
