# U52b: failed-start prompt and seeded resume flow

Handed implementation: signed `61d012cf319bd3fee9d533fc9c04a818546ea6d5`.
The command/prompt/intro composition and reached lifecycle pass the designer
look, with original-fidelity follow-ups below still open. This is not full
CTUI-52 parity/readiness clearance. No code audit or test execution by designer.

Port-only Transcript.intro is documented nonselectable opening furniture
after the header, outside recorded entries. Its shape fits the design: no
fake persisted ErrorEntry or generic framework API, compact header identity
retained. The failure scrolls as ordinary excluded intro content; the prompt,
status and overlay anchor remain in their normal places.

## Actual original/port pair

Original head `577b58167672e12c999aeaf4eed2a1a988513dc2`.
Both source launchers use original fake `CHORD_FAKE_START_FAILS=alias`,
separate isolated XDG state/config and the task checkout as cwd. Original
uses its Bun production define with explicit fake command; port uses
bin/chord.dart. No original file was changed, no real agent/model used.

Seed 18 compact type-first version-1 JSONL records, deterministic UUIDs 1..18,
agent fake, one prompt/turn-1/images 0 each, times 1..18 hours before setup.
Indices divisible by 3 belong to one synthetic other directory; the rest to
current cwd. Titles are `Saved failure recovery session <i> · 界😀 with a descriptive title for wrapping`.
Local has 12 choices; all 18. Synthetic directory labels are sanitized only
after capture, without changing original line breaks.

At 120x40 and 80x24 the failure follows the compact header; ordinary prompt
and bottom hint remain available. Literal ordinary draft + separate Enter
stays unsent in both, retaining its text. Clear, literal `/resume`, then
separate Enter opens matching local rows. Ctrl+A all scope matches frame,
metadata/title wrapping, number/edge gutters, hidden counts and hints.
Scope back then Esc closes without clearing the failure/prompt or starting
a session. Reopen `/resume` and Enter first local choice: both successfully
load the saved session, remove the failure, show history and a normal prompt.
This replacement was observed at 80x24 and120x40.

`u52b-comparison-*` puts original/port beside each other; individual text
and ANSI captures remain the source evidence. Original 0.71.0 versus port 0.0.1
and the staged compact-header `/help` clause remain established differences.

## Open original-fidelity follow-ups

The original initial failure prefixes the alias refusal with
`it refused session/new: `; port `61d012c` omits it. It changes wrapping at
both sizes. Main explicitly selected separate U52c for step-aware wording;
design addendum `1ea382d` specifies precedence. Preserve these failure captures;
this is not an accepted wording difference or an intro/cache regression.

After successful replacement at 80x24, original fallback prompt title uses
middle CUT (`Saved fail...h a descriptive title for wrapping`), while the
port truncates at the end. At 120x40 the full title fits/matches. Lead requires
a narrow existing-policy repair while preserving true agent-title wrapping
and header/source identity. Keep the resumed pair as pre-fix evidence.

The port agent-free empty-resume report visibly has one extra space after
`⎿` compared with the retained original empty-resume reference from initial
design. This is an observation, not component/caller attribution; lead asked
for exact original-component diagnosis before any narrow repair. Do not
silently accept it or expand to a broad Note rewrite. Later exact fix pairs
must establish final wording/header/report parity.

## Agent-free scroll/theme and fixture correction

Handed `tool/failed_start.dart --plain` inspected at 120x40/80x24. `/resume`
reports the empty-state sentence, `/help` opens the actual staged shortcuts,
and Esc closes it. This has no record IO or agent process.

Initial `--tall --light` supplies newline-separated synthetic input; existing
printable sanitation turns those controls into U+FFFD, so continuation text
appears beside the next sentence. That is not clipped data or a newly
introduced production geometry bug. Home reveals the compact header and
first failure words; End returns to the full tail while prompt/status stay
fixed. Raw pre-fix fixture captures are retained.

Developer's fixture-only signed `bb3a6d25cabe28521ea1a927379ed9a6e32da4d0`
changes separators to spaces; production sanitizer is unchanged. Because
concurrent U52c source existed, designer ran that exact handed commit from
a source archive under build, redirecting only self-package config roots
and reusing resolved external packages, with no pub get/source edits.
The corrected tall/light fixture is legible at 120x40/80x24; Home reveals
the header/first words and End returns byte-identically (text/ANSI) to its
initial 80x24 tail. This fixture-only finding passes its handback. No live
error-wording U52c result is inferred.

## Cleanup and limits

All live windows exited cooperatively (Ctrl+D); fixtures with Ctrl+Q.
Owned tmux servers ended; no relevant Dart/Bun/fake process remained.
Owned synthetic XDG roots and exact fixture archive were removed. No private
paths remain in retained captures. Sanitized labels shorten cells without
relayout and are not width oracles. Narrow/zero-room and later failure
precedence remain final exact-fix gates; current report covers only the
observed flow. No AOT/display/physical terminal or real-model claim.

Raw pane captures preserve terminal trailing blank rows; derived side-by-side
comparisons trim row-end padding. The scoped whitespace check excludes only
blank-at-EOF for those terminal rows.
