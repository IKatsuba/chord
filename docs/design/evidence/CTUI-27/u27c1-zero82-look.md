# C1 zero-area guard: separate designer handback

Exact fix: `82b23eb`, following the named tester finding on `334f998` + `e52e5f0`. Scope is the existing terminal rows/columns guard in app keys/Window; no painted-editor visibility requirement or geometry API. This handback does not extend C2 clearance.

An immutable exact-82 fixture was used. Normal Tab at 120×40 takes the first queued row. With that row still pending, resize to positive 8×3 and Tab the second row, then restore 80×24 and accept the first: the second becomes `into the running turn: second tiny`, proving the tiny-size dispatch was not lost. Its draft remains `draft kept`. Accept the second, queue a third and Tab at 80×24: the normal pending label remains correct. Final 120×40 capture shows all three accepted once and the draft unchanged. No painted prompt visibility restriction was added by this fix.

Tmux cannot create a 0×0 or zero-axis window. Designer made no live claim for those unrenderable dimensions and ran no headless tests. Tester’s named exact-82 handoff independently reports 147 reached tests, clean statics and positive-size live coverage; it owns the actual zero-area/zero-axis rejection proof. Developer’s retained red log from the prior exact C1 source is copied byte-for-byte here, with a hash in the manifest, as developer evidence rather than a designer reproduction.

The prior C1 screen gate, both fixture-help finding/fix rounds, and retained narrow Working-line limit remain separately scoped in `u27c1-look.md`. No original comparison is manufactured for impossible zero-area terminal geometry. All owned fixture processes/tmux, exact archive and temporary roots were cleaned up; no original source was edited. Source review/combined-head testing remain separate.

The raw developer red log intentionally retains its formatter’s whitespace-only lines. It is excluded from whitespace cleanup so its byte-exact hash/provenance stays intact; all other evidence passes the normal whitespace check apart from terminal blank rows at EOF.
