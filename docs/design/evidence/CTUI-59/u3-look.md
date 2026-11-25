# U3 (CTUI-59): sign-in and pin under a failed start, looked at

Handed source: `c1f47e7`, beside the original (`../chord`, v0.71.0), isolated `XDG_CONFIG_HOME` and `XDG_STATE_HOME`, working directory `/tmp/ctui57-u3/wd`. Two throwaway stubs in that temp directory, outside both repositories, gave both programs the same failures without a network or a real agent:

- `stub`: a user-settings agent (`bun auth_agent.ts`) that answers `initialize` with two `authMethods` (`Log in with a browser`, `API key`) and refuses `session/new` with `-32000 Authentication required`.
- `codex`: the catalog agent, with a `PATH` whose `npx` writes four npm error lines to stderr and exits 1, so the pin line and stderr tail show.

The look passes.

- `u3-stub-{o,p}-{120x40,80x24}`: `stub did not start: Authentication required`, then `⎿  stub offers these sign-ins:`, the two ways with bold names, and chord's sign-in advice wrapped as the original's. Text identical at both sizes; red headline, dim `⎿`, bold names as the original's.
- `u3-codex-{o,p}-{120x40,80x24}`: `codex did not start: it exited with code 1 before answering initialize.`, `⎿  chord ran @agentclientprotocol/codex-acp@2.6.0, the version this chord pins.`, `The end of its stderr:` and the tail two in, wrapped as the original's at 80x24 (`…the version this chord` / `pins.`, `…/tmp/npm-cache/` / `_logs/debug.log`). Text identical at both sizes.
- The ANSI differs only in encoding: the original sets the default foreground to white on spaces and paints a trailing space, neither of which draws anything.

Old, not this unit: the version, the header's `· /help`, and the header's agent line, `codex` in the original and `Codex` in the port (the same before U3, at `345e7c4`).

## U3b: the header names the agent as launched

Handed source: `11134f7`, same setup. `u3b-codex-p-{120x40,80x24}.txt` beside `u3-codex-o-*`: the header's agent line now says `codex`, as the original's; the rest is identical but for the version and `· /help`, both old. The interim start window's `Codex` line is pinned by docs/decisions.md and has no original screen; left to the lead.
