# CHD-608 U5 screen evidence

Screen unit: `0a68ca26a30a4b631587aad64c308051d2def18f`.
Design: `docs/design/CHD-608.md`, as corrected by `f5779cd6`.

These are captures of a running TUI in an owned tmux server/session,
`chd608-designer`, at 120x40 and 80x24. The command was
`bun dev chord --fake --qa chd608 riff`, with inherited `NO_COLOR` cleared
and `FORCE_COLOR=1` for the committed colour captures. All provider traffic
was the local fake provider; no live model, sign-in or credential store.

Each `.txt` is `capture-pane -p`; each `.ansi` is `capture-pane -p -e`.
PNGs render the captured ANSI through the repository's installed `ansi_up`
and `puppeteer-core`, following the screenshot script's approach. They
show the terminal cells without a decorative window or cropped controls.

- `u5-caution-*`: `call shell {"command":"printf '[review:caution]'"}`.
  Warning heading, plain rationale, retained review outcome, countdown,
  Allow once / Deny, footer and auto status remain readable at both sizes.
- `u5-failed-*`: `call shell {"command":"printf '[review:failed]'"}`.
  The fake reviewer returns malformed decisions twice. Error explanation
  wraps cleanly at 80 columns; auto remains selected with no auto-off notice.
- `u5-incomplete-*`: write `.env.review-incomplete` with 65,537 `x`
  characters. The proposed diff is scrollable, with a plain explanation
  of the 64 KiB limit and both answers/footer pinned at both sizes.
- `u5-incomplete-scrolled-80x24`: PageDown moves the diff and changes the
  above/below counts without moving the rationale, answers or footer.

Ordinary scenario text was entered with literal `send-keys -l`, followed
by Enter separately. For the oversized input, one literal tmux command
exceeded tmux's command limit; chunked keys arrived asynchronously and
made an early capture/subsequent input invalid. That attempt was discarded
and the fake session reset. The committed incomplete captures use developer's
working buffer-paste recipe with Enter separately. No product finding is
inferred from the failed input-driving attempt.

The first no-colour captures were replaced after discovering inherited
`NO_COLOR=1`. The committed captures use the colour-enabled session.

- `u5-timeout-*`: the failed-review ask was left unanswered for its real
  five-minute deadline. Its box/countdown disappear and the failed call
  retains `Reviewed: failed` above `Denied: no answer within 5 minutes.`
  The fake model receives and echoes the denial; no command output or
  successful exit appears. Auto remains selected.

Shift+Tab was exercised auto → ask → auto while the failed-review ask
waited. The countdown continued against the original deadline, rather
than restarting. The failed-review capture precedes that manual cycle;
the timeout captures show the final auto state.

Screen judgment: pass; no blocking visual findings. The reason, choices,
footer and draft remain reachable at both sizes, including the tall diff.
This is a screen look, not a code review or a repeat of developer's tests.
Both the original and replacement tmux sessions were killed. The owned
oversized-input buffer and payload file were removed; the denied final
write left no `.env.review-incomplete` in the QA directory.
