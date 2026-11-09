# CHD-485 search: a content-search library for the built-in agent's `search` tool

Run on 2026-11-09 with Bun 1.4.4 on an Apple Silicon Mac, by runtime. The
owner asked for a fast maintained library for `search` (regex over a tree,
.gitignore honoured, context lines, limits), not JavaScript over globby. Every
candidate was installed in its own new empty directory under `/tmp`; the
trial and benchmark scripts lived in a separate directory and took paths as
arguments. No model, agent or provider was reached.

## Candidates

Found by searching npm (`ripgrep`, `ripgrep napi`, `grep napi`, `grep wasm`,
`keywords:grep rust`, `keywords:ripgrep`, and others) and jsr (`grep`,
`ripgrep`, `search`: nothing relevant on jsr). Weekly downloads are npm's for
the week before 2026-11-09.

| Package | Version, date | Weekly | Licence | Kind | Ships per platform |
| --- | --- | --- | --- | --- | --- |
| `@ff-labs/fff-bun` (dmtrKovalenko/fff, 11k stars, pushed 2026-11-08) | 0.11.0, 2026-09-21; nightlies to 2026-11-06 | 307k | MIT | Rust library over `bun:ffi`, indexed finder with grep | `@ff-labs/fff-bin-<os>-<cpu>[-gnu\|-musl]` optional packages, one `.dylib`/`.so` each |
| `ripgrep` (pithings/ripgrep-node, 91 stars) | 0.3.1, 2026-04-06 (6 versions) | 38k | MIT | ripgrep 15 compiled to `wasm32-wasip1` with SIMD, own WASI shim | none: the Wasm is inlined in a JS module (z85 + brotli) |
| `@vscode/ripgrep` (Microsoft) | 1.18.0, 2026-05-07 | 2.8M | MIT | the `rg` executable; exports only `rgPath` | `@vscode/ripgrep-<os>-<cpu>` optional packages |
| `@oh-my-pi/pi-natives` (can1357/oh-my-pi) | 18.18.3, 2026-11-09 | 311k | MIT | N-API addon of the omp agent: grep plus PDF, audio, WebRTC, clipboard… | `@oh-my-pi/pi-natives-<os>-<cpu>`, a 110 MB `.node` on darwin-arm64 |
| `@mcpc-tech/ripgrep-napi` | 0.0.4, 2025-08-19 (2 versions) | 466 | MIT | napi-rs addon over ripgrep's crates | napi-rs optional packages |
| `@ast-grep/napi` | 0.51.1, 2026-11-02 | 5.8M | MIT | AST pattern search | napi-rs optional packages |
| `xgrep` | 0.9.0, 2026-11-05 | 420 | MIT or Apache-2.0 | trigram-indexed search | one 16 MB package |
| `@stll/text-search` | 2.0.1, 2026-11-04 | 75k | Apache-2.0 | regex/literal/fuzzy over strings in memory | napi-rs |
| `@ai-ecoverse/wasi-ripgrep`, `@ai-ecoverse/wasm-grep` | 2026-10 | ~500 | MIT/Unlicense; GPL-3.0 | WASI builds for the slicc kernel | Wasm |
| JS fallback: `globby` + `RegExp` per line | globby 16.2.4 | 113M | MIT | pure JS | none |

