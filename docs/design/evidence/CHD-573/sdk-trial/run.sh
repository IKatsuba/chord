#!/bin/sh
# Runs the CHD-573 library gate: agent.mjs under Bun and from `bun build
# --compile`, driven over real pipes. The scripts are copied to a new directory
# outside the repository, which resolves the SDK through a link to the
# repository's node_modules, so it is the version bun.lock pins and nothing is
# downloaded. Binaries and working files stay there; output comes back here.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo=$(git -C "$here" rev-parse --show-toplevel)
work=$(mktemp -d "${TMPDIR:-/tmp}/chd573-sdk-trial.XXXXXX")
out="$here/output"

cp "$here"/agent.mjs "$here"/client.mjs "$here"/stall.mjs "$here"/queue.mjs "$here"/g8.mjs "$here"/chord_start.mjs "$work/"
ln -s "$repo/node_modules" "$work/node_modules"
cd "$work"

bun build --compile agent.mjs --outfile "$work/agent-bin" >"$work/compile.log" 2>&1

mkdir -p "$out" "$work/start"
{
  printf 'bun %s\n' "$(bun --version)"
  printf 'sdk %s\n' "$(grep '"version"' "$repo/node_modules/@agentclientprotocol/sdk/package.json" | tr -d ' ",' | cut -d: -f2)"
  uname -sm
  printf 'agent binary %s bytes\n' "$(wc -c <"$work/agent-bin" | tr -d ' ')"
} >"$out/versions.txt"

# Node's stdout adapter, then the callback adapter.
bun client.mjs bun bun "$work/agent.mjs" >"$out/bun.jsonl"
bun client.mjs compiled "$work/agent-bin" >"$out/compiled.jsonl"
TRIAL_STDOUT=callback bun client.mjs bun+callback bun "$work/agent.mjs" >"$out/bun_callback.jsonl"
TRIAL_STDOUT=callback bun client.mjs compiled+callback "$work/agent-bin" >"$out/compiled_callback.jsonl"
bun stall.mjs bun bun "$work/agent.mjs" >"$out/stall_bun.jsonl"
bun stall.mjs compiled "$work/agent-bin" >"$out/stall_compiled.jsonl"
bun queue.mjs bun bun "$work/agent.mjs" >"$out/queue_bun.jsonl"
bun queue.mjs compiled "$work/agent-bin" >"$out/queue_compiled.jsonl"
bun g8.mjs bun bun "$work/agent.mjs" >"$out/g8_bun.jsonl"
bun g8.mjs compiled "$work/agent-bin" >"$out/g8_compiled.jsonl"
bun chord_start.mjs "$repo" "$work/start" >"$out/chord_start.jsonl"

# Nothing committed may name this machine (tests/privacy_test.ts).
sed -i '' -e "s#$work#<work>#g" -e "s#$repo#<repo>#g" "$out"/*.jsonl
