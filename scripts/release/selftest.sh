#!/bin/bash
# A built chord's self-test, on the fake agent: --version says package.json's
# version, -p answers, and the window opens, answers a prompt and reads the
# clipboard on ctrl+v, each of which a native library the binary could not
# load would stop. The window runs in a tmux of its own, on temporary state
# and config directories. ARCH x86_64 runs it all under `arch -x86_64`
# (Rosetta).
#   scripts/release/selftest.sh BINARY [ARCH]
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
root=$(cd "$here/../.." && pwd)

binary=${1:?usage: scripts/release/selftest.sh BINARY [ARCH]}
[ -f "$binary" ] || die "no binary at $binary"
# Absolute, as the runs below start in a directory of their own.
binary="$(cd "$(dirname "$binary")" && pwd)/$(basename "$binary")"
arch=${2:-}
command -v tmux >/dev/null || die "the self-test needs tmux"
# A function, not an empty array: macOS bash 3.2 calls one unbound under -u.
run() {
	if [ -n "$arch" ]; then arch "-$arch" "$binary" "$@"; else "$binary" "$@"; fi
}
fake="bun '$root/tests/fixtures/fake_agent/main.ts'"
scratch=$(mktemp -d)
socket="chord-selftest-$$"
cleanup() {
	tmux -L "$socket" kill-server 2>/dev/null || true
	rm -rf "$scratch"
}
trap cleanup EXIT
mkdir "$scratch/project" "$scratch/state" "$scratch/config"
export XDG_STATE_HOME="$scratch/state" XDG_CONFIG_HOME="$scratch/config"

want=$(plutil -extract version raw "$root/package.json")
said=$(run --version 2>&1) || die "$binary --version failed: $said"
case "$said" in *"$want"*) ;; *) die "$binary --version said $said, not $want" ;; esac

said=$(cd "$scratch/project" && run fake --agent-command "$fake" -p text 2>&1) ||
	die "$binary -p failed: $said"
case "$said" in *"Hello, world."*) ;; *) die "$binary -p answered: $said" ;; esac

# The screen, once it shows what is waited for, or a death with what it showed.
screen() {
	tmux -L "$socket" capture-pane -t selftest -p 2>/dev/null || true
}
wait_for() {
	for _ in $(seq 1 60); do
		case "$(screen)" in *"$1"*) return 0 ;; esac
		sleep 0.5
	done
	die "$binary's window never showed \"$1\"; stderr: $(cat "$scratch/stderr" 2>/dev/null) screen:
$(screen)"
}
tmux -L "$socket" new-session -d -s selftest -x 100 -y 30 -c "$scratch/project" \
	"${arch:+arch -$arch }'$binary' fake --agent-command \"$fake\" 2>'$scratch/stderr'; sleep 60"
wait_for 'for shortcuts'
tmux -L "$socket" send-keys -t selftest text Enter
wait_for 'Hello, world.'
tmux -L "$socket" send-keys -t selftest C-v
sleep 2
case "$(screen)" in *"cannot be read"*) die "$binary could not load the clipboard:
$(screen)" ;; esac
case "$(cat "$scratch/stderr")" in *dlopen* | *"Team IDs"*) die "$binary failed to load a library: $(cat "$scratch/stderr")" ;; esac
printf 'self-tested %s%s\n' "$binary" "${arch:+ under $arch}"
