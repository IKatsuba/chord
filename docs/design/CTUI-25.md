# CTUI-25: bash mode and code commands in the prompt

This is the build contract for CTUI-25, following host-only CTUI-51 on the
shared task branch. No implementation acceptance is claimed here.

## Authority and scope

Original: `577b58167672e12c999aeaf4eed2a1a988513dc2`, read-only `../chord`:
`src/ui/prompt/bash.ts`, `src/shell.ts`, `src/ui/app/{keys,state,terminal}.ts`,
`src/ui/transcript/{markdown,code_pick}.ts`, `docs/guide.md` and
`docs/design/CHD-394.md`. Current source wins over older layout sketches.
Keep [CTUI-48](CTUI-48.md)'s descriptor identity, shared source shaping,
selection exclusions, parser closure metadata and two-pass query contract.
This slice adds bash commands and their held context, not monitors, a terminal
emulator, interactive stdin or a new Markdown parser.

## Framework API

The framework draws an explicitly requested action and returns the current
code descriptor. It never chooses a shell language, strips prompts or executes.
The small API choice below was settled with developer before implementation.

```dart
final source = SelectionSource.markdown(
  id: entry.identity,
  revision: revision,
  text: reply,
  copyCodeBlocks: true,
  runCodeBlockLanguages: const {'sh', 'bash'}, // application policy
);

Markdown.fromSelectionSource(
  source,
  selectedCodeBlock: picked,
  onCopyCodeBlock: copyBlock,
  onRunCodeBlock: putBlockInPrompt,
);

Markdown(
  reply,
  runCodeBlockLanguages: const {'sh', 'bash'},
  onRunCodeBlock: putBlockInPrompt,
);
```

Add `Set<String> runCodeBlockLanguages = const {}` to
`SelectionSource.markdown` and ordinary `Markdown`; add
`void Function(MarkdownCodeBlock)? onRunCodeBlock` to both Markdown
constructors. `Markdown.fromSelectionSource` takes an optional nullable
`Set<String>? runCodeBlockLanguages`: omitted/null inherits the source;
an explicit value must equal it. The callback is present exactly when the
effective set is nonempty; mismatches throw `ArgumentError`, including a
bound source that reserves run controls without the callback. Bound factories
validate at construction. Ordinary Markdown keeps its established const
constructor and validates when deriving its source during build. Copy's existing
independent presence/geometry validation remains unchanged. Run-only generic
controls are supported; the port supplies both callbacks.

SelectionSource factories immediately defensively freeze the set; source
getters are unmodifiable. Ordinary Markdown captures an immutable set when
deriving its source during build, preserving const compatibility. The caller
must treat widget configuration as read-only; there is no widget construction-
time or pre-mount caller-mutation isolation promise. Later caller mutation
cannot alter an already-derived source. Replacement widget configuration
derives a replacement source/revision using value-based geometry comparison. Equality is
unordered exact string value equality, case-sensitive, with no aliases,
trimming or normalization. Match the existing descriptor's language exactly.
There is no built-in `sh`/`bash` set or shaping-time application predicate.
Preserve `MarkdownCodeBlock` fields, complete text, opaque ID and revision.
No run-command string is added to its descriptor.

The language set is source geometry, including on offscreen sources: controls
can grow a short box. Changing the effective set needs a replacement source
revision and the list's geometry/itemVersion invalidation, as with
`copyCodeBlocks`; callback replacement alone does not change geometry.
Ordinary Markdown derives its immutable source from these inputs. Selection,
code queries/reveal and painting share that same shape, never a port row-count
or min-width workaround.

Closed ordinary matching code gets `[run]`; open fences and quoted code have
no run control. Indented/unlabelled code has no matching language. Quoted
closed descriptors remain available to the application's keyboard action.
The framework never installs `r`: an app binds every action through Actions.

## Controls and input

Use CTUI-48's text-colour buttons, dim frame, accent picked frame/label and
bold picked buttons; plain uses foreground and bold. No hover state.

```text
┌─ sh ─[copy]─[run]─┐
│ printf 'ready'     │
└───────────────────┘
```

Minimum widths with both controls: sh 21 cells, bash 23. More generally use
the original border formula with actual label/button widths; run-only is the
same formula for its single button. Grow within the available column first.
If it cannot fit, omit run before copy, then apply existing label clipping.
Hidden controls retain keyboard availability. Preserve existing code insets,
wrapping and approved Markdown geometry.

