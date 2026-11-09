# CHD-485 commands: which shell commands auto admits without review

Run on 2026-11-09 with Bun 1.4.4 on an Apple Silicon Mac, by runtime. The
owner's decision A6 (b): under the built-in agent's auto mode, fx's
reversible read-only shell commands are admitted without review. This file
reads what fx admits, collects the classification bypasses fx's CHANGELOG
records as test cases, tries the libraries that could parse a command line,
and recommends what is library and what is chord's port of fx.

Sources: the fx repository at tag `v0.0.16` (paths below are relative to its
root, read through `gh api …/contents/<path>?ref=v0.0.16`), its
`CHANGELOG.md` at `v0.0.16` and on `main` (identical on 2026-11-09: no
release since). Every npm package was unpacked or installed in its own new
directory under `/tmp`, with install scripts blocked; the trial scripts
lived in a separate directory and took the install directory as an
argument. No model, agent or provider was reached.

## 1. What fx admits

fx has two separate admissions for a shell call, and the owner's words
("reversible read-only") touch both. Neither is exposed by libfx 0.0.16:
both are compiled into the core (`auto.md` §2).

### The order (src/core/tooling/tool_admission.zig)

`resolveOrdinaryPermissionOutcome` (`:1091`):

1. **Direct read-only plan, every mode** (`:1099-1108`, through
   `defaultRunCommandPermissionOutcome` `:2117-2143` and
   `command_admission.defaultForRunCommand`,
   `src/core/permissions/command_admission.zig:126-153`). A call in a tty,
   or one that asks for the user's shell environment, never takes this path
   (`command_admission.zig:131-139`). If `command_effect.plan` returns a
   direct plan, the call is admitted with `direct_only` authority: fx runs
   the planned argv itself, **not through a shell**. If the plan fails only
   because fx cannot run git safely here, auto does not run the command at
   all and tells the model so (`:2135-2148`).
2. **Known reversible, auto only** (`:1126-1147`):
   `command_effect.knownReversibleAutoCommand`, run **through the user's
   shell**. Skipped when the user's startup files define an alias or
   function named by any word of the command, or when fx could not capture
   those names (`:1129-1135`).
3. Everything else in auto goes to the reviewer model (`:1149-1156`).

### Direct read-only plan (src/core/shell_command/command_effect.zig)

`plan` → `planWithGit` (`:491`):

- Refused outright: background (`:498`), any OS but macOS and Linux, empty,
  over 8 KiB (`:5`).
