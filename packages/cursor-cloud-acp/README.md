# @chorded/cursor-cloud-acp

Cursor's cloud agents as an [Agent Client Protocol](https://agentclientprotocol.com)
v1 agent on stdin and stdout, written on Cursor's TypeScript SDK,
`@cursor/sdk`. [chord](https://github.com/IKatsuba/chord) starts it as its
`cursor-cloud` agent.

It is being built (CHD-622) and is not published yet.

Node 22.13 or newer.

## Signing in

```sh
npx -y @chorded/cursor-cloud-acp login    # Cursor's browser login, the key kept in the OS keychain
npx -y @chorded/cursor-cloud-acp status   # whether the keychain holds a login
npx -y @chorded/cursor-cloud-acp logout   # the key removed from the keychain
```

`CURSOR_API_KEY`, when set, is used instead of the keychain's key. Where no
keychain is there (Linux without a Secret Service), `login` refuses and
points to `CURSOR_API_KEY`; no key is written to a file.

What each prints, on stdout (the SDK's own lines, the login URL among
them, go to stderr):

| Command | Says |
| --- | --- |
| `login` | `Signed in to Cursor as <email>; the key expires <YYYY-MM-DD>.`, each part only when the SDK gives it |
| `login` without a keychain | `No keychain to keep the key in: <the keychain's error>. Set CURSOR_API_KEY instead.` on stderr, status 1 |
| `logout` | `Signed out of Cursor: the key is removed from this machine's keychain.` |
| `status` | as `login`, or `Not signed in to Cursor.`; then `CURSOR_API_KEY is set; it is used instead.` when it is |
| any other word | `Usage: cursor-cloud-acp [login \| logout \| status]` on stderr, status 2 |

## License

MIT
