# CHD-485 library gate: libfx under Bun and `bun build --compile`

Run on 2026-11-09 with Bun 1.4.4 and libfx 0.0.16 (npm latest, published
2026-10-29), in a scratch project outside the repository. No real provider
was reached: every turn ran against a fake OpenAI Chat Completions server on
`localhost`, through libfx's custom provider, with one host tool.

## What was run

The gate script starts `Bun.serve` on `127.0.0.1`, answering the first
request with a streamed `tool_calls` chunk for a tool `echo` and the second
with the text `done`. It calls `getBackendInfo()`, then `createFxEngine()`
with `provider: { name: 'fake', baseUrl: 'http://localhost:<port>/v1', … }`
and the `echo` tool (`idempotent: true`), runs one prompt and checks the turn
ends `end_turn` with text `done` after two model requests. `GATE_BACKEND`
picks `auto`, `native` or `wasm`.

Binaries were built with `Bun.build({ target: 'bun', compile: { target } })`
for each of `scripts/targets.ts`: bun-darwin-arm64, bun-darwin-x64,
bun-linux-x64, bun-linux-arm64, and run from a directory with no
`node_modules`. darwin-x64 ran under Rosetta; the Linux binaries in
`debian:bookworm-slim` (glibc 2.36) containers of their architecture, and
linux-x64 also in `ubuntu:20.04` (glibc 2.31).

## Results

| Case | Native | Wasm |
| --- | --- | --- |
| `bun gate.ts` from source, darwin-arm64 | passes | passes |
| Compiled as is, every target | fails | fails |
| Compiled with the assets embedded and passed in, darwin-arm64 | passes | passes |
| Same, darwin-x64 (Rosetta) | passes | passes |
| Same, linux-arm64 and linux-x64, glibc 2.36 | passes | passes |
| Same, linux-x64, glibc 2.31 | fails: needs `GLIBC_2.34` | `auto` falls back and passes |

Compiled as is, `getBackendInfo()` reports `unavailable`:
`LIBFX_NATIVE_ARTIFACT_MISSING … access '/$bunfs/root/libfx.node'` and
`LIBFX_WASM_LOAD_FAILED … open '/$bunfs/root/fx-core.wasm'`. libfx names both
assets with `new URL('./…', import.meta.url)` (the platform package's
`index.js` for the addon, `node.js` for the Wasm), which webpack, Turbopack
and Next.js trace and Bun's bundler does not: neither file goes into the
binary, which grows by only the JavaScript.

"Embedded and passed in" means the entry imported
`./node_modules/@libfx/libfx-<platform>/libfx.node` and
`./node_modules/libfx/fx-core.wasm` with `with { type: 'file' }`, which Bun
embeds and gives as `/$bunfs/root/…` paths, and handed them to libfx's own
documented options: `nativeAddon` (a path) and `wasm` (the bytes). The
package specifiers `libfx/fx-core.wasm` and
`@libfx/libfx-<platform>/libfx.node` do not resolve: neither package exports
those files, so the import has to name the file inside `node_modules`,
past the packages' `exports`. Bun writes the embedded addon to the temporary
directory before loading it (`/tmp/.bun-…node` in the glibc 2.31 error).

## Size

Binary size in bytes, an empty entry against the gate with both assets
embedded (the JavaScript of libfx alone adds about 0.3 MB):

| Target | Empty | With libfx | Added |
| --- | --- | --- | --- |
| bun-darwin-arm64 | 89,159,906 | 99,413,858 | 10,253,952 (9.8 MiB) |
| bun-darwin-x64 | 98,168,288 | 109,800,928 | 11,632,640 (11.1 MiB) |
| bun-linux-arm64 | 109,235,192 | 119,524,344 | 10,289,152 (9.8 MiB) |
| bun-linux-x64 | 109,123,760 | 120,764,592 | 11,640,832 (11.1 MiB) |

Of that, the addon is 7.3 to 8.7 MB and `fx-core.wasm` 2.2 MB. Against
chord's current binaries (115 to 143 MB) it is 7 to 9 percent.