- `validateShellShape` (`:554-608`) on the raw text: invalid UTF-8, NUL or
  CR; unquoted `$ \` * ? [ ~` (dynamic); unquoted `\ # ; ( ) { }` or
  newline; `&` (and `&>`); `||`; any `>`; `<(`, `<>`, `<<`, `<&`; inside
  double quotes `$`, backtick, `\` or newline; an unterminated quote. Each
  sends the call to approval with a reason.
- Split on unquoted `|` into at most 8 stages (`:10`); each stage is
  tokenized; an unquoted `<` (input redirect) or any operator token in a
  stage is refused (`parseStage`, `:610-642`); a first word containing `=`
  (an assignment) is refused (`:629-631`).
- `planFamily` (`:654-674`): `touch rm mkdir rmdir mv cp install chmod chown
  ln` (`:1067`), `curl wget ssh scp nc` (`:1080`) and `sh bash zsh dash env
  xargs sudo doas kill pkill nohup` (`:1088`) are refused by name; then only
  these, each rewritten to a fixed absolute executable and canonical argv:

| Command | Admitted form | Lines |
| --- | --- | --- |
| `printf` | format of printable ASCII with only `\n`, `%%`, `%s`, and exactly one operand per `%s` → `/usr/bin/printf` | `:676-731` |
| `pwd` | no operand or `-P` → `/bin/pwd -P` | `:733-745` |
| `ls` | flags from `1 a A d F l n p` (`l` becomes `-n`), up to 64 operands, any path → `/bin/ls -q … -- <operands>` | `:747-808` |
| `wc` | flags from `L c l m w`, **no operand** (reads the pipe) → `/usr/bin/wc` | `:810-836` |
| `cat` | no argument at all (reads the pipe) → `/bin/cat` | `:838-848` |
| `head`, `tail` | optional `-n N` with N ≤ 10000, **no operand** → `/usr/bin/head -n N` | `:850-873` |
| `grep` | flags from `E F i n v`, exactly one pattern, **no file** → `/usr/bin/grep … -- <pattern>` | `:875-912` |
| `git status` | `-s -b --short --branch --porcelain --porcelain=v1 --untracked-files=no\|normal\|all` | `:948-973` |
| `git diff` | `--cached --staged --stat --shortstat --numstat --name-only --name-status --check --no-renames`, then `--` and up to 64 pathspecs; no revisions | `:975-1008` |
| `git log` | `--oneline --stat --shortstat --name-only --name-status --no-merges --decorate[=short\|no]`, `-n N` / `--max-count=N` with N ≤ 1000, `--` and up to 64 pathspecs; `--max-count=100` by default | `:1010-1058` |

  Every other first word, and `git` with any other subcommand or with an
  option before it (`git -C`, `git -c`), goes to approval.

So the direct set never names a file for `cat`, `head`, `tail`, `wc` or
`grep`: file reads go through the read tools, and these only filter another
stage's output. `ls` and `git diff`/`git log` pathspecs take any path,
inside the workspace or not.

How fx runs a direct plan (not parsing, but part of why it is safe):

- Each stage's argv is spawned directly, in its own process group, piped to
  the next; output is capped at 64 KiB across stages
  (`src/core/permissions/direct_command.zig:13`, `:161`).
- Environment `PATH=/usr/bin:/bin`, `LC_ALL=C`, `LANG=C` and nothing else
  (`direct_command.zig:412-427`).
- git through `safe_git` (`src/core/shell_command/safe_git.zig`): a git at
  a fixed system path, never from `PATH` (`:142-157`), version ≥ 2.25;
  `--no-pager --no-optional-locks -c core.fsmonitor=false -c
  core.hooksPath=/dev/null -c log.showSignature=false`, every filter driver
  the repository's config defines blanked (`-c filter.<name>.clean=` …),
  `--no-ext-diff --no-textconv --ignore-submodules=all` (`:84-122`); an
  environment of fixed `PATH`, `C` locale, no prompt or pager, and only the
  variables that locate the user's own git config (`:124-140`); and
  `prepare` refuses when it cannot read the repository config, a filter name
  holds `=`, or git would resolve another repository than the one read
  (`:56-73`).

### Known reversible, auto only (command_effect.zig:16-285)

- Refused: background, empty, over 8 KiB, any `\n` or `\r` (`:21-28`).
- Tokenized; stages are separated by a **bare** `&&` only (`:54-56`); an
  unquoted `| || & ; ( ) { }` anywhere refuses (`:69-80`).
- Per stage: one trailing `2>&1` written bare and touching (`:86-101`) is
  dropped; any other redirection refuses; any token whose raw text (quoted
  or not) holds `$ \` * ? [ ~ ^ # ; ( ) { }` or a newline refuses (`:137-143`:
  `^` and `#` are zsh `extendedglob` globs); a token starting with `#` (a
  comment) refuses (`:60-62`).
- The stage's first word must then be one of (`:103-135`):

| Command | Admitted when | Lines |
| --- | --- | --- |
| `node` | exactly `-v` or `--version` | `:116-118` |
| `which` | one or more operands, none starting with `-` | `:119-121` |
| `git status` | **with any arguments** | `:157-160` |
| `git remote -v` | exactly | `:161-163` |
| `git worktree list …` | any arguments after `list` | `:164-166` |
| `git fetch` | only the options in `:175-189` (exact spelling; no `--upload-pack`, no prune, no `--filter`), value options `--depth= --deepen= --shallow-since= --shallow-exclude= --jobs= --recurse-submodules=`; no repository that names a remote helper (`<x>::…`, or a URL scheme other than file, git, ssh, git+ssh, ssh+git, http, https), also after `--` | `:175-247` |
| `npm` | `-v`/`--version`; `install`, `i`, `ci`, `test` without `-g --global --location[=global] --prefix[=…]`; `run <script> …` | `:249-261`, `:275-285` |
| `bun`, `pnpm`, `yarn` | `-v`/`--version`; `install`, `test` without the global flags; `run <script> …` | `:263-273` |
| `zig` | `build …` | `:130-132` |

This list is **reversible, not read-only**: `npm install`/`ci` and
`bun|pnpm|yarn install` reach the network and run lifecycle scripts;
`npm|bun|pnpm|yarn run <script>` and `test` run whatever the project's
`package.json` says; `zig build` runs the project's `build.zig`; `git fetch`
reaches the network and writes refs. Only `node -v`, `which`, `git status`,
`git remote -v` and `git worktree list` in it only read, and `git status`
runs plain git through the user's shell, where the repository's
`core.fsmonitor` and the user's aliases apply.

