# CTUI-67 captures

The port's use of layout readings (U6, commit 2674d490), run from a clean
`git archive` of the commit beside the original, both on the original's
fake agent, from a scratch directory `here` whose path is relabelled
character for character. Each file ends with a `cursor x,y` line read from
tmux. Cyrillic was typed with `send-keys -l`, so these runs cover the
Russian table (no kitty base key: tmux re-encodes keys and does not pass
kitty's alternate fields). The kitty base-key path, including the key in
`?`'s place on an empty prompt, is covered by the widget tests and needs a
physical kitty window to see.

- `u6-russian-text-*`: `привет, мир` typed in the prompt stays as typed.
- `u6-ctrl-x-pending-*`: Ctrl+x, the leader line naming what follows.
- `u6-ctrl-x-ef-*`: then `ф`, the key in `a`'s place: the chord ends.
- `u6-vim-rr-*`: `/vim`, `abc def ghi`, Esc, `р р` (h h).
- `u6-vim-shts-*`: then `д` (l), `ш` (i), `ц` typed as itself, Esc.
- `u6-vim-i-*`: then `и` (b).

The vim and text states are identical to the original. Two differences
predate this unit and do not come from the reading: after Ctrl+x `a` (or
`ф`) with nothing waiting, the original says `Nothing waits on you` in the
hint line and the port says nothing; and while a chord waits, the original
hides the terminal cursor while the port keeps it at the draft.
