# Script rules

- `release.sh` is the owner's, on an arm64 Mac (`docs/decisions.md`, "Releasing"); nobody else publishes.
- The release steps are `release/`'s scripts, each runnable alone.
- `targets.ts` is the one list of release platforms.
- `memory.ts` is too slow for `bun run check` (`docs/memory.md`).
- Scripts run on Bun; no `npx`.
