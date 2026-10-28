# U2 Tab sends the oldest queued message: screen check

Screen code: `2cd329e2`. Design: `40da17fc`, `08b55826`. Captured 2026-10-28.

`bun dev chord --fake --qa d535`, one tmux session per case and size, text
sent with `send-keys -l` and Enter separately. Each PNG is the whole window
rendered from `capture-pane -p -e`.

- `c535-queued-*`, `c535-tab1-*`, `c535-tab2-*` (`CHORD_FAKE_STEERING=claude`,
  prompt `slow`): two queued rows and a draft; Tab sends the oldest, its `›`
  row is drawn in the transcript, the draft stays; Tab again sends the next.
  In `c535-tab2-120x40` the short turn had ended and the reply came.
- `c535-nosteer-80x24` (no steering): both rows stay; warning note
  `This agent does not take messages into a running turn · it stays queued`.
- `c535-refused-*` (`CHORD_FAKE_STEER_REFUSE=1`): both rows stay in place;
  warning note `Not taken into the running turn · it stays queued`. At 80×24
  the model on the right is cut with `…`.
- `c535-late-*` (`CHORD_FAKE_STEER_LATE=1`, `texttillsteeredheld`):
  `› into the running turn: …` while out; after Esc it goes once, as the
  next turn.
- `c535-shortcuts-80x24`: `tab to send the oldest queued now` after
  `enter to send`.

Not reached on screen: a refusal with an agent `←` row ahead in the queue,
and held rows (`after the running calls:`), unchanged from CHD-378.

Result: visual pass.
