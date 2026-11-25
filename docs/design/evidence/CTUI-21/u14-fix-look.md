# U14 pending-status fix visual pass

Fix37a3c75 passes the isolated designer recheck, resolving u14-finding.md.
Exact commit export excluded WIP; command `dart run example/chord/tool/
dev.dart chord --fake`, with CHORD_SOURCE selecting ../chord.

At120x40 and80x24, Ctrl+X shows exactly:
`ctrl+x …  a the one that waits · esc never mind`
No model/effort/context facts remain. At80, Esc clears the chord but keeps
help open; ordinary help hint and facts return. A new chord left beyond
three seconds also restores them. Empty Ctrl+D exits. Both required-size
pending captures, cancellation and expiry are saved with ANSI counterparts.

The paired original baseline includes b/code-block wording; main approved
removing only that clause for M1. The fix is checked against that settled
line, not claimed byte-identical to the full original. Prior 40x12 overflow
and permission overlap passes remain in u14-finding.md. No tests, audit,
whole suite or AOT repeated. Owned session closed and export removed.
