# U25b keyboard repair: help change required

Handed fixture repair: `f445681`. Generic implementation remains6bf37fa.
The reviewer-found run-only keyboard target gap is repaired: literal R
(Shift+R) records Run only: run only at120x40 and80x24; ordinary r separately
records Run: x at80x24. Both target descriptors are reachable without pointer.

The updated one-line KeyHelp truncates: at80x24 it ends c Record copy… and
hides p/n entirely; at120x40 n reads Toggle…. The whole demo must expose all
its described controls at both required sizes. Use clear compact labels or a
readable multiline help presentation, preserving the binding descriptions and
current-descriptor activation. This is a fixture/help issue, not a new generic
widget API request. No reviewer return or tester handover yet.

This corrects the earlier U25b-6bf37fa visual report's statement that KeyHelp
wrapped normally: the actual default widget truncates instead. That earlier
API/style/narrow-control inspection remains evidence, but its complete-screen
acceptance was incomplete and is superseded by this finding until repaired.

Live exact f445681 source ran from a separate immutable ignored-build snapshot:

```sh
env -u NO_COLOR dart run example/markdown_run_controls.dart
```

Owned120x40 session resized80x24; text/key events sent literally. TXT and ANSI
pairs retain full windows including intentional empty trailing rows. No compile
or heavy tests ran; no current-tree WIP or model/clipboard/process action was
used. The owned session/process exited and the snapshot was removed. Developer
must hand a signed help repair back to designer before reviewer continues.
