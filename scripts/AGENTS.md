# Script rules

These scripts are the TypeScript workspace's tooling, kept for
`packages/cursor-cloud-acp` alone; chord itself is built and released by
its Dart tools.

- `bun dev <command>` is the Cliffy CLI in `dev.ts`, with modules in
  `dev/`; declare its arguments there, not in each module. Its commands
  are `quality`, `lint` and `release`, each taking a package by its npm name
  without the scope. The packages are the root `package.json`'s workspaces;
  the root itself is never one. Each runs that package's own `steps.ts`:
  checks, lint argv and release stages, with publish last. `bun check` and
  `bun fmt` are native Bun commands.
- `bun test ./tests/scripts ./lint` runs the tooling's own tests;
  `tests/scripts/dev/release/fixtures/chord_steps.ts` keeps the TypeScript
  chord's release stages as a fixture for the release engine's tests only.
- `bun dev release <package> [--bump <version|major|minor|patch|fix>]` is
  the owner's; nobody else publishes. cursor-cloud-acp runs install,
  quality, build, pack and publish, tags `cursor-cloud-acp-v<version>` and
  makes no GitHub release. A bare release releases nothing. Use `--bump`
  instead of editing the version by hand. `--channel <name>` makes
  `<base>-<channel>.<n>`; bumps count from npm's latest stable. If
  package.json holds that base on that channel, its number goes up;
  otherwise it starts at 0. Labelled versions are refused; a stable bump
  from a pre-release needs an exact version. Without `--bump`, `--channel`
  requires package.json already on that channel.
- Before any stage, a new version's package.json is committed alone as
  `chore: <package> v<version>`. Publishing requires the channel's branch,
  or main for a stable release, level with origin, and pushes it there. A
  run with state keeps the commit on a failed push, later failure or signal.
  A dry run or a run without publish that makes a new version keeps no state
  and drops its commit, on failure, SIGINT, SIGTERM or SIGHUP too. SIGKILL
  may leave it: `git reset --keep HEAD~1`.
- Select stages with `--skip`, `--only`, `--from`, `--to`; guards always
  run. After the guards, every named release requires npm authentication,
  even dry runs and runs without publish. Successful `npm whoami` needs no
  terminal. On failure, stdin and stdout must be terminals for one plain
  `npm login` and a successful `npm whoami` recheck. Missing terminals,
  failed or cancelled login, signals or a failed recheck stop the release.
  npm may open a browser and save credentials or registry settings even in
  a dry run.
- A publishing run, or one at package.json's version without `--dry-run`,
  records progress in `.release/<package>/state.json`, gitignored. Rerun
  `bun dev release <package>` to continue. The state refuses `--bump` and
  `--dry-run` while unfinished. Completion removes state; abandon it by hand
  with `rm -r .release/<package>`. The checkout-wide lock in git's common
  directory, `chord-release.lock`, is shared with chord's Dart release, so
  the two never run at once; it never goes stale. A lock left by SIGKILL, a
  crash or reboot is refused with its pid and path, to remove by hand.
- Scripts run on Bun; no `npx`. The release runs npm on node through
  `dev/release/lib.ts`.
