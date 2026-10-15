# Session and ACP rules

These rules also cover `src/acp/`.

- Every session's traffic runs through the enricher chain (`enrich.ts`, `enrichers.ts`) on the transport's relay; state, record, window and `-p` read only what it leaves.
- Enrichers are pure, with ACP's shape on both sides; name what chord filled under `_meta`'s `chord/filled`.
- `transcript/` is a pure reducer, one module per kind of update.
- Records (`record.ts`, `windows.ts`) are stored formats: records written before a change must still read back.
- The window's sessions are recorded; `-p`'s are not.
- This layer is below the interface and shared with `-p`: nothing here or in `src/acp/` imports from `src/ui/`.
