# U12 failed-prompt visual look

Developer acceptance commit d3c96be adds tests only; runtime source is
4e3bafb, unchanged by U12. Original 577b58167 in the matching live fake
window; command and session provenance are in u11-look.md.

Pass geometry/wording at120x40 and80x24: error prompt produces one blank
spacer, one inset-1 marker and exact message after the reply. No Error:
prefix, frame or crash screen. At20x40 both wrap the error identically,
continuations under the message. Clearing an abc draft with Ctrl+C and
sending text leaves the error in history and produces a normal reply.
See u12-error/wrap/recovered pairs and side-by-side comparisons.

Live foreground color remains unmeasured: both windows rendered the error
without a foreground color in this environment. ANSI captures preserve that
fact. Developer reports dark/light/plain widget test coverage in d3c96be;
that report is not a live red-style claim. Reviewer/tester can assess it.
No extra tests or source changes. Owned panes were closed after U13 check.
