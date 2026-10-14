#!/bin/bash
# The release, on the owner's Mac, not in CI: build every binary, sign the
# macOS ones and the native libraries they embed, self-test, notarise, pack,
# verify the installed copies, and publish to npm.
#   scripts/release.sh            everything, publishing last
#   scripts/release.sh --dry-run  everything up to `npm publish`, then stop;
#                                 it still submits to Apple for notarisation
# Each step is checked before the next and dies with what it read; the steps
# are scripts under scripts/release/, runnable on their own. The last line
# printed is the published version, printed only when everything held.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
steps="$root/scripts/release"
# shellcheck source=release/lib.sh
. "$steps/lib.sh"

dry_run=false
case "${1:-}" in
"") ;;
--dry-run) dry_run=true ;;
*) die "usage: scripts/release.sh [--dry-run]" ;;
esac
cd "$root"
out="$root/dist/release"

publish_missing() {
	for name in "${PACKAGES[@]}"; do
		if published "$name" "$version"; then
			printf 'already published: @chorded/%s@%s\n' "$name" "$version"
			continue
		fi
		tarball="$out/tgz/chorded-$name-$version.tgz"
		[ -f "$tarball" ] || die "no $tarball to publish; nothing of this run is left to resume from"
		npm publish --access public "$tarball" || die "npm publish of $tarball failed"
	done
}

# 1–3. A clean tree, the version not yet published (or a run stopped between
#      publishes to resume), and the owner's npm login: they only read, and
#      scripts/release/preflight.sh runs them on its own as well.
if $dry_run; then
	preflight=$("$steps/preflight.sh" --dry-run)
else
	preflight=$("$steps/preflight.sh")
fi
read -r mode version <<<"$preflight"
[ -n "${version:-}" ] || die "preflight gave no version: $preflight"
# A run stopped between publishes is finished from the packages it built,
# without building again.
if [ "$mode" = resume ]; then
	printf 'resuming %s: a platform package is published, @chorded/chord is not\n' "$version"
	publish_missing
	printf '%s\n' "$version"
	exit 0
fi

# 4. The signing identity, found before the build.
identity >/dev/null

# 5. Dependencies as locked, and every check.
bun install --frozen-lockfile || die "bun install --frozen-lockfile failed"
bun run check || die "bun run check failed"

# 6. Every platform's native packages, the macOS libraries signed by the
#    team, then every binary, built on this arm64 Mac.
bun install --frozen-lockfile --os='*' --cpu='*' || die "installing every platform's packages failed"
"$steps/natives.sh"
bun run compile --all || die "compile --all failed"
check_kind() {
	kind=$(file "dist/$1/chord")
	case "$kind" in *"$2"*) ;; *) die "dist/$1/chord is $kind" ;; esac
}
check_kind bun-darwin-arm64 'Mach-O 64-bit executable arm64'
check_kind bun-darwin-x64 'Mach-O 64-bit executable x86_64'
check_kind bun-linux-arm64 'ELF 64-bit LSB executable, ARM aarch64'
check_kind bun-linux-x64 'ELF 64-bit LSB executable, x86-64'

# 7. The macOS binaries signed, verified, entitlements compared, each
#    self-tested.
"$steps/sign.sh" dist/bun-darwin-arm64/chord dist/bun-darwin-x64/chord
"$steps/selftest.sh" dist/bun-darwin-arm64/chord
"$steps/selftest.sh" dist/bun-darwin-x64/chord x86_64

# 8. One zip notarised; both must satisfy codesign's =notarized requirement.
"$steps/notarise.sh" "$out" dist/bun-darwin-arm64/chord dist/bun-darwin-x64/chord

# 9. The packages, packed, installed from the tarballs, verified, self-tested.
"$steps/packages.sh" "$out/packages"
mkdir -p "$out/tgz"
cp "$out/packages/tgz/"*.tgz "$out/tgz/"

# 10. A dry run stops here.
if $dry_run; then
	printf 'dry run: @chorded/chord %s is packed in %s, not published\n' "$version" "$out/tgz"
	exit 0
fi

# 11. The platform packages, then the main one. Never unpublish.
publish_missing
printf '%s\n' "$version"