## 2. The bypasses fx fixed, as test cases

Every Security entry of fx's CHANGELOG (v0.0.1 to v0.0.16; `main` is the
same file) that concerns which command skips review. The expected verdicts
are fx's own, from its tests at `command_effect.zig:296-387`. All are for
`knownReversibleAutoCommand`.

| CHANGELOG | Entry | Command | Expected |
| --- | --- | --- | --- |
| 0.0.16 (`:49`) | escaped or separated stderr descriptors | `git status \2>&1` | review |
| | | `git status<TAB>\2>&1` | review |
| | | `git status 2 >&1` | review |
| | | `git status '2'>&1` | review |
| | | control: `npm install 2>&1` | admit |
| 0.0.15 (`:155`) | shell comments | `git status #note` | review |
| | quoted command separators | `git fetch '&&' git status --prune` | review |
| | | `git fetch \&\& git status --prune` | review |
| | zsh extended globs | `git fetch ^nomatch .` | review |
| | | `git fetch --prun#e` | review |
| | | `npm install react@^18` | review |
| | | `npm test x##` | review |
| 0.0.15 (`:156`) | `git fetch` options or address that start a program | `git fetch --upload-pack=x .` | review |
| | | `git fetch --upload-pack x origin` | review |
| | | `git fetch --upl=x .` (prefix of a long option) | review |
| | | `git fetch origin --upload-pack=x` | review |
| | | `git fetch '--upload-pack=x' .` | review |
| | | `git fetch probe::x`, `git fetch ext::sh` | review |
| | | `git fetch 'probe.v2+x::y' main` | review |
| | | `git fetch -- probe::x`, `git fetch origin -- probe::x` | review |
| | | `git fetch --multiple origin probe::x` | review |
| | | `git fetch probe://host/repository`, `PROBE://…`, `ftp://…` | review |
| | | `git fetch --prune origin`, `git fetch -p` | review |
| | | `git fetch --filter=blob:none origin` | review |
| 0.0.14 (`:258-259`) | read-only git checks ran repository-configured programs; auto reran a refused git check unprotected | not a parse case: `safe_git`'s hardening and the hold at `tool_admission.zig:2135-2148` | – |
| 0.0.13 (`:328`) | routine commands using captured aliases or functions | not a parse case: needs the shell's alias and function names (`tool_admission.zig:1129-1135`) | – |

