# U25a2 designer look: changes required

Implementation: `73573594605ae88f88ee473986fb7ad85935fd08`.
Original: `577b58167672e12c999aeaf4eed2a1a988513dc2`, read-only `../chord`.
This is a running-screen look, not a code review or test-suite acceptance.

## Blocking finding

Every injected fitting state shows `↓ 1 line below · end to jump to the
bottom`, including empty, successful, running and full output at120x40
and80x24. There is ample blank room and every shell row is already visible.
End leaves the indicator unchanged. This reads as hidden output the person
cannot reach; it is not present in the corresponding original fitting states.
The fixture must show no below indicator when all content fits, and its
advertised standard transcript scroll keys must function. Keep the shell-row
content/source contract and shared two-pass budget. Do not hide real overflow
or remove legitimate scroll feedback to make this fixture pass.

See port-empty-120x40.txt, port-running-120x40.txt and the full-comparison
pairs. Original application chrome differs from the standalone port fixture;
that alone cannot explain a false hidden-output indicator. Developer receives
this finding before reviewer. No reviewer/tester handover or screen pass yet.

## What looked right

Full twelve-line stdout remains visible, followed by stderr and the failed
exit note, with no ten-line fold. Multiline command and long command wrapping
remain visible. Running/stopped/empty/success/error/blank fixture states were inspected
at both sizes across the retained matrix. Truncation-marker appearance was
checked at80x24; no separate wide truncation acceptance is claimed.

Original running and stopped captures use an explicitly bounded
`!printf ready; sleep 30` followed by Esc. Empty uses `!true`. Full output uses
twelve printf lines, warning on stderr and exit3, matching the supplied fixture.
The injected running process stops through Esc and displays the stopped note.

Dark stderr/exit RGB255,107,128 matches the original; port light uses
RGB196,22,42. Dark bash marker is RGB253,93,177 and held/shown selection uses
slate66. Explicit dark/light captures remove inherited NO_COLOR. Plain captures
retain inverse selection and no colour. ANSI pairs retain these measurements;
no physical-terminal colour appearance or clipboard receipt is claimed.

Live plain120x40 and dark80x24 drags crossed command, blank output and stderr,
then moved over the ending note. Only command/output characters highlight;
!, output gutter/arrow, placeholder blank cells and ending note do not.
The image does not establish the selected LF string; developer/tester tests
own exact serialized-copy proof. No clipboard callback was used.

## Capture provenance and differences

Port commands, run from an ignored immutable source snapshot of7357359:

```sh
dart run example/chord/tool/shell.dart full
env -u NO_COLOR dart run example/chord/tool/shell.dart full
env -u NO_COLOR dart run example/chord/tool/shell.dart full --light
```

Pinned dependencies were resolved offline, with the port's framework path
pointing into the same snapshot. No U25b WIP was read/run and no compile or
heavy test command ran. Initial inherited NO_COLOR=1 captures use generic
port-state names; explicit theme captures carry dark/light/plain names.

Original command: `bun dev chord --fake --qa ctui-designer-u25a2`, then an
explicit colour run with `env -u NO_COLOR` and QA name
`ctui-designer-u25a2-color`. Each owned session began120x40 and resized80x24.
Text was sent literally; Enter was sent in a separate call. Primary SGR
reports were injected for the port's no-clipboard selection checks.

The port fixture contains only a transcript and fixture key footer; the
original has header, prompt and status. Its one-column placement offset and
its existing word-boundary wrapping versus original mid-token wrapping are
fixture/shared-text geometry differences, not a shell semantic change. The
original prior entries remain above newer shell references. They are shown
honestly rather than relabelled as identical application screenshots.

All owned tmux sessions exited cooperatively; process/session checks found
nothing left. Bounded original sleep was stopped, fake exited, owned QA state
and immutable snapshot were removed after retaining evidence. Developer must
hand the repair back to designer before this unit can go to reviewer.
