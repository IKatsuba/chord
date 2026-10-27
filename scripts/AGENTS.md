# Script rules

- `bun dev <command>` is the Cliffy CLI in `dev.ts`, with modules in
  `dev/`; declare its arguments there, not in each module. `bun quality`
  and `bun lint` use `quality.ts` and `lint.ts`; `bun check` and `bun fmt`
  are native Bun commands.
- `bun dev release [version|major|minor|patch|fix]` is the owner's
  (`docs/decisions.md`, "Releasing"); nobody else publishes. Give it the
  version instead of editing package.json's by hand. It needs an arm64 Mac
  when `natives`, `sign` or `notarise` is selected. A dry run still submits
  to Apple unless `--skip notarise` is passed.
- A new release version needs `compile`. Before any stage it is committed
  alone as `chore: chord v<version>` and pushed to main when publishing.
  A failed push drops it; a later failure keeps it on origin. A dry run or
  run without publish drops its local commit, on failure and SIGINT,
  SIGTERM or SIGHUP too. SIGKILL may leave it: `git reset --keep HEAD~1`.
  Rerun with no version, or the same one, to release package.json's version.
- Release stages live in `dev/release/`. Select them with `--skip`, `--only`,
  `--from` and `--to`; preflight always runs. `--package` selects a publish.
- `dev/compile.ts` uses `Bun.build` with a plugin resolving OpenTUI's
  `react/jsx-dev-runtime` imports to `dev/jsx_dev_runtime.ts` on React's
  production runtime. Its `buildOptions` also builds the boundary test.
- `targets.ts` is the one list of release platforms.
- `bun dev memory` is too slow for `bun quality` (`docs/memory.md`).
- Scripts run on Bun; no `npx`. The release runs npm on node through
  `dev/release/lib.ts` (the owner's exception in `docs/decisions.md`).
