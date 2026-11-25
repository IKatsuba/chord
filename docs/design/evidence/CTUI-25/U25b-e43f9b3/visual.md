# U25b keyboard/help repairs: designer pass

Generic source/control implementation: `6bf37fa168492d4dd63891ff794a0179ba1eb3cf`.
Theme fixture: `fd4a106`; run-only key fixture/test: `f445681`;
final two-row help fixture/test: `e43f9b3`.
This resolves the reviewer key gap and designer help truncation finding.

Live exact e43f9b3 source ran from a separate immutable ignored-build snapshot:

```sh
env -u NO_COLOR dart run example/markdown_run_controls.dart
```

At120x40 and80x24 the two help rows show all six actual registered chords and
full descriptions, with no clipping: Quit, Record run action, Record run-only
action, Record copy action, Toggle picked frame and Toggle narrow controls.
The example's whole scene has room for this help. Shift+R records Run only:
run only at both sizes. At80x24 r records Run: x and c records Copy: x;
Shift+R afterward records the separate run-only descriptor again. No action
requires a pointer and no clipboard write, execution or model turn occurs.

Earlier dark/light/plain styling,25-to24 narrow omission, current run/copy
callbacks and quoted/open-fence appearance proof remain under U25b-6bf37fa.
The earlier incomplete keyboard/help acceptance is superseded by this final
live repair check; failure evidence remains under U25b-f445681. The framework
itself still binds no run key. No API or control geometry changed in these
fixture repairs, and no new production finding remains from this look.

Owned120x40 session resized80x24, literal keys, TXT+ANSI captures. No compile
or heavy test run was used; no current-tree WIP ran. Pinned dependencies were
resolved offline. The session/process exited and the immutable snapshot was
removed. Raw trailing blank rows are retained as part of the window capture.
Pass U25b plus its handed fixture/test repairs back to reviewer, not tester.
