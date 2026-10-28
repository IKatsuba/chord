# U2b the fork's view: screen check

Screen code: `0d0ba305` (with `0a85d12d` in the tree). Design: `896f4337`,
`9432f544`. Captured 2026-10-28.

`CHORD_FAKE_FORK=1 bun dev chord --fake --qa d101`, one tmux session per
size, text sent with `send-keys -l` and Enter separately. Each PNG is the
whole window rendered from `capture-pane -p -e`.

- `b-fork-120x40`, `b-fork-80x24`: after `text` (and `thought` at 80×24)
  and `/fork`, the picked fork shows its header, main's conversation as it
  stood, then the dim `── forked from main · 23:58 ──`.
- `b-after-120x40`: `thought` in the fork continues below the divider.

Also checked as text: main's own view has no divider.

Result: visual pass.
