# CTUI-48 interface draft

## Authority and evidence

Read the brief, repository guidance, README, FEATURES, decisions, CTUI-1/2/4/5/6/9/47/50 and current original CHD-172/394/396. Current original `../chord/src/ui/app/selection.ts`, `App.tsx`, `terminal.ts`, `keys.ts`, `src/ui/transcript/code_pick.ts`, `Reply.tsx`, `markdown.ts`, `src/ui/status/Status.tsx`, selection/code-pick tests and window tests take precedence over early design prose. In particular CHD-396 supersedes CHD-172's old wrapped-copy examples.

Live comparison: original `577b58167`, port `7e3da14`. Files are under `../interface-captures/` relative to this draft. For each size 120x40 and 80x24, `original-markdown`, `original-leader`, `original-pick`, `original-pick-up`, `original-help` compare with corresponding `port-*`; `original-drag-held` records a held drag. Each has plain `.txt` and styled `.ansi` output. Original commands used `bun dev chord --fake --qa ctui48-interface` from `../chord`. The port used its native Dart launcher with the original fake-agent command, isolated XDG state and a neutral capture directory. Both received the fake `markdown` prompt. An owned tmux server isolated these windows; tmux capture-pane records cells and ANSI, not physical mouse motion, terminal focus appearance or delivered clipboard contents.

No release was injected after held drag; no copy key or button was invoked. Escape cleared it. Copy outcomes below are source-derived contracts, not clipboard observations. No real agent/model or host clipboard was used. Neutral directories avoid private header paths; saved capture content was checked before writing and no redaction was necessary. Cleanup completion is recorded at the end.

Current port has no CTUI-48 implementation. In the original, leader then b selects the newest visible block, ↑ moves its accent frame, and the status shows the action keys. In the port the same unsupported chord leaves the leader without selecting a block; the 120x40 ↑ trial retrieves prompt history. The 80x24 saved ↑ trial leaves the draft empty. These baseline effects are not code-pick behavior. Port trials reset the draft between sequences; their filenames describe attempted inputs, not implemented states. Original [run] and its r hint appear in captures because they exist there; the proposal below omits them by the owner's CTUI-25 deferral. Existing frame inset, label position, Code continuation wrapping, virtualized scrolling and geometry differences remain approved. Captures are design baselines, never implementation acceptance.

## Call site first

Framework architect owns exact API declarations; this is the intended author-facing composition, using that draft's names:

```dart
final selection = SelectionController();
final reply = SelectionSource.markdown(
  id: replyId,
  revision: replyRevision,
  source: replyText,
);

SelectionArea(
  controller: selection,
  selectionStyle: palette.selection,
  onSelectionChanged: selectionChanged,
  onSelectionFinalized: selectionReleased,
  child: Column(children: [
    Expanded(child: Markdown.fromSelectionSource(reply)),
    SelectionContainer.disabled(child: const StatusLine()),
  ]),
);
```

SelectionArea owns gestures, mapping and highlight only. It does not write the clipboard, make status notes, choose copy-on-release, dispatch session actions or bind Ctrl+C by itself. The port surrounds the whole live window with one area so header, transcript and draft can participate in one selection. Furniture opts out with SelectionContainer.disabled, with explicit semantic exceptions for table grids and quote-contained rendered structures. ListView uses framework's SelectionChildDelegate for offscreen intermediate sources; the port supplies item identities and domain content rather than maintaining a second Markdown parser or registry of painted strings. App state owns code-pick reference and clipboard policy. Dispose the controller with its window.

The port adds a constructor/configuration seed `copyOnSelect = true`. CTUI-29 later loads it from the user's settings file; project/agent settings never control it. There is no new command, agent /config toggle or “disable auto-copy in /config” hint. Main explicitly settled this staged seam.

## What is highlighted and copied

Selection source identities follow logical content, never recycled list slots. Mouse positions resolve at grapheme boundaries against actual paint clipping. A wide grapheme is selected whole; no continuation half, ANSI control sequence or hidden row is copied. Forward/reverse drag normalize to document order. Intermediate offscreen source content may join an already established transcript range; clipping still prevents a hidden surface from starting a selection. Framework mapping supplies all cases below, using existing parser results and current port geometry.

