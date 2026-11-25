# CTUI-9: terminal services and keyboard negotiation

Framework services, fakeable at the existing Terminal seam. No chord
session knowledge, draft-file policy, notification timing or port editor
action belongs here. Main approved that boundary: port editor and notify
policy remain M3. Bracketed paste and OSC 11 retain their contracts.

References: original `src/editor.ts`, `src/notify.ts` and
`src/ui/app/terminal.ts`; CTUI-3, CTUI-7 and CTUI-20; the current Terminal,
InputParser and runApp baseline. Protocol reference:
https://sw.kovidgoyal.net/kitty/keyboard-protocol/ .

## Call site

```dart
final terminal = StdioTerminal();
try {
  await runApp(
    ServiceDemo(terminal: terminal),
    terminal: terminal,
    exitProcess: false,
  );
} finally {
  await terminal.close();
}

// Inside Actions, with descriptions shown by KeyHelp:
Binding('ctrl+y', 'Copy sample', () => terminal.copyToClipboard(sample));
Binding('ctrl+g', 'Open sample in editor', () async {
  final code = await terminal.runEditor(sampleFile);
  // Caller chooses what a nonzero exit means for its own file or draft.
});
Binding('ctrl+b', 'Ring bell', terminal.bell);
Binding('ctrl+n', 'Notify', () => terminal.notify(
  'Sample is ready', channel: NotificationChannel.osc9,
));
Binding('ctrl+t', 'Set sample title', () => terminal.setTitle('Services'));
```

`sampleFile` is caller-owned. This slice never writes draft content, adds
or removes a newline, interprets a successful edited file, chooses a port
status message, or silently replaces a draft on editor failure.

## Public shape

```dart
enum TerminalState { inactive, active, suspended }
enum NotificationChannel { bell, osc9, osc777 }

// Additions to Terminal, alongside size/input/resizes/write/enter/leave:
Stream<TerminalState> get states;
void copyToClipboard(String text);
void bell();
void notify(String message, {
  required NotificationChannel channel,
  String title = '',
});
void setTitle(String title);
Future<T> suspend<T>(Future<T> Function() action);
Future<int> runEditor(String path, {
  String? command,
  String? workingDirectory,
});
```

Terminal remains the injectable dependency; no global singleton and no
widget-owned process. Service calls emit terminal effects, not widgets.
A fake records semantic calls and may deterministically emit state changes
or complete a suspended callback. Tests need neither a real terminal nor
an editor. Production StdioTerminal uses standard process/stream facilities;
package selection and any package mismatch follow AGENTS before coding a
workaround. Existing test fakes must implement the expanded seam.

`states` delivers transitions synchronously, before the corresponding
terminal ownership changes can race a frame. Repeated enter/leave must
not accumulate subscriptions or push keyboard modes twice. StdioTerminal's
existing reusable input and explicit permanent close remain distinct.
`close()` never means resume. Invalid suspension outside an active run,
nesting and overlapping suspension reject with StateError before any
terminal effect or callback. State changes do not mount a second widget
root or replace app state.

## Bytes and effect results

- Copy uses UTF-8 plus base64 in OSC 52 with clipboard selector `c`,
  terminated by BEL. It writes only: no clipboard query/read, local helper
  process, success acknowledgement or claim that a host accepted the copy.
- Bell writes BEL.
- OSC 9 carries message; OSC 777 carries `notify;title;message`. Flatten
  C0, DEL and C1 control characters to spaces. For OSC 777 also replace
  semicolons inside fields with commas, as the original does. OSC 9 has no
  title field. Channel choice is explicit; auto/off policy belongs to apps.
- Title writes OSC 2 with the same control flattening. No original-title
  query or automatic restoration is promised. An empty title is valid.
- tmux passthrough uses StdioTerminal({bool? tmuxPassthrough}),
  defaulting to a nonempty TMUX environment variable; bytes are DCS-wrapped with doubled ESC
  for forwarded effects. Do not claim acceptance when tmux disables it.
  Forward OSC 52 and notifications only; title stays local.
- A failed terminal write propagates to the caller; no fake receipt is
  drawn by the framework. Async editor spawn failures reject; nonzero
  child exit returns its integer after restoration. Applications decide
  their wording and whether a file is usable.

