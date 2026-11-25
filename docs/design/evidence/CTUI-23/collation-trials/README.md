# Locale collation package trials

Developer handed these exact package-trial sources, manifests, locks and
compile logs for retention. No repository dependency was added. Designer
copied the artifacts and independently ran localized-sorter/probe and the
original Bun locale script; both runs exited0. Compile trials were not
repeated by designer. Generated absolute path is sanitized to Generated: probe.

intl4x1.0.1 (transitive icu4x2.3.2) and icu_kit0.2.0 reject dart compile exe
because they require build hooks. localized_sorter0.1.2 compiles but differs
from original localeCompare. Pair signs in en-US:

| Pair | Original Bun | localized_sorter |
| --- | --- | --- |
| a / A | -1 | 0 |
| Z / z | 1 | 0 |
| _private / -x | -1 | 1 |

Original default locale is en-US. Full four-locale sort outputs are retained
in original-locale-probe.jsonl and localized-sorter/run.jsonl. The localized
package uses underscore locale identifiers per its API; original/ICU use
BCP47. Reproduce original from its checkout with bun --eval and the contents
of original-locale-probe.js. Reproduce each package in an isolated Dart
package using its pubspec/lock and probe.dart.txt copied as probe.dart, then dart
compile exe. The .txt suffix preserves exact tried source as evidence
without making it part of repository Dart analysis/formatting.

Main approved the casefold/original-codepoint fallback and its documented
non-ASCII limitation; the lead owns that decisions entry. These artifacts
show why the packages did not fit, not locale parity for the fallback.