| Visible material | Drag copy |
| --- | --- |
| Header text, prompt transcript, draft, assistant/tool text | Actual selected content; no app gutters or logos. Draft soft wraps join; typing/paste first clears selection, then edits at the existing insertion point. |
| Paragraph, heading, ordinary list item, quote paragraph | Semantic inline text, preserving explicit hard breaks and joining soft wraps; normal list/task markers, hanging indent and outer quote bar excluded. Links retain whatever address text the renderer actually presents. |
| Normal/list-contained code box | Selected source characters; soft wraps join, source LF/tab/space semantics preserved. No label, border, layout padding, line numbers or ↪ continuation mark. |
| Two reply blocks separated by a blank row | Exact original separator `first\n \nsecond`, including its one-space line. Loose-list gaps do the same; tight list items/blocks use LF without a blank line. |
| Quote-contained code | Current port's rendered code-box rows and borders, including displayed wrapping, rather than bare source. Outer quote bar remains furniture. This original serialization class overrides the ordinary Code source rule. |
| Quote-contained list | Retain its displayed list markers and rows, as original's quote-text class does; use current approved drawing geometry. |
| Table | Rendered rows and grid, including its current narrow fallback. Do not manufacture unseen cell text. |
| Diff | Visible code content, no line numbers, change gutters or headers; collapsed/omitted rows cannot be acquired by dragging hidden content. Source spans must distinguish any actual code prefix from diff furniture. |
| Folded output | Only shown content. Fold marker and hidden output excluded. |
| Permission/picker/shortcuts/status/app decorations | Not selectable, unless they contain an explicitly eligible existing agent-authored text surface. The permission UI itself starts no selection. |

The table is a selection mapping contract, not a request to change parser output, redraw quotes or strip copied text after the fact. Main approved preserving original serialization classes using current approved port drawing. Main also approved fixing the original's nested-list quirk: one report crossing several nesting levels must resolve the actual target immediately; no artificial extra report per level.

A code button copies the complete closed block's source, regardless of wrapping, and no trailing delimiter newline; agent-sent internal/leading/trailing blank code lines remain source content. This is distinct from partial drag and from quote drag serialization. Quoted code has no button but keyboard c copies bare block source. Tables never become code picks. Source mutation while selection lives must keep highlight and synchronous copy read in agreement; once no selected source remains, clear the hint and restore ordinary Ctrl+C. Resize, clear, verbose toggle and terminal handoff clear selection. Async copy results cannot reselect removed content.

## Person-visible lifecycle and precedence

| State/event | Result |
| --- | --- |
| Empty window | Header lines and draft selectable; mark, rules, empty layout start nothing. |
| Primary down on selectable source | Begin drag; hold following. Motion updates live slate/inverse highlight. No edge autoscroll. Wheel/scroll keys move transcript and update selection. |
| Primary release with no text | No copy, no selection; resume following only if it was following and the person did not scroll while down. |
| Release with text | Show selection; with auto-copy true capture text now and start copy; false shows `ctrl + c to copy`. Resume following by the same rule. |
| Auto-copy success/sent | Show note for 3 seconds; retain highlight and copy hint afterwards. |
| Explicit selection-copy success/sent | Clear selection after success; feedback lasts 3 seconds. |
| Selection-copy failure | Keep selection and persistent failure/retry note; Ctrl+C retries. While a copy is pending ignore duplicate selection-copy requests. |
| Code-copy success/failure | End pick; feedback lasts 3 seconds in either case. Failure omits retry hint. |
| Ordinary key/paste | Clear selection first, then ordinary action/edit on the same event. Empty paste also clears. Prefix and scroll keys preserve selection. |
| Permission waiting/error/streaming | Existing content can still be selected; selection Ctrl+C wins over stopping, draft clear, quit arming and modal context. With no selection ordinary behavior returns. |

