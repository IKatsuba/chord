# Original numbered picker wheel ownership

Original head 577b58167672e12c999aeaf4eed2a1a988513dc2. Owned session ran
`bun dev chord --fake --qa designer-picker-wheel`; send `markdown`, Enter
separately, wait until complete, then `/model`, Enter separately. This fake
scenario never contacts a model. A typed `codexmodels` was cleared without
submission after reading that it queries another runtime; it was never run.

At 120x40 the model list fits. Inject SGR up `ESC[<64;15;29M` over choice 1:
the transcript's top visible code row moves one line while picker choices
and selection remain fixed. Before/up captures retain this result.

Resize to 80x14, close model picker, open `/effort`. Three choices now
exceed the single visible choice row: Medium is shown at row 5, with an
upper edge marker and `… +2 more`. Inject down `ESC[<65;15;5M`. The complete
plain screen before/after is byte-identical. This list does not take its own
wheel viewport steps. The layer covers the transcript at this size, so its
underlying scroll movement is not claimed from this capture alone.

Resize to 80x24, inject up `ESC[<64;15;15M` over the visible Medium choice.
The transcript scrolls; the effort choices remain fixed. Capture pairs are
`original-picker-wheel-before/up-80x24` and `before/up-120x40`, plus
`before/down-80x14`, each txt and ansi. Default theme only is reached.

Source confirms the behavior: src/ui/pickers/Pickers.tsx PickerList renders
a plain box at lines1136-1162; Body at190-233 only clips. There is no
scrollbox or wheel listener in that file. App.tsx root useMouse dispatches
wheeled steps to transcript. Numbered picker overflow therefore does not
justify adding a generic framework Picker wheel consumer. Completion's
CommandList scrollbox is a distinct case.

Esc closed the picker, Ctrl+D exited the owned original normally; session
and process cleanup checked. This is original discovery only, not a U3 port
implementation gate.