Left out without a trial: `@ast-grep/napi` (AST patterns, not text regex),
`@stll/text-search` (searches strings it is given, walks no tree), `xgrep`
(an index to build and keep, 420 downloads a week), the two `@ai-ecoverse`
packages (built for another kernel's runtime; `wasm-grep` is GPL-3.0), and
`@mcpc-tech/ripgrep-napi` (two releases a year ago, the README still the
napi-rs template, synchronous only, no context lines). `@lvce-editor/ripgrep`
and `@joshua.litt/get-ripgrep` wrap or download the same `rg` executable as
`@vscode/ripgrep`.

## What was tried

### Under `bun build --compile`

A gate entry per library makes a temporary tree (a `.git` directory, a
`.gitignore` naming `ignored/`, two files with matches and one ignored file
with a match), searches `needle\d*` with one line of context before and
after, and passes when it gets exactly the two expected matches and their
context lines. Binaries were built with `Bun.build({ target: 'bun', compile:
{ target } })` for each target in `scripts/targets.ts` and run from a
directory with no `node_modules`: darwin-x64 under Rosetta, the Linux
binaries in `debian:bookworm-slim` (glibc 2.36) containers of their
architecture under OrbStack. Other platforms' packages were installed with
`bun install --os='*' --cpu='*' --libc='*'`, as chord's compile does.

| Library | darwin-arm64 | darwin-x64 | linux-arm64 | linux-x64 | How it embeds |
| --- | --- | --- | --- | --- | --- |
| `@ff-labs/fff-bun` 0.11.0 | passes | passes | passes | passes | by itself: its `embedded.ts` imports the platform library `with { type: 'file' }`; on Linux the build adds `--define FFF_LIBC='"gnu"'`, as its README documents |
| `ripgrep` 0.3.1 | passes | passes | passes | fails, see below | nothing to embed: the Wasm is JavaScript |
| `@vscode/ripgrep` 1.18.0 (darwin-arm64 only) | fails | – | – | – | `rgPath` throws (the platform package is not in the binary); the executable imported `with { type: 'file' }` is embedded but `Bun.spawn` of its `/$bunfs/root/…` path fails `ENOENT … posix_spawn` |
| `@oh-my-pi/pi-natives` | not tried | | | | no documented option: its `embedded-addon.js` is "null on disk; standalone binary builds replace this module in memory" by omp's own `scripts/embed-native.ts` |

Both passing libraries also passed from source (`bun gate.ts`) and inside a
Bun `Worker` in a compiled binary (darwin-arm64 and linux-arm64, the worker
as a second entry point), where the main thread's largest timer gap stayed
under 8 ms.

The `ripgrep` failure on linux-x64:
`CompileError: WebAssembly.Module doesn't parse at byte 204: wasm-simd is not
enabled`. OrbStack's x64 emulation reports no AVX (`/proc/cpuinfo` stops at
`sse4_2 … bmi2`), and the package ships only the SIMD build. On darwin-x64
under Rosetta, which reports AVX, it passed. Whether it loads on real x64
Linux hardware with AVX was not checked; on any x64 machine without AVX it
cannot load at all.

A `ripgrep` trap found on the way: `ripgrep()` adds every argument that does
not start with `-` to WASI's preopens, resolving relative ones against
`process.cwd()`. With the default `preopens: { '.': cwd }` and `.` as the
path, in a container whose cwd was `/` it searched the whole file system
(`/proc` included). Passing the absolute root as the path and `preopens: {}`
(both documented) searches only the root.

`@ff-labs/fff-bun`'s Linux libraries require glibc 2.30 at most (the highest
`GLIBC_2.x` symbol version in both `.so` files), below libfx's 2.34.

### Size added to the binary

Against an empty entry compiled the same way:

| Target | `ripgrep` (Wasm) | `@ff-labs/fff-bun` |
| --- | --- | --- |
| bun-darwin-arm64 | 743,040 (0.7 MiB) | 5,481,984 (5.2 MiB) |
| bun-darwin-x64 | 737,280 (0.7 MiB) | 10,076,160 (9.6 MiB) |
| bun-linux-arm64 | 720,896 (0.7 MiB) | 6,094,848 (5.8 MiB) |
| bun-linux-x64 | 749,568 (0.7 MiB) | 11,227,136 (10.7 MiB) |

`@oh-my-pi/pi-natives` would add about 110 MB on darwin-arm64, close to
doubling the binary.

## Benchmark

Tree: a shallow clone of `torvalds/linux` at 7475ea8b5 (2026-11-08) under
`/tmp`: 97,243 files, 1.8 GB without `.git`. (macOS's case-blind file system
kept one file of each of 13 case-colliding pairs.) Queries: the literal
`EXPORT_SYMBOL_GPL` and the regex `static\s+int\s+\w+_probe\(`, both
case-sensitive, .gitignore honoured, hidden files skipped.

