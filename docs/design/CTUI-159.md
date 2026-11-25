# CTUI-159: the terminal's user variable

The window tells the terminal which session to resume: iTerm2's
`SetUserVar`, which WezTerm reads too, named `chord_session`, its value the
main session's id in base64, empty for none
(`../chord/src/notify.ts:313-328`, `../chord/docs/design/CHD-492.md`).
Writing a terminal user variable is not chord's own, so the bytes and the
write belong to the framework, beside `notify` and `setTitle`; which name,
which value and when are the port's.

## The framework

In `packages/chord_tui/lib/src/terminal/terminal.dart`:

```dart
/// The OSC 1337 `SetUserVar` sequence that sets the terminal's user
/// variable [name] to [value], the value base64 of its UTF-8 as the
/// protocol asks; an empty [value] sets it empty. Throws [ArgumentError]
/// for a [name] that is empty or holds anything but ASCII letters, digits
/// and `_`.
String userVariableBytes(String name, String value) =>
    '\x1b]1337;SetUserVar=$name=${base64.encode(utf8.encode(value))}\x07';

/// [bytes] inside tmux's passthrough: a DCS with each ESC doubled, which
/// tmux hands to the terminal outside when `allow-passthrough` is on.
String tmuxPassthrough(String bytes) =>
    '\x1bPtmux;${bytes.replaceAll('\x1b', '\x1b\x1b')}\x1b\\';
```

On `Terminal`, after `setTitle`:

```dart
/// Sets the terminal's user variable [name] to [value] with OSC 1337
/// `SetUserVar`; terminals without it ignore it. Throws [ArgumentError]
/// for a name [userVariableBytes] refuses.
void setUserVariable(String name, String value) =>
    write(userVariableBytes(name, value));
```

`StdioTerminal` overrides it as it does `notify`, through its own tmux
passthrough:

```dart
@override
void setUserVariable(String name, String value) =>
    write(_forward(userVariableBytes(name, value)));
```

and `_forward` becomes `_tmuxPassthrough ? tmuxPassthrough(bytes) : bytes`,
so clipboard, notifications and the user variable share one wrapper. Both
functions are exported from `chord_tui.dart`.

Why this shape:

- `setUserVariable(name, value)`, not `setSessionVariable`: the framework
  knows nothing of sessions. The verb follows `setTitle` and
  `setProgramStatus`.
- The value is a plain `String`; "none" is the empty string, which is what
  the protocol writes for it. The framework does not take `null`.
- The name is checked, as `setProgramStatus` checks its id, because a `=`
  or a control character in it breaks the sequence; the value needs no
  check, base64 carries anything.
- Like the clipboard and the notifications, and unlike the title, it goes
  through tmux: the variable is for the terminal outside, which the
  launcher reads.

## The port

`lib/notify.dart` gains the original's pure function, built on the
framework's two and byte-equal to `../chord/src/notify.ts:320-328`:

```dart
/// The name of the terminal user variable the window keeps the main
/// session's id in, for a launcher to reopen it with `--resume`.
const sessionVarName = 'chord_session';

/// The bytes that set `chord_session` to [id], or empty for none; inside
/// tmux, through its passthrough.
String sessionVarBytes(String? id, {required bool tmux}) {
  final bytes = userVariableBytes(sessionVarName, id ?? '');
  return tmux ? tmuxPassthrough(bytes) : bytes;
}
```

Its tests pin the original's three cases from
`../chord/tests/notify_test.ts:457-475` (an id, none, each inside tmux).
The window does not call `sessionVarBytes`: it calls
`terminal.setUserVariable(sessionVarName, id ?? '')`, and the terminal
wraps for tmux as it wraps the notifications, from its own `TMUX`, as the
original's `env.tmux` does. `sessionVarBytes` exists so the bytes the
original writes are checked once, against the framework that writes them.

When the window writes, and what it never writes, is the task's acceptance
as the board states it (`board show CTUI-159`), from
`../chord/src/ui/app/terminal.ts:67-120`.

## What tests see

The port's `RecordingTerminal` (`test/ui/app/selection_window_test.dart`)
records the calls, not bytes, as it records `notify` and
`setProgramStatus`:

```dart
/// The user variables set, as `setUserVariable` was called.
final userVariables = <(String, String)>[];
@override
void setUserVariable(String name, String value) =>
    userVariables.add((name, value));
```

A window test then reads, for example,
`[('chord_session', ''), ('chord_session', id)]`. The framework's own test
checks `StdioTerminal`'s bytes through its `output` sink, with and without
`tmuxPassthrough`.

## The screen

Nothing is drawn. A terminal without OSC 1337 ignores the sequence, and the
framework's renderer does not count it as drawing.
