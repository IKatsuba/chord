# CTUI-2 primitive API and screen assertions

The lead explicitly authorized API/design and headless screen assertion
checks for public-widget units before their runnable fixture is ready.
This is not the fixture's live tmux acceptance or a code audit.

Handed-over units: Positioned 02d8090; Overlay entries 099d0e2;
anchored followers a5b53ad with fix a5de657.

The public constructors match CTUI-2's call sites: Positioned's six cell
parameters, Overlay entries and insertion, target/link and follower anchors.
The lead approved follower-at-entry-root/zero-offset-wrapper restriction is
explicit in the design and has a rejecting test. The skipped-layout test
checks disappearance and return without accepting a stale anchor rectangle.

Read the tests' rendered-row assertions and ran just these three files:
`dart test test/widgets/positioned_test.dart test/widgets/overlay_test.dart test/widgets/overlay_follower_test.dart`.
All 40 tests passed. At 120x40 and 80x24 these cover the bottom-positioned
bar, layer paint order, same-frame four-row picker over the transcript, and
a tall picker bounded to 36/20 rows without painting the prompt's four rows.
Further assertions cover opaque blank cells, moving and missing anchors,
virtualised targets, nested overlays, out-of-place follower rejection,
negative offsets and wide graphemes. No API or screen-assertion finding.

The first invocation was stopped by the Dart wrapper's SDK-cache sandbox
restriction before tests loaded; the authorized rerun completed normally.
Developer's broader test/static-check evidence remains in the handover.
Focus is the next unit; the live look at both sizes and all themes remains
unit 4's fixture gate. No original port screen has been implemented here.

## Unit 3: focused entries

Handed over c2d6ed6. FocusScope(node:, autofocus:, child:) and the scope
node read as specified. Reviewed only the handed-over API and its screen
assertions, then ran `dart test test/widgets/overlay_focus_test.dart`:
13 tests passed. At both 120x40 and 80x24, the layer visibly focuses X,
Tab stays in X/Y, closing visibly returns to the previous B field, and
the enabled shortcut descriptions include Next field, Previous field and
Quit while excluding the base-only action. Further assertions cover passive
layers keeping the base's keys, missing/zero-room suspension, relink,
detached return targets, no fallback, nested/out-of-order close and chord
reset. No design-look finding. The fixture still supplies live captures.
