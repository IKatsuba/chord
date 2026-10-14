# CHD-334 design look at 37e3eac9

Fake agent only. Each run is a fresh session with `-C` set to a `/tmp/chord-qa.*` directory. The steps are `?` on the empty draft, then Esc, then `hello` and Enter sent separately. tmux `pipe-pane` recorded the raw output of every run.

| run | MaxListenersExceededWarning in raw output |
| --- | --- |
| source 120x40 | 0 |
| source 80x24 | 0 |
| host binary 120x40 | 0 |
| host binary 80x24 | 0 |

The dismissed and reply screens are clean: the header, the transcript, the rounded prompt box and the `? for shortcuts` footer, with no fragments. The open shortcuts panel and the prompt rows match the approved captures in `docs/design/evidence/CHD-305/main-*/07-shortcuts.txt` line for line. Only the transcript above them differs, because those captures had a session behind them.
