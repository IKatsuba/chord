/**
 * The commands of the fake agent's `heredoc` and `longcommand` scenarios,
 * those of the Claude Code capture in docs/design/CHD-393.md, so a capture
 * of chord compares with it line for line.
 */
export const NOTES_COMMAND = [
  "cat <<'EOF' > notes.md && wc -l notes.md",
  '# Release notes',
  '',
  '- Added a greeting helper module',
  '- Introduced add and sub math utilities',
  '- Improved error messages for invalid input',
  '- Updated dependencies to latest versions',
  '- Fixed a typo in the README',
  '- Reduced startup time by caching config',
  '- Added unit tests for greet',
  '- Removed deprecated farewell API',
  'EOF',
].join('\n');

/** A 309-character sentence upper-cased and counted, one line. */
export const WEATHER_COMMAND =
  'echo "This morning the weather started out cool and misty with a thin ' +
  'layer of fog rolling over the hills, but by noon the sun had burned ' +
  'through the clouds, the temperature climbed steadily, a light breeze ' +
  'came in from the west, and forecasters warned that scattered ' +
  'thunderstorms could arrive late in the evening" | tr a-z A-Z | wc -c';

/**
 * The arguments of the Claude Code capture's MCP call, `notes`'s
 * `save_note`, for the fake agent's `mcpnote` scenario: as an adapter sends
 * them, in `rawInput` alone.
 */
export const NOTE_ARGUMENTS = {
  title:
    'Tool-call rendering test: long titles, wrapped bodies, and multiple ' +
    'tags in one note',
  body:
    'This note is part of a UI test that checks how tool calls are drawn in ' +
    'the terminal. It covers a long single-line Bash command, a heredoc ' +
    'that writes a file, a file read, an edit, a write, a wide regex ' +
    'search, a brace-expansion glob, this MCP call, a subagent call, and ' +
    'finally a 300-line heredoc. The goal is to see how titles, bodies, and ' +
    'tag arrays are truncated, wrapped, or expanded in the rendered output.',
  tags: ['ui-test', 'tool-rendering', 'mcp', 'terminal', 'claude-code'],
};
