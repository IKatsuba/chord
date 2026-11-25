# U13 fixed armed-quit visual look

Fix427d6f7 passes the designer recheck. Exact signed commit exported under
ignored build/, with copied package metadata only. Root/port package roots
were verified relative to the export, so uncommitted U14 work was excluded.
Command inside that export: `dart run example/chord/tool/dev.dart chord
--fake`, with CHORD_SOURCE selecting ../chord. No source edits or pub get.

At120x40 and80x24, first Ctrl+C shows only `Press ctrl+c again to quit`.
All model/effort/context facts disappear, matching the original577b58167
idle/armed baseline captured at both sizes. The original and fixed port
are shown side by side in u13-fix-comparison-armed-*.txt. Version, directory
and the original /help alias retain their previously documented differences.

After waiting beyond two seconds the warning clears and facts return at
both sizes. Two Ctrl+C presses before expiry then exit. Original evidence
in u13-finding.md remains as the pre-fix symptom; this recheck resolves it.
No source audit, extra tests, whole suite, AOT or compiled shutdown claim.
The owned tmux session was confirmed closed and its exact-commit export
removed. No fixture process remained to keep the export in use.