The original retains mounted transcript entries while selection lives. The framework design uses logical source identities and lazy source mapping instead, as settled by the lead: keep the visible highlight/source contract without retaining unbounded mounted widgets.

Notes use exact original wording and grapheme counts:

- `copied N chars to clipboard` only if a service can confirm host write.
- `sent N chars to the terminal's clipboard` for OSC 52 emission alone; this is the CTUI-48 production path with existing terminal services.
- Selection failure: `could not copy: <reason> · ctrl + c to try again`.
- Block failure: `could not copy: <reason>`.
- Empty pick: `No code block to pick` for 3 seconds.

A note/pick hint occupies the status line alone, suppressing model/effort/context beside it. Copy errors use error tone; success/sent use status notice tone. Preserve current armed-quit/closing priority. Code-pick hint takes precedence over other ordinary notes and modes while active. Do not append claims that the terminal accepted or delivered OSC 52. Long failure details follow existing one-line status truncation; standard notes fit both required widths.

## Keys and binding scopes

Every declared action is a described Binding in Actions. Ctrl+C is also a reserved contextual behavior before ordinary scopes, matching existing port key routing. Merely adding an enabled Actions binding below TextArea is insufficient: resolve selection before editor/modal dispatch and before clearing it. Keep copy chord-prefix ordering consistent with the original.

| Scope | Key | Description / help wording | Behavior |
| --- | --- | --- | --- |
| Selection, shown only | ctrl+shift+c | Copy selection | Explicit copy; legacy Ctrl+C decoding still reaches reserved selection behavior. |
| Window contextual priority | ctrl+c | ctrl + c to copy | Copy shown selection, never stop/clear/arm quit on that press. |
| Window | ctrl+x b | Pick a code block | Start mode; newest partially visible block, otherwise newest listed block. |
| Code pick | up / down | Previous code block / Next code block | Move in drawn transcript order, clamp at ends; preserve draft/history. |
| Code pick | c | Copy code block | Snapshot picked source, end pick and request copy. |
| Code pick | escape | Finish picking a code block | End pick without editing or interrupting. |
| Existing scopes | pgup / pgdn / wheel | Existing scroll descriptions | Scroll while preserving pick; do not create new pointer-only actions. |

Normal Esc with a selection clears it and then performs existing Esc behavior. Any other key ends code picking and executes normal behavior on the same key. In particular r is ordinary typing now: it ends the pick and reaches the prompt; no dormant run binding is advertised. Prefixes preserve selected text until their resolution, misses clear it before ordinary behavior. Existing scroll bindings preserve selection and pick. A rebound copy binding is heard before form/search typing suppression. Help derives actual keys rather than hard-coded alternative bindings.

Staged shortcuts additions, adjacent to existing scrolling/leader entries:

```text
ctrl + c to copy
ctrl + x b to pick a code block
c to copy the picked block
```

Leader hint includes `b a code block` with current staged leader options. Pick hint is `↑ ↓ another block · c copy · esc done` at both required widths. Under narrower/rebound widths use `↑ ↓ block · c copy · esc done`, then retain complete items that fit in order; if none fits use bare cancel key; if no cancel binding exists use `picking a code block`. Do not copy original full catalog geometry: current port's staged catalog decides its own columns/overflow. No [run], r help clause or bash prompt behavior until CTUI-25.

## Code boxes and pick mode

Closed fence: `[copy]` on the right end of top border, one `─` before/after, no surrounding spaces; language label remains left. Buttons use text foreground against dim border, no hover treatment. Picked border/label/buttons use accent, buttons bold. Original minimum copy-only widths: unlabelled 10, ts 15, console 20; formula label cell width + 13, or 10 unlabelled. Grow a short box to fit if its column permits; if the column itself is narrower, drop [copy] before sacrificing label through existing clipping. Do not overflow its column. Existing port Code inset and continuation wrapping remain approved.

The whole six-cell `[copy]` word is one action surface. Primary press and release on the same live visible button, with no drag, clicks. Release outside, different button, disposal, reflow moving it away, or code-to-button drag never clicks. Wheel is independent. Buttons/furniture start no text selection; pressing them clears existing shown selection. A drag already in progress retains pointer ownership when crossing a button.

