# CHD-441, an agent that takes no MCP servers: captures

Taken at 5a0c3e7c (f28c1702's words, with the main session reading the
setting), on the fake with `agents.fake.mcpServers: false` and a stdio, an
http and an sse server in a scratch user settings file.

**Known, open as Q104:** at 80×24 the start line breaks before the comma
after `chord (chord's own)`, so its second line starts with `,`
(`start-80x24.txt`). The line is a plain OpenTUI text and OpenTUI's word
wrap makes that break; whether chord accepts it and reports it upstream,
rewords, or wraps the line itself is the owner's. At 120×40 the line wraps
well, and `/mcp` reads as designed at both sizes.
