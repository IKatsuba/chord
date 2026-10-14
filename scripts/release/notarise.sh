#!/bin/bash
# Notarises the signed macOS chords as one zip with the team-wide App Store
# Connect key in the login keychain, keeps Apple's log beside the build
# whatever the verdict, stops unless Accepted, then checks that each binary
# is one Apple's log lists a ticket for, by its cdhash, so what is packed is
# what was notarised. Not codesign's =notarized requirement: it asks this
# Mac's view of Apple's ticket service, which can say no for minutes after
# Apple accepted and the ticket is online (seen at 0.54.0, about 8 minutes).
# spctl is no check either: `spctl -a -t exec` rejects any bare Mach-O as
# "does not seem to be an app". A bare Mach-O cannot be stapled; Gatekeeper
# looks the ticket up online on a quarantined copy.
#   scripts/release/notarise.sh OUT_DIR BINARY...
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

out=${1:?usage: scripts/release/notarise.sh OUT_DIR BINARY...}
shift
[ "$#" -gt 0 ] || die "usage: scripts/release/notarise.sh OUT_DIR BINARY..."
mkdir -p "$out"
zip="$out/chord.zip"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
mkdir "$staging/chord"
for binary in "$@"; do
	cp "$binary" "$staging/chord/$(basename "$(dirname "$binary")")-chord"
done
ditto -c -k --norsrc --noextattr --keepParent "$staging/chord" "$zip"
# The result is kept, and Apple's log fetched, before any verdict is judged.
# The JSON result is stdout alone; notarytool's diagnostics are kept apart.
submitted=0
result=$(xcrun notarytool submit "$zip" --keychain-profile roost-notary --wait --output-format json 2>"$out/notarytool-submit.stderr") ||
	submitted=$?
printf '%s\n' "$result" >"$out/notarytool.json"
submission=$(printf '%s' "$result" | plutil -extract id raw - 2>/dev/null || true)
status=$(printf '%s' "$result" | plutil -extract status raw - 2>/dev/null || true)
if [ -n "$submission" ]; then
	for attempt in 1 2 3; do
		if fetched=$(xcrun notarytool log "$submission" --keychain-profile roost-notary "$out/notarytool-log.json" 2>&1); then
			break
		fi
		[ "$attempt" = 3 ] && die "the notarisation log of $submission could not be fetched: $fetched"
		sleep 10
	done
fi
[ "$submitted" = 0 ] || die "notarytool submit exited $submitted: $result $(cat "$out/notarytool-submit.stderr")"
[ "$status" = Accepted ] || die "notarisation of $zip ended $status: $result"
tickets=$(plutil -extract ticketContents json -o - "$out/notarytool-log.json" | grep -o '"cdhash":"[0-9a-f]*"' || true)
for binary in "$@"; do
	cdhash=$(codesign -dvvv "$binary" 2>&1 | sed -n 's/^CDHash=//p')
	[ -n "$cdhash" ] || die "the cdhash of $binary could not be read"
	case "$tickets" in *"\"cdhash\":\"$cdhash\""*) ;; *) die "Apple's log has no ticket for $binary (cdhash $cdhash); it lists: $tickets" ;; esac
	printf 'notarised %s: %s\n' "$binary" "$cdhash"
done
