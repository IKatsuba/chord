# Dialog live look

Handed over 0acbc9f, including example/dialog.dart and its reached tests.
Ran `dart run example/dialog.dart` in owned tmux sessions at 120x40 and
80x24, dark fallback with NO_COLOR unset, light via COLORFGBG=0;15, and
plain via NO_COLOR=1. All owned sessions removed. These are framework
fixture captures, not a completed port permission screen or its acceptance.

The full-width rounded frame, bold focus title, body, choices and source
hint wording read clearly at both sizes. The prompt gap and prompt stay
uncovered. ANSI confirms the focused border/title roles change between
light and dark; plain uses bold and no colour. Choice numbers and marker
remain visible in plain mode. No match-position decoration is introduced.

At 120x40, Up wraps the first highlight to Reject; Enter visibly records
Answer: rejected, closes the layer and restores the base's open/quit hints.
Ctrl+o reopens at 80x24. At 80x14 the body retains its top lines and a dim
count of two hidden rows. At 80x10 body and its gap give way while title,
both choices and hint remain. At 80x7 only Allow once is painted; pressing
2 does nothing, and restoring 80x10 confirms the same open Dialog. Escape
closes and returns focus/hints. Text and ANSI captures preserve these states.

No visual finding. The developer's first-frame scheduling note is retained:
the fixture requests its initial entry after layout and settles focus on
the next app frame. Designer judged the settled running screen. The widget
and fixture can proceed to reviewer; broad tests remain tester's work.

## Changed-screen re-look: 32b1392 + 30c74f1

Ran the same live fixture at 12x24: `Allow c…` remains on one title row.
The lead, relayed by reviewer, explicitly accepted live ASCII truncation
plus the focused `Allow 日本語 command?` screen assertion at 16x9 for the
wide-grapheme edge. Ran `dart test test/widgets/dialog_test.dart -n 'long title ends'`:
1 pass, expecting `│ Allow 日本…  │` and body on the following row. No claim
that the example displayed a wide-title variant live.

At 80x5 and 80x4 the layer has two/one rows above the protected prompt.
Both live screens paint no Dialog, expose only the base open/quit hints,
and keep Answer: none yet. Pressing 2 while hidden, then restoring 80x24,
keeps the answer unchanged and restores the focused dialog. Captures use
dialog-fixed-* names. No changed-screen finding. All owned sessions removed.
Reviewer's separate unlinked empty-size branch fix 8cf5cc0 was source-cleared
by reviewer; this entry does not claim a live example of that branch.
