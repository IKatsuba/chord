# Runtime rules

- Only this folder calls `Bun.*`; everything else in `src/` calls `node:` built-ins, so moving runtime is this folder's change.
