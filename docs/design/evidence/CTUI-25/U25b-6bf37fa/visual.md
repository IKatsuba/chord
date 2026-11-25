# U25b public-widget designer pass

Implementation: `6bf37fa168492d4dd63891ff794a0179ba1eb3cf`.
Explicit-theme fixture followup: `fd4a106cc6a574e974f426ac72eedb9dc01d565d`,
only the demo launch/theme flags.
Design: CTUI-25, including const-boundary clarification `e66629a`.
This gate covers API shape and live widget appearance, not implementation audit.

## Result

Pass to reviewer. Generic source/callback API reads coherently: an explicit
application language set and descriptor callback, no framework shell default,
transformation or execution. Existing const ordinary Markdown is retained,
with source-derivation capture, while bound sources keep immutable geometry.
Public source/constructor signatures were checked against the design; reviewer
and tester own implementation validation and mutation/exception regressions.

At120x40 and80x24 the custom-language short box grows to25 columns for both
buttons. Toggling its available width to24 omits run first and retains copy.
Keyboard r still records Run: x in that narrow state. The separate run-only
box remains clear. Quoted and open-fence blocks show no controls. Default
KeyHelp truncation was initially misread as wrapping.
That help/reachability acceptance is superseded by the reviewer finding
and U25b-f445681 designer report; its later fixture repair must pass first.

Same-cell down/up on the ordinary run control records Run: x; run-only records
Run only: run only. No clipboard, process or model is invoked. Recording uses
the current full descriptor text. Failure/race/occlusion/revision transitions
are left to the reached automated tests and reviewer; this live look does not
claim an exhaustive pointer or offscreen audit.

Picked frame/label/buttons are accent, buttons bold: dark RGB71,231,165,
light RGB20,125,85. Unpicked controls use text foreground on the dim frame.
Plain picked controls are foreground/bold with no colour. Text and ANSI pairs
retain exact cells, including the original trailing blank window rows.
Those raw capture rows intentionally trigger Git blank-at-EOF warnings;
whitespace verification disables only blank-at-EOF for this evidence directory. No hover, launcher action or shell classification appears.
No blocking API or screen finding remains for U25b.

## Provenance

Separate immutable snapshots were exported from the two handed commits into
ignored build directories. Dependencies resolved offline. Dark/plain used the
exact6bf37fa demo; forced light used the explicitly handed fd4a106 demo.
Commands from each snapshot root:

```sh
env -u NO_COLOR dart run example/markdown_run_controls.dart
env NO_COLOR=1 dart run example/markdown_run_controls.dart
env -u NO_COLOR dart run example/markdown_run_controls.dart --light
```

Owned sessions began120x40 and resized80x24. Keys and SGR reports were sent
literally. No compile or heavy test run was used. This is a framework widget,
so there is no original port screen counterpart; CTUI-25/48 define retained
control styling and geometry rather than pretending custom-language original
screens exist. Exact sh21/bash23 thresholds and offscreen geometry remain
specified automated acceptance, not new live proof from this custom fixture.

All U25b owned sessions/processes were checked closed and its immutable
snapshots removed. U25a2 repair inspection is independent and is not passed
by this report. Hand this unit to reviewer, never directly to tester.