Each tool ran from source under `bun` in a fresh process, twice (two
rounds); in each process both queries ran once ("first") and then five times
more (median, "warm"). The page cache was primed once before the rounds
(macOS gives no cold disk without root), so "first" means the first search
in a new process: module load, Wasm compile and fff's index are in it, disk
reads are not. "Loop gap" is the longest stretch the search held the event
loop (a 5 ms interval timer's largest gap). Times in milliseconds, round 1 /
round 2.

| Tool | Load + init | Literal first | Literal warm | Regex first | Regex warm | Loop gap |
| --- | --- | --- | --- | --- | --- | --- |
| JS fallback (globby + RegExp) | 47 / 43 | 9,622 / 9,490 | 9,473 / 9,447 | 9,667 / 9,602 | 9,640 / 9,603 | 7,104–7,511 |
| `ripgrep` (Wasm, one thread) | 3 / 2 | 9,626 / 6,822 | 11,679 / 9,854 | 13,640 / 10,130 | 13,356 / 11,539 | 10,404–15,027 |
| `@ff-labs/fff-bun` | 174 / 125 (scan) | 2,576 / 2,445 | 96 / 66 | 623 / 464 | 153 / 148 | the whole search |
| reference: `rg` 15 native, spawned | 2 / 2 | 1,592 / 1,375 | 1,490 / 1,364 | 1,501 / 1,420 | 1,524 / 1,397 | 6–26 |
| reference: `@oh-my-pi/pi-natives` | 112 / 149 | 3,580 / 2,846 | 3,679 / 2,860 | 3,708 / 3,107 | 3,854 / 2,929 | 7–11 |

Peak resident memory of the whole fff run: 464 MB (`/usr/bin/time -l`),
against 70 MB for the process that spawned native `rg` (the child not
counted). The Wasm build's first run ever decodes the module into
`$TMPDIR/ripgrep-wasm-<hash>.wasm` (2.2 MB): the gate binary took 0.16 s
then and 0.03 s after.

### Results checked equal

Match sets (`path:line`) were compared with native `rg`'s:

- Literal: `ripgrep` (Wasm), fff and pi-natives match `rg` exactly, 21,283
  matches.
- Regex: `ripgrep` (Wasm) and pi-natives match `rg` exactly, 10,582
  matches. **fff finds 132 more** (10,714): its regex mode lets `\s` match a
  newline, so `static int` at the end of one line and `foo_probe(` at the
  start of the next count as one match, reported at the first line
  (`arch/arm/common/locomo.c:355` and others). ripgrep refuses matches
  across lines unless asked (`-U`). fff has no option for this.
- **The JS fallback is wrong**, not just slow: it misses 25 literal matches
  in 11 files, all `.S` assembly. The kernel's root `.gitignore` has `*.s`;
  globby's ignore matching (the `ignore` package) is case-blind, so it drops
  all 1,348 tracked `.S` files, which git (`git check-ignore`) does not
  ignore. globby exposes no option for this.

## What could not be checked

- Real x64 Linux hardware: linux-x64 ran only under OrbStack's emulation,
  which has no AVX; the Wasm build's failure there is real for x64 machines
  without AVX, its success on ones with AVX is not shown.
- A cold disk: no root to drop the page cache on macOS.
- Older glibc in containers (only bookworm's 2.36 was run; fff's floor of
  2.30 is read from its symbols), musl, Windows.
- The benchmark on Linux, and fff with its watcher on (it was off) or
  through a long session where files change under it.
- `@ff-labs/fff-node` (the same library over `ffi-rs`, for Node): chord runs
  on Bun, so only `fff-bun` was tried.

## Recommendation

**`@ff-labs/fff-bun`, exact-pinned at 0.11.0** (pre-1.0, per AGENTS.md).
It is the only candidate that is fast, maintained, honours .gitignore,
gives context lines and limits (`pageSize`, `maxMatchesPerFile`,
`maxFileSize`, `timeBudgetMs`, a cursor), and fits `bun build --compile`
on all four targets as it is, through what its README documents: the build
adds `--define FFF_LIBC='"gnu"'` for the Linux targets and nothing else.
Warm searches on the kernel tree took 66 to 153 ms, ten times faster than
native `rg`; the first search in a process was 0.5 to 2.6 s. It adds 5.2 to
10.7 MiB per binary.

What comes with it, for the design to carry:

- `grep()` is a synchronous FFI call: it holds the event loop for the whole
  search (2.6 s on the first kernel search). It must run in a Bun `Worker`,
  which works in the compiled binary. `bun:ffi` is Bun's own, so the
  worker's loader belongs in `src/platform/`.
- It is a finder with state, not a function: `FileFinder.create({ basePath })`
  scans the tree and keeps an mmap cache and a content index (464 MB peak on
  the kernel tree; a background watcher unless `disableWatch`). One finder
  per session's working directory, destroyed with the session.
- Its regex mode lets `\s` cross lines, so it can return matches ripgrep
  would not; results come in frecency order, paginated, not path order. The
  `search` tool's description to the model should say what it does rather
  than call it grep.
- Its `fileSearch` and `glob` could serve the `list` tool too; not tried here.

No candidate needs a workaround around the library to fit, so no choice is
forced on the owner here. If the owner would rather have ripgrep's exact
semantics, the options are:

1. **`ripgrep` (Wasm) as it is**: +0.7 MiB and no build step, but on this
   tree it was as slow as or slower than the JS fallback (7 to 14 s), holds
   the event loop unless in a `Worker`, and cannot load on x64 without AVX.
2. **`@vscode/ripgrep` with chord writing the embedded `rg` to disk and
   marking it executable before spawning it**: native speed (1.4 s), but that
   is a workaround the package does not document (it exports only `rgPath`,
   which fails in a compiled binary), so it is the owner's decision.
3. **Change the task**: accept fff's semantics as they are (the recommendation
   above).

`@oh-my-pi/pi-natives` is async and matched `rg` exactly, but it is a 110 MB
addon of another agent's internals whose embedding goes through that agent's
own build step, and `ripgrep-napi` is abandoned. The JS fallback is both the
slowest and wrong on case (`*.s` drops `.S`), so it should not ship even as
a fallback.
