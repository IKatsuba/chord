# Bounded C1 fixture-help layout

Lead-approved final fixture-only contract, settled with developer before edits. Reuse existing FocusScope, ListView, scrollBindings and KeyHelp; no product Window/catalog or framework API change.

At 32×10, a borderless, full-width opaque surface owns every cell (including blank fill), with one horizontal inset and no vertical padding:

```text
 Fixture controls
 ctrl+q Quit fixture
 f1     Close controls
 f2     Accept pending steer
 f3     Refuse pending steer
 f4     Finish current prompt
 f5     Toggle open call
 f6     Ask permission
 f7     Emit late text
 F1 close · ↑↓ scroll
```

The same title/list/footer shape applies at 120×40 and 80×24. The list uses remaining height; its unused cells are opaque blank, and the footer stays at the terminal bottom. Each compact control uses one row, end-cutting description text instead of wrapping. The F1 close hint stays at the beginning of the footer. This avoids the prior truncated title, unreachable F4–F7 and exposed underlying logo/prompt fragments.

At 32×6, title/footer remain fixed while the existing ListView scrolls through all controls; verify the last control remains reachable. Height two draws title/footer with no list body; height one draws only the close footer. At 0×0 there is no paint or scrolling/fake-control activation and no deferred action. F1 dismissal and Ctrl+Q quitting remain safe escape actions; underlying editor and fake-agent controls must not receive help-owned typing, paste or Enter. Reset list scroll on each opening; close restores the existing prompt focus/cursor/draft and byte-identical normal frame at both required sizes.

This is the final bounded fixture follow-up after the retained 780a52c narrow failure. Any remaining finding is escalated to the lead rather than growing another fixture redesign. This paper contract is not a runtime pass.
