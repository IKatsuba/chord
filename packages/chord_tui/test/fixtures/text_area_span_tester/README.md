Independent framework TextArea span validation

Production 85bccdc02b64ecbd72712c17c1acf17f821c6287; fixture-only correction b4b82cde12266f1979611bf38cc9cdc1fc831899. The immutable snapshot used the latter commit; the three production/probe files were byte-identical to the production commit.

The reached 12-file command passed 199 tests; snapshot analysis was clean and format checked 703 files without changes. Added tests cover every UTF-16 boundary through wide, emoji and combining graphemes; 1,000 captured-style changes; focus, undo/redo, invalid rebuild and pre-paint input rejection.

Independent nice-19 JIT and AOT probes each passed six runtime checks with assertions disabled. Raw JSON/stdout/stderr and exact commands/hashes are retained in the manifest. This is validation of runtime rejection, not a performance measurement or a port consumer pass.

Owned live tmux checks at 120x40 and 80x24 preserved text and logical cursor when decoration toggled; undo/redo restored the edit. Zero-room rendering hid editor rows and cursor at both sizes, including decoration/theme toggles and resize. Total wrapped rows correctly changed from three to two with width. Captures prove logical terminal output, not physical focused/unfocused cursor appearance or theme color fidelity.

All owned processes, sessions, snapshot and binary were removed. No product finding remains.
