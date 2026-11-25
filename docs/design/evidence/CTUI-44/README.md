# CTUI-44 live design evidence

Original: `577b58167672e12c999aeaf4eed2a1a988513dc2`.
Port: shipped UI at main `63734e8ef460b1958a65138890803f0392b86d06`.
The port ran on the shared CTUI-45 branch while its launch-only units moved
forward; no framework or port UI file differed from that shipped main.
No unhanded screen implementation was inspected. This is baseline evidence,
not acceptance of a new screen unit.

Commands, each in an owned tmux session:

- Original: `(cd ../chord && bun dev chord --fake --qa designer-ctui44)`.
- Port: `dart run example/chord/tool/dev.dart chord --fake`.

Both unset `NO_COLOR`, set `FORCE_COLOR=3` and `COLORTERM=truecolor`.
Original used an isolated settings file selecting dark, then light.
Port selected the corresponding theme with `COLORFGBG=15;0`, then `0;15`.
Prompts `error` and `plan` were typed with `send-keys -l`; Enter was sent
separately. Text captures use `capture-pane -p`, ANSI captures add `-e`.
The port header's expanded worktree directory is replaced by `<task worktree>`
in wide captures; narrow captures retain only the nonprivate truncated task
name. Header version, directory and M2 `/help` differences are outside scope.

## Error row: match

At 120x40 and 80x24, in both themes, the error is on row 10:
column 2 is `⏺`, column 3 is an uncoloured separator, columns 4–36 are
`The fake agent failed on purpose.` (coordinates are one-based).
Dark foreground is `#ff6b80` / RGB `(255, 107, 128)` on marker and message;
light is `#c4162a` / RGB `(196, 22, 42)` on the same cells.
Original and port both emit those truecolour SGR values. The original's
uncoloured spaces sometimes carry its renderer's explicit white fallback;
the failure foreground is identical. No style fix or U6 is needed.

See `error-{dark,light}-{original,port}-{120x40,80x24}.{txt,ansi}` and
matching `comparison` files. These replace the previously unmeasured live
red claim; they do not claim terminal display calibration.

## Plan row: OpenTUI layout artifact

At 20x40, original and shipped port respectively draw:

```text
original                  port
☒ Read...code             ☒ Read...code
☒Writ...hange             ☒ Writ...ange
☒ Run ...ests             ☒ Run ...ests
```

The original's second row becomes `☒ Writ...hange` at 21 columns and
`☒ Write...hange` at 22 columns. At 120x40 and 80x24 both draw every
step whole, with a separator. The width probes and paired baselines are
saved as `plan-baseline-*`.

Source explanation, read only in the original:
`src/ui/plan/Plan.tsx` always emits `${mark} ` as a separate TEXT element;
the content sibling alone uses CUT. `src/ui/plan/plan.ts` chooses rows and
marks, with no separator-dropping policy. `src/ui/theme/text.ts` makes CUT
nonwrapping with `truncate: true`; TEXT sets no fixed width or shrink
policy. OpenTUI 0.8.4 defaults each widthless text to `flexShrink: 1`
(`setupYogaProperties` in its installed core implementation).
The three-cell Gutter alone explicitly has `flexShrink: 0`.
Under shortage the longer content competes with the two-cell mark element:
its mark element shrinks to one cell and loses the trailing space, leaving
one extra cell for the middle-truncated step. Shorter rows retain the space.
This is an engine consequence, not an authored rule that removes separators.

Lead decision `0d21a2d`: keep the separator, as an approved small-slip fix.
The semantic drawing rule stays: mark, one separator cell, then step content
middle-truncated within the remaining width. No width-specific omission
should be added. U5 is test-only; there is no new screen unit to accept.

## Cleanup

All owned windows quit through empty-prompt Ctrl+D. Both owned tmux
sessions (`designer-ctui44-original`, `designer-ctui44-port`) were killed.
A process-tree check after closing them found no remaining owned shell,
Dart window/dev runner, original runner/window, or fake-agent process.
No original source or implementation file was changed; no tests, AOT build
or suite was run by designer.