An open fence draws code but has no button and is not pickable until its actual closing fence arrives. Main approved using the pinned markdown parser's public parser-state adapter to record closure metadata, including nested fences. An EOF-open block is never treated as closed merely because the parser returns a code node.

Listed closed blocks in assistant replies and supported agent messages are reachable even offscreen; drawn-only blocks (expanded tool summaries/output, plan content) are eligible only while visible. Avoid offering blocks from unimplemented port entry types. Quoted code has no button but participates in picks. Pick identity follows source item/block identity through streaming append and list reordering. If a pick no longer exists, reconcile against original reducer behavior: next move falls back to newest eligible block; no blocks means no pick. Never copy stale removed text. A picked block already whole in view does not scroll; otherwise align its top to the viewport top; oversized code/quote aligns its top and remains normally scrollable.

## Ownership and acceptance units

Framework-owned state: controller range/direction, gesture capture, source geometry, highlight and invalidation. App-passed state: copyOnSelect seed, theme role, clipboard callback/results, pure window reducer and selected code reference. Pure logic beside widgets: key routing, selection lifecycle/follow intent, code eligibility/order/movement, serialization mapping and note formatting/grapheme counts. Widgets draw that state and dispatch. Clipboard is a terminal service boundary, never a text widget side effect.

1. Source mapping + selection area: failing widget tests at both sizes for reverse drag, grapheme/tab/wide cells, clip/overlay hit boundaries, normal soft-wrap joining, hard LF, selected gap space, quoted code/table/list exceptions, draft clearing-before-edit, and virtualization across offscreen intermediate items. A test must distinguish source code copy from visible quoted rows, inclusive anchor/focus endpoints and cross-entry LF separators. One cross-level nested motion reaches the actual target.
2. Port lifecycle + feedback: pure reducer/key tests and injected clipboard window tests cover auto-copy on/off, success note expiry with retained highlight, explicit success clear, persistent failed-selection retry, block failure expiry/no retry hint, duplicate pending copy, late result after clear/dispose, scroll/follow intent and permission-context Ctrl+C precedence. No test reaches host clipboard; recording terminal adapter proves sent-only reporting.
3. Buttons + code picks: failing tests for literal full-word click bounds, no click from drag or moved/disposed button, open/closed/nested fence transition, quote no-button/keyboard copy, newest-visible/default-newest, offscreen navigation, clamp/end behavior, source replacement/removal, preserving draft/history, pgup/pgdn/wheel preservation, and every help key in Actions.
4. Ship visual acceptance: original comparison and implemented port at 120x40/80x24, dark/light/NO_COLOR; empty/focused/dragging/released/streaming/waiting/failure/overflow; open/closed/quoted/nested code and narrow button suppression. Use clipboard stubs for release/button captures. Verify native compiled binary in PTY and cleanup. Baseline files here do not discharge any of these implementation checks.

## Themes and sketch notation

Main settled slate background 256 index 66 on dark, 152 on light. Preserve original foreground/syntax roles under the highlight. Under NO_COLOR use inverse only, without foreground/background color escape; this is an approved difference from original's real slate. Plain picked frame uses terminal foreground, bold buttons, no colored accent. Real terminal contrast still needs ship validation; baseline live captures here cover the original/port default theme, not light/plain contrast.

Following full-size text sketches are proposals, not terminal captures. Each is an exact 120x40 or 80x24 cell rectangle; blank rows are intentional. Braces mark selected ASCII content for illustration and are not painted glyphs. Named styles: H=selection background (inverse in NO_COLOR), A=accent/bold picked controls, D=dim border/label/gutter, E=error note, T=normal or syntax text, S=status notice. Prompt focus uses existing terminal steady-block cursor rather than a painted fake cursor. Selection does not transfer editor focus. States vary only the affected interface; unrelated existing screens retain their established design.

### empty — 120x40

D borders/gutters; T source; S note.

