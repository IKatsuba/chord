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

## The list tool on fff

Run on 2026-11-09 by runtime, after the owner chose fff for `search`, to see
whether the same finder can serve `list` (files in a directory or by glob,
.gitignore honoured, limits) as it is. Same scratch setup and the same
`@ff-labs/fff-bun` 0.11.0; finders created with `disableWatch: true,
aiMode: true`. The truth is `git ls-files --cached --others
--exclude-standard`, run with `core.ignorecase=false` (on macOS `git init`
sets it to true, which would make `*.s` hide `.S` too); the glob reference is
`minimatch` 10, npm `glob`'s matcher, with default options.

The fixture is a git repository: a root `.gitignore` with `*.s`, `ignored/`,
`/build`, `*.log`, `!keep.log`, a nested `docs/.gitignore`, tracked and
untracked files, `arch/head.S` beside an ignored `arch/gen.s`, dotfiles
(`.hidden`, `.config/x.ts`), `node_modules/`, an empty directory, a name with
a space, nested `src/deep/er/est/`, a symlinked file and a symlinked
directory, a tracked file that matches an ignore rule (`git add -f`) and an
entry in `.git/info/exclude`.

### What each call returns

- **`glob(pattern)`** returns files only, as paths relative to `basePath`,
  with `totalMatched` and `totalFiles`. It is case-sensitive. **It is not npm
  `glob`'s semantics**, although its doc says "100% compatible": `*` crosses
  `/`, and a pattern without `/` matches at any depth.

  | Pattern | fff | minimatch over git's list |
  | --- | --- | --- |
  | `*` | all 16 files, every depth, dotfiles too | `README.md`, `keep.log` |
  | `src/*` | `src/a.ts`, `src/b.TS`, `src/deep/c.ts`, `src/deep/er/est/d.ts` | `src/a.ts`, `src/b.TS`, `src/link.md` |
  | `src/*.ts` | `src/a.ts` and the two nested `.ts` | `src/a.ts` |
  | `src/deep/*` | `src/deep/c.ts`, `src/deep/er/est/d.ts` | `src/deep/c.ts` |
  | `*.md` | `README.md`, `docs/Readme.md`, `docs/with space.md` | `README.md` |
  | `.*` | `.gitignore`, `.hidden`, `.config/x.ts` | `.gitignore`, `.hidden` |
  | `**/*` | 16 files including dotfiles | 12, no dotfiles (`dot: false`) |

  `**/*.S` finds `arch/head.S` and `**/*.s` nothing, as git does (globby got
  this wrong). `?`, `[ab]`, `{a,c}` and `**/x/**` work. `src`, `src/` and
  `src/deep/**/` as patterns return nothing or only files: there is no way to
  ask for the direct children of a directory.
- **Directories** never come from `glob` or `fileSearch`.
  `directorySearch('')` lists every indexed directory (12 here, the root as
  `""`, the empty directory included, ignored ones left out); with a query it
  is fuzzy: `src` returned 11 of 12. `mixedSearch('')` is both lists one after
  the other.
- **`fileSearch(query)`** is the fuzzy finder: `''` returns all files, any
  other query a ranked list, not a filter (`ts` returned all 16, `src/` 12 of
  16, `*.ts` 5).
- **Outside `basePath`** nothing is reachable: `../*`, `/etc/*` and even an
  absolute pattern inside the tree return 0, without an error.
- **Order** is the index's, not path order and not stable by name: in the
  fixture tracked files came first, then the rest by directory.
- **Pagination**: `pageSize` defaults to 100; `pageIndex` is an item offset,
  not a page number, contrary to its name and doc (`pageSize: 3, pageIndex: 1`
  returned items 2 to 4); an offset past the end returns an empty page with
  the right `totalMatched`. No limit other than the page.

### Against git's file list

| Case | git | fff |
| --- | --- | --- |
| `.gitignore` at any level, negation (`!keep.log`), anchored `/build` | honoured | honoured |
| `*.s` against `arch/head.S` | listed | listed |
| dotfiles, `node_modules/` not ignored | listed | listed in a git repository; **left out** in a directory with no `.git` |
| a tracked file matching an ignore rule | listed | **left out** |
| `.git/info/exclude` | honoured | **not honoured**: the file is listed |
| symlinked file or directory | listed as an entry | **never listed**, with `followSymlinks` off or on |

