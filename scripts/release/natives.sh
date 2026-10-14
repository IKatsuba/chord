#!/bin/bash
# Signs, with the team's Developer ID, every macOS native library in
# node_modules that `bun build --compile` may embed: OpenTUI's renderer and
# the clipboard's addon. A compiled chord writes an embedded library to a
# temporary file and loads it from there, and the hardened runtime loads only
# a library signed by the binary's own team, so OpenTUI's and the
# clipboard's own signatures would leave the window unable to start. Only the
# signature changes; the release's self-test opens the window and reads the
# clipboard on each signed binary, which a library left out fails.
#   scripts/release/natives.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
cd "$here/../.."

id=$(identity)
found=0
while IFS= read -r -d '' library; do
	# Signed as a copy and renamed over the original, so a chord running from
	# source keeps the library it mapped rather than one changed under it.
	signed="$library.signing"
	cp -p "$library" "$signed"
	codesign --force --sign "$id" --timestamp "$signed" ||
		die "codesign failed for $library"
	codesign --verify --strict "$signed" || die "$library does not verify"
	mv -f "$signed" "$library"
	printf 'signed %s\n' "$library"
	found=$((found + 1))
done < <(find node_modules -path '*darwin*' \( -name '*.dylib' -o -name '*.node' \) -type f -print0)
[ "$found" -gt 0 ] || die "no macOS native library found under node_modules; was bun install --os='*' --cpu='*' run?"