```text
 █▄     chord                                                                                                           
 ▀██▄   fake                                                                                                            
 ▄██▀   capture directory                                                                                               
 █▀     ? for shortcuts                                                                                                 
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                                                       
```

### focused — 120x40

D borders/gutters; T source; S note.

```text
 ⏺ Example reply                                                                                                        
                                                                                                                        
   Selected source stays independent of wrapping and app furniture.                                                     
                                                                                                                        
   ┌ ts ───────────────────────[copy]─┐                                                                                 
   │   const value = 1;              │                                                                                  
   └─────────────────────────────────┘                                                                                  
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ › unsubmitted draft                                                                                                  │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
                                                                                                                        
```

### dragging — 120x40

D borders/gutters; T source; H selected span; S note.

```text
 ⏺ Example reply                                                                                                        
                                                                                                                        
   {Selected source} stays independent of wrapping and app furniture.                                                   
                                                                                                                        
   ┌ ts ───────────────────────[copy]─┐                                                                                 
   │   const value = 1;              │                                                                                  
   └─────────────────────────────────┘                                                                                  
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                                                       
```

### auto-copy note — 120x40

D borders/gutters; T source; H selected span; S note.

```text
 ⏺ Example reply                                                                                                        
                                                                                                                        
   {Selected source} stays independent of wrapping and app furniture.                                                   
                                                                                                                        
   ┌ ts ───────────────────────[copy]─┐                                                                                 
   │   const value = 1;              │                                                                                  
   └─────────────────────────────────┘                                                                                  
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  sent 15 chars to the terminal's clipboard                                                                             
```

### streaming open fence — 120x40

D borders/gutters; T source; S note.

```text
 ⏺ Example reply                                                                                                        
                                                                                                                        
   Selected source stays independent of wrapping and app furniture.                                                     
                                                                                                                        
   ┌ ts ───────────────────────────────┐                                                                                
   │   const value =                                                                                                    
   └──────────────────────────────────┘                                                                                 
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  Working… (esc to interrupt)                                                                                           
```

### waiting permission — 120x40

D borders/gutters; T source; S note.

```text
 ⏺ Example reply                                                                                                        
                                                                                                                        
   Selected source stays independent of wrapping and app furniture.                                                     
                                                                                                                        
   ┌ ts ───────────────────────[copy]─┐                                                                                 
   │   const value = 1;              │                                                                                  
   └─────────────────────────────────┘                                                                                  
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
   Allow this tool call?                                                                                                
   1. Allow once                                                                                                        
   2. Reject                                                                                                            
   ↑ ↓ to move · enter to choose · esc to reject                                                                        
                                                                                                                        
                                                                                                                        
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ctrl + c to copy                                                                                                      
```

### copy failure — 120x40

D borders/gutters; T source; H selected span; E note.

```text
 ⏺ Example reply                                                                                                        
                                                                                                                        
   {Selected source} stays independent of wrapping and app furniture.                                                   
                                                                                                                        
   ┌ ts ───────────────────────[copy]─┐                                                                                 
   │   const value = 1;              │                                                                                  
   └─────────────────────────────────┘                                                                                  
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  could not copy: no clipboard to write to · ctrl + c to try again                                                      
```

### overflow/pick — 120x40

D borders/gutters; T source; A code frame/label/buttons; S note.

```text
   +12 above                                                                                                            
                                                                                                                        
   Picked block: top aligned after navigation                                                                           
                                                                                                                        
   ┌ ts ───────────────────────[copy]─┐                                                                                 
   │   const value = 1;              │                                                                                  
   └─────────────────────────────────┘                                                                                  
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
   +8 below                                                                                                             
                                                                                                                        
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ↑ ↓ another block · c copy · esc done                                                                                 
```

### empty — 80x24

D borders/gutters; T source; S note.

```text
 █▄     chord                                                                   
 ▀██▄   fake                                                                    
 ▄██▀   capture directory                                                       
 █▀     ? for shortcuts                                                         
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                               
```

### focused — 80x24

