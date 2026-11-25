# CTUI-120 captures

`dart run example/chord/tool/children.dart` (plain, `--many`, `--codex`) at
120x40 and 80x24, after picking a child from the agent list (Down, Down,
Enter), at commit a7c529dc.

Each child's first line now gives a plausible age in the original's wording
(`../chord` src/ui/agents/agents.ts: `parser · codex · gpt-5.3-codex ·
opened by main 4m ago`): parser 18m ago, and with `--many` the last child
(review) 4m ago. Before the fix it read `opened by main 498652h ago`.
