# Script rules

- `bun dev <command>` is the Cliffy CLI in `dev.ts`, with modules in
  `dev/`; declare its arguments there, not in each module. `bun quality`
  and `bun lint` use `quality.ts` and `lint.ts`; `bun check` and `bun fmt`
  are native Bun commands. Local quality checks the host's installed libfx
  package and every target's metadata; CI's static job installs all platforms
  and sets `CHORD_LIBFX_ALL_TARGETS=1` to check all four packages.
- `bun dev chord --qa [name]` remakes its capture directory and sibling
  `.state` directory together (`/tmp/chord-qa[.<name>]` and that path plus
  `.state`). `--fake` without `--qa` uses `/tmp/chord-fake`, made if missing
  and kept across runs. QA takes precedence. Both set only `XDG_STATE_HOME`,
  never writing records or riff's state into the person's own state; config,
  data and cache stay unchanged. Plain `bun dev chord` keeps the person's
  XDG state.
- `bun dev release [version|major|minor|patch|fix]` is the owner's
  (`docs/decisions.md`, "Releasing"); nobody else publishes. Give it the
  version instead of editing package.json's by hand. `--channel <name>` makes
  `<base>-<channel>.<n>`; bumps count from npm's latest stable. If package.json
  holds that base on that channel, its number goes up; otherwise it starts at 0.
  Labelled arguments are refused; a stable bump from a pre-release needs an
  exact version instead. With no version, it finishes package.json's release;
  `--channel` then requires that version already on that channel.
  It needs an arm64 Mac when `natives`, `sign` or `notarise` is selected.
  A dry run still submits to Apple unless `--skip notarise` is passed.
- A new release version needs `compile`. Before any stage it is committed
  alone as `chore: chord v<version>`. Publishing requires the channel's branch,
  or main for a stable release, level with origin, and pushes it there.
  A failed push drops it; a later failure keeps it on origin. A dry run or
  run without publish drops its local commit, on failure and SIGINT,
  SIGTERM or SIGHUP too. SIGKILL may leave it: `git reset --keep HEAD~1`.
  Rerun with no version to release package.json's version.
- Release stages live in `dev/release/`. Select them with `--skip`, `--only`,
  `--from` and `--to`; preflight always runs. Selecting `publish` requires
  installed, signed-in `gh`, checked with `gh auth status` among the guards.
  After the guards, npm authentication precedes release work, including dry
  runs and runs without publish; no stage selection skips it. Successful `npm whoami`
  needs no terminal. On failure, stdin and stdout must be terminals for one
  plain `npm login` with inherited stdio and a required `npm whoami` recheck.
  Missing terminals, failed or cancelled login, signals or a failed recheck
  stop the release. npm may open a browser and save credentials or registry
  settings even in a dry run. `--package` selects a publish. `pack` uses
  `curl` to fetch FFmpeg and zlib source archives into `dist/release/source/`
  and checks their sums against OpenTUI's native package `FFMPEG-SOURCE.md`.
  Failed downloads or mismatches stop the release; dry runs need the network
  too. Publishing, including resume, rechecks the archives before npm;
  `--skip pack` needs copies from an earlier pack. Every channel package
  publishes with `--tag <channel>`, leaving latest unchanged; a channel dry
  run prints its stages and each package's npm publish arguments.
  After pushing the tag, publish runs
  `gh release create v<version> --draft` with the archives
  attached, adding `--prerelease` for a channel. The owner writes the notes
  and publishes the draft. A failed draft leaves the version on npm and
  tagged; finish with the printed `gh` command, since rerunning cannot create it.
- `dev/compile.ts` uses `Bun.build` with a plugin resolving OpenTUI's
  `react/jsx-dev-runtime` imports to `dev/jsx_dev_runtime.ts` on React's
  production runtime. It installs all target packages, then checks the pinned
  libfx layout for each target it builds with `dev/libfx_assets.ts`; a mismatch
  names the package and version and stops the build. A plugin embeds only the
  target's `libfx.node`. The binary includes fff's Worker and exactly its
  target's fff library (gnu on Linux); the build checks that selection.
  Its `buildOptions` also builds the boundary test.
- `bun dev selftest <binary>` checks the version, `-p`, ACP stdio, the window
  and clipboard with the fake agent. On native and WebAssembly, riff
  searches with fff, reads `needle.txt`, then answers `done`: three requests
  per backend to a local fake provider through `--riff-agent`.
- `targets.ts` is the one list of release platforms. Resource collector support
  is separately guarded; compiling a target does not enable its collectors.
  Keep the resource worker in the same binary and provider executables external.
- `bun dev memory` is too slow for `bun quality` (`docs/memory.md`).
- Scripts run on Bun; no `npx`. The release runs npm on node through
  `dev/release/lib.ts` (the owner's exception in `docs/decisions.md`).
