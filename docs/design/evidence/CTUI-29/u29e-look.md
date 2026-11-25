# U29e: /cost and /context for one session

Handed source: `aa31426`, plus `da49579`, which changes only tests and decisions and nothing on screen. It was run from a clean archive of `aa31426` beside the original at `577b581`. Both apps ran `chord fake` with the original's fake from the same directory with isolated config and state, as is (N) and with `--tokens-only` (T), at 120x40 and 80x24. Each run did the same steps:

1. `/cost` before any prompt (`cost-before`).
2. `/c` typed into the prompt (`complete`).
3. `hello` sent.
4. `/cost` (`cost`).
5. `/context` (`context`).

The look passes.

- `pair-*-cost-before`: `fake has not reported what this session has used.` followed by `Session time:`, the same in both apps.
- `pair-*-cost`: the same aligned rows in both. N gives `Total cost: $0.0125`, `Tokens in: 1,000`, `Tokens out: 200`, `Cache read: 800` and `Session time`. T gives the same with the estimate wording.
- `pair-*-context`: `Used: … of … tokens (P%)` and `Free: …`. T adds `(chord's estimate)` to both rows, as the original does.
- Every one of these screens has the same text in both apps, apart from the version, the old missing `· /help` in the header, and the `Session time` seconds, which come from when each capture ran.
- `pair-*-complete`: `/context` and `/cost` sit between `/config` and `/echo` with the original's descriptions. The only difference is the original's `/mcp` row. `/mcp` is a reserved but unported command in the port, as it was before this unit, so the list is one row shorter.

All tmux sessions were killed, and no process of this run was left. The scratch directory was removed.
