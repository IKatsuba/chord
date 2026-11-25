# C2 rich middle-CUT fix handback

Exact fix `3ed7182`, scoped to SearchLine’s existing `TextOverflow.middle` plus regressions; modal lifecycle fix remains separate. An immutable exact source archive and paired original/full-port fake CLI used equal one-prompt history, an unsent `cut draft`, and identical queries.

At 120×40 and 80×24, the formerly failing ASCII query now matches the original middle `...` prefix/suffix exactly. The long Unicode query likewise keeps the same CJK/emoji/combining-text suffix. ANSI captures retain the dim label, normal query/ellipsis and inverse final blank cursor; no forced extra cursor or preprojection was added. Short query rows remain correct at both sizes. Initial exact-d374 end-ellipsis failures remain separately retained.

Developer’s red/green logs are copied byte-exact and hashed in the manifest. They are developer headless evidence, not designer reruns. Raw formatter whitespace is retained deliberately. Main-approved query-paste correction4b027fd remains unchanged; no exact-runtime paste parity is asserted. This handback closes only the CUT finding, not the held modal lifecycle case, all-C2 source review, AOT or final combined testing.

All paired apps/fakes/tmux quit cooperatively; exact archive and isolated state/config/cwd were removed. No original edits, real model/agent, shell command or clipboard. Header cwd is sanitized after capture, not relaid out; no header width oracle. Existing version/header-help/default-color reset differences remain outside this query-row comparison.

Only the two raw developer logs are exempt from whitespace cleanup, preserving exact hashes/formatter output. Other capture files retain terminal blank rows at EOF.