On the kernel tree (97,362 files by git) fff's `glob('**/*')` returned 97,242,
none extra. The 120 missing: 106 symlinks (94 to files, 12 to directories),
13 files whose name differs from another only by case (on macOS's
case-insensitive disk only one of each pair exists, so this is the checkout,
not fff), and `Documentation/.renames.txt`, tracked but matching the root's
`.*` rule.

Without a `.git`, the `.gitignore` rules still applied, but `.hidden`,
`.config/x.ts`, both `.gitignore` files and `node_modules/pkg/index.js`
disappeared: fff's rules differ by whether the directory is a repository.

### Time, kernel tree, warm cache, Apple Silicon

| Call | ms (two runs) |
| --- | --- |
| `create` + `waitForScan` | 327, 155 |
| `glob('**/*')`, all 97,242 in one page | 106, 86 (75, 95 again) |
| `glob('**/*')`, `pageSize: 100` | 11, 16 |
| `glob('drivers/net/**/*.c')`, 3,644 | 9, 11 |
| `glob('**/*.S')`, 1,339 | 6, 5 |
| `fileSearch('')`, all files | 65, 72 |
| `directorySearch('')`, 6,338 directories | 3, 4 |

Peak resident memory of the process: 471 and 485 MB, the same finder as
`search` with its mmap cache and content index (not measured with them off).
The calls are synchronous FFI, so they belong in the same `Worker` as
`search`.

### Inside a compiled binary

The fixture probe and the kernel run, built with `Bun.build({ compile:
{ target: 'bun-darwin-arm64' } })` and run from a directory with no
`node_modules`, gave output identical to the source run (the 40 fixture lines
byte for byte, the kernel's sorted list equal) and the same times (scan
261 ms, full glob 91 to 103 ms). The other targets were covered for `search`;
`list` uses the same library and was not rebuilt for them.

### Verdict

**fff does not fit `list` as it is.** It is fast, honours `.gitignore` the
way git does on case, and paginates, but:

1. its glob is not glob: `*` crosses `/` and bare patterns match at any
   depth, so "the files in `src/`" cannot be asked for, only "everything
   under `src/`";
2. it lists files only; directories come from a separate fuzzy call, so a
   directory listing (files and subdirectories) has to be assembled;
3. nothing outside the finder's `basePath` is reachable;
4. its file set is not git's: tracked-but-ignored files, `.git/info/exclude`
   and symlinks differ, and outside a repository dotfiles and
   `node_modules/` vanish.

Options for the owner:

- **a. Change the task to fit fff**: `list` becomes "files under the session
  directory matching fff's pattern", described to the model as it behaves
  (`*` matches across `/`, files only, relative paths, index order, a
  directory listing through `directorySearch`), with the set differences
  above accepted.
- **b. fff plus chord's own filtering**: take fff's results and cut them to
  direct children by path depth, merge in `directorySearch('')` entries,
  and sort. That is a workaround around the library (rewriting its output to
  mean something it does not), so it is the owner's decision.
- **c. Another library for `list`**, not tried here: a maintained walker or
  glob matcher with git's ignore semantics, case-sensitive, that survives
  `bun build --compile`. globby is already shown wrong on case.

## One library for search and list

Run on 2026-11-09 by runtime, after the owner ruled out two engines: one
maintained library has to serve `search` (regex over a tree, context lines,
limits, .gitignore) and `list` (a directory's entries, files and
directories, git's ignore semantics, case-sensitive), reach paths outside
the session's directory when a grant allows it, and survive
`bun build --compile` on all four release targets from a directory with no
`node_modules`, embedding only as the library documents. Same scratch rules
as above: every package in its own new directory, scripts elsewhere, paths
as arguments.

### Candidates

npm searched again (`ripgrep napi`, `ripgrep node binding`, `grep rust node`,
`keywords:napi grep`, `keywords:napi walker`, `keywords:gitignore rust`,
`ignore walk napi`, `fast file search napi`, `bun ffi grep`, `napi glob`,
`agent tools grep glob native` and others); jsr (`grep`, `ripgrep`, `walk`,
`glob`, `gitignore`, `search`) has nothing that walks a tree and greps it.
Weekly downloads are npm's for the week before 2026-11-09.

| Package | Version, date | Weekly | Licence | Search | List | Why in or out |
| --- | --- | --- | --- | --- | --- | --- |
| `@bastani/atomic-natives` (bastani-inc/atomic, 881 stars, pushed 2026-11-09; 294 versions since 2026-06) | 0.9.74, 2026-11-09 | 17.5k | MIT | `grep`: ripgrep's `grep-*` and `ignore` crates, context, `maxCount`, `offset`, `maxCountPerFile`, timeout, abort | `glob`: files, directories and symlinks, `recursive: false` for a directory's own entries | **tried, fits** |
| `@oh-my-pi/pi-natives` | 18.18.3, 2026-11-09 | 311k | MIT | same API family | `glob`, `listWorkspace` | tried: fails in a compiled binary, see below; 110 MB addon |
| `@gajae-code/natives` (pi-natives fork) | 0.20.0, 2026-11-08 | 2.9k | MIT | `grep` | `glob` | not tried: ships omp's `embedded-addon.js` ("See scripts/embed-native.ts"), the same build-step embedding as pi-natives; 48 MB addon |
| other pi-natives forks (`@sayknow-cli/natives`, `@f5-sales-demo/pi-natives`, `jeopi-natives`, `@ngodeai/natives`, …) | 2026 | under 1.2k each | MIT | | | not tried: same loader, a few hundred downloads |
| `@ff-labs/fff-bun` | 0.11.0 | 307k | MIT | yes | no, see "The list tool on fff" | out for `list` |
| `ripgrep` (Wasm) | 0.3.1 | 38k | MIT | yes | `rg --files` lists files only, never directories | out: no directory entries, 7 to 14 s on the kernel, no load on x64 without AVX |
| `@mcpc-tech/ripgrep-napi` | 0.0.4, 2025-08-19 | 472 | MIT | synchronous `search`, no context lines | none | out: no list, abandoned |
| `@immich/walkrs` | 0.0.13, 2026-02-20 | 24 | AGPL-3.0 | none | walker on ripgrep's `ignore` | out: no search, AGPL |
| `fast-find-in-files` | 2.0.1 | 7k | MIT | C++ addon, text search | none | out: no list |
| `weavatrix-scan` | 0.5.3 | 24 | MIT | repository scanner | | out: 24 downloads, not a grep |
| `@vscode/ripgrep` | 1.18.0 | 2.8M | MIT | `rg` executable | `rg --files`, files only | out: fails in a compiled binary (above), no directories |

### What was tried

**`@bastani/atomic-natives` 0.9.74**, its published README: "native `glob`,
`grep`, and `search` operations for Atomic's built-in `find` and `search`
tools". A standard napi-rs loader (`require('./atomic_natives.<target>.node')`
and the `@bastani/atomic-natives-<target>` optional packages); both calls are
async and take any directory as `path`.

