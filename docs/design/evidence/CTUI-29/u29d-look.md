# U29d: a context chord worked out is marked with ~

Handed source: `ecdc934`. It was run from a clean archive of that commit beside the original at `577b581`. Both apps ran `chord fake` from the same directory with isolated config and state. The original's fake was started through `.chord/settings.json` with `--tokens-only` (case T) and without it (case N). The prompt `hello` was sent, and the screen was captured once the turn had settled.

The look passes.

- `pair-T-120x40` and `pair-T-80x24`: the status line is `GPT-5.3 Codex · medium effort · ~1% context used` in both apps. The window is taken from the model, so the figure is marked.
- `pair-T-64x24`: the short form `GPT-5.3 Codex · medium · ~1% used` appears in both.
- `pair-N-120x40` and `pair-N-80x24`: the agent's own usage shows `1% context used` and `1% used`, unmarked in both.
- The whole screens have identical text, apart from the version and the old missing `· /help` in the header. The status line is dim with the default foreground in both apps. The original also paints its spaces white, which draws nothing.

All tmux sessions were killed, and no process of this run was left. The scratch directory was removed.
