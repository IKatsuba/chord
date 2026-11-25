# Original-only bounded search acceptance reference

Requested flow: establish one history match at 80×24; Ctrl+R/query, resize once to 8×3, Enter once, restore 80×24. Then perform one normal-size control. Original source only; no port/C2 source inspected or run.

The sole submitted synthetic prompt was `needle recalled`, followed by the fake’s canned reply. Leave `saved draft`, open Ctrl+R and query `needle`. Normal capture shows the query and matched full prompt. At 8×3, the captured frame contains a blank row and the rounded prompt top/bottom borders: **neither query text nor the matched editor is visible** in this observed geometry. Do not claim the requested query-visible condition was established.

Enter at 8×3 closes search. After restoring 80×24, the prompt contains `needle recalled`, the search overlay is gone, and the transcript still contains exactly one submitted user prompt and its original answer. No send occurred. Clear that recalled draft, leave `normal control`, repeat Ctrl+R/query `needle` at 80×24 and Enter once: same recall/closed-search/no-send result. No other tiny-size probe or retry was run.

Original `../chord/src/ui/app/keys.ts` accept_search branch (858–872) closes search and recalls the matched text without an explicit matched-editor visibility guard. This source fact and the bounded runtime observation support acceptance even with the editor clipped. They do not establish an arbitrary port/query visibility rule, new geometry API, product defect or port implementation pass.

Launch used the original Bun production source CLI with the original fake, step 25 ms and fresh isolated XDG state/config/cwd. Captures are text and ANSI. Only the synthetic cwd header is sanitized after capture; this is not a width oracle. All owned apps/fake/tmux processes quit cooperatively and the isolated roots were deleted. No real model/agent, clipboard, AOT or performance claim.

Main subsequently settled the port contract explicitly: at any positive terminal size, query-owned Enter/Tab recalls and closes search without sending even when both query and readonly editor are clipped; 0×0 is inert. Hidden editor editing/send remain excluded. This is the owner decision, not an inferred new visibility or geometry API. The reference did not execute 0×0 or a port implementation.
