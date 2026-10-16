# Script rules

- `bun dev <command>` is the Cliffy CLI in `dev.ts`, with modules in
  `dev/`; declare arguments there, not in each module.
- `bun dev release` is the owner's (`docs/decisions.md`, "Releasing");
  nobody else publishes. It needs an arm64 Mac when `natives`, `sign` or
  `notarise` is selected. A dry run still submits to Apple unless
  `--skip notarise` is passed.
- Release stages live in `dev/release/`. Select them with `--skip`, `--only`,
  `--from` and `--to`; preflight always runs. `--package` selects a publish.
- `targets.ts` is the one list of release platforms.
- `bun dev memory` is too slow for `bun run check` (`docs/memory.md`).
- Scripts run on Bun; no `npx`. The release runs npm on node through
  `dev/release/lib.ts` (the owner's exception in `docs/decisions.md`).
