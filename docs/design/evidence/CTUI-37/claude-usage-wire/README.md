# What SDK 0.3.325 sends `claude` for the usage getter

The recording runtime draft §3.2 asks for: no real `claude`, no network to
it, and no machine path in the log.

- `fake.ts`: a fake `claude`, run by deno. It writes `{argv, env}` (the
  environment filtered to names matching `CLAUDE|SDK|NODE_OPTIONS|DEBUG`)
  as the log's first line, then each stdin line, answers `initialize` and
  any other control request, and writes `EOF` when stdin ends.
- `fake-claude`: the executable the SDK starts, with no `.js`/`.ts` suffix
  so the SDK runs it as a native binary.
- `run.ts`: `query()` from `npm:@anthropic-ai/claude-agent-sdk@0.3.325`
  with exactly the original's `src/platform/resource_worker.ts` options,
  then `initializationResult()`, the getter with `skipBehaviors: true`,
  and `close()`.
- `wire.log`: the recording. The request ids are the SDK's random ones.

To record again, copy the three scripts to a scratch directory outside
the repository and run, with an empty environment so nothing inherited
is logged:

```sh
env -i PATH="<deno's bin>:/usr/bin:/bin" HOME="$HOME" \
  deno run --allow-all --node-modules-dir=auto run.ts
```

The only network use is deno fetching the SDK from npm.

What the log shows:

- argv: `--output-format stream-json --verbose --input-format stream-json
  --tools= --setting-sources= --strict-mcp-config
  --no-session-persistence --settings {"disableAllHooks":true}`.
- env the SDK sets: `CLAUDE_CODE_ENTRYPOINT=sdk-ts` and
  `CLAUDE_AGENT_SDK_VERSION=0.3.325`, each when unset, and
  `CLAUDE_CODE_SDK_READS_SESSION_STATE=1`, unless a variable of that name
  in any case is set (sdk.mjs). The third is missing from runtime §3.2's
  list.
- stdin: `initialize` with `systemPrompt: [""]`, then `get_usage` with
  `skip_behaviors: true`, then end of input.