D borders/gutters; T source; S note.

```text
 ⏺ Example reply                                                                
                                                                                
   Selected source stays independent of wrapping and app furniture.             
                                                                                
   ┌ ts ───────────────────────[copy]─┐                                         
   │   const value = 1;              │                                          
   └─────────────────────────────────┘                                          
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
╭──────────────────────────────────────────────────────────────────────────────╮
│ › unsubmitted draft                                                          │
╰──────────────────────────────────────────────────────────────────────────────╯
                                                                                
```

### dragging — 80x24

D borders/gutters; T source; H selected span; S note.

```text
 ⏺ Example reply                                                                
                                                                                
   {Selected source} stays independent of wrapping and app furniture.           
                                                                                
   ┌ ts ───────────────────────[copy]─┐                                         
   │   const value = 1;              │                                          
   └─────────────────────────────────┘                                          
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                               
```

### auto-copy note — 80x24

D borders/gutters; T source; H selected span; S note.

```text
 ⏺ Example reply                                                                
                                                                                
   {Selected source} stays independent of wrapping and app furniture.           
                                                                                
   ┌ ts ───────────────────────[copy]─┐                                         
   │   const value = 1;              │                                          
   └─────────────────────────────────┘                                          
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  sent 15 chars to the terminal's clipboard                                     
```

### streaming open fence — 80x24

D borders/gutters; T source; S note.

```text
 ⏺ Example reply                                                                
                                                                                
   Selected source stays independent of wrapping and app furniture.             
                                                                                
   ┌ ts ───────────────────────────────┐                                        
   │   const value =                                                            
   └──────────────────────────────────┘                                         
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  Working… (esc to interrupt)                                                   
```

### waiting permission — 80x24

D borders/gutters; T source; S note.

```text
 ⏺ Example reply                                                                
                                                                                
   Selected source stays independent of wrapping and app furniture.             
                                                                                
   ┌ ts ───────────────────────[copy]─┐                                         
   │   const value = 1;              │                                          
   └─────────────────────────────────┘                                          
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
   Allow this tool call?                                                        
   1. Allow once                                                                
   2. Reject                                                                    
   ↑ ↓ to move · enter to choose · esc to reject                                
                                                                                
                                                                                
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ctrl + c to copy                                                              
```

### copy failure — 80x24

D borders/gutters; T source; H selected span; E note.

```text
 ⏺ Example reply                                                                
                                                                                
   {Selected source} stays independent of wrapping and app furniture.           
                                                                                
   ┌ ts ───────────────────────[copy]─┐                                         
   │   const value = 1;              │                                          
   └─────────────────────────────────┘                                          
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  could not copy: no clipboard to write to · ctrl + c to try again              
```

### overflow/pick — 80x24

D borders/gutters; T source; A code frame/label/buttons; S note.

```text
   +12 above                                                                    
                                                                                
   Picked block: top aligned after navigation                                   
                                                                                
   ┌ ts ───────────────────────[copy]─┐                                         
   │   const value = 1;              │                                          
   └─────────────────────────────────┘                                          
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
   +8 below                                                                     
                                                                                
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ↑ ↓ another block · c copy · esc done                                         
```

The waiting sketch assumes a previously shown selection above the permission, hence Ctrl+C copies rather than rejects. The focused sketch puts the existing terminal cursor at the draft insertion point; its shape is not represented by an extra character. The streaming sketch intentionally has no copy button. In the overflow sketch style A applies to the shown code frame; the text label describing alignment is explanatory sketch content, not product wording. Successful explicit copy, auto-copy with its note expired, copyOnSelect false and failed block copy reuse these screens with respectively cleared highlight/status success, retained highlight/`ctrl + c to copy`, retained highlight/`ctrl + c to copy`, and no highlight/`could not copy: <reason>`. The state table above is normative for these transitions.

## Settled owner differences and remaining limits

