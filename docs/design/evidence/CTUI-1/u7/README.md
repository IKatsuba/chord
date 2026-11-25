# U7 designer look: scroll bindings and demo

Unit: `83b07c0`; merged demo checked at `62d2f2a`; anchor fix rechecked at
`e643e4c`. These are live `tmux capture-pane -p` frames from
`dart run example/demo.dart`, at 120x40 and 80x24. No compiled binary was
used. No implementation code was inspected for this visual look.

## Resolved finding

At `62d2f2a`, fill the log with ctrl+x f, pageup, shift+up, then ctrl+o.
At 120x40 item 141 was the top item before the toggle but moved about
13 rows below it afterwards. At 80x24 a continuation of item 177 at the
top became item 167 after the toggle. See `before-fix/`.

Expected: preserve the first visible item and row into that item while
details change wrapping, as the settled design's anchor contract states.
This finding was sent to developer; `e643e4c` was handed back as its fix.

## Recheck result

No remaining visual blocker in the exercised U7 behavior. See `after-fix/`:

- Initial and cleared content sits at the top with blank space below.
- Fill follows line 200 to the bottom, wrapping inside the log's border.
- pageup moves back a page; shift+up moves one row. shift+down restores
  that row, and pagedown restores the filled bottom view.
- At 120x40, details retain item 141 as the first list item below the
  newly visible theme sample. Turning details off restores the exact
  preceding view.
- At 80x24, the first list row remains a continuation of item 177 when
  details change wrapping; item 178 follows it. Turning details off
  restores the exact preceding view.
- After paging back, literal text followed by Enter appends the message,
  returns to the bottom and clears the prompt, at both sizes.

Capture sequence: initial, ctrl+x f, pageup, shift+up, ctrl+o, ctrl+o,
shift+down, pagedown. The narrow run follows a resize and ctrl+x c.
Send checks page up, type with `send-keys -l`, then send Enter in its own
call. The wide send check follows the narrow send, so it includes both
messages. The earlier wide send under `before-fix/` is from `62d2f2a`.

## Scope and known limits

The settled design and interface draft section 3 require the framework to
draw only items. The demo adds no port scroll rules or gutters. This is a
framework demo, so no original port screen comparison applies.

The one-line KeyHelp truncates at both sizes: at 120 columns it reaches
pageup; at 80 columns even the fill binding is beyond the ellipsis. This
is the existing KeyHelp limitation named by developer, not evidence that
all scrolling descriptions are visible. Home/End remain the design's
known TextInput focus gap. This look did not retest those keys, scope
shadowing, themes, colours or the full API: those remain code-review and
tester responsibilities.

The designer-owned session `designer-ctui1-u7` was killed after each run;
the final `tmux has-session` reported no server running.
