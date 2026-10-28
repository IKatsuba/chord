# Interface rules

- Split by feature, one folder each (`docs/decisions.md`, "The interface split by feature").
- Components only draw state and dispatch; pure logic is a snake_case `.ts` beside its feature's PascalCase `.tsx`.
- No `index.ts`: an import names its file.
- A feature's `state.ts` knows only its slice and imports nothing from `app/`.
- `app/App.tsx` defines no component but the window and routes every key through the pure `app/keys.ts`.
- Draw on OpenTUI's `box`/`text`/`span` through `theme/text.ts` and hear keys through `app/input.ts`'s `usePress`, with no layer between (`docs/decisions.md`, "OpenTUI part 8b").
- `app/renderer.tsx` wraps the window in `app/Crash.tsx`'s crash boundary.
  Any key gives the terminal back, writes the stack to stderr and exits 1.
  Install `app/caught.ts`'s filter before `createRoot`: it drops React's
  single log of the caught error and passes every other console error on.
- A string an agent sent goes through `theme/Ansi.tsx` unless something cleaned it: OpenTUI's text draws escape bytes as text.
- Choose colours by role from `theme/theme.ts`.
- Keep transient completions (including `@@`), history search and help above
  the prompt; status/leader hints, agents and background summary stay below.
  Ordinary same-draft open/close comparisons keep prompt borders and
  permanent rows fixed. Only the demonstrated cramped 80×24→80×25
  resize/menu-close shift is accepted (see `docs/design/CHD-525.md`);
  it permits no arbitrary shifts. At zero visible completion rows, suppress
  paint, navigation and acceptance, including pending picks; preserve normal
  draft submission and restore completion when room returns.
- Tab sends the oldest personal plain queued row into the running turn; leave
  the draft untouched and skip agent messages and sent/held rows. Esc leaves
  a row while its send is pending. Refusals restore its original queue place.
- Transcript blocks use `transcript/gap.ts`'s `useGap`: margins in the
  transcript, spacer rows in background logs. OpenTUI #1739 omits margins
  from a one-row scrollbox's height; `tests/ui/transcript/gap_test.tsx`
  pins it so the spacer can go once the pinned library counts them.
- Direct team runs and picker Enter keep saved composition with no extra main
  turn. Existing team instructions and MCP tools drive optional selection;
  never inject a selection prompt or add an enabling team field.
- Resource reads belong to the caller and request cancellation; never retain
  readers between calls. Window exit waits for their process-group cleanup.
- Resource reports show per-provider windows or unavailable reasons. Older
  answer formats show only the older-format notice. Recorded Team receipts
  keep historical reads and warnings; no read means no Read line. Their
  current state stays unknown; genuine ACP
  linkage replaces the Chord-owned fallback rather than duplicating it.
