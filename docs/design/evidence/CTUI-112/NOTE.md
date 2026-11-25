# CTUI-112 evidence: /mcp lists chord's own server

Commit 1f9609e5. The original and the port side by side in tmux at 120x40
and 80x24, on the fake with an isolated, empty XDG_STATE_HOME, `/mcp`
typed once the session is up:

    (cd ../chord && bun dev chord --fake --qa <name> [--no-mcp-servers])
    dart run example/chord/tool/dev.dart chord --fake --qa <name> [--no-mcp-servers]

- `*-passed-mcp.*`: chord's row first (http, its loopback URL, `chord
  itself`) and the line naming the tools it gives fake; no "No MCP servers
  were passed".
- `*-held-mcp.*`: with `--no-mcp-servers`, `not passed` and the held-back
  line, under the startup note.

Text is identical row for row; the URL's port differs by nature. In the
`.ansi` captures the panel's styles match (title bold accent, subtitle,
header and line dim, row plain); the remaining escape differences (the
original's explicit white resets, the prompt border's grey) are outside
this unit. The qa directory in the header is relabelled `<project>`.

Fix b89ec3f3 (the line names the agent shown): `*-120x40-child-mcp.txt`,
prompt `agents`, ctrl+x a, ↓, Enter to show a child (docs), then `/mcp`.
Both draw the child's tools, "close_agent for its own tasks", and
"send_message to main only", identically. The fake's children run on fake,
so the name matches main's either way; mcp_window_test covers another
runtime.
