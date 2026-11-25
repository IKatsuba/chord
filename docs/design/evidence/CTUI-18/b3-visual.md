# B3 live permission integration: visual acceptance

Base window handover: `3b6ff60`, with corrected B2 `e889f76`.
B3a final integration fix: `107bc05` (after `056c817`).
B3b held-permission status notice: `d060e26`.

## Method

Ran `dart run example/chord/tool/dev.dart chord --fake` beside the
original's `bun dev chord --fake --qa` in owned tmux sessions. Submitted
scenario text with literal send-keys and Enter separately. Compared
permission, bigask, twins, permissionmeta and reviewpermission at 80x24
and 120x40. Also drove bigaskleft to check held requests, unsent drafts
and attention. Captures include text, ANSI attributes and side-by-side
pairs. The port's private working-directory display alone is replaced
with `<repository>`; its CLI has no directory flag. Original QA uses a
neutral directory. Timers were not synchronized or normalized.

## Observed

- The ordinary permission box matches title, proposed diff, question,
  numbered choices and hint at both sizes. Arrow/Enter selection works.
- bigask scrolls request content above pinned title, question and answers.
  The complete options remain visible at 80x24. PageDown changes only the
  request, with truthful above/below counts for its available rows.
- twins retains both allow-once options. Literal 2 returns `allow-here`
  in both apps, matching the intended distinct option.
- permissionmeta presents the same fallback title and sole Deny choice.
  Esc rejects it without leaving a stale box.
- reviewpermission keeps review reason and all choices visible at both
  sizes. Its deadline hint matches. Arbitrary typing does not enter the
  prompt while the request owns focus.
- bigaskleft shows `main asks · between turns`, unmarked/inactive choices
  and the attend hint. The prompt can hold `kept draft` while held.
  ctrl+x a activates choices without changing the draft. Esc rejects;
  typing ` restored` then yields the same `kept draft restored` in both
  prompts, proving editing focus returned.

## Findings resolved

The initial reviewed tool had an extra indented Waiting row. B3a's first
attempt `056c817` still showed it in a fresh live run at both sizes
(`review-fixed` captures record that failed attempt, not a pass).
Developer then supplied `107bc05`, wiring the actual Transcript Tool.
Fresh `review-final` captures at both sizes show only Reviewed: caution,
as the original does. Fresh `ordinary-final` captures prove ordinary
permission still shows Waiting. B3a passes on `107bc05`.

The initial held flow omitted the original status notice. B3b `d060e26`
now matches exactly: at 80 columns, `● permission · ctrl+x a to answer`;
at 120 and 160 columns, `● permission asked between turns · ctrl+x a to
answer`. The short version is chosen before further compression of the
model facts. Attending removes the notice and restores the ordinary
facts row. The draft still survives and regains focus after rejection.
B3b passes. The initial held captures remain as historical evidence;
`notice-final` and `notice-attended-final` are the corrected states.

## Accepted differences and limits

The lead explicitly accepted the existing pinned interim top line.
Unlike the original's scrolling Header, it consumes one request row in
bigask/bigaskleft at 80x24, so hidden counts and page movement differ by
the resulting row budget. The scrolling Header belongs to M3 and is out
of this slice. The existing missing shortcuts question-mark hint likewise
remains deferred. Version and directory displays differ by construction.
These differences do not hide the reason, choices or answer hint.

No chromatic warning/waits hue parity is claimed: this run's captures
rendered without chromatic colours, though ANSI captures preserve the
observed attributes. Deadline expiry, all queued/race scenarios and
protocol lifecycle are reviewer/tester work; no suite was run by designer.

## Result and cleanup

Pass for B3 + B3a + B3b on their final handed commits, with the accepted
header difference and limits above. All owned tmux sessions were closed
through app quit keys; original quit presses were sent within its timing
window. No owned fake-agent, dev runner or app process remained.
