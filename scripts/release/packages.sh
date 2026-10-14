#!/bin/bash
# Lays out the five npm packages from the signed binaries in dist/
# (scripts/npm.ts), packs them, installs the tarballs in scratch projects,
# and checks the installed copies as a user gets them: the same bytes as
# built, a macOS one still verifying and not quarantined, and the arm64 one
# self-tested through the shim, the x64 one under Rosetta.
#   scripts/release/packages.sh OUT_DIR
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
root=$(cd "$here/../.." && pwd)

out=${1:?usage: scripts/release/packages.sh OUT_DIR}
rm -rf "$out"
mkdir -p "$out/tgz"
(cd "$root" && bun scripts/npm.ts >/dev/null) || die "laying out npm/ failed"
for name in "${PACKAGES[@]}"; do
	(cd "$root/npm/$name" && npm pack --pack-destination "$out/tgz" >/dev/null) ||
		die "npm pack of $name failed"
done
version=$(plutil -extract version raw "$root/package.json")
tgz() { printf '%s/tgz/chorded-%s-%s.tgz' "$out" "$1" "$version"; }
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
(cd "$scratch" && npm init -y >/dev/null && npm install --no-audit --no-fund \
	"$(tgz chord)" "$(tgz chord-darwin-arm64)" >/dev/null) ||
	die "installing the tarballs failed"
# Every other platform package goes into a scratch project of its own; npm
# refuses one for another platform unless forced past its os and cpu
# check, which changes nothing in it.
for name in chord-darwin-x64 chord-linux-arm64 chord-linux-x64; do
	mkdir "$scratch/$name"
	(cd "$scratch/$name" && npm init -y >/dev/null && npm install --no-audit --no-fund --force \
		"$(tgz "$name")" >/dev/null 2>&1) ||
		die "installing the $name tarball failed"
done
check_installed() {
	local installed=$1 built=$2
	cmp -s "$installed" "$built" || die "the installed $installed differs from $built"
	case "$installed" in *darwin*)
		codesign --verify --strict "$installed" || die "the installed $installed does not verify"
		case "$(xattr "$installed")" in *com.apple.quarantine*) die "npm quarantined $installed" ;; esac
		;;
	esac
}
check_installed "$scratch/node_modules/@chorded/chord-darwin-arm64/bin/chord" "$root/dist/bun-darwin-arm64/chord"
for name in chord-darwin-x64 chord-linux-arm64 chord-linux-x64; do
	check_installed "$scratch/$name/node_modules/@chorded/$name/bin/chord" "$root/dist/bun-${name#chord-}/chord"
done
"$here/selftest.sh" "$scratch/node_modules/.bin/chord"
"$here/selftest.sh" "$scratch/chord-darwin-x64/node_modules/@chorded/chord-darwin-x64/bin/chord" x86_64
printf 'packed %s\n' "$out/tgz"
