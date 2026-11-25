# U54c2 cap follow-up screen recheck

Exact handed source: signed `c784f3d` (resume capped frame sizing only).
Designer screen PASS to reviewer. No source audit, test execution or
performance certification is claimed. The arithmetic proof/counters remain
reviewer/tester gates; the pre-3N AOT evidence stays untouched.

`git diff --quiet c784f3d -- lib example/chord/lib
example/chord/tool/resume.dart example/chord/pubspec.yaml
example/chord/pubspec.lock` confirmed running source/dependencies matched
the handed fix. No unhanded WIP was inspected. Ran owned live instances of
`dart run example/chord/tool/resume.dart` with --many, --many --tall --light,
--many --zero --plain, and --many --empty --light. Colour runs explicitly
remove inherited NO_COLOR. All run at120x40 and then80x24.

The 16 initial text/ANSI comparisons (four states, two sizes, two formats)
are byte-identical to the retained79dc587 fixture gate. There is no visible
change in frames, metadata/title shaping, body rows, hidden counts, hints
or theme styling. Local/all were inspected at both sizes. Ctrl+A all-scope
80x24, tall Down scrolling80x24, zero-room Enter/Down/digit1, empty-to-all
scope plus Enter acceptance, and local threshold41/42 text/ANSI also match
the prior gate exactly. At120x40 all-scope metadata/title hang correctly.

Retained files are `u54c2-cap-c784f3d-*`. The prior gate's paired original
local/all120x40/80x24 and32x10 references remain in `u54c2-comparison-*`;
this follow-up uses identical frozen fixture comparisons, not a new seeded
original run. The accepted original32x10 hint-over-border slip remains
unchanged in disposition (decision c1fb6c8); no new original defect or source
regression is inferred.

All four owned fixtures exited cooperatively with Ctrl+Q. Owned tmux server
ended and no resume-fixture Dart process remained. No fake/model/state root
was used in this follow-up. Designer honored developer's numeric quiet and
resumed only after release. New post-cap AOT evidence8d3cc83 is separate and
awaits reviewer/tester validation before any designer performance summary.