A same-button primary down/up at the same cell and current ID/revision with no
motion invokes once. Press clears selection and captures; release outside,
reflow, changed kind/eligibility/revision, disposal or a text drag never
activates. Wheel does not activate; existing owner absorption remains intact.
Use current exposed geometry, with unresolved queries producing no action.

## Port policy and states

Only exact language `sh` or `bash` is runnable. Take the current descriptor's
whole text and remove `$ ` only at the start of each line. Preserve other
spaces, blank lines and line order. No extra trimming or shell parsing.
An empty draft becomes bash mode with that script and cursor at its end,
nothing executed. Even an empty runnable block follows this insertion policy.
A nonempty draft, including whitespace, remains untouched; show warning
`The prompt holds a draft · ctrl+c clears it` for 3000 ms. This works during
an agent turn too. Revalidate the picked/current descriptor before insertion.

`!` typed or pasted at the beginning of an empty normal draft enters bash
mode; the mode owns the prefix, so the editable text excludes that first `!`.
Inside a nonempty ordinary draft `!` stays ordinary text. History stores
`!` plus command and restores bash mode/cursor correctly. Backspace on an
empty bash draft leaves the mode. Preserve original Ctrl+C/Esc precedence,
selection-copy priority and pending-chord behavior.

Bash prompt border and first `!` gutter use the existing bash palette role;
continuation gutters retain original cells. Status says `! for bash mode`
when the higher-priority quit/closing/pick state does not replace it.
Empty or whitespace-only command does not submit. Enter while a shell is
already running does not start another. Enter otherwise records history,
returns to the ordinary empty prompt, then starts one script in the session
directory using the original shell defaults and process-group stop behavior.
Esc stops that session's active command according to existing action priority.

Output is stdout then stderr, sanitized by the existing context policy, with
stderr/error tone as original. The actual Shell widget calls shellView with expanded=true: show ALL output
lines wrapped, never the helper's ten-line collapsed cap or a fold action. Preserve original
running/stop hint, `(No output)`, stopped/error/exit notes and context
truncation. Finished runs are held for the next agent prompt, once, in order,
using the original context envelopes. Clearing/sending/queue/session behavior
must follow original state/reducer rules, not a widget-owned buffer.

## U25a shell row and source contract

Original `src/ui/transcript/Transcript.tsx:682` is the current screen authority;
there is no separate Shell.tsx. Keep its existing transcript gap policy.
Draw command after a bash-coloured `!` gutter; wrap the complete multiline
command in the remaining content width, without truncating the headline.
Output follows stdout then stderr, not arrival-interleaved. Each logical line
wraps at max(transcript width minus five gutter cells, 1). The first rendered
output row has `⎿`; following wrapped/output rows retain its blank gutter.
Blank output lines occupy a row. Stdout uses normal text; stderr uses error.
No border or code control is added.

Command and cleaned output are selectable, using shared immutable source
shaping and stable ShellEntry identity. Exclude `!`, `⎿`, gutters, gap rows,
placeholder padding, running/ending/no-output notes and other furniture.
A genuine blank output line contributes LF, not its drawn placeholder space.
Wrapping alone must not insert copied line breaks into a logical text line;
retain the original text-source class, not a Code/Markdown fence scanner.
Excluded note children retain real geometry through the existing selectable
flag; no fabricated separator or port-side row count. Code-like shell output
is plain text, with no Markdown code descriptors or run/copy controls.

The actual widget passes expanded=true to shellView regardless of verbose
state: twelve output lines remain twelve, plus their wraps. A running row
ends with `Running… (<bound stop key> to stop)` or `Running…` when unbound.
An empty successful result shows `(No output)`; successful nonempty output
has no ending note. Error is `Error: <reason>`; stopped is `Stopped by the
user`; nonzero code is `Exit code N`. Notes hang under `⎿` when there were
no output lines, otherwise a blank output gutter; failure notes use error,
other notes dim. Preserve original treatment of a signal-only end rather
than inventing a new status string.

U25a includes the typed run/model/reducer, plain injected coordinator at the
original terminal lifecycle split, separate typed/sent Conversation payloads,
and this actual transcript row/source. Coordinator actions remain tied to the
session/run that started them; stop/clear/close/dispose and late output/end
must not target a new session/run. No widget owns a child process. Held run IDs
belong to AppState. U25c later wires ! editing/history/held-context dispatch
and run controls/r/help; U25a must not advertise those unfinished actions.