The fixture is the one of "The list tool on fff", copied, with every file
holding `before`, `needle <path>`, `after`, and the symlinked directory now
pointing at a real directory outside the tree. A second repository outside
the tree has its own `.gitignore`. The truth for files is `git -c
core.ignorecase=false ls-files --cached --others --exclude-standard`; for a
directory's entries, every entry `ls -A` shows that `git check-ignore` does
not report (so tracked files count as not ignored).

| Case | git | `glob` (`hidden: true`, `includeNodeModules: true`) | `grep` |
| --- | --- | --- | --- |
| `.gitignore` at any level, negation, anchored `/build` | honoured | honoured | honoured |
| `*.s` against `arch/head.S` | listed | listed; `**/*.s` finds nothing, `**/*.S` finds it | searched |
| `.git/info/exclude` | honoured | honoured | honoured |
| dotfiles, `node_modules/` not ignored | listed | listed (both options default off: `hidden: false`, and `node_modules` pruned unless named) | searched (`hidden` defaults on) |
| a tracked file matching an ignore rule (`app2.log`) | listed | **left out** | **not searched** |
| symlinked file and directory | listed as entries | listed as entries (`fileType` 3), not followed | not entered, as `rg` without `-L` |
| empty directory | not listed (git tracks no directories) | listed | – |
| root's `.gitignore` when the path is a subdirectory (`arch/`) | – | honoured | honoured |
| a path outside the tree (another repository) | – | listed, its own `.gitignore` honoured | searched, its own `.gitignore` honoured |
| no `.git` at all | – | `.gitignore` still honoured | same |

