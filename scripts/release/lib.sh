# shellcheck shell=bash
# Shared by scripts/release.sh and its steps: every check dies with what it
# read.

die() {
	printf 'release: %s\n' "$*" >&2
	exit 1
}

# The packages, in the order they are published: the platform packages,
# then the main one, whose exact-version optionalDependencies must resolve.
PACKAGES=(chord-darwin-arm64 chord-darwin-x64 chord-linux-arm64 chord-linux-x64 chord)

# The one Developer ID Application identity of the team, found by team in the
# login keychain so a renewed certificate is picked up; none or several stop.
TEAM=YQ8ZD2KZ3T
identity() {
	found=$(security find-identity -v -p codesigning "$HOME/Library/Keychains/login.keychain-db")
	matches=$(printf '%s\n' "$found" | grep "Developer ID Application: .*($TEAM)" || true)
	count=$(printf '%s' "$matches" | grep -c . || true)
	[ "$count" = 1 ] || die "expected one Developer ID Application identity of team $TEAM, found $count; security find-identity said:
$found"
	printf '%s\n' "$matches" | sed -E 's/^ *[0-9]+\) ([0-9A-F]{40}) .*/\1/'
}

# Whether @chorded/NAME has VERSION on npm: yes, no (a 404, or the package
# without that version), or a failure to ask, which stops the release.
published() {
	local said errors
	errors=$(mktemp)
	# Only stdout is the answer; npm's warnings go to stderr.
	if said=$(npm view "@chorded/$1@$2" version 2>"$errors"); then
		rm -f "$errors"
		[ "$said" = "$2" ] && return 0
		[ -z "$said" ] && return 1
		die "npm view @chorded/$1@$2 answered \"$said\""
	fi
	local diagnostics
	diagnostics=$(cat "$errors")
	rm -f "$errors"
	case "$diagnostics" in *"code E404"*) return 1 ;; esac
	die "npm view @chorded/$1@$2 failed: $diagnostics"
}
