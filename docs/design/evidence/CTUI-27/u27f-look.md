# U27F API and live look

Source: `85bccdc02b64ecbd72712c17c1acf17f821c6287`; approved API: `156d729`.

The nullable `TextArea.textSpanBuilder(context, text)` reads naturally beside `style`, and defaults to existing editing. It styles exact normalized controller text. Runtime rejection belongs to the normal outer build-error boundary before editor handlers; current constrained rows remain authoritative. The published contract covers first-UTF16-unit grapheme style, existing row sanitation, current plain fallback on stale decoration, and callback purity. No API finding.

At 120×40 and 80×24, decorated and null-builder captures have byte-identical text and equal reported cursor coordinates. At 80 columns, inverse `needle crosses` continues across `needle cro` / `sses`; the two-cell gutter remains aligned. Literal Unicode editing, single-grapheme undo/redo and bracketed multiline paste work. One undo restores the pre-paste screen at both sizes. Light, plain and 24×10 narrow runs remain legible. KeyHelp advertises all three fixture actions; its narrow middle cut preserves the outer keys.

Initial zero-room finding: the editor correctly paints no rows, but the status says `rows 1–0 of 2` / `rows 1–0 of 3`. The initial `u27f-zero-*` captures retain this inverted range. Fixture-only fix `b4b82cde12266f1979611bf38cc9cdc1fc831899` changes only the summary plus its fixture regression. The `u27f-fixed-zero-*` captures now show `rows 0 of 2` / `rows 0 of 3`; light/decoration toggles and plain zero-room remain correct. Required-size fixed positive captures equal the initial text captures byte-for-byte. Finding closed; API/live gate passes for source `85bccdc` plus fixture fix `b4b82cd`, before separate review/test gates.

`u27f-aot.json` is the developer-handed report, copied byte-for-byte (SHA256 `1a8c3aeaf9eea97e5dd19f3b79dac8dee62466c16176b069830ec3aa8133e52b`). Its three source hashes match the handed commit. It records six JIT and six AOT checks, assertions disabled and runtime rejection active. Commands and limits remain in the original JSON. This is retained developer evidence, not an independent designer rerun or performance result. The developer reports 193 reached tests; reviewer/tester gates remain separate.

No original comparison applies to this independent framework fixture. No port consumer was inspected. TextArea selection eligibility, invalid-result recovery and adversarial freshness are covered by the handed test groups; this live look does not claim to reproduce them. Tmux coordinates do not prove physical cursor shape or unfocused appearance. The exercised theme paths use the same dim/inverse attributes here; no distinct RGB-color claim is made.

All designer fixtures quit cooperatively. No owned tmux session, paste buffer, source archive, fake agent or isolated state remains.
