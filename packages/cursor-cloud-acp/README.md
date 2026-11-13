# @chorded/cursor-cloud-acp

Cursor's cloud agents as an [Agent Client Protocol](https://agentclientprotocol.com)
v1 agent on stdin and stdout, written on Cursor's TypeScript SDK,
`@cursor/sdk`. [chord](https://github.com/IKatsuba/chord) starts it as its
`cursor-cloud` agent.

Requires Node 22.13 or newer. Version 0.1.0 is not published yet; the
commands below require that release.

## Signing in

```sh
npx -y @chorded/cursor-cloud-acp@0.1.0 login    # Cursor's browser login, the key kept in the OS keychain
npx -y @chorded/cursor-cloud-acp@0.1.0 status   # whether the keychain holds a login
npx -y @chorded/cursor-cloud-acp@0.1.0 logout   # the key removed from the keychain
```

`CURSOR_API_KEY`, when set, is used instead of the keychain's key. Where no
keychain is there (Linux without a Secret Service), `login` refuses and
points to `CURSOR_API_KEY`; no key is written to a file. The SDK's own
login file is not used. Keychain calls time out after 10 seconds.

What each prints, on stdout (the SDK's own lines, the login URL among
them, go to stderr):

| Command | Says |
| --- | --- |
| `login` | `Signed in to Cursor as <email>; the key expires <YYYY-MM-DD>.`, each part only when the SDK gives it |
| `login` without a keychain | `No keychain to keep the key in: <the keychain's error>. Set CURSOR_API_KEY instead.` on stderr, status 1 |
| `logout` | `Signed out of Cursor: the key is removed from this machine's keychain.` |
| `status` | as `login`, or `Not signed in to Cursor.`; then `CURSOR_API_KEY is set; it is used instead.` when it is |
| any other word | `Usage: cursor-cloud-acp [login \| logout \| status]` on stderr, status 2 |

## Running

```sh
chord cursor-cloud
# Or serve ACP v1 to another client in the current directory:
npx -y @chorded/cursor-cloud-acp@0.1.0
```

Start in a git work tree on a pushed branch with a push remote. The check
uses the local remote-tracking ref, without fetching. A refusal tells you
what to fix. Cursor starts from the remote branch; local changes are not
uploaded. The first message names the repository, branch and agent link.
Work runs in Cursor's cloud, pushes a branch of its own and keeps running
when the client closes. Results name branches, PR links and artifact paths;
nothing is downloaded.

Creating a session is refused while the Cursor account's prepaid balance
is empty: top up or enable auto top-up. `usage_limit_exceeded` appears as
one plain line with Cursor's message.

Agent and Plan modes apply from the next prompt. Models have one entry
each, with separate parameter options; choosing a model starts outside
max mode when possible. Cursor's default is offered until a model is set.
Text, thinking, tool results and plans arrive as ACP updates. Cursor
requests for input or approval are text only; the adapter cannot answer
them. Cancel stops the run, with a warning if Cursor has not confirmed it
within 10 seconds. A lost connection ends the turn with the agent link.

In chord, `/resume` lists chord's records;
`chord cursor-cloud --resume bc-…` also reopens an agent started elsewhere.
The adapter replays the history Cursor provides. A run still going is
reported, not followed live; prompts are refused until it ends.
ACP `session/list` lists the account's cloud agents for the repository.
MCP servers are not forwarded: chord holds them back by default; servers
sent by another client are named unreachable in the first message.

## Development

From the repository root, `bun install` installs the workspace.
`bun dev quality cursor-cloud-acp` checks types, tooling types, coverage,
lint and format, then runs tests, the build and a packed Node smoke.
`--static` leaves out tests, build and smoke. Tests use a fake Cursor and
keychain; the smoke installs dependencies but reaches neither Cursor nor
the keychain. The [guide](../../docs/guide.md#development) gives the offline
window fixture command.

The owner's `bun dev release cursor-cloud-acp` runs install, quality,
build, pack and publish, tags `cursor-cloud-acp-v<version>` and creates no
GitHub release. `@cursor/sdk` 1.3.1 is an external dependency, as are the
ACP SDK and keyring. The package bundles none of them; chord's binary
contains neither the Cursor SDK nor the keyring.

## License

MIT