StdioTerminal takes `Map<String, String>? environment`, defaulting to
Platform.environment, and a narrow typed `editorLauncher` callback (the
developer chooses its exact typedef). Its contract includes inherited
stdio, executable/arguments, working directory and integer exit status.
Tests assert launch and failure without running a real editor. This is not
a public general process abstraction.

## Editor lifecycle

Use the original command precedence: explicit command, then nonblank
VISUAL, then nonblank EDITOR, then vi on supported POSIX systems. Run
through the user's SHELL or /bin/sh so quoting, flags and variables mean
what they do in an editor command. Pass the file separately as a positional
argument, never interpolate its path into shell code. Shell/editor launch
is a process concern; do not invent a command tokenizer. A package that
cannot meet this contract goes to the lead with options before a workaround.

U4 starts with a bounded scripted PTY feasibility probe: pause the actual
stdin source subscription, run an inherited-stdio scripted child, confirm
it receives typed input, then confirm the existing source resumes with no
child-input replay. A paused stream can buffer pending bytes; parser reset
alone cannot prove absence of replay. Do not
cancel and re-listen to single-subscription stdin. A downstream listener
pause or dropping input is insufficient proof. If source pause cannot give
the child input, stop for the lead before alternate fd or FFI plumbing.

Suspension ordering, including callback failure:

1. Mark suspended before yielding. runApp gates frame scheduling and input
   dispatch, cancels its escape timer, clears parser fragments and the
   pending chord. No queued key or paste is replayed into the app later.
2. Pause source reads, release negotiated keyboard modes, disable bracketed
   paste, restore style/cursor, leave alternate screen and flush output;
   restore saved terminal modes. The callback starts only after release.
3. Run and await the callback. App state and stream reducers may update,
   but they produce no terminal frames while the child owns the terminal.
4. In finally, if the run is still live, restore raw/alternate-screen,
   hidden cursor and bracketed paste, then resume source reads and keyboard
   negotiation. Mark active only after restoration. Redraw the whole current
   window at the current size; discard the renderer's previous cell buffer.
5. On callback error, complete the same restoration before propagating it.
   A restore failure reaches normal runApp cleanup; all remaining restoration
   steps are still attempted, and the original error is not silently lost.

A resize while suspended changes the first resumed frame, without drawing
over the editor. No background re-query delay or intermediate empty frame
is required on resume. No input fragment/chord survives either direction.
On quit requested while suspended, defer teardown until the callback gives
up the terminal, suppress re-entry/redraw, then restore/release exactly once
and reach beforeExit. Close likewise prevents late reactivation. There is
no framework ability to force-stop an arbitrary callback; timeout, process
cancellation and port draft policy are outside this service contract.
All exits and errors balance only modes this run actually acquired.

## Keys and negotiation

Main approved the spelling change: `meta` means kitty Meta, independently
of Alt. `alt` and `option` mean Alt. `cmd` and `command` alias `super`.
Add `superKey`, `hyper`, `meta` booleans default false to KeyEvent and KeyCombo,
including factories, equality, hash, stringification, synthetic events,
matching and test helpers. Canonical binding labels use `super`. Dart
reserves `super`, so main approved `superKey` for the public field and named
parameter, consistently across constructors and factories; this does not
change binding strings.
`char` is null with any Ctrl/Alt/Super/Hyper/Meta modifier. Preserve the
existing Ctrl-letter case normalization; no physical-key or IME API here.

Use kitty's modifier integer minus one: Shift 1, Alt 2, Ctrl 4, Super 8,
Hyper 16, Meta 32. Lock bits must not become bindings or typed characters.
Tab's legacy byte remains Tab; CSI 105;5u is Ctrl+I. CSI 13;2u is
Shift+Enter. Preserve existing CSI/SS3 arrows, tilde keys and paste fallback.
Map kitty functional codes to existing key names rather than rendering
private-use code points as text. Validate Unicode scalar values and numeric
fields before producing a key. Unknown/unusable complete controls stay
controls, never invented printable text.

Each active terminal run sends CSI ? u and waits up to the existing 100 ms
startup budget concurrently with OSC 11, holding ordinary early input once.
A valid CSI ? flags u reply enables a single kitty push, CSI > 1 u, requesting
only disambiguation. Timeout or unsupported terminals retain today's parser
and send no push. Pop with CSI < u before suspend/leave only if this run
pushed, and renegotiate after resume. No terminal-name capability guess.
Late/duplicate replies are consumed as non-key events without enabling an
expired negotiation; parse valid CSI-u keys even without negotiation.

