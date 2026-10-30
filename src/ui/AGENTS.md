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
- Float transient completions (including `@@`), history search, help and
  command pickers over the transcript above the prompt (CHD-545). Keep the
  transcript's height, scroll and following state; opening and closing must
  leave the prompt, its gap row and permanent rows fixed and uncovered.
  Frameless lists have a dim top rule; framed pickers keep only their frame.
  They may reach the window's top. Short pickers keep title and hint or
  choices, cutting the body from the bottom with one gap before the hint.
  A picker with no visible choice names only keys that act: its Esc action
  and `/resume`'s scope key; disable navigation and acceptance.
  At zero visible completion rows, suppress paint, navigation and acceptance,
  including pending picks; preserve normal draft submission and restore
  completion when room returns.
- Tab sends the oldest personal plain queued row into the running turn; leave
  the draft untouched and skip agent messages and sent/held rows. Esc leaves
  a row while its send is pending. Refusals restore its original queue place.
- Transcript blocks use `transcript/gap.ts`'s `useGap`: margins in the
  transcript, spacer rows in background logs. OpenTUI #1739 omits margins
  from a one-row scrollbox's height; `tests/ui/transcript/gap_test.tsx`
  pins it so the spacer can go once the pinned library counts them.
- Forks are top level, after main's tree; main's clear leaves them open.
  Closing a fork closes its tasks and monitors without notifying a parent.
  Forks cannot use open_agent, run_team, propose_team, settings, close_agent
  or clear_agent, or message main; main cannot message them.
- Clearing a picked child or fork preserves its identity and long-lived
  children. Withdraw old requests, close tasks, stop monitors and block late
  delivery. Restore personal queued prompts with images; report other dropped
  messages. Only a person's clear notifies the parent. The fresh session waits
  for a message, which carries its team and role instructions once.
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
