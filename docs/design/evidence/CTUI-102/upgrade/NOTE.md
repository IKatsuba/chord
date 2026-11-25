# chord upgrade (U2, CTUI-131): help and usage error

Captured with tmux `capture-pane -p` at 120x40 and 80x24, the port from a clean
export of commit 0d2684df, the original from `../chord` (cliffy, version
0.71.0). Help and usage errors only: nothing here reads the npm registry or
runs a package manager. The upgrade's own lines (already latest, not found,
success, -v, failures, the self-built and official refusals) are pinned in
`example/chord/test/cli_upgrade_test.dart`, which passed (25 tests) on the same
export. The shell's end marker was taken out of the command lines.

- `port-help-*`: `chord --help` lists `upgrade` after `acp`, the original's
  words; the original lists it there too (`original-help-*`).
- `port-upgrade-help-*`: the design's text exactly; args' layout with the
  original's words (Q370 departure: layout, `(defaults to "latest")`).
- `port-upgrade-V-*`: help on stdout, `error: Unknown option "-V". Did you
  mean option "-v"?`, exit 2, as the original.
- At 80 columns the 85-column `--force` line is wrapped by the terminal, as
  the design says and as `chord agents --help` already wraps; cliffy wraps
  it itself.

## U4 (CTUI-135): upgrade through Homebrew

Commit b7691a23 adds no help text: `upgrade --help` and `upgrade -V`, captured
again at both sizes from it, are byte-identical to the captures above. The
Homebrew lines (upgrade, reinstall with -f, already latest, unreadable
listing, brew failing or missing, -v, the --version and -l refusals) and the
self-built refusal naming Homebrew and the release archive are reachable only
from a Homebrew-installed chord; they were read in
`example/chord/test/upgrade_brew_test.dart` and `cli_upgrade_test.dart`
against design U4 word for word, and those tests with `upgrade_test.dart`
passed (84 tests). The original has no Homebrew route; these lines are the
design's.