A directory's own entries come from `glob({ pattern: '*', path: dir,
recursive: false })`: for the root, `src/`, `docs/` and `arch/` the result
equals the truth exactly except `app2.log`. `*.ts` without `recursive: false`
matches at any depth ("simple patterns recursive by default", as its doc
says). `\s` does not cross lines; context lines, `maxCount`, `offset`
(with `limitReached`) and case-sensitive matching behaved as documented.
`fileType` takes the numeric enum (1 file, 2 directory, 3 symlink), not the
string its doc comment names.

On the kernel tree its full listing equals git's 97,362 entries minus 14:
the 13 case-colliding names this macOS checkout cannot hold and
`Documentation/.renames.txt`, tracked but matching `.*`. The 106 symlinks are
listed. The listing of `drivers/net` (64 entries, files and directories)
equals the truth exactly. Both searches match native `rg`'s `path:line` sets
exactly (21,283 and 10,582).

**Compiled**, a gate entry that lists a temporary tree's root (`.gitignore`
naming `ignored/` and `*.s`) and greps `needle\d*` with one line of context,
built with `Bun.build({ target: 'bun', compile: { target } })` from a
directory where `bun install --os='*' --cpu='*' --libc='*'` had put every
platform package, then run from a directory with no `node_modules`:

| Target | Result | Added to the binary |
| --- | --- | --- |
| bun-darwin-arm64 | passes | 18,014,592 (17.2 MiB) |
| bun-darwin-x64 (Rosetta) | passes | 17,842,176 (17.0 MiB) |
| bun-linux-arm64 (`debian:bookworm-slim`, OrbStack) | passes | 36,503,552 (34.8 MiB) |
| bun-linux-x64 (`debian:bookworm-slim`, OrbStack) | passes | 37,314,560 (35.6 MiB) |

Nothing was added to the build: Bun's compiler embeds the `.node` files the
napi-rs loader `require`s, which is Bun's documented way for N-API addons.
On Linux it embeds both the gnu and the musl addon, because the loader
requires both; that doubles the Linux cost, and the package offers no way to
drop one. The gnu addons need glibc 2.17 at most.

**`@oh-my-pi/pi-natives`** compiled the same way (darwin-arm64) fails at
start: "Failed to load pi_natives native addon for darwin-arm64". Its loader
expects omp's own embed step, so it does not fit as it is.

### Time, kernel tree, warm cache, Apple Silicon

Each tool in a fresh process, two rounds; "first" is the first call in the
process, "warm" the median of five more. Milliseconds, round 1 / round 2.

| Call | atomic-natives first | atomic-natives warm | fff first | fff warm |
| --- | --- | --- | --- | --- |
| scan before the first call | none | | 124 / 113 | |
| literal `EXPORT_SYMBOL_GPL` | 3,383 / 1,827 | 3,297 / 1,840 | 2,385 / 3,872 | 59 / 58 |
| regex `static\s+int\s+\w+_probe\(` | 3,461 / 2,133 | 3,427 / 2,131 | 463 / 190 | 137 / 139 |
| full listing (97,348 / 97,242 files) | 134 / 130 | 114 / 120 | 63 / 67 | 60 / 58 |
| `drivers/net` (atomic: its 64 entries; fff: all 6,959 files under it, the nearest call) | 9 / 10 | 9 / 9 | 10 / 11 | 9 / 10 |

Native `rg` took 1.4 to 1.6 s for the same searches (above). atomic-natives
has no index, so every search walks and reads the tree again: about as fast
as `rg`, never as fast as fff's warm index. Its calls run off the main
thread: the longest event-loop gap was 16 ms during a 3.1 s grep and 20 ms
during the full listing, so no `Worker` is needed. `signal` stopped a grep
206 ms after an abort at 200 ms, `timeoutMs: 100` at 102 ms. Peak resident
memory of the whole run: 131 MB (fff: 464 MB).

### What could not be checked

- Real x64 Linux hardware, musl, Windows, older glibc in a container.
- A cold disk; the kernel benchmark on Linux or inside a compiled binary
  (only the gate ran compiled).
- `core.excludesFile` (a global gitignore), nested repositories and
  submodules; `cache: true`.
- How stable its API is: it is released with the Atomic agent almost daily
  (0.9.72 to 0.9.74 in two days), pre-1.0, and promises nothing to outside
  users.

### Verdict

**`@bastani/atomic-natives`, exact-pinned at 0.9.74, fits both tools as it
is.** One async `grep` and one `glob` over ripgrep's crates: git's ignore
semantics on case, `.git/info/exclude` and nested `.gitignore`, a
directory's own entries with directories and symlinks, any path chord
grants, context lines and limits, abort and timeout, and all four targets
through `bun build --compile` with nothing but Bun's documented addon
embedding. What comes with it:

- It is another agent's internal addon (a PTY, tree-sitter, a task
  supervisor ship in the same `.node`), versioned with that agent; chord
  takes it for `grep` and `glob` only and pins it exactly.
- It adds 17 MiB to the macOS binaries and 35 MiB to the Linux ones (both
  libc builds); fff adds 5 to 11 MiB.
- Searches walk the tree each time: 1.8 to 3.4 s on the kernel tree, against
  fff's 60 to 140 ms warm; on a project tree of a few thousand files that is
  tens of milliseconds.
- Tracked files that match an ignore rule are neither listed nor searched,
  as with ripgrep; empty directories are listed, which git cannot show.
- Its defaults differ between the calls (`hidden` off for `glob`, on for
  `grep`; `node_modules` pruned by `glob`): chord sets them explicitly.

If the owner does not want another agent's addon, the options are:

- **a.** Change the task to fit fff: `search` and `list` inside the
  session's directory only, `list` with fff's semantics as "The list tool on
  fff" describes them.
- **b.** fff for `search` alone, with its limits stated (inside its
  `basePath` only, `\s` crossing lines, frecency order), and `list` left
  without a library.
- **c.** `@oh-my-pi/pi-natives` (311k a week, the upstream of the same API)
  only with a workaround: chord would have to reproduce omp's undocumented
  embed step for its 110 MB addon. Named here as a workaround, not
  recommended.
