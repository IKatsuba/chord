# U14 reviewer finding 1: leader-line visual pass

Developer fix127eccf passes the designer look. Exact commit exported under
ignored build/ with copied root/port package metadata, command `dart run
example/chord/tool/dev.dart chord --fake`, CHORD_SOURCE selecting ../chord.
Original577b58167 runs with `bun dev chord --fake --qa ctui21-leader`.
No WIP source entered the export. Captures are plain/ANSI at each width,
with original/port comparisons; directory text is neutralized.

120x40 and80x24 keep full M1 hint:
`ctrl+x …  a the one that waits · esc never mind`.
40x12 uses `ctrl+x …  a waits`, with no partial description or middle dots
inserted inside a word.20x12 and12x12 drop the complete a item, retaining
`ctrl+x …`. No right facts appear while pending. ANSI captures show held
keys and follow-up key names plain, descriptions/separators dim. Escape
between width checks clears the pending state; empty Ctrl+D exits both.

Original's extra b item is the already approved M1 omission. At12 columns,
original displays `ct...…` despite the full held prefix fitting the port's
8 status cells. Main chose A: keep the port's clipping-only held prefix,
recorded in section5. This difference does not block the fix or U14.

No source audit, additional tests, whole suite or AOT run. Both owned
sessions were confirmed closed and the exact-commit export removed.
