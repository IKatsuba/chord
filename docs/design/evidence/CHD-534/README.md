# CHD-534: synthetic T1 screen evidence

Screen look: PASS, 2026-10-27. Handed implementation commit:
`c1bf4d84615de94021de20806be1a5048eff9ed6` (signed). Design:
[CHD-534](../../CHD-534.md), including owner-approved standard ACP boundary.

The designer ran an immutable `git archive` of the exact implementation commit
in `/tmp/chd534-designer-c1bf4d84`, with the checkout's existing `node_modules`
linked. No source file or private historical record was inspected. No live
agent, model, authentication or provider call was made. This is source-mode QA,
not a compiled-binary check.

## Commands and sequence

Wide session:

```sh
tmux new-session -d -s chd534-designer-wide -x 120 -y 40 \
  'cd /tmp/chd534-designer-c1bf4d84 && env -u NO_COLOR bun dev chord --fake --qa chd534-designer-wide'
tmux send-keys -t chd534-designer-wide -l fxerror
tmux send-keys -t chd534-designer-wide Enter
tmux capture-pane -t chd534-designer-wide -p
tmux capture-pane -t chd534-designer-wide -e -p
```

After inspecting the first error, send `fxerror` again with literal text and
Enter in separate calls. Capture the second error, press PageUp and capture
the first turn still present above the second. Press End, then send `text`
and Enter separately; capture the normal reply. For the narrow run, use
`chd534-designer-narrow`, dimensions `-x 80 -y 24`, and QA name
`chd534-designer-narrow`. Also PageUp after the first narrow failure to inspect
the earlier completed tool rows, then End before the second request.

`tmux list-panes` verified actual pane sizes of 120×40 and 80×24. All captures
are unmodified `capture-pane` output: `.txt` is plain text and `.ansi` preserves
colour. The designer read every plain capture and inspected the corresponding
ANSI colour roles. No PNG rendering was needed for this terminal text check.

## Captures and findings

| Capture stem | Observation |
| --- | --- |
| `120x40-first-error` | All seven completed calls, explanation, one terminal error and ordinary prompt fit together. |
| `120x40-second-error` | The first error and second failed turn are visible together, with two separate terminal labels. |
| `120x40-two-turns-scrolled` | The first complete failed turn remains above the second prompt; the scroll hint identifies later output. |
| `120x40-followup` | Both errors remain and the next `text` request has the normal chunked reply. |
| `80x24-first-error` | Latest tool results, full wrapped explanation, one terminal error and prompt remain readable. |
| `80x24-first-tools-scrolled` | Earlier completed tool rows remain accessible by PageUp. |
| `80x24-second-error` | The second failed turn ends with one terminal label and idle prompt. |
| `80x24-two-turns-scrolled` | The first error remains immediately before the second prompt and its tool calls. |
| `80x24-followup` | The second error remains above the next prompt and normal reply. |

Completed tool markers use dark-theme success RGB `78;186;101`; the terminal
label and marker use error RGB `255;107;128`. The explanatory assistant text
uses ordinary foreground. Synthetic clipped JSON stays visible as ordinary
tool content. Its clipping is intentional fixture text, not a new renderer
failure. No completed call becomes a failed call when its turn ends in error.

The screen reads clearly at both sizes. Older rows scroll out normally; the
ordinary prompt and latest error stay readable. No action or shortcut was
added. No visual finding blocks the handed T1 unit.

## Cleanup and limits

Both owned sessions were removed with `tmux kill-session`. Afterwards tmux
reported no server on its socket, and process inspection found no owned QA
shell or fake-agent process. The temporary source archive and both fixed QA
directories were removed after captures were saved.

These synthetic runs establish existing display and next-request usability.
They do not reproduce the historical fx extension or establish model
acceptance, response-language expectation, upstream root cause, rejected
candidate or exact Russian wire content. The fixture is standard ACP only.
Two synthetic failures are not an exact replay of three historical failures.
No production code review, streaming-timing inspection, light-theme check,
permission scenario, compiled build or full application suite was run by the
designer. Privacy and prose checks are reported in the evidence commit handoff.
