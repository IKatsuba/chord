# U6 designer look: ListView.builder

Implementation handed over: `64f15e6`, with test lint fix `c68574f`.

Observed through the headless tester at 120x40 and 80x24. The frames in
`tester-captures.txt` add a border around the actual cells; that border is
capture formatting, not list chrome. Ten selected cases passed.

```sh
SHOW_SCREENS=1 dart test test/widgets/list_view_test.dart -n 'following the bottom|pageup, 200 appends|changing height|resize while scrolled back|cut at both edges' --reporter expanded
```

## Findings

No visual blockers in the handed-over cases:

- Following 10 000 one-row items fills the view and ends at item 9999:
  item 9960 starts the 40-row view, item 9976 the 24-row view.
- After paging up and appending 200 items, the scrolled-back view remains
  on its earlier rows. The fixture overlay occupies the last row and
  shows 238 below at 120x40 and 222 below at 80x24.
- Growing an item above the view leaves item 100 at its top.
- Resizing a scrolled-back list keeps item 150 at the top; wrapping is
  clean at both final widths.
- A tall item clipped at both edges shows consecutive rows 10 through
  49 at 120x40, and 10 through 33 at 80x24, with no leaked adjacent item.

This matches the settled design's following, anchor and clipping shapes,
and interface draft section 3's content behavior. The framework draws
items only. The fixture's `-- N below --` is an overlay for checking the
same-frame controller geometry; it does not implement the port's rule,
wording, covered-row count or colours. No original port screen comparison
is required for this framework unit.

Scope: a visual look at these five scenarios at both sizes, not a code
review or the full acceptance matrix. Keys and the live demo belong to U7.
No tmux session was started for U6, per the tester-output handover.
