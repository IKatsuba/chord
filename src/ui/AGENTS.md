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
