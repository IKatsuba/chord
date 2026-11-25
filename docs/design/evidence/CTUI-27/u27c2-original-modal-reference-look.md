# Original modal arrival closes search

One original-only runtime reference, no retry. The existing fake `overlapask` scenario opens a call, waits `STEP_MS * 20`, then asks permission. `CHORD_FAKE_STEP_MS=500` gives a bounded 10-second setup interval.

At 120×40, submit `alpha reference` and let its canned response end. Submit `overlapask`; during its initial call, leave `saved modal`, open Ctrl+R and query `alpha`. The before capture shows the matched `alpha reference` editor and search query/rule. At approximately 11 seconds, permission arrives: query/rule are gone, editor shows the saved draft, and permission’s `Esc to reject` cue and bottom border remain intact. Resize to 80×24: same state. Reject permission once: search does not return and the saved draft remains. All before/arrival/post-reject text and ANSI frames are retained.

The runtime result is supported by original `../chord/src/ui/app/state.ts` 1105–1116 (transcript fold closes search for asksPerson while not heldBack) and 620–628 (actual attend of a held request closes search). The distinction matters: this is original state lifecycle, not an invented overlay priority, blanket held-request cancellation or new geometry API. Main authorized the corresponding narrow port lifecycle repair.

This evidence/design settlement is not a port fix pass. The separately retained exact-d374 fixture has search furniture covering permission cue/border; its fix must be handed back by developer and checked separately. Key routing in that initial fixture already gives Enter to permission and leaves search active afterwards; visual/state lifecycle is the finding.

Fresh isolated original state/config/cwd and a synthetic notes file only. Bun production source and original fake; no original edits, real model, real agent, real shell, clipboard or source archive. Original app/fake/tmux quit cooperatively and the isolated root was removed. Header cwd is sanitized after capture and is not a width oracle.
