# U25a2 fixture repair: designer pass

Shell implementation: `73573594605ae88f88ee473986fb7ad85935fd08`.
Fixture repair: `ee205d54cd9536e3cf330684b1a434c01b168b0c`.
Original references/failure: sibling U25a2-7357359 directory and visual.md.
This report resolves that designer finding and hands U25a2 to reviewer.

Exact repair source ran from a separate immutable ignored-build snapshot,
pinned dependencies resolved offline. Launch:

```sh
env -u NO_COLOR dart run example/chord/tool/shell.dart full
```

At120x40 and80x24, full twelve-line output and an empty result after long
output show no below indicator. The original fitting reference likewise has
none. U25a2's previously accepted row/gutter/wrapping/selection/style behavior
is unchanged; only the fixture/controller wiring and regression test changed.

Real100-row overflow remains visible and navigable. At120x40 Home shows64
below; Shift+Down then PageDown shows26; End reaches the true bottom with no
indicator. At80x24 the same progression is81 then60 then none. Returning to
key3 empty removes overflow feedback at both sizes. Narrow key2 running then
Esc displays the stopped result correctly with no false hidden-output rule.
The fixture help now lists key9 long alongside its prior actions.

No hidden content was concealed and no layout-pass workaround was needed.
The earlier full-source/ANSI original comparisons remain the row reference;
there is no original counterpart to this injected long-fixture key footer.
All interactions were observed live with owned tmux captures. No heavy test
or compile command ran, no current-tree WIP ran, and no model/clipboard/real
shell process was started by the port fixture. Original reference resources
had already been cleaned after the first look.

The owned repair session and processes exited cooperatively; the immutable
snapshot was removed. Pass U25a2 plus this repair to reviewer. This says
nothing about U25b's separately discovered demo key gap or its repair.