Developer supplies a standalone shell screen fixture using immutable sample
runs and injected shell processes: running, successful empty/nonempty,
stdout+stderr, nonzero error/stopped, multiline/long wrap, blank lines,
truncated marker and more than ten lines. Include a real transcript window
fixture where reached to verify virtualization/source eligibility. The fixture
never starts an agent or a real shell implicitly; deterministic optional
bounded shell execution must be explicit in its named launch command.
Designer captures it at both sizes beside matched original harmless command
states, with ANSI for stderr/bash roles, and checks selection excludes notes
and furniture. Framework generic run controls are the next unit, before U25c.

## Keys and help

`ctrl+x b`, arrows, c and Esc keep CTUI-48 behavior. `r` inserts and ends pick
only for a runnable block. On another language it does nothing and leaves the
pick; its hint omits run. On a runnable block the full hint is:

```text
↑ ↓ another block · c copy · r put in the prompt · esc done
```

At both required sizes it fits with default keys. Narrow: try
`↑ ↓ block · c copy · r prompt · esc done`, then whole items in order that
fit, then bare cancel, then existing unbound wording. Use actual bound keys.
Shortcuts replace the staged copy-only clause with original order:

```text
ctrl + x b to pick a code block
c r to copy or put in the prompt
```

Bind/document all introduced bash/pick actions; do not add unavailable monitor
or vim controls. Natural catalog height owns overflow; do not trim rows to
force prior fitting. An overflowing panel owns wheel; underlying transcript
must remain still.

## Original evidence and proposed port

Captured using `bun dev chord --fake --qa ctui-designer-120`, in an owned
120x40 session resized to 80x24. Only bounded printf fixtures were executed;
the fake Markdown script was inserted by r and cleared without execution.
Matching `.ansi` files retain colour. Captures contain neutral QA paths only.

| State | Original 120x40 / 80x24 | Proposed port |
| --- | --- | --- |
| Bash draft | [120](evidence/CTUI-25/original-bash-draft-120x40.txt) / [80](evidence/CTUI-25/original-bash-draft-80x24.txt) | Same prompt mark, palette and status; existing port header/status differences stay. |
| Full output / failed exit | [120](evidence/CTUI-25/original-shell-full-120x40.txt) / [80](evidence/CTUI-25/original-shell-full-80x24.txt) | Twelve stdout lines, stderr, wrapped command and Exit code 3; no ten-line fold. |
| Completed command | [120](evidence/CTUI-25/original-shell-output-120x40.txt) / [80](evidence/CTUI-25/original-shell-output-80x24.txt) | Same command/output ordering and return to normal prompt. |
| Runnable code picked | [120](evidence/CTUI-25/original-picked-120x40.txt) / [80](evidence/CTUI-25/original-picked-80x24.txt) | Same full run hint; keep approved port code wrapping/insets. |
| r filled prompt | [120](evidence/CTUI-25/original-run-filled-120x40.txt) / [80](evidence/CTUI-25/original-run-filled-80x24.txt) | Same two-line script, end cursor, bash mark and no execution. |

The complete text captures are the whole-window mocks for the proposed state,
with only already-approved port geometry/header/staged-feature differences.
Implementation handover adds actual matched port captures beside these;
source/design evidence is not runtime acceptance. Do not emulate OpenTUI
selection or layout quirks; record any newly observed difference explicitly.

## Units and acceptance

A separate framework sanitizer unit gates before U25a. Main approved a
maintained-package trial first, then an exact port of the published regex if
needed; developer records the trial and approved choice in the decisions log.
This is shared sanitization, not a shell-specific escape workaround.

Framework API/control unit gates before port consumption. Test generic custom
language and run-only controls, immediate source caller-set isolation, ordinary
source-derivation capture/validation with const compatibility, unordered equality,
bound mismatches, source revisions/offscreen measurement, quoted/open/empty
blocks, narrow 21/20 and 23/22 thresholds, click cancel/reflow/disposal and
unresolved geometry. Existing copy/selection serialization stays green.

Port gates cover prefix typing/paste/history/empty Backspace, one running
command, successful/empty/failed/stopped/truncated output and held context;
current code insertion and refusal with draft; nonrunnable r; dark/light/plain,
120x40/80x24 and narrow controls; real pick/help/overflow/wheel behavior.
Use only fake agents and bounded harmless shell fixtures. Designer receives
a named commit and launch command, checks owned live original/port sessions,
retains captures, cleans up and hands to reviewer. Tester owns final heavy runs.