Settled by main through the lead: [run]/r wait for CTUI-25; copyOnSelect constructor seed defaults true until CTUI-29; NO_COLOR inverse-only; existing Code wrapping/virtualization retained; quote/table serialization follows original classes using current drawing; nested-list report quirk is fixed; pinned Markdown parser public-state closure metadata adapter approved. No unresolved interface owner choice remains. Framework parameter details remain owned by its draft and must be reconciled during merge. Runtime copy/follow/source invalidation details remain owned by runtime draft.

Live evidence deliberately does not exercise clipboard results, failure timers, dark-vs-light contrast, native binary behavior or a completed implementation. These are ship acceptance obligations, not silently accepted limits.

Cleanup completed: both owned fake windows received normal Ctrl+D exit; the isolated tmux server was then removed. Task-created neutral capture directories and isolated XDG state were deleted. Retained evidence is confined to CTUI-48/interface-captures and this draft. No original source was edited; no independent commit was made.

## Final adjacent comparison

| Paired files (each size) | Original | Current port | Cause / status |
| --- | --- | --- | --- |
| original-markdown / port-markdown | Closed code has copy/run controls; label after one border dash; code begins one cell inside padding. | No controls; earlier label placement and two-cell Code mark column/inset. | Controls missing until CTUI-48; run deferred CTUI-25. Existing framework inset/wrapping retained, no original renderer bug emulation. Final port files wait for complete reply and no Working line. |
| original-leader / port-leader | Leader includes b a code block and a for waiting work. | Leader only includes a and cancel. | Code-pick action absent in baseline. |
| original-pick / port-pick | Newest visible code border is accent, controls bold, action hint alone. | No picked frame or code hint. | Baseline lacks CTUI-48. |
| original-pick-up / port-pick-up | Accent moves to previous code; draft unchanged. | No code move; at 120x40 ordinary prompt history appears. | Original owns arrows only in code-pick mode. Port has no such mode yet. |
| original-help / port-help | Full product catalog includes selection/code actions, run, sessions and other later features. | Smaller staged catalog; no copy/pick entries. | Add only the CTUI-48 staged rows; preserve current natural column/overflow behavior. |
| original-drag-held | Slate 66 paints live selected cells at both sizes. | No matching port drag-selection implementation. | Original live hold only, no release or clipboard; proposed port appearance needs ship evidence. |

The markdown captures include identical completed fake text and existing table rows; minor code-frame widths/insets come from current framework drawing rather than selection serialization. No theme-contrast or clipboard-outcome claim is inferred from these paired cells.

## Endpoint and separator addendum: closed by original probe

`../interface-captures/endpoints.test.ts` is a task-local read-only harness probe. Run from the task tree with CHORD_SOURCE pointing to ../chord and `bun test docs/design/evidence/CTUI-48/interface-captures/endpoints.test.ts`. It imports the original window helpers and uses only its fake agent. Auto-copy is disabled and the injected copy callback throws if invoked. `endpoints.jsonl` records its results; one test passed, zero failures, at 120x40 and 80x24. The original harness unmounts each window, stops its fake child and verifies process cleanup. The probe selects content, not the host clipboard. It does not change original files.

Observed at both sizes (the reply source is `Hello, world. This reply came in chunks.`):

| Gesture | Selected text |
| --- | --- |
| Press/release on the same cell | Empty |
| Anchor on T of This, focus on s | `This` |
| Anchor on s, focus on T | `This` |
| Anchor on T, focus at terminal right edge on same row | `This reply came in chunks.` |
| Anchor on s, focus at terminal left edge | `Hello, world. This` |
| Anchor on s, focus on blank rows below text | `s reply came in chunks.` |
| Anchor on s, focus on prior row before source | `Hello, world. This` |
| User transcript prompt through reply, stepped reports | `text\nHello, world. This reply came in chunks.` |
| Same cross-entry range reversed, stepped reports | Same document-order text |

Thus a click without movement is empty; a nonempty drag includes both endpoint glyphs. Internally half-open source intervals must extend the greater endpoint through its whole grapheme, and the lesser endpoint begins at its grapheme start. Reversing endpoints changes no serialized text. Pointer positions outside the source do not copy screen padding: clamp x to actual source line bounds, above to source start and below to source end while retaining the inclusive anchored glyph. Empty furniture neither contributes characters nor starts a selection. A drag already started retains capture while crossing it. Source order and current geometry determine the endpoint; never clamp to a widget's stale pre-scroll rectangle.

