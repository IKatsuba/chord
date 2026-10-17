# Claude Code 2.1.301: tool-call headlines

Taken in tmux from one session in a throwaway git repository, in the default
permission mode (auto). One prompt asked for ten tool calls in a row; an
earlier one was cut off by the paste and answered with a question. The
session was drawn at 120x40, then resized to 80x24, which Claude Code
re-flows.

Claude Code draws in the alternate screen, so tmux keeps no scrollback. Each
file is the transcript paged through inside the app (PageUp/PageDown in the
main view, ↑↓ in ctrl+o's detailed transcript) and stitched where the pages
overlap. Dropped while stitching: the main view's sticky first row (the
current prompt, pinned) and the "Jump to bottom" hint drawn over the last
transcript row. The repository's path is replaced with `/tmp/repo`, so lines
that held it are shorter than the width they were drawn at.

- `120x40-transcript.txt`, `80x24-transcript.txt`: the main view.
- `120x40-ctrl-o.txt`, `80x24-ctrl-o.txt`: ctrl+o, the detailed transcript.

This build exposes no Grep or Glob tool: the search calls are `Bash(grep …)`
and `Bash(find …)`.
