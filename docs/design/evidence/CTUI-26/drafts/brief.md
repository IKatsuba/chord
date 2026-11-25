# CTUI-26: saved sessions and resume — architecture brief

## Problem and visible result

Persist a single main session in the chord port and reopen it through
`--continue`, `--resume` and `/resume`, including the resume page. Preserve
what the original shows, the keys it accepts and the ACP load/resume behavior.
The original is the specification: `../chord/src/session/record.ts`,
`replay.ts`, `sessions.ts`, `session.ts`, `conversation.ts`, the resume page,
`src/ui/pickers/`, `docs/guide.md` and record designs under `docs/design/`.

A person can leave a prompted session, reopen its history and continue with
the same agent session id. Discovery, filtering, unknown ids, failed loads,
unsupported capabilities and cross-directory selection follow the original.
New sessions remain the normal launch path. Record logic is plain Dart
reached by tests; the interface composes existing terminal widgets.

## Constraints

- Design only; no changes under `lib/`, `test/` or `example/`.
- All work is in the supplied CTUI-26 worktree on branch CTUI-26 from main.
  Never work in the main checkout, never edit the original, never switch
  branches, and never commit independently. The lead signs the final commit.
- Read AGENTS.md, README.md, docs/FEATURES.md, docs/decisions.md and relevant
  existing designs. CTUI-15's session/conversation/reducer and record seam,
  the current transcript, start page, slash dispatcher and Picker are the base.
- Prefer version-1 records in the original's XDG state directory so either
  program can resume the other's main sessions where practical. State exact
  compatibility and concurrency limits.
- Maintained packages precede new non-terminal infrastructure. Trial a
  proposed package with AOT evidence; a misfit goes to the owner with options,
  never an unapproved workaround. SDK use/existing adapters must be explicit.
- Every action has an Actions binding, description and shortcuts coverage.
  Screen evidence at 120x40 and 80x24, narrow edges and relevant themes.
  Distinguish observed captures from proposals and unimplemented port states.
- English only; no private paths or private data in artifacts.

## Non-goals and seams

Children, teams and monitors on resume belong to M4/M5. Do not revive their
runtime or invent their semantics. Identify opaque preservation needed for
safe interchange and how unsupported history is handled. Fork, headless,
compaction and other later features need owner authorization to come forward.

## Draft ownership and questions

Each architect writes only their own draft here. Request evidence additions
outside it through the lead. No commits.

- **framework.md:** Does a general file-backed store or atomic-write service
  belong in lib/? Which existing primitives suffice? Define any minimal
  prerequisite, package trial and gate. Avoid exporting chord policy.
- **interface.md:** Original flags, resume page, /resume, states, keys,
  wording, filtering, directory scope and failures. Capture original/current
  port at required sizes; request evidence additions through lead. Supply
  concrete Dart call site and buildable units using current widgets.
- **runtime.md:** Record schema subset/unknown preservation, event ordering,
  streaming writes, flush/close/crash failures, original/port concurrency and
  locking. ACP load versus resume, record versus agent history, interruption
  and session swap. Tests against the original fake and compiled executable.

## Deliverable and owner boundary

After critic review the lead writes docs/design/CTUI-26.md in buildable units
and append-only decisions entries. Changes of scope, original behavior and
package misfits go to main with few, short options and a recommendation.
They remain OPEN until answered.

## Owner answers during investigation

Main approved these boundaries before final synthesis:

1. Match the original's per-process serial appends with no cross-process
   lock; document its parallel-open/interleaving limit.
2. Preserve all existing record lines when appending. Replay supported
   history only and never revive children, teams or monitors. Emit one
   window-only plain line when saved content is omitted:
   `Some saved history is not shown in this version.` No fitting generic
   original notice exists; specific child/monitor notices would misdescribe it.
3. Use xdg_directories with HOME or XDG_STATE_HOME required. If neither
   supplies a directory, report a clear error. The original's OS-account
   home fallback without HOME is an accepted narrow difference.
4. args cannot express the original optional resume argument and accepts
   repeats differently. A bounded token adapter for -r/--resume alone is
   approved before args, with original-oracle cases; no CLI migration.
5. args 2.7.0 and timeago 3.7.1 were tried under AOT. Main approved a
   bounded port of the original lastUsed's six fixed English units and
   numeric:auto labels after the relative-time package misfit; fixtures
   retain actual Bun oracle boundary outputs. intl has no relative formatter;
   intl4x's existing native build-hook failure remains in CTUI-23 evidence.
