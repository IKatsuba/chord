# U52d: report columns and compact header CUT

Handed initial repair: signed `ef1d313fecb285a9f983f605499719d263c41f72`.
Handed narrow-header follow-up: signed `162f512aa3d1a7fbab783fbb20ea145a1091dfa6`.
Both presentation findings pass the designer live handback to reviewer.
No code audit, headless execution or whole-CTUI-52 readiness claim is made.
The separately observed cancel-focus finding and its U52e fix remain
independent evidence/gates, not silently covered by this report.

## Exact original/port flow

Original head `577b581`; isolated original-fake windows and XDG roots only.
At ef1d313, source was archived under build with self-package config roots
redirected, avoiding concurrent source. Both apps initially failed with the
original fake alias refusal, using the same task cwd and empty record stores.
Literal `/resume`, then separate Enter produced the same original empty
sentence at 120x40 and 80x24. The body now starts after `⎿` in the exact same
column. This resolves the one-extra-space observation; labelled reports and
other Note/Outcome/Under presentations were not changed or broadly audited.

Seed one compact type-first version 1 record in each isolated store: UUID2,
agent fake, current cwd, timestamp two hours before setup; one prompt/turn-1/
images 0 containing `Saved failure recovery session 1 · 界😀 with a descriptive title for wrapping`.
Type `/resume` again, Enter, then Enter on the local record. Both load it,
remove the startup failure and show the saved history with a usable prompt.
At 120x40 the complete resumed fallback title fits and matches. At 80x24 both
now show `Saved fail...h a descriptive title for wrapping` in the same header
row. Prior end-ellipsis failure remains preserved in u52b evidence.

Home at 32x10 initially exposed another instance of the settled header CUT
contract: original agent/model row middle-cut, port end-ellipsis. Lead
explicitly authorized all nonwrapped CompactHeader rows and matching lazy
source to use existing middle CUT; no generic Text wrapping change.
The pre-fix 32 pair is retained as u52d-*-resumed-home-32x10.

## Final 162f512 follow-up

Before launch, git diff --quiet confirmed shared framework/port source,
launcher and pinned dependencies equal handed `162f512`; source was idle by
lead coordination. No unhanded source ran. Using the same long fallback
record with the original fake and fresh isolated roots, launched saved resume
at 32x10. Home now shows the same `fake · Fak...ext window` agent/model row.
One Shift+Down reveals the resumed row; both show `resumed · ...r wrapping`.
Both keep the same Below rule and usable prompt.

Rechecked 80x24 and 120x40 after resizing/Home: agent/model and fallback title
still match the original; full title fits at 120 and middle CUT retains its
end at 80. `u52d-final162-*` text/ANSI and side-by-side captures retain these
observations. Earlier ef1d313 report-column proof remains valid because this
follow-up changes only nonwrapped header rows and their source projection.
Genuine titled-header wrapping and logical source identity are reached
headless-test obligations reported by developer, not extra live cases
manufactured here. No new key, API, package or global rendering policy.

## Limits and cleanup

Established version 0.71.0/0.0.1 and staged header `/help` differences remain.
Startup token-break behavior is the separately documented existing plain-Text
wrapping difference, not a header CUT exception. Required-size fixed prompt/
status geometry and source text remain intact. No cell-identical claim is
made for independently accepted render policies outside these repaired rows.

All paired windows quit cooperatively. Owned tmux servers ended and no
relevant Dart/Bun/fake process remained. All owned state/config roots and
initial exact source archive were removed. Captures replace complete
synthetic cwd labels with fixture-project after capture; no private path
is retained. Such shortening does not relayout cells and is not a width
oracle. Raw terminal blank rows at EOF are preserved. No AOT, physical
terminal, clipboard or whole-heap measurement was performed by designer.