Distinct transcript entries join with one LF in this observed prompt-to-reply case; empty layout spacing contributes no additional blank line. Do not confuse that with an explicit selectable one-space Markdown gap inside a reply: that copies LF + one space + LF, exactly as CHD-396's current `Reply.tsx` Blank/spaced source specifies. Tight list items use LF. Multiple semantic gaps copy their registered separators, never a count of every blank terminal row.

The direct one-report cross-entry probe selects only `text` in the original until its selection root expands through additional reports. Stepped forward and reverse reports produce the complete same range. This is an OpenTUI report-dependent expansion quirk, like its nested-list case. Under main's explicit rule that library quirks are not copied, the framework resolves the actual endpoint on the first valid motion; it must immediately produce the full range and the same separator. This addendum closes the endpoint/separator conventions for implementation; there is no deferred design gate.

Final cleanup audit: all owned tmux servers are gone, both baseline fake runs exited, and the replacement run's isolated XDG state was removed. Probe-created windows/processes were cleaned by withWindow. The retained task-local probe and JSON results are evidence; no capture/log includes a private filesystem path. The temporary raw probe log was removed after its JSON results were retained.

## Final critic endpoint edges: observed and closed

`../interface-captures/endpoint_edges.test.ts` extends the read-only original probe, with the same disabled auto-copy and throwing clipboard stub. One test passed, zero failures; `endpoint_edges.jsonl` retains 22 observations covering 120x40 and 80x24. Both sizes agree. Before-release and after-release text were recorded separately.

| Motion/release sequence, anchor on T in This | Before release | After release |
| --- | --- | --- |
| No motion, release at anchor | Empty | Empty |
| Motion report at same anchor, release there | Empty | Empty |
| Motion to s, then back to anchor, release at anchor | Empty | Empty |
| No motion, release at s | Empty | Empty |
| Motion to h, then release at s | `Th` | `Th` |

The source-fidelity rule is therefore precise: equal anchor and last motion cell means no selected text, even after an earlier nonempty range. A nonempty range includes both endpoint glyphs. Release finalizes the range from the last motion; the release coordinate does not independently relocate its extent. A displaced release with no preceding motion still behaves as a click. This describes observed original behavior rather than inferring an end position from the release byte.

The original fake's markdowncode fixture has an empty source line immediately before `echo done`. Using the actual code-content x coordinate on that blank row:

| Blank-code-row gesture | Before and after release |
| --- | --- |
| Same-cell click | Empty |
| Same-cell motion | Empty |
| Horizontal motion across the blank row | Empty |
| Blank row to final e of echo done | `\necho done` |
| Final e of echo done back to blank row | `\necho done` |
| First e of echo done back to blank row | `\ne` |

A blank code row is a valid source position at its line boundary, not a glyph or a selectable run of layout spaces. Moving into a nonempty source row includes the actual crossed LF and endpoint characters; selecting only horizontal positions on the same empty row adds no spaces and remains empty. Code's semantic LF is different from Markdown's explicit one-space separator row. Preserve this distinction in both hit mapping and copied text.

Lead's explicit no-hit policy closes the remaining geometry ambiguity: while an active drag has no eligible source under its motion point, clamp within its last eligible focus source using that source's current row/start/end bounds. Do not choose a different source by distance, mount order or nearest rectangle; only an actual eligible hit changes the focus source. Hidden and disabled content cannot win by proximity. A source-owned blank code row is eligible; border padding and unrelated empty layout are not. Existing pointer capture carries the active drag across furniture. The same policy applies when the last focus source differs from the anchor source.

The follow-up harness unmounted both windows, stopped its fake agents and verified cleanup. The temporary raw log was removed after retaining sanitized JSON. No tmux server or persistent fixture was created by this follow-up, and no clipboard callback was invoked.