Recognize fragmented replies independently from keys. Bound pending CSI
length and integer fields; define malformed/timeout handling explicitly in
tests so input cannot stay buffered forever. Keep OSC 11's existing limits.
For event-type subparameters, press and repeat dispatch once, release is
consumed. Missing event type means press. Do not request event reporting,
alternate keys or associated text in this slice; if received, parse the
primary key and modifiers without treating extra fields as typed text.

TextArea adds cmd/super+left and right to move to logical line start/end,
as the original prompt's bindings do, through described Actions. Existing
Home/End and fallback controls remain. Super/Hyper/Meta combinations never
fall through into text insertion. The shortcut/help snapshot must list
new described bindings; the port's curated panel policy remains its own.

## Demo, states and visual acceptance

U6 adds one framework example with described Actions and KeyHelp. Its
KeyHelp.builder filters the real active snapshot to service chords and
Super+Left/Right, then draws concise key/description spans in wrapping Text.
Do not manually duplicate the binding catalog or use the default single-line
clipping for this example. Every service action and both Super bindings
must be visibly listed at 80x24 and 120x40. Help takes the rows it needs;
the TextArea receives the remaining space. Service chords are Ctrl+Y copy,
Ctrl+G editor, Ctrl+B bell, Ctrl+N OSC 9, Ctrl+X N OSC 777, Ctrl+T title,
and Ctrl+Q quit. Preserve live action descriptions in the snapshot.

It owns its sample file and a scripted editor mode; no real model/agent.
`--scripted-editor` selects a direct inherited-stdio self-child launcher;
its full normal-screen marker waits for Enter before finishing. This avoids
shell quoting machinery inside the fixture. `--editor-fails` returns code
7 as a visible nonzero-exit state. The fixture owns and cleans its temporary
file/directory on every path. Neither mode launches the person's editor. The normal
interactive editor uses the person's command only when explicitly invoked.
The visual check uses an explicitly selected scripted child, not that
command. Its file, child and session are removed afterward.

Illustrative screen at 120x40 and 80x24 (remaining rows blank):

```text
Terminal services
Copy sample: Terminal services
Editor: ready
Last key: none
[TextArea containing two sample lines]
[KeyHelp: copy, editor, bell, notify, title, quit]
```

At 80 columns KeyHelp wraps/shortens by its existing policy. Empty sample
copies an empty payload; an empty editor file stays empty. Focus remains
in TextArea after return. The Copy sample caption always reserves one row,
using existing Text with softWrap false, maxLines 1 and ellipsis overflow.
A long caption must not consume the rows needed for help. The complete
sample remains wrapped and scrollable in the Expanded TextArea, and copy
sends the full payload, never the displayed ellipsis. Regress visible
service/Super help at 80x24 and 120x40 with a long sample. Other overlong
text uses existing layout, not a new truncation API or policy. A failed child returns
to the same full screen and a caller-owned result line. No notification or
copy acceptance is asserted from tmux pixels. The editor fixture fills the
normal screen with an obvious marker; no TUI frame may overwrite it.
Capture before suspension, editor ownership, after success/error and resize
at 120x40/80x24. Protocol bytes, fake effects and mode balance need unit/PTy
assertions; these captures establish readability and redraw only.

If CTUI-47 follows, mouse tracking must also be disabled while the child
owns the terminal and on every exit, then restored with other acquired
modes on resume. Recheck editor captures and cleanup with those modes.

## Build units

| Unit | Scope | Required evidence |
| --- | --- | --- |
| U3 | Terminal effect API, safe encoders and fakes | exact OSC/BEL/Unicode/control-field cases; no host effects |
| U4 | stdin feasibility probe, suspend lifecycle and editor launch | pause-child-resume, throw/exit/resize/quit/close, exact restoration order |
| U5 | modifiers, CSI parser, bounded negotiation, TextArea cmd movement | fragmented controls, fallback, reply race/timeout, no release insertion, described bindings |
| U6 | runnable framework demo and visual look | designer-owned captures at both sizes, scripted editor and cleanup |

No implementation is authorized by unsettled package or stdin feasibility
questions. The lead approved this unit order and lifecycle decisions.