`0.0.15` `:158` ("approval screens recognize destructive commands after
quoted environment values or command substitutions") is about labelling
the approval screen (`command_classification.zig`), not admission.

The two runtime entries cannot be tests of a classifier; they are
conditions on how an admitted command runs (§6, Q2).

## 3. Candidates

Found by searching npm (`bash parser`, `shell parser`, `sh-syntax`,
`tree-sitter-bash`, `bash ast`, `shell command classify`, `shell command
safe`, `is safe command`, `dangerous command detect`, `command read-only
classifier`, `shell permission agent`). Weekly downloads are npm's for the
week before 2026-11-09.

| Package | Version, date | Weekly | Licence | Kind | Size |
| --- | --- | --- | --- | --- | --- |
| `unbash` (webpro-nl/unbash, 147 stars, pushed 2026-11-07) | 6.0.4, 2026-11-07 | 27.0M | ISC | Bash parser in TypeScript: typed AST with source positions, word parts (literal, quoted, glob, expansions, brace…), errors; zero dependencies | 359 KiB unpacked, 460 KiB `dist` |
| `sh-syntax` (un-ts/sh-syntax, 71 stars, pushed 2026-11-09) | 0.8.3, 2026-11-09 | 519k | MIT | mvdan/sh compiled to Wasm (Go); bash, POSIX, mksh, bats and zsh variants; sync and async | 3.8 MB Wasm |
| `web-tree-sitter` + `tree-sitter-bash` (335 stars, pushed 2026-09-13) | 0.27.2 + 0.25.1, 2025-12-02 | 9.0M + 3.9M | MIT | tree-sitter runtime in Wasm plus the bash grammar's Wasm; a CST | 206 KiB + 1.3 MB Wasm (the grammar package ships 19 MB with sources and a native addon chord would not load) |
| `shell-quote` (already chord's, `src/acp/process.ts:2`, lock 1.12.0) | 1.12.0, 2026-10-02 | 97.2M | MIT | a lexer: words, operator objects, globs, comments; no source positions | 26 KiB |
| `bash-parser` and forks | 0.5.0, 2017 | 30k | MIT | unmaintained since 2017 | – |
| `sh-ast`, `@aliou/sh`, `bash-ast`, `@dsherret/shell` | 2026 | 2.9k–25k | MIT | another mvdan/sh Wasm build; a parser marked WIP; a small parser; dax's shell (an executor) | – |

Ready-made "is this command read-only" classifiers:

- `@gotgenes/pi-permission-system` 42.0.0 (MIT, 11.6k weekly): an extension
  of the Pi coding agent, peer-dependent on `@earendil-works/pi-coding-agent`;
  rules are user wildcard patterns over a tree-sitter parse. Exports a
  service bound to Pi, no classifier.
- `@dsh-cc/permission-rules` 0.9.4 (Apache-2.0, 588 weekly): a Claude
  Code–style rule engine with a risk tier list (catastrophic, destructive)
  for a plugin waterfall; denies the dangerous, does not prove a command
  only reads.
- `@shinynito/pi-menshen` 2.1.0 (no licence field, 10 weekly): a Pi
  extension, TypeScript sources only.
- `@google/gemini-cli-core` 0.67.0 (Apache-2.0) is 46 MB of agent;
  `@openai/codex` and `opencode-ai` on npm are launchers of native binaries
  whose classifiers (Codex's `is_safe_command` in Rust) are not callable.

None gives fx's verdicts; none was carried to a trial. So: a parser from
the list above, with chord's port of fx's rules on top.

Left out without a trial: `bash-parser` (dead), `sh-ast` (a second build of
what `sh-syntax` is, 4.4k weekly), `@aliou/sh` (WIP by its own words),
`bash-ast`, `@dsherret/shell`.

## 4. Trials

### The corpus

218 cases (`corpus.ts` of the trial, to become chord's test table):

- the bypass table above (29);
- fx's own expectations for `knownReversibleAutoCommand`
  (`command_effect.zig:296-387`, 28 more) and for `plan`
  (`:1305-1444`, 29 admitted, 62 refused, incl. the 8- and 9-stage
  pipelines);
- 70 ordinary commands judged by hand against fx's rules for the combined
  auto verdict (direct or reversible): read-only that fx admits (`ls -la`,
  `git diff --stat`, `git status --short | wc -l`, `git status --ignored`…),
  read-only that fx reviews (`cat README.md`, `rg foo`, `find . -name
  '*.ts'`, `head -n 5 README.md`, `git show HEAD`, `ls -la ~/.ssh`…),
  reversible that fx admits (`npm install`, `npm run build`, `zig build`,
  `git fetch`), and 47 that change something or run code (`rm -rf build`,
  `git push`, `curl … | sh`, `echo x > f`, `find . -delete`, `find . -exec rm
  {} \;`, `xargs rm < list`, `env FOO=1 rm x`, `sh -c 'rm x'`, `ls $(rm x)`,
  `` ls `rm x` ``, `sed -i …`, `git -c core.pager=sh status`, `git status;
  rm x`, `git status || rm x`, `git status & rm x`, `ls >| out`, `ls &>
  out`, a heredoc, `ls <(rm x)`, `timeout 5 rm x`, `nice rm x`, `sudo ls`,
  `FOO=1 ls`, `npx x`, `bunx y`, `pnpm dlx x`, `git status 2>&1 > f`, `ls |
  xargs rm`, `npm install -g x`, a newline-separated pair, `ls {a,b}`, `ls
  !(x)`, `npm run =ls`, `(ls)`, `{ ls; }`, `ls |& wc -l`, `! ls`, `time ls`,
  a mixed `&&` and `|` line).

### The port over each parser

`rules.ts` (~280 lines) ports `knownReversibleAutoCommand` and `plan`'s
rules over a parser-neutral form: a line is one `&&`-joined or `|`-joined
list of simple commands; each word carries its source text, its unquoted
and double-quoted source text, its value after quote removal, and whether
every part is a plain or quoted literal; each redirection its source text,
descriptor, operator and target. An adapter per parser (40–70 lines)
builds that form, or returns nothing for any node outside it (compound
commands, subshells, functions, `;`, background, negation, `time`, `|&`,
`||`, heredocs, assignments counted), which means review. The rules keep
fx's own character checks on the source text (`$ \` * ? [ ~ ^ # ; ( ) { }`)
on top of the parse, as fx keeps them on top of its lexer, and add two of
chord's own, both stricter than fx: any `\` reviews (fx admits `\&\&` as an
argument), and an unquoted word starting with `=` reviews (zsh's `EQUALS`
turns `=ls` into `/bin/ls`; chord runs `$SHELL -c`, `src/shell.ts:73`).

Results, the 218 cases under Bun 1.4.4 from source (`git` stages with
`safeGit: true`, i.e. as if `safe_git` were ported):

| Parser | As fx expects | Wrong |
| --- | --- | --- |
| `unbash` 6.0.4 | 218/218 | – |
| `sh-syntax` 0.8.3, zsh variant | 218/218 | first run 217: mvdan/sh keeps a terminating `;` only as a position (`ls ;` came out as plain `ls`); the adapter now reads that position |
| `sh-syntax` 0.8.3, bash variant | 218/218 | as above |
| `tree-sitter-bash` 0.25.1 | 218/218 | – |
| `shell-quote` 1.12.0 | 209/218 | **all four 0.0.16 bypasses admitted** (`\2>&1`, `<TAB>\2>&1`, `2 >&1`, `'2'>&1` lex to the same `"2", {op:">&"}, "1"`); `printf $'x'` and `printf x\ y` admitted; `printf 'unterminated` admitted (no error for an open quote); `printf 'hello\n'` and `printf '$(touch x)'` refused (no source text to tell quoted from unquoted) |

fx's near-miss list (`parity_probe_commands`, `command_effect.zig:2412-2449`,
inputs fx "may or may not" run without review) plus 30 more edge cases, run
through all five, differ between the three AST parsers in two places:

- `npm run é`: the `sh-syntax` adapter refuses non-ASCII, because mvdan/sh
  positions are byte offsets and the adapter does not map them. unbash and
  tree-sitter use UTF-16 offsets and admit, as fx does.
- `npm run 'build' 2>&1 && git status 2>&1`: tree-sitter-bash attaches the
  last `2>&1` to the whole `&&` list (`(redirected_statement body: (list …)
  redirect: …)`); bash attaches it to `git status`. The verdict is review,
  the safe side, but the tree is wrong.

What each parser leaves to chord's code:

- unbash: the word value after quote removal, globs, expansions and brace
  expansions as typed parts, redirection descriptor separate from the word
  before it (`\2>&1` is the word `\2` and a redirection with no
  descriptor). It drops comments; the adapter treats any non-blank text
  outside the one statement's range as one. It parses Bash: zsh-only
  syntax (`=cmd`, `extendedglob`'s `^` and `#`) is ordinary text to it,
  which the character checks catch (as they do for fx, whose lexer is no
  more zsh-aware).
- sh-syntax: literal parts keep their backslashes (no unescaped value);
  globs are plain text in the bash variant and in the zsh variant alike
  (mvdan/sh's zsh support does not model `EQUALS` or `extendedglob`); a
  Go runtime in Wasm; byte offsets.
- tree-sitter-bash: words are CST leaves with their raw text: quote
  removal, glob detection and backslashes are chord's code; the redirection
  attachment above.

### Under `bun build --compile`

A gate entry per parser runs the 218 cases and passes only on 218. Built
with `bun build --compile --target=bun-<target>` and run from an empty
directory: darwin-x64 under Rosetta, the Linux binaries in
`debian:bookworm-slim` containers of their architecture under OrbStack
(`orb start`, then `orb stop`).

| Parser | darwin-arm64 | darwin-x64 | linux-arm64 | linux-x64 | Embedding | Binary growth (darwin-arm64) |
| --- | --- | --- | --- | --- | --- | --- |
| `unbash` | passes | passes | passes | passes | nothing to embed: plain modules | +0.23 MB |
| `sh-syntax` | passes | – | – | – | `main.wasm` imported `with { type: 'file' }`, bytes given to the exported `getProcessorSync` (its `index.js` reads the Wasm from beside itself and fails in a binary) | +3.85 MB |
| `web-tree-sitter` + `tree-sitter-bash` | passes | – | – | – | both `.wasm` imported `with { type: 'file' }`, bytes given to `Parser.init({ wasmBinary })` and `Language.load` | +1.72 MB |

Load and first parse from source: unbash 8 ms, tree-sitter 13 ms, sh-syntax
26 ms. A whole 218-case run takes 7–8 ms for unbash and tree-sitter (well
under 0.1 ms per command).

## 5. Library and port

- **Library: `unbash`** parses the command line: quoting, escapes, words,
  operators, redirections with their descriptors, expansions and globs as
  typed parts, parse errors.
- **Port of fx (Apache-2.0, attributed to `vercel-labs/fx` `v0.0.16`
  `src/core/shell_command/command_effect.zig`, with "changed by chord")**:
  which shape of line is accepted (one `&&` list or one pipe of ≤ 8, the
  trailing bare `2>&1`), the character checks, the command and flag lists
  of §1, the git fetch option and remote-helper rules, the size limits. In
  the trial it is one pure module of ~280 lines plus a ~70-line unbash
  adapter; in chord, one pure module under the built-in agent's folder with
  its test at the mirrored path, the corpus as its table.
- **Port or design, depending on Q2**: how an admitted command runs (fx's
  direct executor and `safe_git`), and what replaces fx's alias and function
  check.

## 6. Recommendation and owner questions

Recommended: `unbash` 6.0.4 (caret range: it is past 1.0) as the parser,
with chord's port of fx's rules on top. It is the only candidate that
reads the bypass cases correctly with no Wasm, no runtime to start and no
work around it: positions, descriptors and quote removal are its own
documented output. It passes the corpus on all four targets and adds
0.23 MB. `shell-quote` is out: it cannot tell `2>&1` from `\2>&1` or `2
>&1`, fx's latest bypass. tree-sitter-bash misplaces a redirection after
`&&` and leaves quote removal to chord; `sh-syntax` adds 3.8 MB of Go Wasm
and keeps escapes raw.

The library fits as it is. The questions are about what the owner's A6 (b)
admits and how it runs, not about the library:

**Q1. Which of fx's lists does "reversible read-only" mean?**
- a. fx's direct read-only set only (§1, the first table): `printf`,
  `pwd`, `ls`, and `wc`/`cat`/`head`/`tail`/`grep` filtering a pipe, `git
  status`/`diff`/`log` with the listed flags. Only reads.
- b. a, plus the read-only part of the reversible list: `node -v`, `which`,
  `git status` with any arguments, `git remote -v`, `git worktree list`.
- c. Both of fx's lists as fx has them: b plus `npm`/`bun`/`pnpm`/`yarn`
  `install`, `test`, `run`, `zig build`, `git fetch`. These run the
  project's own code (scripts, lifecycle hooks, `build.zig`) and reach the
  network: reversible, not read-only.

**Q2. How does an admitted command run?** fx proves the direct set
read-only partly by running it without a shell. chord's shell tool runs
`$SHELL -c` (`src/shell.ts:73`): zsh reads `~/.zshenv` there, so an alias,
function, option such as `extendedglob`, or a `PATH` entry can make the
text do something else than what was classified, and plain `git status`
starts the repository's `core.fsmonitor` program.
- a. Port fx's direct executor for admitted commands: spawn each stage's
  argv with fx's fixed executables, `PATH=/usr/bin:/bin`, `C` locale, its
  own process group, piped, 64 KiB cap; git through a port of `safe_git`
  (trusted git path, version check, `-c` overrides, filter names read from
  the repository's config, same-repository check). The most code; the only
  option that keeps fx's guarantee. With Q1 b or c, the reversible list
  still runs through the shell, as in fx.
- b. As a, without `safe_git`: git stages are not admitted (reviewed);
  `ls`, `pwd`, `printf` and the filters are.
- c. Run admitted commands through `$SHELL -c` like any other call and
  accept the alias, function, option and `PATH` exposure, and repository git
  config. fx itself refuses this for aliases and functions it can see
  (CHANGELOG 0.0.13); chord cannot see them without capturing the shell's
  definitions first, which is more of fx to port.

Whichever is chosen, the bypass table goes in as tests, every case outside
the subset is reviewed, and a parse error is reviewed.

## 7. Not checked

- fx's own binary was not run on the corpus: fx's verdicts come from its
  tests, and for the 70 ordinary commands from reading its rules.
- fx's shell-parity harness (`command_effect.zig:1987-2534`, which runs
  admitted forms under sh, dash, bash and zsh and compares argv) was not
  reproduced for chord's port.
- `sh-syntax` and tree-sitter were compiled for darwin-arm64 only.
- How `safe_git`'s `indexer.repoFilters` reads repository config (includes,
  worktrees) was not traced; Q2 a would need it.
