# Decisions

A log. An entry is added when something is decided and is not rewritten
later; a decision that changes gets a new entry that names the old one.

## State is `setState`

README's open question "`setState` or signals". `setState`, `InheritedWidget`
and `Listenable` come first, because they are the Flutter way and the one
people know. Signals may come later as an option beside them; nothing in the
element tree rules them out.

## Actions are bound at run time, for now

README's open question "How actions are generated". Until the code generator
exists, keys are bound with the `Actions` widget and `Binding('ctrl+o',
'Toggle details', fn)`. Two bindings of one scope that claim one key, and a
chord that starts with another binding's key, throw when the scope is
mounted, which is the run-time form of "the build fails". The `@Action`
annotation and the generated rebinding file are a task of their own; when
they land they sit on top of `Actions`, not beside it.

## With ctrl, the case of a letter means nothing

A terminal without the kitty keyboard protocol sends one byte for ctrl+o and
ctrl+O, so `ctrl+O` in a binding is read as `ctrl+o`. Without ctrl, an
upper-case letter is shift plus the lower one: `G` is `shift+g`.

## The whole tree is laid out and painted every frame

A terminal has a few thousand cells, and what reaches it is only the cells
that changed, so the cost that matters, bytes written, is already bounded by
the diff. Marking render objects dirty one by one is left until a profile
shows that layout is what a frame spends its time on. Long lists do not wait
for that: they are virtualised.

## Render children are synced from the element tree

Flutter inserts and moves render objects one by one as elements change.
Here, when an element was mounted or unmounted since the last frame, every
render object's child list is read again from the element tree before
layout. It is one walk of a small tree and has no slot bookkeeping to get
wrong.

## Raw mode through `stty`

Dart's `stdin.lineMode = false` leaves signals, flow control and CR
translation on, so ctrl+c, ctrl+s and ctrl+q never arrive as keys and Enter
arrives as a line feed. `stty raw -echo` on `/dev/tty` turns all of that
off, and the saved `stty -g` puts it back. Where `stty` fails, Dart's own
modes are the fallback.

## Windows is out of the first version

README's open question. Raw mode, SIGWINCH and the process groups the port
needs are POSIX. The `Terminal` interface is the seam a Windows terminal
would go behind.

## The tester depends on `test_api` and `matcher`, not `test`

`lib/testing.dart` gives `testWidgets` and `shows`, so it needs `test` and a
matcher base class. `test_api` and `matcher` are what `flutter_test` builds
on too, and are much lighter than `test` as a dependency of every app.

## The port is a package of its own, under `example/chord/`

The port needs packages the framework must not carry (an ACP client, YAML,
process handling), and it must use the framework only through what
`package:chorded_tui` exports, as any app would. A package with a path
dependency gives both.

## The port's fake agent is the original's, run with bun

CTUI-13 asked the owner to choose between running the original's fake agent
(`../chord/tests/fixtures/fake_agent/main.ts`) with bun and porting it to
Dart. The owner left it to main's recommendation: run the original's. Every
scenario exists at once, and the port is checked against the very agent the
original is checked against, which is the point of a port. The cost is that
the port's tests and `--fake` need bun and `../chord`; a test that finds
neither is skipped with a message saying so, never failed silently. A
scenario the port needs and the original lacks is not added under
`../chord`: it is raised with the owner.

## Each team run works in its own git worktree

Several team runs go at once, and runs that switched branches in one working
tree would trample each other. A run for task `<key>` works in
`../chorded-tui-worktrees/<key>`, a worktree of this repository on branch
`<key>` made from `main` (`git worktree add ../chorded-tui-worktrees/<key>
-b <key> main`). main merges the branch into `main` when the lead reports it
ready and removes the worktree.

## CTUI-1: no scrollbar in the first list

The task asked for a scrollbar drawn in one column; the original draws none
(every scrollbox in `../chord/src` hides its own, and the transcript and the
logs say what is hidden with a rule row). Options: a `Scrollbar` widget the
port does not use, or none. The owner, through main, chose none.
`ScrollController` exposes `contentRows`, `viewRows` and `offset`, so one
can be added later without changing it.

## CTUI-1: the port does not port `mount.ts`

The original mounts only a tail of the transcript's entries and loads older
ones in chunks as the view nears the top (`src/ui/transcript/mount.ts`),
because OpenTUI lays out and keeps every mounted renderable. A virtualised
list builds only what is in sight, so the port passes every entry to
`ListView.builder` and needs no mount window and no insert-above contract.
Options were not porting it, or porting it with an `insertedAbove(n)` on the
controller. The owner, through main, chose not to. A deliberate difference:
home reaches the first entry in one press, where the original stops at the
top of the mounted window and then loads more.

## CTUI-1: a list builds its items during layout

How heights are known is decided by laying items out, so which items are in
sight is known only in layout. Options: lay the whole list out every frame
(the reason virtualisation exists); the original's shape, a mounted window
laid out whole with culled paint; choosing the range in build from cached
heights (a wrong guess shows a gap for a frame); Flutter's slivers whole;
and Flutter's child manager alone. Chosen: the last. `ListViewportElement`
is the render object's child manager and mounts items from inside
`performLayout` under `BuildOwner.buildDuringLayout`, which syncs the new
item's subtree and leaves `structureChanged` alone. "Render children are
synced from the element tree" still holds for everything else. Only the
items in sight stay mounted; no keep-alive.

## CTUI-1: every item's height is measured exactly

chord's rule says "12 lines below" and the log box "155 lines above", and
the follow rule decides fits and the bottom from the content's height, so an
estimate can resume following and lose the reader's place. Options:
estimates refined by a background measurer (Flutter's way); exact below the
view and estimated above it; every height measured exactly, in the frame,
when it is unknown. Chosen: the last, as the simplest and the original's own
result. Heights are cached by index at one width and dropped by a width
change or by `itemVersion(i)`, a value the app gives that changes with
anything that changes the item's height, global inputs included; without it
every rebuild drops every height. Consequence: a width change or the first
frame of a resumed session measures every item once. The ship task
benchmarks 10 000 entries under `dart compile exe`; if that frame is too
slow, the fallback (exact below, estimated above) is a new entry here.
Items built only to be measured run `initState` and `dispose`, and items in
a list take no focus.

## CTUI-1: the follow rule is the original's reducer, in the framework

`reduceScroll` (`src/ui/transcript/scroll.ts`) is ported case by case into
`lib/src/foundation/scroll_state.dart`, plain Dart, with the original's
tests, because following the bottom is what any log or chat view needs and
README promises it as `Follow.bottom`. The drag hold is left out (no mouse).
`Follow.none` is the same state with following never set, for pickers.
News is set only by `markNews()`, never inferred from growth, because a
relayout also changes the content's height and the original does not call
that news. The controller's counts are plain geometry; the rule's wording
and its count, which includes the row the rule covers, are the port's.

## CTUI-1: a frame lays out at most twice

Layout sets the scroll state; what draws from it (the transcript's rule, a
log box's rules) was built before. Options: draw it a frame late, as the
original does; give the list a footer built inside its layout; or build and
lay out once more when layout's notifications dirtied anything. Chosen: the
last, once, in `AppHost.drawFrame`, so one `pump()` shows a settled screen;
what a second layout changes is drawn next frame, never in a loop.
Listeners are never called during layout, mutations made while a controller
notifies are applied after the round, and `ChangeNotifier` gains a disposed
flag.

## CTUI-1: scroll keys are the app's, through `Actions`

`ListView` binds no keys and takes no focus. `scrollBindings(controller,
keys: ScrollKeys(...))` returns plain `Binding`s with descriptions; the
defaults are pageup, pagedown, home and end, and no line keys, because
plain up/down belong to a prompt's history and a picker's highlight. The
port passes chord's keys (`shift+up`/`shift+down` for lines, a shifted twin
for each). A widget layer over it (`ScrollActions`) was dropped as a second
keymap API with no need. `TextInput` takes home and end itself; whether it
can leave them to an outer scope is the text area task's question.

## CTUI-1: no package for scrolling

Scrolling, virtualisation and the follow rule are about the terminal's
layout, so the rule "a maintained package before our own code" does not
apply. No package was tried.

## Until the picker, `chord` opens an interim window

CTUI-11 builds the port's CLI before its ACP client and its start page.
`chord <agent>` refuses an unknown name and a start command missing from
PATH as the original does, word for word; `chord` with no name starts
`claude`, the original's default, until the start page (M1) asks. Past
the refusals it opens one line, `chord v<version> · <agent title> ·
<directory>`, with a key hint; ctrl+c and ctrl+d quit at once, bound
through `Actions`. It shows the port starts on the framework, and the
tasks that start the agent and draw the start page replace it.

## The port has a version of its own

`chord --version` prints `chord <version>` as the original's Cliffy does,
with the port's version from `example/chord/pubspec.yaml`, starting at
0.0.1, not the original's: the port does not do yet what that release
does.

## The port's help is the original's wording in `args`' layout

The original's help is Cliffy's. The port parses with `package:args`,
whose usage text is laid out differently, and copying Cliffy's layout by
hand would be a printer of our own beside the package. So the help keeps
the original's words (the description, the commands, the options and the
examples for what exists) in a plain layout built from `args`' usage.

## The port finds commands on PATH with `process_run`

The original refuses an agent whose command PATH lacks, through
`@david/which`. pub.dev's `which` does not fit: its last release, 0.1.3, is
from 2015, before null safety, and Dart 3 will not resolve it.
`process_run`'s `which` does fit: it is maintained, pure Dart, so it builds
under `dart compile exe`, and checks the file is executable as the
original's does. By default it also lays its own user env files (and the
running Dart's directory) over PATH, which would find commands the person's
shell does not; the port calls it with `Platform.environment` and
`includeParentEnvironment: false`, so the real PATH alone is read, and a
test holds that. `process_run` needs Dart 3.12, so the port's SDK
constraint rose to `^3.12.0`; the framework's stays where it was.

## The port refuses a call as the original's Cliffy does, but for `--nope`

A call chord cannot take (an unknown agent, an unknown option, too many
arguments, an argument to `chord agents`) prints the help on stdout, then
`  error: <message>` between blank lines on stderr, and exits 2, as the
original's Cliffy does. `args` words its failures differently, so the port
words the ones in scope as Cliffy does, without Cliffy's "Did you mean"
suggestion. As in the original, `chord -V` prints the bare version and
`chord --version` prints `chord <version>` ("The port has a version of its
own"). One difference is deliberate: the original's Cliffy hands an unknown
option on the main command, `chord --nope`, to `[agent]` and says
`Unknown agent "--nope"`; the port says it is an unknown option, as that is
an accident of Cliffy's, not something chord means.

## CTUI-13: `chord --agent-command x agents` runs `chord agents`

The original's Cliffy reads `chord --agent-command x agents` as a window on
an agent named `agents`, started with `x`; the port's `args` runs the
`agents` command, as it does for `chord agents` alone. The owner, through
main, chose to leave it: like `--nope` above, it is an accident of Cliffy's,
not something chord means, and copying it would take a special case in the
parse.

## The theme's roles are styles, and the terminal is asked once at start

CTUI-3. `ThemeData`'s roles are `Style`s, not colours, so `dim` stays the
attribute and the plain theme (NO_COLOR) can still mark focus and the
selection with `bold` and `inverse`; plain and dim text are never painted,
as in the original. `runApp` asks the terminal for its background with OSC
11 at start and waits at most 100 ms, then reads `COLORFGBG`, then takes
dark, which is the original's order and wait. The input parser reads OSC
replies as events of their own, so an answer that comes late is dropped
instead of arriving as typed keys; the original needed a filter in front
of its input for that. A reply's code has at most nine digits and a reply
at most 1024 characters; past either, its bytes are given back as keys.
NO_COLOR outranks every theme, an app's own included, and the framework's
demo shows it. Text that hides itself whole when it does not fit
(a `TextOverflow` mode, or `LayoutBuilder`) was left out of CTUI-3: the
demo's label ends in an ellipsis instead.

## CTUI-1: a resize frame of about 110 ms at 10 000 entries is accepted

The design made exact heights depend on a benchmark: if the frame that
measures every item after a width change is too slow, the fallback (exact
below the view, estimated above it) is a new decision.
`benchmark/list_view.dart`, 10 000 markdown-like entries (63 002 rows), no
terminal, under `dart compile exe`: first frame 112 ms, a resize to 80x24
116 ms and back 110 ms, a steady frame 0.11 ms, 16 appends per frame
(about 1 000 a second at 60 frames) 0.44 ms median and 1.1 ms at most
while following, 0.48 ms median and 1.5 ms at most while scrolled back.
Under `dart run` the resizes took 67 and 64 ms. Options: accept the one
hitch per resize and per resumed session, or build the fallback now. The
owner, through main, chose to accept. The fallback comes only when a real
session shows the resize hitch; the benchmark stays in the tree to be run
again.

## CTUI-35: the switch frame, measured

The design keeps one transcript keyed by the shown session over that
session's retained `ScrollController`, so every switch builds a new
viewport whose item heights start cold; if that frame is too slow, the
fallback is per-session extents kept outside the viewport (open question 2
of the framework draft). `benchmark/list_view.dart` gains a switch run:
two sessions of 10 000 markdown-like entries (62 999 rows each at
120x40), one following and one scrolled back to entry 5 000, the list
keyed per session as the window keys its transcript, 40 round trips, no
terminal. Under `dart compile exe`: a switch to the following session
425 ms median, 445 ms at most; to the scrolled-back one 432 ms median,
450 ms at most; a round trip 856 ms median, 894 ms at most; a switch back
after a resize to 80x24 469 ms. The scrolled-back session landed on entry
5 000 at its row in 40 of 40 round trips, and on entry 5 000 after the
resize. Under `dart run`: 379 and 382 ms median, 550 and 634 ms at most,
a round trip 765 ms median. The run was at the lowest priority on a busy
machine, and the same binary's first frame took 433 ms and its resizes
449 and 427 ms where CTUI-1 recorded 112, 116 and 110, so the absolute
figures are about four times what CTUI-1's conditions give. The finding
holds either way: a switch costs what the first frame of a resumed
session or a resize costs, one measurement of every entry, so on CTUI-1's
terms about 110 ms. It does not fit a 16 ms frame at 60 fps; each switch
to a long session is a visible hitch. Not built: per-session extents kept
outside the viewport, the fallback, which would make a switch a steady
frame. Accepting the hitch, as CTUI-1 accepted it for resize and resume,
or building the fallback is the owner's call; the benchmark stays in the
tree to be run again.

## CTUI-12: the port serves no fs and no terminal requests

The task asked for "fs and terminal requests"; the original's
`clientCapabilities()` declares neither, on purpose, so agents use their
own tools, and draws command output from the tool call's `_meta`. Options:
follow the original (declare neither, answer -32601); handlers left
undeclared; handlers declared, differing from the original. The owner,
through main, chose to follow the original and said the task's wording was
wrong. Serving them later is a feature of its own (file access inside the
session's directory, a terminal manager), not a change to the wire.

## CTUI-12: chord's requests through `json_rpc_2`, the agent's through a dispatcher of ours

`json_rpc_2` 4.1.0 builds under `dart compile exe`, answers -32601 and
-32700, and fails every pending request when the stream ends; it frames
nothing and never gives a handler its request's id, so the agent's
`$/cancel_request`, how it withdraws a permission request, cannot reach the
handler through `Peer`. `jsonrpc2` 3.0.1 is Dart 2 only. Options: `Peer` as
it is, with no withdrawal; `json_rpc_2`'s `Client` for chord's requests and
about a hundred lines of our own for the agent's; all our own. The owner,
through main, chose the second. The framing (newline-delimited, the SDK's
32 MiB cap, -32700 and -32600 untapped) is ours below both.

## CTUI-12: no Dart ACP package; the types are views over the decoded maps

Tried: `dart_acp_sdk` 0.1.1 (drops unknown update kinds, enum values and
fields; lacks 2.6's notices, compaction, subagents), `acp_dart` 0.5.0
(tracks TS SDK 1.5.0; loses a tool call with an unknown kind and prints the
error to the console), `acpd` 1.0.0 (stable v1 only), `acp` 0.1.0-rc.3
(ACP v0.12, unlisted), `dart_acp` 0.1.1 (an early spec). None follows the
schema the original pins (SDK 2.6.0), and the typed ones drop what the
original keeps. Generating: `dart_acp_sdk`'s generator stops on 2.6's
`x-deserialize-default-on-null`; quicktype was not run (its install was not
allowed in the trial); `json_serializable` reads no schema. Options:
generated classes, hand-written classes, maps with hand-written extension
types as views. Chosen: the last, about thirty views for M0/M1, with a
library-private representation, kinds dispatched on their string, enum
values as strings, so unknown kinds, values and fields are kept as the
original keeps them. A generator of our own may be weighed when M2 and M3
grow the set.

## CTUI-12: an agent's process group through a re-exec launcher

Dart's `Process.start` cannot `setsid`; `setpgid` from the parent is
refused after exec; `detachedWithStdio` loses the exit code; `setsid(1)` is
missing on macOS; `butcher_process` 0.1.0 takes no environment, sends only
SIGKILL and needs perl on macOS. Options: chord re-executing itself as a
launcher that calls `setsid` and `execv` through `dart:ffi`; a
setsid-then-perl shim of our own; `butcher_process` after upstream changes.
The owner, through main, chose the launcher. It also resets SIGPIPE, which
Dart's children inherit ignored, and tells chord the group exists with a
nonce frame on stderr the agent cannot forge. Cost: about 12 ms per agent
compiled, about 170 ms under `dart run` and `dart test`. `posix_spawn`
through ffi was set aside for needing our own pipes and reaping.

## CTUI-12: M0 and M1 declare no client capabilities

The original declares elicitation, `plan`, `session.compaction`,
`session.notices`, `subagents` and `_meta.terminal_output_delta`, and each
changes what agents send. M1 draws none of them. Options: declare nothing
until each is drawn; declare as the original and hide what is not drawn;
bring the drawing forward into M1. The owner, through main, chose the first,
a staged difference from the original: until each lands, agents send their
fallbacks (reply text, tool calls; Codex sends no subagent work and its plan
as reply text). M1's plan checklist is the base `plan` update, which needs
no capability. Each capability is declared by the task that draws it,
listed in `docs/design/CTUI-12.md`. `elicitation/create` is answered
`cancel` and cursor's and grok's plan requests `cancelled` meanwhile, never
-32601, which cursor reads as accepted.

## CTUI-12: the agent's command line is split by a port of shell-quote's parse

The original splits a settings file's command with shell-quote 1.12.0,
keeping `$NAME` literal and refusing operators, globs and comments. Tried
on 16 lines: `io` 1.1.0's `shellSplit` and `shlex` 2.0.2 refuse none of
those, differ on `${X}y`, and throw on an unclosed quote that shell-quote
accepts. Options: a port of the parse; `io` with a check of our own in
front; `io` alone. The owner, through main, chose the port, with
shell-quote's results on the 16 lines as its tests.

## CTUI-12: cancellation through `cancellation_token`

The client needs a token many listeners share, an "any" of several, and a
cancel that runs its callbacks synchronously, so `close()` can enqueue every
`cancelled` answer ahead of stdin's end. `cancellation_token` 2.0.1 does all
three (`MergedCancellationToken`, synchronous `onCancel`).
`package:async`'s `CancelableOperation` cancels one operation and has no
merge. Taken; no token of our own.

## CTUI-12: the client follows the original where the schema or caution would differ

Decided without the owner, since the port follows the original: the
protocol version an agent answers is kept and not acted on (the schema says
a client should disconnect); no timeout on `initialize` or any request, only
the stop is bounded; the connection ends at stdout's end, not at the exit;
chord's writes to an agent are not bounded (a non-reading agent is a hung
agent the person closes; a bound that treats it as gone was proposed and
not taken); chord closes its agents on SIGTERM, SIGINT and SIGHUP and kills
their groups before it exits. A permission withdrawn by `$/cancel_request`
is tested in unit tests only, as no scenario of the original's fake agent
plays it; the owner, through main, chose that over asking for a scenario.

## CTUI-12: relative PATH entries are the agent's directory's, laid over `process_run`

`process_run` 1.4.4's `whichSync` joins each `PATH` entry with chord's own
current directory and takes no other, so a relative or empty entry (`bin`,
`.`, `::`) found a program beside chord rather than beside the agent, or
refused one the agent's directory holds. The original starts agents through
node's `spawn` with a `cwd`, and libuv looks the program up with `execvp`
after the child's `chdir`, so relative entries are the agent's. Options:
make every relative or empty entry absolute against the agent's directory
before calling `whichSync`; a lookup of our own; accept the difference. The
owner, through main, chose the first: `resolveProgram` rewrites the agent's
`PATH` for the lookup alone, an empty entry meaning the directory itself.

## CTUI-12: a malformed answer to a waiting request fails it, laid over `json_rpc_2`

The SDK's `Connection.handleResponse` fails a request of chord's when the
agent answers its id with a malformed response (no `result` and no
`error`, both, no `jsonrpc`, an error without an integer code or a string
message): -32600 "Invalid request", the response as data. `json_rpc_2`
4.1.0's `Client` drops such a response, so the request would wait until
the person cancelled or closed. Options: accept the difference; turn such
a response, in our router, into a well-formed -32600 error for the id the
`Client` waits on. The owner, through main, chose the second, so a person
sees the failure as in the original. A malformed response to an id nobody
waits on is dropped, as both do. An error code written as an integral
double (`1.0`), which the SDK reads as the integer it is and `json_rpc_2`
would drop, is read as that integer first, as the lead settled within
that choice; a code that is not integral is malformed.

## CTUI-13: the dev runner reads and quotes its own arguments

`example/chord/tool/dev.dart chord [--fake] [args…]` follows the original's
`bun dev chord`, a Cliffy command with `stopEarly` and `[args...]`: its one
option comes first, chord's own options pass through untouched, an empty
word is dropped before the first `--`, and what follows `--` goes to chord
as it is. `args` 2.7 was tried: with `allowTrailingOptions: false` and a
`fake` flag on a `chord` command, `chord --fake -p hi` and `chord --fake
--unknown x` throw on the option it does not know, where Cliffy hands them
to chord, and it keeps the empty words Cliffy drops. Fitting it would take
splitting the argv ahead of it, a workaround, so the owner, through main,
chose a parse of our own of about twenty lines, held by tests on the six
cases checked against Cliffy itself. The fake's command line, which the
port splits back with its port of shell-quote, is quoted by a few lines of
our own too: a word of `[A-Za-z0-9_@%+=:,./-]` alone as it is, any other
in single quotes with `'` written `'\''`. `shlex` 2.0.2 (last published
2021) was set aside as unmaintained. `process_run`'s `shellArguments`,
already a dependency, was tried and quotes only for whitespace, quotes and
backslashes, so a path holding `;`, `|`, `&`, `(`, `*` or another
operator came out bare and chord's split refused it; the owner, through
main, chose our own quote over a workaround around it. Tests round-trip
every operator through chord's split.

## CTUI-15: the session keeps the original's three layers

Considered: one session object for M1 holding turns and the queue, or the
original's `Session` (one agent, one ACP session), `Conversation` (turns,
queue, delivery) and the window's `reduceApp`. Chosen: the three, with the
early buffer and routing as a pure `SessionInbox` in `inbox.dart` and
`ui/app/state.dart` in CTUI-15. Merging would be undone in M2, when clear
and resume swap a `Session` under one `Conversation`. Consequence:
`Session` keeps ten of the original's forty members, `withdraw()` not among
them; routing is an exact session-id comparison until subagents bring
`routed`; `Conversation` emits events and holds no state. Events wrap
transcript actions (`Transcribed`), since a sealed class's direct subtypes
must share its library and the reducer must not import `Conversation`.

## CTUI-15: transcript state is sealed classes, and identity is the change signal

Considered: sealed classes, extension-type views as CTUI-12 chose for the
wire, records. Chosen: sealed classes with final fields, ACP data inside
them kept as CTUI-12's views; no `==` overrides, no `copyWith`, no code
generation. Reducers return the identical object for what they did not
change, so CTUI-1's per-item version check is a pointer compare and "news"
is a new entries list, as the original's `withNews`. Tests compare by value
through an exhaustive `described()`. Lists are core `List`s copied on write
behind `entries.dart`'s three writers. Packages tried under
`dart compile exe`: `fast_immutable_collections` 12.0.0, `built_collection`
6.0.0, `collection` 1.19.1; all build, none is cheaper on the hot write
(replacing the last entry: 11 µs copied, 20 µs with FIC, at 10 000
entries), so none is taken. The benchmark carries an AOT budget; missing it
changes the writers' backing, as a new decision.

## CTUI-15: a reply's text is a `TextRun` over a shared `StringBuffer`

A literal port of `appendText` copies the whole reply per chunk, since Dart
strings are not ropes: the fake's `flood` folds in 3 632 ms against 6 ms
with the parts kept. Chosen: an immutable snapshot over a core
`StringBuffer` its successors share, appending in place from the latest
snapshot and forking from an older one, its joined text cached. No package:
the core library is the rope. What the transcript holds and shows is the
original's; the owner, through main, agreed.

## CTUI-15: enrichers run as a relay on CTUI-12's connection

The original runs the enricher chain on the transport, before the tap,
routing and the permission handler. Options: (a) run it in the session
layer twice, on updates and in the permission bridge, CTUI-12 untouched;
(b) an optional `relay` on `openAgent`/`connectAgent` at the original's
place; (c) no chain in M1. The owner chose (b). It is additive: no relay is
CTUI-12's behaviour and every one of its tests stands; a throwing relay
fails open, the raw message passed on. `docs/design/CTUI-12.md` is amended
in place with a pointer to CTUI-15. Consequence: the tap, the inbox and
`onPermission` see enriched messages, so a permission request's title is
filled before the bridge sees it; the record will keep enriched traffic, as
the original's; CTUI-13's `AgentOpener` gives way to `SessionOpener`, which
takes env and the relay.

## CTUI-15: M1 takes four enrichers

Of the original's fourteen: `toolCallFacts` and `rawOutputContent` (a
permission's title, output sent only as `rawOutput`), and, by the owner's
choice (option a over deferring them as recorded differences),
`codexMcpCall` and `codexGuardianReview`, with `ToolCall.mcp` and
`guardian`, since both change tool calls CTUI-16 draws. The other ten join
with subagents, mode setting, costs and elicitation.

## CTUI-15: command output under `_meta` is folded without declaring the capability

CTUI-12 said command output arrives as text once while
`_meta.terminal_output_delta` is undeclared. Runtime's captures show that
holds for Claude, droid and autohand only: Codex and pi send output only
under `_meta` (`terminal_output_delta`, `terminal_output`, `terminal_exit`)
to every client, and the original's reducer folds those keys whatever was
declared. Options: (a) accept no output for those agents until M3; (b) port
the fold now without declaring; (c) declare the capability in M1. The owner
chose (b), as its own last unit, with a package trial for the VT parser
(`terminal_text.ts`) before any of our own; a package that does not fit
goes back to the owner. Declaring stays the M3 task's.

## CTUI-15: the status line shows what the agent reports, read-only

CTUI-19 asks for model, effort, mode and context; the brief had left them
out. The owner chose read-only facts: `AgentState` seeded from
`session/new`'s answer and folded on `config_option_update` and
`current_mode_update`, the transcript's `mode` and `usage` (`used`, `size`)
as the original's reducer keeps them. No setters, no `windowFromModel`
estimate, no cost.

## CTUI-15: after the agent exits, send stays enabled, as the original

The interface draft proposed disabling send once the agent is gone. The
original's `canSend` reads only that the session was ready, and its
conversation draws the next prompt and fails it with `The agent exited…`.
Chosen: the original's; the owner, through main, agreed. The window learns
of the exit through a `Gone` event carrying CTUI-12's bounded stderr tail;
an idle exit adds no transcript notice, as in the original.

## CTUI-15: a permission's review reason and deadline are carried

`_meta["chord/permission"]`'s `review` and `deadlineAt` reach the state
through a port of `permission_review.ts`, as the original's `waitFor`
spreads them, because CTUI-18 must show the reason at 80x24. Generic
permission metadata, apart from Codex's Guardian tool. The deadline is the
agent's; chord never computes one.

## CTUI-15: a permission's deadline is carried as the agent's number

The design typed `PermissionWait.deadlineAt` as `int?`, which would have
truncated a fractional deadline and clamped one past 2^63. The original's
`permission_review.ts` keeps any finite, non-negative number the agent sent,
unchanged. Options: truncate to `int`; read a non-integral or out-of-range
number as no deadline; carry a `num?` unchanged. Main chose the last:
`deadlineAt` is `num?`, kept as the agent sent it, fractions included, with
the original's finite, non-negative check. The design is amended in place.

## CTUI-15: a malformed field of a permission request is left out

CTUI-12 checks a permission request's session id, tool call id and options;
the tool call's title, kind, locations and content arrive unchecked. The
original's `waitFor` spreads whatever arrived and never drops or answers a
request for its fields, but a Dart wait holds typed fields and the screens
read them. Options: drop the whole request, answer it `cancelled` at once,
or leave out the malformed field. Chosen, with main's agreement: `waitFor`
leaves out a title or kind that is no string and locations or content whose
fields do not read, and keeps the request, so the person can still answer
it and the agent is not left waiting.

## CTUI-15: terminal output is parsed by our own port of terminal_text.ts

Command output Codex and pi send only under `_meta` is folded as the
original's `terminal_text.ts` folds it: a streaming VT500 parser whose state
between deltas is a small value (the escape it ends inside), over a screen
with no width or height, cut to the last 30 000 characters from a line's
start. Tried first under `dart compile exe`, against its 23 fixtures read
whole and split at every position:
- `xterm` 4.0.0 (last released 2024-02, declares Flutter; `core.dart` builds
  AOT): a full emulator with a fixed geometry and a mutable whole-screen
  state; 10 of 23 fixtures as the original, as it takes C1 bytes for text,
  `\v` and `\f` for line feeds, and reads nF escapes, intermediates and CAN
  otherwise.
- `xterm2_core` 1.0.0 (pure Dart, one release, 2026-10): the same model; 11
  of 23, a line feed keeps the column, lines scroll and wrap by its
  geometry, and an nF escape filled a line with `E`.
- `termparser` 0.5.0: a parser of a terminal's input (keys, mouse,
  reports); `CSI 2 A` came out a key, `CSI K` was swallowed, an OSC ate what
  followed.
- `ansi_escape_codes` 4.0.1: reads a whole string for its styles; no
  stream, no cursor or erase, no state between deltas.
- `ghostty_vte` 0.1.3 (FFI to libghostty-vt): `dart compile exe` refuses its
  build hooks, and it needs Zig or a prebuilt library.
Both emulators read every fixture the same whole and split; the misfit is
the model. Main chose our own port, in `example/chord/lib/session/
terminal_text.dart`, graphemes by the `characters` package and cell widths
by the framework's `graphemeWidth`. Where Dart's grapheme breaks differ from
the original's `Intl.Segmenter`, a lone high surrogate (a delta ending
between a pair's halves) is kept with the cluster before it, as ICU does,
so a split there folds as the whole.

## CTUI-15: numbers the agent sends are carried as num?, unchanged

The design typed some of the agent's numbers as `int`, which in Dart turns
a float the agent sent into a type error or a truncation where the original
keeps the number as it came. Main set the rule: any number the agent sends
is carried as `num`, unchanged, without asking each time. Applied to
`PermissionWait.deadlineAt` (already, by its own entry above) and
`Terminal.exitCode`, and to the views the slice reads: `UsageUpdate.used`
and `size` (so `Usage`), and `ToolCallLocation.line`. A number that is no
finite number, where the original's schema refuses it, still makes its own
field malformed. The JSON-RPC error code stays an `int`, as `json_rpc_2`
reads it, and chord's own clock readings are `int`. The design is amended in
place.

## CTUI-4: code blocks in Markdown wrap, unlike chord's

chord's code boxes cut a long line at the box's edge, and with no
horizontal scroll the rest of it cannot be reached. Markdown's code blocks
go through Code, which wraps long lines and marks each continuation with
`↪`; `Code` takes `softWrap`, on by default, as `Text` does. A deliberate
difference from the original, decided by main for the owner: the keyboard
comes first, and clipped code cannot be read. Copying is not affected, since
a copy takes the source, not what is drawn.

## CTUI-4: a new link reference definition re-parses the whole reply

Markdown keeps the top-level blocks before the last one frozen while a
reply grows. A link reference definition can change how earlier blocks
read, so when appended text adds one (a line that starts `[label]:` as
CommonMark allows), the frozen blocks are dropped and the reply is parsed
whole. Definitions are rare in replies, and this stays exactly equal to a
full parse without tracking which block uses which label.

## CTUI-6: one shared number gutter, as chord's

A diff row carries one number: the old line's on a removed row, the new
line's on every other row, as chord's `DiffRows` and `docs/images/edit.png`
draw it. That is what the task's "old and new line numbers" means here; two
columns would take cells from the code and differ from the original.

## CTUI-5: code is highlighted by `highlighting`, pinned

chord colours code with emphasize 7, that is lowlight over highlight.js
11.9 and its `common` set of 35 languages. Tried under `dart compile exe`:
- `highlighting` 0.9.0+11.8.0 (a Dart port of highlight.js 11.8, pure Dart,
  last released 2023-05, not maintained since): builds AOT, has every
  language of the common set among 192, and its classes, character by
  character, matched chord's own lowlight on twelve languages (TypeScript,
  Python, bash, JSON, Rust, Go, YAML, CSS, C++, diff, XML, SQL). It is
  slower than linear on long input: under `dart run`, 50 lines 2 ms, 500
  lines 15 ms, 5 000 lines 385 ms; AOT, 7 500 lines 800 ms. Its `parse`
  takes a grammar's id and throws on an alias, so names are resolved
  through each grammar's own `aliases` list, as emphasize's `registered`
  does.
- `highlight` 0.7.0 (highlight.js 10, 2021): builds AOT and is fast
  (62 ms for 7 500 lines), but lacks php-template, python-repl and wasm,
  and its classes matched lowlight's on 58 to 100 per cent of characters.
- `val_highlight` 0.1.1 (2026-10, maintained): builds AOT and is the
  fastest (6 ms for 7 500 lines), but its grammars and scope names are its
  own, so colours would differ from chord's, and it lacks arduino,
  php-template, python-repl, vbnet and wasm.
- `re_highlight` 0.0.3 (2024-02): its library imports Flutter; the AOT
  build fails on `dart:ui`.
- `syntax_highlight` 0.5.0: Flutter only (its grammars are Flutter assets).
Main chose `highlighting`, pinned to the exact version, for being the only
one that draws as chord draws, accepting that it is unmaintained and slow
on long files. The 64-result cache, as chord's, absorbs repeats. It sits
behind `highlightLines`, `fenceLanguage` and `pathLanguage`, which name no
package type, so a swap stays inside `lib/src/text/highlight.dart`. Its
other grammars beyond the common set (Dart among them) are kept: no alias
is claimed by two grammars, so every name chord knows means the same here.
CTUI-4's streaming benchmark measured the cost: a reply that is one open
50 KB code block takes 82 ms a frame at 50 KB (30 ms median over the
stream), almost all of it highlighting the whole block again on every
chunk, since its text changes each time and the cache cannot hold it. The
lead accepted it for this slice; later options are highlighting an open
fence only up to its last complete line, or not until it closes.

## CTUI-4: Markdown is parsed by `markdown`, its block ends noted by subclassed syntaxes

chord lexes replies with marked (GitHub's flavour). `markdown` 7.3.1
(dart-lang, 2026-03) was tried under `dart compile exe`: its GitHub set
gives tables with alignment, task lists, strikethrough and fenced code; an
unclosed fence is code to the end; with `encodeHtml: false` text stays
literal. A 50 KB reply parses in 17 ms AOT (20 ms under `dart run`). The
document is configured as marked reads GitHub's flavour: no footnotes, no
emoji codes and no inline HTML, so raw HTML stays text. No other Dart
Markdown parser was weighed beside the language team's own.

The design re-parses an appended reply from its last top-level block, so
the parse needs where each top-level block ends in the source; the
package's nodes carry no source positions and `BlockParser` keeps its line
position private. Options taken to main: (a) note the boundaries through
the package's public extension point, its block syntax list; (b) a scan of
our own for block boundaries; (c) re-parse the whole reply on every update.
Main chose (a). Each of the package's block syntaxes is subclassed with a
mixin whose `parse` calls the package's and notes, for the top-level parser
only, the line after the block; subclasses rather than wrappers, so the
package's own `is` checks between syntaxes still hold. A tail is parsed by
the same `Document`, so references defined above it still resolve; an
appended line that starts a reference definition re-parses the whole text,
as the design says, since it can change links above. A test checks that
every prefix of two fixtures parses as a whole parse of it does.

## CTUI-4: definitions are blocks, and a changed set of them re-parses

This supersedes the last part of "CTUI-4: Markdown is parsed by
`markdown`, its block ends noted by subclassed syntaxes", and the trigger
in "CTUI-4: a new link reference definition re-parses the whole reply":
invalidating on an appended line that starts `[label]:` misses a definition the package
accepts only lines later (a destination or a label continued on the next
line), after its label line was frozen. The lead, following chord, settled
that definitions show as written where they stand, so the package's
definition syntax is subclassed too and a definition comes back as a block
carrying the label it registered. Each tail parse starts from a fresh
`Document` holding the frozen blocks' definitions; when an append changes
the text's set of definitions (one arrives, or the one being typed
changes), the whole text is parsed again. A test checks every prefix of
three fixtures against a whole parse.

## CTUI-4: a definition left at its opening `<` is caught from the package

`markdown` 7.3.1, the latest release, throws a `RangeError` when a
reference definition's text ends right after the `<` that opens its
destination (`[a]: <`, `[a]:\n<`, inside a list or a quote too): its link
parser reads past the end. A plain `Document().parse` crashes the same way,
so a one-shot parse of such a reply throws, and a streamed reply throws
whenever a chunk ends on that `<`. CommonMark reads an unclosed `<`
destination as no definition. Options taken to main: (a) in our
definition-syntax subclass, catch the package's `RangeError`, step the
parser back to where the definition began with the public `retreatBy`, and
return no definition, so the next syntax (a paragraph) takes the lines, as
the package does for any text that is not a definition; (b) skip the
package's parse when the text ends on `<` after the colon, duplicating its
grammar; (c) a fork of the package under a dependency override. Main chose
(a). Tests cover the shapes above and an every-prefix fixture holding an
angle-bracketed destination. An upstream issue draft for dart-lang/tools
is in `docs/design/evidence/CTUI-4/markdown-rangeerror-issue.md`, for the
owner to file.

## CTUI-6: line diffs by `dartdiff`, a port of the jsdiff chord uses

chord diffs an edit with jsdiff 9's `structuredPatch` (context 3,
`stripTrailingCr`). Tried under `dart compile exe`: `dartdiff` 1.0.0
(2026-02, pure Dart, one release so far) ports jsdiff: its
`structuredPatch` and `parsePatch` gave output identical to chord's
`diff` 9.0.0 on eight fixtures (CRLF, empty old and new, no change, a
reorder, tabs, two hunks), and a 2 000-line file with 40 edits diffs in
2 ms AOT. `diff_match_patch` 0.4.1 (2021) keeps its line mode
(`linesToChars`) private and makes character patches, not unified ones;
`diff` 0.1.1 is Dart 1 and does not resolve; `deviation` 0.1.0 is
experimental and parses no unified text. Main agreed on `dartdiff`. The
unified parser is its `parsePatch`, whose errors become `FormatException`;
a patch of several files, or text with no hunk, is refused by us, and so
are hunks out of order.
Its port has one bug met here: a hunk whose counts promise more lines than
follow, in a patch ending with a line break, indexes the empty last line
and throws a `RangeError` where jsdiff throws its own error; the lead
settled mapping it to `FormatException` with the package's other errors.
Its parser is as lenient as jsdiff's, and the lead kept that, as the
original's behaviour: a count of 1 with no such line reads as 0, an empty
line in a hunk is a blank context line, and any line starting with `\` is
metadata, dropped.

## CTUI-8: fuzzy matching is a port of fzf-for-js, the matcher chord uses

chord filters its `/` commands and `@` files with fzf-for-js 0.5.2: basic
(not extended) matching, its FuzzyMatchV2 scoring, a stable score sort,
`byLengthAsc` and a limit of 100 for files, case-insensitive. Tried under
`dart compile exe`, against a bun oracle over chord's command names and the
22 424 paths `git ls-files` lists in its checkout: `fuzzy` 0.5.2 and
`fuse_dart` 1.0.2 (Bitap, from Fuse.js) are typo-tolerant, so they return
items that do not hold the query's letters in order (`rev` finds `rename`)
and rank by edit distance; `fuzzywuzzy` 1.2.0 and `rapidfuzz` 0.1.1 rank by
Levenshtein ratios over the whole string (`co` puts `pr-comments` first) and
take 3–6 s over the paths; `fuzzy_bolt` 2.0.2 (Jaro-Winkler with
thresholds) drops real matches (`rev` loses `security-review`); `ffuzzy`,
the only package that names fzf, needs Flutter; `fuzzy_string` 1.0.0 has
distance metrics and no search. None reproduces fzf's filter, scores or
order, and none can be configured to. Main chose a port: `lib/src/text/
fzf.dart` carries FuzzyMatchV2, V1 for the inputs upstream sends to it
(length times pattern over its 100 KiB scratch), the basic match, the score
groups cut at the limit before ties are broken, and `byLengthAsc`, with
upstream's BSD-3 notice. Positions are UTF-16 code units, as upstream's.
Its golden cases are upstream's own answers, written by
`test/text/fzf_golden.mjs` and checked in; the tests never run bun.

Upstream normalises items and queries to NFC before matching, and its
positions index the NFC text. Dart has no NFC of its own, so `unorm_dart`
0.3.3 (pure Dart, AOT) does it, at the same two points.

Upstream reuses one module-wide scratch slab without clearing it; a stale
cell can move a reported start and positions in the backtrace, never a score
or the order (2 of the golden results). The lead settled that the port
clears its arrays instead; the golden file takes those results' start and
positions from a fresh copy of the module, which agrees with the port.

Upstream lower-cases a case-insensitive query with JavaScript's
`String.toLowerCase`, which applies two SpecialCasing rules Dart's does not:
İ becomes i and a combining dot above, and a word-final Σ becomes ς
(Final_Sigma). The lead settled porting just those two in `fzf.dart`, with
Dart's own `\p{Cased}` and `\p{Case_Ignorable}`; no package does full
SpecialCasing.

## CTUI-39: no MediaQuery yet

`MediaQuery.sizeOf` was asked for only if a screen needs it. None does:
a `LayoutBuilder` at the root gives the window's size, and the demo's label
drops whole through one. The lead left MediaQuery out until a screen asks.

## CTUI-2: layers find their anchors inside the overlay, by a layout stamp

`RenderOverlay` lays out its base, then walks that subtree summing offsets
to find each `LayerLink` target, and builds its entries with
`buildDuringLayout`; no global-offset pass, paint hook or second tree. So
that a child its parent skipped this frame (a closed Fold's body) is never
read at a stale offset, `RenderBox` carries the layout pass it was last laid
out in, and `AppHost` starts a pass before each frame's layout. The lead
settled both as part of the new render object. A follower is its entry's
root or sits under single-child render wrappers at offset zero; under a
multi-child render object it is an error, which keeps the walk that decides
whether the entry may hold focus complete.

## CTUI-8: Table takes Flutter's parameters, borderless by default

The task names `Table(columns, rows)`; the lead settled Flutter's call site
(`columnWidths`, `TableRow` children of widgets) as the project's shape, with
`columnGap` added and no border by default, since chord's tables outside
Markdown (`/mcp`, `/resume`) are aligned columns. `TableBorder.all` gives
Markdown's grid. Cells are widgets, so an ellipsis is a `Text`'s overflow.

## CTUI-8: Fold is controlled and also folds by height, as chord's

The task's `Fold(title, open, child)` is controlled; chord's own Fold shows
a held box's top rows and `… N more lines` when room runs short. The lead
settled one widget doing both, and no key of its own: the app's action flips
`open`, as README's ctrl+o does.

## CTUI-8: Picker positions index the label, and Text policy is inherited

A `PickerMatch`'s positions index the original label's UTF-16 units; the
fzf adapter maps NFC offsets back per grapheme cluster. chord draws no
matched letters, so the default row does not either. For Dialog's title to
ellipsize whatever widget it is, the lead settled Flutter's way:
`DefaultTextStyle` carries `softWrap`, `overflow` and `maxLines`, and
`Text`'s own, now nullable, fall back to it and then to the old defaults.

## CTUI-41: a growing code block is highlighted on from where it stopped

A reply that is one open 50 KB code block cost 82 ms a frame at its end,
since the whole block was highlighted again on every chunk. While a source
is growing (`growing` on `highlightLines`, `Code` and `Markdown`), the
package's `continuation` resumes it at its last complete line, and the
trailing partial line is highlighted fresh and not kept; once it stops
growing it is highlighted whole, once. Resuming is not exact: whole
highlighting lets a match on one line look into the next (a setext title,
`const f =` before `(x) => x`, a JSON key before its colon) and embedded
grammars lose their state between calls, so while a block streams a line
can briefly show a colour it loses when the block is done. Markdown treats
the reply's last top-level code block as growing while the reply is, since
the parser does not tell an open fence from a closed one; code nested in a
list or a quote is highlighted whole as before. AOT, a growing dart block's
frame at 50 KB is 3.48 ms median (p95 4.44) against a 16 ms budget; the one
whole highlight when it stops takes 112 ms, once. An allowlist of grammars
where resuming is exact was tried first and dropped: the cross-line
patterns are in almost every grammar. Main chose this over highlighting off
the main isolate; the isolate, plain text until the colours arrive, is the
way to remove that last frame if a real session shows it.

## CTUI-7: the text area's words are the original's, and cmd is not bound

The text area moves and deletes by word as the original's textarea
(OpenTUI's edit buffer) does, stops included: between two spaces, at
punctuation, not at an underscore, and back across a line break to the end
of the line before. TextInput keeps its own whitespace word deletion. The
original binds cmd+left and cmd+right; the input parser reports no cmd or
super modifier, so they are left unbound, and nothing else stands in for
them, until the keyboard protocol brings that modifier.

The input parser reads CR as enter and LF as ctrl+j, the original's
linefeed, which adds a line. Where raw mode falls back to turning off line
mode because `stty raw` failed, the terminal may still turn CR into LF, so
there LF is read as enter, and ctrl+j sends as enter does.

## CTUI-16: a diff's rows and counts are the framework's, as a view

The original's tool headline counts a diff's added and removed lines, and
its proposals keep the first ten rows; the framework's `Diff` kept its rows
private. Options: diff again in the port, or open the framework's model.
The lead settled the second (designer's `docs/design/CTUI-16.md`, U2a):
`DiffModel.view(maxRows:)` gives the rows with a gap between hunks, the full
counts and the hidden lines, and `Diff.fromView` draws one. A normal tool
call draws its diff whole, with or without ctrl+o, as `tools.ts` does; the
cap waits for proposals.

## CTUI-16: text can be cut in the middle

OpenTUI's `truncate` keeps a line's head and tail with `...` between, and
chord's plan steps, Guardian line, folded output and rule row use it.
`TextOverflow` had only `clip` and `ellipsis`. The lead settled a framework
mode, `TextOverflow.middle`, with the original's cell budgets and its ASCII
marker in the base style, over a cut written in the port.

## CTUI-16: a tool's folded output is the port's selection, not `Fold`

The original folds a tool's output by choosing source lines and adding
`… +N lines (ctrl+o to expand)`; the framework's `Fold` draws a header of
its own and folds by height. The lead settled the original's selection as
the port's pure code (`summary`, `terminalView`), drawn as text, with no
clipping of its own and no change to `Fold`.

## CTUI-16: a review row and terminal or diff output draw two `⎿`, as chord's

In the original a completed call with a review and terminal output or a
diff, and no text, draws `⎿` on the review row and again on the output's
first row, while text output draws one. It looks like a slip, but the port
follows the original; the lead kept it and took it to main as a question
for the owner.

## CTUI-16: an interim one-line input until the prompt

The fake answers what it is sent, and CTUI-17's prompt was not built, so the
transcript could not be seen against it. Options: an interim input on
`TextArea`, a dev runner flag that sends prompts at start, or screens only
in the tester. The owner, through main, chose the interim input: Enter
sends through `Conversation.send`, Esc interrupts; no history and no queue
UI. CTUI-17 replaces it.

## The port copies the original's double ⎿ on reviewed calls

CTUI-16 found that the original draws two `⎿` on a tool call with a review row followed by terminal or diff output, but one when the output is text. It looks like a slip in the original, but the port follows the original as it is; if the original changes, the port follows.

## CTUI-17: the text area undoes edit by edit, keeping 100 steps

The original's prompt binds ctrl+z and ctrl+y to OpenTUI's native undo,
whose grouping and depth its source does not show. The lead settled: one
step per edit that changes the text (a typed grapheme, a paste, a line
break, each delete or cut), the cursor restored with it; a new edit clears
redo; cursor moves and edits that change nothing add no step; replacing the
whole text through the controller clears both stacks, as the original's
`setText` does, so recalling history and sending clear them too; the last
100 steps are kept.

## CTUI-17: the prompt keeps the original's scope for M1

The lead settled what the M1 prompt leaves out, each for its own later
task: history without the agents' kept drafts or images; ctrl+c on an
empty prompt still quits at once, until the quit task brings the second
press; no `?` hint in the status line until the shortcuts panel. The box's
editor is keyed in the window, since a plan or working line appearing
above it would otherwise mount a second text area on the same controller;
that the framework fails there for any unkeyed sibling swap is left as a
follow-up for the framework.

## CTUI-19: the working line is the original's three `›`, not `✻`

The task's `✻ Working…` is Claude Code's, from the original's list of
features; the original draws three `›` marks turning in the theme's mark
tones. The port draws the original's.

## CTUI-19: truncation can prefer a space, as cli-truncate

The original cuts a long model name in the status line with cli-truncate's
`preferTruncationOnSpace`. The lead settled an optional flag on the
framework's truncation with cli-truncate's rule, over a hard cut recorded
as a difference.

## CTUI-19: themes take extensions, for an app's own colours

The original colours modes (plan, accept edits, auto, bash) and the
spinner's marks in its theme; `ThemeData` had no such roles. Options:
reuse the accent and dim, which differs from the original, or let an app
declare roles of its own. The lead settled the second, as Flutter's
`ThemeExtension`, designed in `docs/design/CTUI-17.md`; the port declares
the original's values and `lib/` names none of chord's roles.

## CTUI-19: the status line reads the mode as the original seeds it

The original seeds the transcript's mode from the mode config option or
the older `modes` on every session answer and option update; CTUI-15's
reducer keeps those in `AgentState` only. The status facts read the mode
option, then `modes.currentModeId`, then the transcript's mode, in pure
code, leaving CTUI-15's reducer as it is.

## CTUI-43: the newest TextArea owns its controller

When unkeyed siblings shift, the element tree mounts a TextArea's new
State before the old one is disposed, and the one-controller check fired.
The lead settled: the newest attach owns the controller, a detach by a
State that no longer owns it does nothing, and two areas still mounted on
one controller once the frame is built still fail. The port's prompt
drops the key CTUI-17 gave it as a workaround.

## CTUI-18: Picker can be held, wrap and leave keys to the window

The original's ChoiceList turns its keys and its highlight off while a
request between turns is held, wraps ↑ and ↓ at the ends, and numbers
its labels inside the text, so a long one wraps under its number. The
lead settled three opt-in additions to the framework's `Picker`, designed
in `docs/design/CTUI-18.md`: `enabled` with a caller-owned `focusNode`,
`unhandledKeys` as `TextArea`'s, and `wrapNavigation` with `showNumbers`.
Defaults keep the old behaviour; the start page's agent picker clamps,
as the original's `PickerList` does.

## CTUI-18: the deadline is the original's fixed hint

The original says ` · denied by itself in 5 minutes` beside the reject
key when a request carries `deadlineAt`, with no countdown. The port says
the same.

## CTUI-18: a tool call asked about draws no second `Waiting…`

The original's tool rows read whether a waiting permission names the call
(`asksFor`): a reviewed call asked about draws no `Waiting…`, and one
without a review draws it first. CTUI-16 could not reach this rule before
the prompt existed; the port ports it here.

## CTUI-18: the status line names a request held between turns

The original's `betweenNotice` says `● permission asked between turns ·
ctrl+x a to answer`, shortened to `● permission · ctrl+x a to answer`.
The port draws it for its session's own permission; the input and other
agents' notices come with elicitation and children.

## CTUI-18: the interim header keeps its row

The port's window line stays pinned at the top while the original's
header scrolls with the transcript, so a tall request at 80x24 shows one
row fewer than the original's. The header is M3's task; the reason and
choices are never cut.

## CTUI-20: `chord` with no agent named opens the start page

This ends the interim rule of "Until the picker, `chord` opens an interim
window" for the agent: as the original's `chooseAgentAtStart`, a new
interactive start with no name, no `--agent-command` and terminals on
both ends shows the agent picker, and the pick goes on as `chord <name>`.
Without settings files, the preferred agent is the default, and every
agent is offered.

## CTUI-20: the mark's colour comes from the theme alone

The original paints the mark per chalk's colour level: none, one tone,
the nearest of 256 colours, or true colour. The port has no colour-depth
detection yet, so with main's agreement the mark draws the theme's
gradient where it has stops, its one tone where it has only that, and no
colour otherwise. Matching the terminal's depth is the terminal services
task's.

## CTUI-20: the wordmark is OpenTUI's fonts, as rows

The original draws `CHORD` with OpenTUI's `ascii-font`, `block` on the
full page and `tiny` on the compact one. The port keeps those two
renderings as constant rows in `example/chord/lib/ui/header/wordmark.dart`
with OpenTUI's MIT notice, and README credits it; a font renderer in the
framework waits for a second user.

## CTUI-40: PENDIN is settled with FIONREAD on macOS

After the window exited, `stty -g` differed from before only in PENDIN.
XNU's `tty.c` sets PENDIN whenever ICANON is switched back on and ORs the
old PENDIN into whatever `tcsetattr` is asked for, so neither the saved
state nor `stty -pendin` clears it. A `FIONREAD` ioctl runs the kernel's
reinput, which clears the flag and leaves the queued bytes readable. The
lead settled: on macOS only, after a successful restore and only when the
saved state had PENDIN clear, the framework calls `FIONREAD` on the tty,
through `dart:ffi` and `package:ffi`; it never reads or flushes input.

## CTUI-21: the shortcuts panel is the original's list, checked both ways

The task asks for every key, from the bindings in scope; the original's
panel is an editorial list in its own wording, without the standard
editing keys. The owner, through main, chose the original's M1 subset in
its wording and order, each row backed by a registered binding, with a
test both ways: every bound app key is listed, every listed key is bound.
The framework's `KeyHelp.builder` hands the port the bindings in scope.
Clauses for features M1 lacks are cut from a line rather than listed
dead: `↑ ↓ for prompts`, `esc to interrupt`, `esc to leave a picker or
shortcuts`, `↑ ↓ j k to move or change a value`'s value arrows, the
wheel, and the pending ctrl+x line's `b a code block`; each returns with
its task.

## CTUI-21: the compact header scrolls with the transcript

This ends CTUI-18's "the interim header keeps its row". The owner, through
main, chose the original's compact header, drawn from CTUI-20's header
pieces, as the transcript's first entry; the pinned line is gone, so the
window is laid out as the original's at 120x40 and 80x24.

## CTUI-21: the crash screen shows Dart's own frames

The original lists JavaScript's `at` frames; the port lists the native
`#N` frames of the Dart stack under the same indent, cut and height rules.
The boundary is the framework's `ErrorBoundary`, which latches a fallback
for a subtree whose build, layout or paint throws.

## CTUI-21: a pending chord times out after three seconds

The framework's `FocusManager` held a chord's first key forever; the
original drops it after `CHORD_WAIT_MS`, 3000 ms. The lead settled a
`chordTimeout` on `FocusManager`, passed through `BuildOwner`, `AppHost`
and `runApp`, three seconds by default.

## CTUI-21: keys are decided by the port's pure keys module

`example/chord/lib/ui/app/keys.dart` turns a press into ordered steps the
window plays; the framework's `Actions` still matches keys and holds their
descriptions. The lead settled the press as the framework's `Chord` (one
combo for a single key), so no second recognizer exists, and the cursor
as the text area's own offset rather than the original's UTF-16 column,
which is JavaScript's and not behaviour. Choosing a permission's option
is a step of its own, played through `Conversation.choose`.

## CTUI-21: `?` is decided when it arrives

`TextArea.unhandledKeys` and `Binding.enabled` only change on a rebuild,
so `draft?` read in one chunk lost the `?`. The lead settled one hook,
`TextArea.shouldHandleKey`, asked at dispatch: the prompt hands `?` to
`Actions` only while its text is exactly empty, and `?` stays bound. The
original, reading the stale state, opens the panel and drops the draft;
the owner, through main, chose to keep the port's behaviour as a fix of
that slip.

## CTUI-21: small visible slips of the original are fixed

At 12 columns the original cuts the pending `ctrl+x …` to `ct...…` though
it fits; the port draws it whole and clips only what does not fit, the
original's full, short and dropped items kept at every other width. The
owner, through main, ruled that a slip of this size, with no behaviour
behind it, is fixed by the lead, recorded here and reported, without a
question first.

## CTUI-44: a plan row keeps its mark's space at any width

At 20 columns the original draws a long completed row as `☒Writ...hange`,
and at 21 as `☒ Writ...hange`. Its `Plan.tsx` writes `${mark} ` and the
entry's words as two text boxes that may both shrink, and only the words
are cut; a long entry shrinks the mark's box from two cells to one, which
drops the space and hands the words its cell. Shorter rows at the same
width keep the space. That is a slip of the layout engine, not a rule, so
the port keeps the mark and its space whole and cuts only the words
(`☒ Writ...ange`), per the ruling on small visible slips above.


## CTUI-46: successful exit bookkeeping is not tool output

The original's `rawOutputContent` serializes a bare `{"exit_code": 0}`
object as JSON. Codex can send that bookkeeping beside Read file output,
so the result shows the object before the file. Main approved this small
visible slip fix: a raw object with exactly the one `exit_code` field equal
to numeric zero contributes no generated content. Its raw value and status
stay unchanged. Nonzero codes, nonnumeric values, camel-case `exitCode`,
and objects with additional fields retain the original's existing rules;
agent-owned content still wins. The original fake's `rawoutputs` scenario
covers the unchanged string, named-text and JSON fallbacks but has no
exit-only Read. Scripted regressions cover bookkeeping before, with and
after text or terminal output at both screen sizes; the reported live
call's exact wire order was not captured.

## CTUI-9: command and option name keyboard modifiers

Main approved keeping kitty's Meta distinct from Alt. In key bindings,
`cmd` and `command` name Super, while `alt` and `option` name Alt. The
protocol's Super, Hyper and Meta remain distinct modifiers rather than
being folded into Alt. This replaces the temporary lack of cmd bindings
recorded for CTUI-7 when terminal keyboard negotiation and parsing land.


## CTUI-9: Dart names the Super modifier superKey

Dart reserves `super`, so it cannot name a boolean field or parameter.
Main approved `superKey` consistently on KeyEvent and KeyCombo, including
constructors and factories. Binding strings remain `super`, with `cmd`
and `command` as aliases; Hyper and Meta keep their own booleans.


## CTUI-47: supported termination signals restore then re-raise

Dart's ProcessSignal.watch permits HUP, INT and TERM, but explicitly
forbids QUIT, ABRT, PIPE and BUS because the VM may use them; the original
renderer watches those too. Main approved per-run handlers for the supported
termination set, removed only after terminal and beforeExit cleanup, then
the original signal re-raised. VM-reserved signals, SIGKILL and an external
terminal crash carry no restoration claim. No native signal workaround is
added. Caller-owned demo files are cleaned in beforeExit as well as an
idempotent finally, since re-raising need not return to the caller.

## CTUI-47: overflowing original bodies consume wheel steps

Original baseline checks corrected the initial root-only wheel scope. Main
approved matching the existing overflowing shortcuts body and permission
proposal body: each consumes one row per wheel report while overflowing;
a fitting body bubbles to the transcript. Titles, rules and choices do not
consume. The original LinearScrollAccel returns one per report. This also
applies to any other already-implemented original wheel-taking box found
in the slice; future completion and background views remain outside it.

## CTUI-47: one signal owner in an embedded window

The port already owns signals through dieBySignal, including process-group
shutdown and deferred terminal release. Main approved runApp.handleSignals
with default true; embedded callers can disable its per-run handlers. The
port explicitly disables them in both startup selection and the live window,
retaining its existing owner rather than installing competing handlers.

## CTUI-47: staged shortcuts evidence uses its actual geometry

The current M1 catalog has 19 entries and fits two columns at 80x24, unlike
the original full catalog. Seven real draft lines still leave it fitting.
Main approved preserving that staged layout: fit evidence at 120x40 and
80x24, natural whole-window overflow at 40x12, and bounded body overflow
checks at both required sizes. No future shortcuts or forced narrow-window
height are added to manufacture the original full catalog's geometry.

## CTUI-47: large proposal title wheel has a known geometry difference

Main accepted one visual limit after the same real fake sequence completed
`long`, answered `permission` with Esc, then opened `bigask` at 120x40.
With choice 2 selected, one SGR up report over the title (column 10, title
row 7) bubbles to the transcript in both implementations. From the same
last MCP headline row, the original then shows the prior numbered reply's
Line 4 and one row below; the port shows the preceding wrapped MCP row and
two rows below. The proposal body and selection match; the cause of the
transcript geometry difference is unproven. The existing one-line ScrollStep
remains unchanged. Main will file a geometry follow-up; no geometry fix is
part of this slice.

Evidence: `docs/design/evidence/CTUI-47/original-u8-proposal-title-up-120x40.txt`
and `docs/design/evidence/CTUI-47/u8-live-proposal-title-up-120x40.txt`, with
matching `.ansi` captures. These byte-injection captures do not measure a
physical mouse or trackpad.


## CTUI-22: Picker reports a changed highlight before acceptance

The model picker previews the highlighted model's settings before Enter.
The lead settled an optional `Picker.onChanged` callback for semantic,
non-null highlight changes, leaving `onSelected` for acceptance. It emits
nothing on mount or an equality-preserving reorder. Item reconciliation
notifies after the frame, with stale delivery cancelled on disposal or a
newer highlight; input changes may notify after updating state. The full
contract is in `docs/design/CTUI-22.md`. Existing Overlay placement is
sufficient for pickers and completion above the prompt.

## CTUI-23: only commands with an available feature are offered

Main approved `/clear`, `/help`, `/exit`, `/status`, and CTUI-22's
`/model`, `/config`, `/effort` and `/fast`. `/status` uses the original's
available facts, omitting absent title and account support. Commands for
features the port does not yet have remain out of completion. Every
original chord-owned name stays reserved locally, including omitted
commands: it is neither offered nor forwarded to an agent command of the
same name. This keeps original ownership while the later features wait.


## CTUI-49: preserve full transcript extents in a one-row viewport

The CTUI-47 tall-proposal difference comes from the original's OpenTUI
measurement defect, opentui#1739, also documented in
`../chord/src/ui/transcript/gap.ts` and its `gap_test.tsx`. A real Tool
inside its Clip measures nine rows with two viewport rows, one row with
one viewport row, then nine again with three. The original places its
Below indicator outside the viewport; showing it leaves one viewport row,
collapses the measured tool and jumps the anchored view to an older reply.
The port keeps the complete item extent, so one upward step shows the
preceding tool row and `+2 below` rather than the original's older numbered
reply and `+1 below`.

Main ruled that CTUI-49's row-for-row requirement excludes this library
bug: preserve correct extents, retain the diagnosis and comparison evidence,
and add a regression across two, one and three viewport rows at both
required screen sizes. No production scrolling or folding change is needed.
This resolves CTUI-47's previously unproven geometry limit above; the visible
difference remains intentionally, with its cause established.

## CTUI-23: command names use the owner's bounded collation fallback

The original sorts command names with JavaScript's `localeCompare`, whose
locale is the runtime's default (`en-US` in the captured original). Maintained
packages were tried before choosing any difference:

- `intl4x` 1.0.1, from Dart labs, resolves with `icu4x` 2.3.2. Its native
  ICU4X backend uses build hooks; `dart compile exe` refuses them before
  compiling, naming `icu4x` and requiring `dart build` instead.
- `icu_kit` 0.2.0 also resolves, but `dart compile exe` refuses its build
  hooks in the same way, naming `icu_kit`.
- `localized_sorter` 0.1.2 resolves with a Flutter SDK dependency, though its
  public sorter is pure Dart and builds with `dart compile exe`. Its custom
  locale rules do not match the original: for `en-US`, `a` versus `A` and
  `Z` versus `z` both compare equal, where the original returns negative and
  positive respectively; `_private` versus `-x` returns positive where the
  original returns negative. Complete command-name probes also differ for
  English, German, Swedish and Turkish. Its public API has no settings that
  recover the original collation; no workaround was added around it.

Reproducible probe sources, resolved package locks, compiler output and the
original's answers are retained in
`docs/design/evidence/CTUI-23/collation-trials/`. No package was added to the
port. Main, for the owner, chose comparison of the lower-cased names by Dart
codepoint order, then the original names by codepoint order to break ties.
Non-ASCII names, case ties and punctuation can therefore sort differently
from the original's locale-aware order. Names themselves stay unchanged.
Fzf matching and its stable scoring retain the existing framework API and
CTUI-8's package decision; only the command catalog's initial order differs.


## CTUI-23: passive overlays expose their laid-out surface

At zero room, a follower skips its child's layout. Completion's last
positive row count then survives, so a prompt-owned Tab action can accept
an invisible choice. The lead settled a read-only `OverlayEntry.visible`
getter rather than duplicating overlay geometry in the port. It exposes
the raw latest-layout paintable surface, independent of focus ownership
and without measuring occlusion. It is false before layout and immediately
on removal, disposal or host unmount; reinsertion starts false. Existing
`showWhenUnlinked: true` painting keeps its existing semantics.

Completion checks this getter together with its current visible item count
at dispatch. Returning room never runs a deferred acceptance. The getter
adds no notification, rebuild or focus behavior. The full lifecycle and
public fixture contract is in `docs/design/CTUI-23.md` under U5a.


## CTUI-50: release resets the cursor to the terminal default

Main approved DECSCUSR 0 on terminal release, suspension and exit through
its existing best-effort cleanup. The next frame after resumption applies
the editor's selected shape. This restores the terminal default, without
claiming recovery of an unknown cursor style chosen before the app.

## CTUI-48: a selection retains sources, not mounted list items

Options: reproduce the original's retained mounted window; scrape screen cells;
or keep logical selectable sources with independently registered paint geometry.
The lead chose logical sources, SelectionArea/SelectionController and a lazy
ListView selection delegate. This adopts Flutter's region/registrar division
without Flutter, handles/toolbars or keep-alives. The port composes eligible
entry content; framework Text/Markdown/Code/Diff/TextArea share source shaping.
Offscreen crossed sources resolve without mounting widgets, preserving CTUI-1.
Header, list and draft have one document order; entry boundaries contribute LF,
while Markdown's explicit blank fragment contributes LF, space, LF.

Immutable current source snapshots take a previous snapshot for revisions.
Opaque fragment IDs reconcile only within surviving compatible parent lineage,
using unambiguous unchanged matches and one-to-one same-kind edits between
noncrossing surviving neighbors. Domain replacement requires a new root ID;
duplicates/retyped or reparented content cannot inherit an old range. This is
terminal selectable identity, not a new general diff/parser. Same-source edits
clamp current offsets rather than clearing every streamed chunk. Snapshot,
visible-code query and reveal are public controller methods over a private
registry; app code needs no render-tree crawl or Markdown extraction.

Consequences: selected model leases can scale with selected content, but live
widgets remain viewport-bounded. Shared shaping must preserve current approved
wrapping, table and quoted-code serialization classes. No new package was
tried for terminal selection/layout. Existing characters, markdown, highlighting
and dartdiff remain responsible for their existing nonterminal work. Details,
identity tests and performance obligations are in docs/design/CTUI-48.md.

## CTUI-48: capture and scroll hold follow the last motion, without autoscroll

Options: hit-test releases independently; retain a pointer route; or depend on
native terminal selection while mouse reporting is active. The lead chose
host-local Listener capture with move/cancel and SGR 1002 alongside 1000/1006.
No hover 1003. Capture cancellation covers detach, ownership loss and teardown;
wheel retains its fresh route. Before route creation/snapshot the host settles
input geometry through the existing bounded two-pass layout, without paint or
terminal writes. Disposed receivers are skipped and capture epochs protect
reentrant drags; routes are never rehit-tested midway.

The original endpoint probes at both required sizes show inclusive nonempty
ranges, equality empty, and release preserving the last motion range rather
than using its own coordinates. Blank source rows preserve LF, not padding.
Held scrolling stops following even when fitting. Explicit transcript scroll
updates the stationary focus after layout; no edge timer/dwell scroll exists.
Release restores following under the original wasFollowing/moved rule. Shown
selection holds logical sources only. This is terminal input/layout work; no
package was needed or tried. Retained stub-only probes and outcomes are under
docs/design/evidence/CTUI-48/interface-captures/.

## CTUI-48: current original copy classes, without its motion-routing quirks

Options: copy raw Markdown, copy rendered cells indiscriminately, or match the
current original's semantic/rendered classes. The lead chose the current
CHD-396 classes: paragraph/list soft wraps join; ordinary code copies source;
tables, quoted code and quoted lists retain their rendered projection. Source
maps distinguish furniture, hard breaks, tabs and synthetic glyphs. Existing
port drawing differences stay; selection is not a redraw task.

Original nested-list and cross-entry drags need extra motion reports to expand
the OpenTUI selection root. Main approved resolving the actual eligible target
in one report, and directed that library quirks not be reproduced, as with
CTUI-49. Exact-string probes record both the original quirk and the intended
complete range. Consequence: a one-report cross-entry drag can select more
correctly than the original; separators and content classes otherwise match.
No new parsing package or workaround is introduced for these terminal maps.

## CTUI-48: OSC 52 reports sent, with generation-safe copy policy

Options: add a native host clipboard now, use OSC 52 alone, or label an emitted
OSC as copied. The task retains CTUI-9's OSC 52 service; successful production
write says `sent N chars to the terminal's clipboard`. No host confirmation is
inferred. Count graphemes using existing characters. Port preflights the
original service's 8 MiB UTF-8 bound before any write; generic Terminal is not
given a new limit. Existing synchronous writes need no acknowledgement timer;
injected asynchronous adapters use the original 1200 ms application bound.

One window coordinator serves code and selection copies. Copy generation,
initiating selection epoch/session and current copying phase guard results.
Auto-copy success retains highlight; explicit selection-copy success clears it.
Selection failure retains a persistent retry note, whereas code failure and
success notes expire after three seconds. Monotonic note IDs reject old expiry.
Quit never awaits pending copy. Preserve the original ordered key policy,
including pending-chord Ctrl+C fallback, prefix misses and body-key-scroll
exceptions, rather than globally binding Ctrl+C ahead of every command.
Consequences and race tests are specified in CTUI-48. No clipboard package was
tried or added; adding host clipboard support is outside this design.

## CTUI-48: staged settings, code actions and plain selection

The original has user settings, bash insertion and coloured selection even
when colour is disabled. Options were bringing those later features forward,
staging their available subset, and preserving the original slate exception
under NO_COLOR. Main chose selection plus copy buttons and ctrl+x b/arrows/c/Esc
now; CTUI-25 supplies run/r and its help clause later. copyOnSelect defaults
true as a window constructor seed; CTUI-29 connects the user's setting. It is
not an agent /config option and no unavailable toggle is advertised.

Main chose inverse-only selection under NO_COLOR, preserving the port's
no-foreground/background invariant; dark/light use original slate 66/152.
This appearance difference requires contrast/protocol evidence. Code-pick and
selection shortcuts appear only for available actions; the staged help's actual
geometry remains authoritative. No new package was needed or tried for this
scope/theme policy.

## CTUI-48: record code-fence closure through the approved parser adapter

Package inspected/tried: the pinned markdown 7.3.1. FencedCodeBlockSyntax uses
a local private closingFence variable and emits identical code ASTs for a
closed fence and an EOF-open fence. Its public parseChildLines returns the
body, without a closure flag. The existing framework Markdown demo compiled
with dart compile exe during architecture; no new closure adapter has yet been
implemented or claimed tested by that build.

Options presented to main: extend the existing block-syntax recording adapter
using the package's public parser state/pattern to note the consumed closer,
or require upstream metadata/package change before enabling actions. Main
approved the adapter extension, including nested fences. No independent fence
scanner or copied package grammar. An EOF-open code block draws normally but
has no button and cannot be picked; appended real closing fences make it
eligible. Required regressions include EOF closers, tildes/longer closers,
empty blocks and list/quote nesting. If the public seam cannot supply the
metadata, stop and return options; the trial is not authority for another
workaround. No dependency/version change was made.

## CTUI-48: selectable sources freeze presentation geometry

The source/delegate API originally retained content and group insets while
bound Text and Code widgets could choose wrapping, truncation or numbering.
A never-mounted crossed item has no widget from which to recover those
options, so guessing defaults could copy hidden text or shape different rows.
Options taken to main: immutable per-kind geometry on source snapshots, a
separate delegate resolver, or restricting bound widgets to default geometry.
Main chose source snapshots, keeping one authoritative model for mounted
rendering and offscreen selection.

Text snapshots freeze effective alignment, wrapping, overflow and maxLines;
Code freezes numbering and wrapping; Diff freezes effective title/showTitle;
Markdown freezes whether copy controls can affect box minimum width. Bound
nullable geometry options use the source when omitted or null, and nonnull
overrides must agree or throw ArgumentError. Clearing a limit or changing a
title uses a replacement source revision; geometry affecting extents also
changes itemVersion. Ordinary Text keeps inherited geometry and snapshots its
resolved values. Styling still inherits, and decorative titles stay excluded
from copied text. The exact defaults and validation are recorded in
`docs/design/CTUI-48.md`. No dependency or parser workaround is introduced.

## CTUI-48: selection queries use declared self-paint coverage

Pointer hit bounds deliberately cover a bordered box's transparent interior,
so they cannot establish exact selection exposure or code-block visibleRects.
Synchronized input queries must not paint. Options taken to main: a pure
coverage hook for the existing primitives with explicit custom declarations,
conservative custom full-bounds coverage, or a broader declarative paint API.
Main chose the bounded pure hook; missing custom coverage remains unknown.

RenderBox.describePaintCoverage returns immutable local cell rectangles before
and after the existing child traversal. Built-ins declare actual written
cells, preserving transparent holes and clipping; no paint call or second
renderer is introduced. An exact runtimeType declaration prevents a custom
paint override from silently inheriting known transparency. Custom boxes must
explicitly declare their coverage, including an empty declaration where
appropriate; an absent or incompatible declaration is unknown.

The lead settled unknown propagation conservatively: an unknown paintable
subtree intersecting the area's effective clip makes that area's geometry
unresolved. Hits/highlight are suppressed and synchronized queries return their
existing null/empty/false results. Active drag cancels without finalization;
finalized logical ranges may retry later but their old UI text cannot be
copied. Clipped-out unknown content does not block the area. Recovery never
replays a cancelled gesture or copy. The precise hook and acceptance cases are
in `docs/design/CTUI-48.md`. No new dependency or general painting subsystem
is added.

## CTUI-48: exposed endpoints and logical copy ranges are separate

Intrinsic truncation, ellipsis, disabled content and omitted rows determine
eligible copy units. Known viewport clipping and overlay coverage instead gate
endpoint hits, highlight and code visibleRects; they do not remove eligible
interior text from an established logical range, including offscreen crossed
items. Unknown coverage still makes synchronized queries unresolved. This
clarifies the logical-source design; no original overlay runtime probe is
claimed.

Main explicitly chose retaining the last exact endpoint when motion reaches a
known-overlay-covered interior with no eligible hit. Do not project through
that hidden cell or choose a nearest edge. The same interior rule applies to
viewport-clipped rows. Exposed hits still update or switch sources, and actual
outside-line or outside-source positions keep the existing start/end clamps
against full shaped source bounds, including eligible offscreen text. This is
our own covered-interior decision, not asserted original parity.

The lead settled the genuine blank-LF row's hit lane as its effective content
width, excluding furniture and placeholder text. Every exposed lane cell maps
to one boundary, so horizontal motion remains empty and crossing preserves LF.
The retained original probes cover the first content cell and horizontal
motion, not exhaustive lane positions. Empty layout supplies no boundary.

The written release and settlement contracts remain strict: a live receiver
gets one immutable finalized event for its matching release after resources
are released, even if a change callback starts a new gesture. The port rejects
stale generations before auto-copy; disposal/unmount suppresses delivery. One
reveal operation shares at most two total layout passes across freshness and
scroll settlement, with no queued retry on exhaustion. Exact rules and reached
acceptance cases are in `docs/design/CTUI-48.md`.

## CTUI-48: held refresh retains fragment identity without freezing text

S3 review found that removing a selected endpoint source could discard the
surviving range. Simply re-hitting the remembered cell could instead inherit
newly inserted fragments, while freezing all source-update projection would
violate fresh geometry/text requirements. Main chose reconciliation by
surviving fragment IDs: endpoints reflow only within those IDs, with current
text and geometry, and inserted fragments join only on real pointer motion or
explicit transcript scroll, including a clamped scroll command. Matching
release reads fresh geometry and text under that same restriction and never
acts as new motion. Removed or ambiguous fragments cannot regain identity.

This applies uniformly to further held-drag identity-versus-refresh cases,
without another owner question. It preserves current same-fragment reflow,
selected-source survival and explicit-scroll projection rather than freezing
an old screen or broadening a range through source updates alone. The design's
reconciliation, frame order and S3 acceptance list are updated in place.

## CTUI-48: capture input before editing through the existing matcher

S5 planning showed that focused form/editor handlers run before ancestor
Actions, so existing APIs cannot give a printable rebound selection-copy key
or prefix its required priority, or clear selection before every key/paste.
Options taken to main: capture callbacks plus a separate Actions priority
option, or capture callbacks with a bounded shared-matcher dispatch seam.
Main approved the latter as its own framework unit S5a before port unit S5b.

Focus and FocusNode gain optional onKeyCapture/onPasteCapture callbacks,
visited ancestor-to-focused before normal input, including empty paste.
FocusManager.matchKey previews through the existing matcher and returns an
immutable KeyBindingMatch with exact/prefix/dropped/none kind, binding and
sequence. Its one-use dispatch accepts exact/prefix only during the same
active key input with unchanged focus, pending, binding and input epochs;
stale results have no effects. Filter enabled bindings before shadowing so
explicit selection-copy matching can precede modal typing. Normal action order,
pending state, timeout and miss behavior remain owned by the same matcher.
No Actions priority flag, second recognizer or global keymap is added.

The port supplies only live policy and dispatches an accepted copy match before
editing; other input clears/preserves state through pure ordered key decisions.
Copy wiring borrows bin's existing terminal or an injected Copy adapter, with
adapter precedence and no widget terminal ownership or implicit StdioTerminal.
Production synchronous OSC 52 reports sent. Tests control duration timers with
the existing fake_async Zone and adapters/completers, so no unused Clock
constructor field or new clock abstraction is needed. Existing packages remain;
the exact API, reentrancy guards and separate unit gates are recorded in
`docs/design/CTUI-48.md`.

## CTUI-48: key-match capabilities use immutable registrations

The S5a capability guard needs a stable binding registration, so the lead
settled defensive unmodifiable snapshots in FocusNode.bindings. Mutating the
caller's list cannot silently change registrations; the getter is read-only.
Existing setter/Actions replacement remains the update path and invalidates an
old match even when displayed labels are equal but callbacks differ, while
existing notification conventions remain. Dispatch also revalidates current
enabled eligibility and the supplied live where filter before accepting exact
or prefix results. A stale result returns false without effects. Binding.enabled
remains its existing bool; no new predicate API or precedence setting is added.
The design and focused acceptance cases are recorded in `docs/design/CTUI-48.md`.

## CTUI-48: command and prompt geometry must converge within two passes

S5a reached port tests exposed typing and same-batch quit failures before
FocusManager dispatch. A complete pre-S5a production comparison reproduced the
narrow command case, so this was not accepted as a capture-feature limitation.
The completion lifecycle redundantly dirtied an already-built overlay entry;
a binding-label update also left an earlier KeyHelp sibling dirty inside a
layout-built subtree. The bounded repairs avoid that redundant lifecycle
rebuild and drain existing dirty work only within the returned
buildDuringLayout subtree before render sync/layout. Ancestors and unrelated
work remain queued; no layout pass or new settlement loop is added.

After those two bounded attempts, the remaining quit failure was taken back to
main before another repair. A recalled two-row draft clearing to one row left
its old gutter height in control of the prompt for the first pass; shrinking
that gutter in the second pass changed transcript measurement and dirtied the
window again. Options were a positioned/clipped port gutter or a new generic
current-layout TextArea gutter API. Main approved the former as the third
repair, with tests and designer recheck at both required sizes.

The editor alone determines prompt height. The gutter is decoration clipped
to that height, preserving its cells, editor width, cursor, focus and keys.
Acceptance covers two-to-one and one-to-many row transitions, complete command
typing/current choices/room-dependent acceptance and same-batch clear/arm/quit.
Failure/fix evidence distinguishes the baseline probe from later repairs.
Main separately owns the general requirement never to lose a key on settlement
exhaustion; that framework follow-up is outside this run. These local fixes
retain two layout passes, normal notifications and no input replay or fallback.

## CTUI-48: transcript entries have independent logical identity

A turn ID is not an entry ID: several chunks can share it without message IDs,
and reducer updates replace entry objects. Main approved a minimal opaque
EntryIdentity token for selection sources, preserved on same-slot reducer
replacement and fresh on append, with duplicate, reuse and retention tests.
The token never stores an Entry or uses an old Entry as its value.

All Entry constructors retain const support with an optional typed identity.
The getter returns that token or a lazy independent token in a weak Expando.
The three entry writers enforce occurrence semantics: appended clones each new
occurrence with a fresh token even when the input object/token was reused;
replacedAt/lastReplaced carry the old slot's token into the new data. Untouched
entries/no-op results keep object identity. Exhaustive cloning preserves all
fields, including the agent's num? values. Reusing a canonical entry twice in a
raw const Transcript bypasses the writers and remains an invalid duplicate for
the selection delegate; it is rejected rather than silently normalized.

The exact Entry contract is amended in place in `docs/design/CTUI-15.md`, with
a pointer and selection acceptance in `docs/design/CTUI-48.md`. This is port
domain identity, not another text diff, parser, revision chain or cache of old
entries, and it adds no dependency.

## CTUI-48: excluded source children keep shared layout geometry

Current original content opts into selection explicitly; visible text or agent
provenance alone is insufficient. Source review found whole reports, notes,
queued rows and outcome/error furniture excluded, while header/draft and
specific thought/tool/plan content opt in. Permission diff code remains eligible
inside excluded request furniture. The source references and evidence limits
are recorded in `docs/design/CTUI-48.md`; no new runtime parity is claimed.

Partially eligible composites interleave wrapped excluded rows before eligible
content. Counting those rows in the port or adding fake newline fragments would
break authoritative shared shaping. Options taken to main: an immutable
selectable flag on SelectionSourceChild, or a larger excluded-source wrapper.
Main approved selectable, default true, as its own framework unit S5a2 tested
and gated before the port consumes it.

A false child retains normal geometry, insets, wrapping and height but emits
no fragments, hits, highlight, code descriptors/bounds or separator. Nested true
children cannot re-enable it; model lookup remains available for drawing.
Provider registration cannot re-add an excluded bound leaf automatically.
Only the next eligible child's configured separator joins eligible content,
without leading/trailing/excluded separators. Eligibility changes need a new
revision, release affected leases and cannot resurrect old selection. This adds
no parser, dependency, port row-count workaround or parallel-row source API.

## CTUI-48: geometry observers share the two-pass operation budget

S5a2 fixture checks exposed a prior S3 observer race. Recording a new motion
before synchronization projected that motion twice; a live parent setState
from the first notification could invalidate the operation. Motion now
synchronizes from the prior saved cell before recording/projecting the actual
new cell once. Fresh-source snapshot/release regressions then showed geometry
observers could update selection after host settlement, dirty the parent and
cause false cancellation while a layout retry was still available.

Options taken to main: include geometry-observer/notification effects in the
same bounded host operation, or introduce a larger deferred selection-event
boundary. Main approved the former. Observers run after a stable candidate,
outside layout and settling flags; their effects may use only the remaining
part of the same two-total-pass budget. No retry receives a new budget. Genuine
exhaustion reports unresolved once, with no stale text, queued retry, third
pass, input replay or fallback.

Reentrant key, paste or pointer input supersedes the old pre-route operation.
The old continuation cannot dispatch its event or cancel a newer capture;
input/capture epochs retain those guards without adding public API. Main's
separate CTUI-51 owns the general exhausted-geometry key-delivery guarantee.
The shared settlement path and exact repair commit are handed to that task on
the board; this run changes only the bounded geometry/selection contract.

## CTUI-48: pending presentation reads the live KeyHelp snapshot

S6b integration reproduced a same-batch ctrl+x b failure: the port mirrored
KeyHelp pending state into AppState through afterLayout, causing another parent
build and spending both allowed geometry passes before the accepted pick action
queried current code. The matcher accepted the binding, but its geometry query
correctly returned unresolved. This was found on S6b work in progress and is
not attributed to an untouched baseline.

Options taken to main: draw pending presentation directly from the existing
live KeyHelp snapshot, or retain the mirror with another explicit boundary
synchronization seam. Main approved direct presentation and removal of the
afterLayout AppState mirror. Query and reveal current code before mutating pick
styling; a clear of already-empty selection adds no redundant invalidation.
Wording, keys, Focus notifications, existing matcher and the shared two-pass
budget stay unchanged. There is no framework scheduler, fallback, replay or
automatic retry added here.

The cause is recorded on CTUI-51 as the third afterLayout budget consumer,
separately from that task's general exhausted-geometry key-delivery guarantee.
The exact current-window red/green acceptance is amended in
`docs/design/CTUI-48.md`.

## CTUI-48: live status shares the transcript footer layout scope

The approved live-pending change removed one afterLayout mirror, but the reached
command tests then exposed a second boundary: command-binding changes dirtied
KeyHelp outside the Transcript subtree being built during layout. The lead
approved a second bounded port repair using the existing footer API. The same
live status row now follows the conditional prompt parts inside an unconditional
Transcript.footer Column, with a stable keyed Padding2 boundary; the outer
status duplicate is removed. Cells, width, inset, order, height and cursor stay
the same, including non-send/startup/failure/closing states. No framework,
notification, matcher, pass-limit or retry change is made. The six reached
command failures were reproduced before this repair and passed afterward.

The real code-pick help rows also change the staged catalog's natural geometry:
at 80x24 the tall-draft fixture has twelve rows in eleven rows of room and shows
the existing two-below indicator; 120x40 fits. Tests derive that from the real
catalog and available room while preserving wheel/closing/draft/focus checks.
This does not rewrite CTUI-47's earlier M1 fitting evidence or manufacture rows.

## CTUI-48: unchanged selection reuses the settled scene and range

S7 internal numeric measurements found repeated work at 600 entries: steady
held/shown frames resolved all 600 roots again and recomposed ranges despite
zero parser calls. Work stopped before the 10 000-entry AOT run. Options taken
to main: reuse the current settled scene/range under existing geometry and
ownership epochs, or add larger per-slot revision caches across distinct scenes.
Main approved current-scene reuse with freshness and ownership regressions.

Reuse requires unchanged geometry epoch and root/boundary/controller ownership.
Source/tree/scroll/resize changes, ownership replacement, clear, unresolved state
and detach invalidate it. Explicit scroll intent, including a clamped command,
still admits current fragments under the held-drag identity rule; actual motion
still projects. Snapshot, release and reveal synchronize current geometry/text.
No new public API, pass, notification policy, fallback or retry is introduced.

The earlier clear measurement also found offscreen resolved layouts retained
by the old scene after ranges were released. Clear drops that scene cache after
clearing highlights and before public observer continuation, so old cleanup
cannot erase a newer gesture. Immediate and next-frame references are measured
against baseline. The 600/10 000 AOT reports retain parser, root-resolution,
scene/range-work, lease/cache and frame-time metrics separately; the unchanged
frame and prompt/virtualization contracts are not weakened.


## CTUI-24: agent mentions accept a staged recipient snapshot

The original completes the live recipients that send_message reaches from the
picked session, including runtime and team reachability. Those registries belong
to M4 and M5 and are not implemented in the port yet. Options taken to main:
injected recipient snapshots now, or bringing the runtime registry forward.
Main approved immutable injected snapshots, empty by default, with populated
fixtures and tests. The empty list reads `No agents to mention`. M4 supplies
the live roster later; this slice does not offer installed agents or invent
recipients from the current session. Agent mentions stay prompt text and attach
no file link.


## CTUI-25: shell output uses the original ANSI stripping pattern

The existing framework stripAnsi missed the original strip-ansi 7.2.0 test
for eight-bit CSI. A maintained package was tried first: ansi_escape_codes
4.0.1, through ansiRemoveEscapeCodes, builds with dart compile exe but passes
seven of strip-ansi's eight own cases; it leaves eight-bit CSI intact. No
workaround was put around the package. Sources, pinned dependencies, cases
and output are retained under docs/design/evidence/CTUI-25/sanitizer-trial.

Main approved porting the single published regex actually resolved by the
original: strip-ansi 7.2.0's nested ansi-regex 6.4.0, with its MIT notice.
Framework stripAnsi and text escape-range mapping share the pattern and the
same ESC/eight-bit-CSI fast path. This deliberately preserves upstream's
standalone eight-bit OSC fast-path behavior, rather than inventing another
sanitizer. Text shaping strips escapes across style boundaries and keeps
clean grapheme offsets; source projection uses those same ranges.

The exact upstream regex recognizes a split displayed row ending in ESC [ 3
as a related escape. A two-cell draft viewport therefore keeps the following
literal tail `1mred[0m` where the earlier pattern kept `[31mred[0m`; sanitizing
the complete string still yields `red`. This is the original sanitizer's
behavior applied to the existing displayed-row draft policy, not a new draft
parser or a change to its raw controller text. Exact upstream cases, OSC
terminators, incomplete controls and width/selection boundaries cover it.
No dependency is added. The sanitizer gates separately before shell context
consumes it.

## CTUI-24: all original locale comparisons use the bounded fallback

Main extended CTUI-23's settled collation fallback to every original
localeCompare encountered by the port, without another package trial.
Files sort by depth first, then lower-cased codepoint order, then original
codepoint order. The existing collation trials and their AOT/package findings
remain the reason. Non-ASCII names, punctuation and case ties can differ from
the original locale order; literal names, fzf scores and stable score ties
stay unchanged. No new normalization, transliteration or runtime locale
service is added.


## CTUI-25: run languages freeze at the selection-source boundary

The ordinary Markdown widget has an established const constructor. Freezing
a caller-supplied language set during widget construction would remove that
API and require unrelated callsite changes. The lead and designer settled
source derivation as the immutable boundary instead: ordinary Markdown keeps
const support and captures and validates its language configuration when it
derives a selection source. Callers treat widget configuration as read-only;
pre-mount widget-set isolation is not promised. SelectionSource.markdown
defensively freezes its set immediately and exposes an unmodifiable getter.
Bound widgets validate their effective configuration against that snapshot.
Mounted rendering and offscreen geometry therefore retain the same immutable
source contract. The exact API and validation timing are in
`docs/design/CTUI-25.md`.


## CTUI-24: file discovery uses the approved narrow BSD Ignore helper

The maintained-package trial used serverpod_cloud_cli 1.3.1's public
`lib/util/ignore.dart`, derived from Dart pub's `e9ad2bc` helper. Its
`Ignore.listFiles` passed an AOT fixture for nested rules, child negation,
anchoring, dotfiles and file-only discovery outside a repository. The normal
callbacks enumerate relative filesystem names, read each directory's
`.gitignore`, identify directories and exclude `.git`. However the package
resolution adds 75 dependencies, including nocterm and serverpod_tui, for
this one helper. Main rejected that production dependency and approved the
narrow helper port, with its BSD notice and no parser/rule changes.

The advertised standalone `ignore` package is unavailable on pub.dev;
`gitignore` 0.2.0+1 and `ignorium` 1.0.0 generate ignore files rather than walk
them. `mold` 0.3.0's discovery is internal to its archive policies. No package
workaround was written. The retained package trial, license and provenance
belong under `docs/design/evidence/CTUI-24/`.

The original globby oracle agrees on nested negation, hidden files and both
internal/external file/directory symlinks. Its file-only traversal omits
broken symlinks whereas the helper's basic callbacks list them. Main approved
filtering discovery callbacks to existing files/directories using the
follow-links filesystem type check; the helper remains unchanged. This is
bounded discovery glue, not an extra ignore rule. Tests compare rule outcomes
with `git check-ignore` where Git is available. Existing cancellation_token
2.0.1 runs the synchronous helper in a cancellable isolate, so a prompt owner
can stop a walk without blocking input. The settled depth/lowercase/original
codepoint ordering remains the explicit locale-comparison difference.


## CTUI-24: asynchronous matching shares the existing Fzf scorer

File completion must keep typing responsive and cancel superseded searches.
The existing framework Fzf API is synchronous. The lead approved a bounded
AsyncFzf prerequisite, designed with the developer, instead of introducing
an isolate-worker subsystem or another matcher. It shares the existing
scorer and result semantics, snapshots candidates and options, and yields
during preprocessing, scanning and stable ordering. Superseded or disposed
work returns null; the port still validates current query, candidates, session
and visibility before acceptance. The API and independent gate are recorded
in `docs/design/CTUI-24.md`.


## CTUI-24: a follower can retain linked geometry without opaque furniture

The file finder's original pending acceptance can wait with no retained
matching rows, provided the prompt still has room for completion. Existing
followers always filled their positive child rectangle, declared opaque
selection coverage and hit that rectangle, even for an empty child. A
positive-height geometry probe therefore erased a transcript row and blocked
its selection/pointer route; a zero-height probe had no visible geometry.

Main approved the bounded `CompositedTransformFollower.opaque` prerequisite,
default true. False removes only the follower's own fill, rectangle coverage
and self hit. Child paint, declared coverage and hits remain, and unknown
child coverage still fails closed. Layout, linking, clipping, raw visibility
and focus policy do not depend on opacity. The pending finder uses an empty
positive-width one-row child with `requestFocus: false` and `opaque: false`;
normal rows retain the default. This framework unit passes its own design,
review and test gates before the port consumes it. No broader visibility or
scheduler API is introduced.


## CTUI-24: async acceptance can synchronize current context geometry

Review found that a completed mention match could publish after a recorded
resize but before the next frame, treating cached finder room as current.
The owner synchronizer is internal. A selection snapshot is not an appropriate
public proxy: its range/exposure and unknown-coverage semantics are unrelated
to completion geometry.

Main approved `BuildContext.ensureCurrentInputGeometry()`, implemented by
Element, with no arguments or pass knob. It delegates once to the existing
shared two-pass synchronization guards and checks the context remains mounted
on the same owner afterward. It neither paints nor queries selection, resets
an operation, retries or replays input. True describes current geometry only;
callers still validate live action ownership and room. The framework API has
its own review/test gate before the port repair consumes it. The pending
completion repair validates its surface before publishing results, preserving
Enter-to-no-match submission when that result legitimately removes its list.


## CTUI-26: session records remain port services

Options: a framework file-backed Store/atomic-write service, a database, or
port-owned original-shaped JSONL using SDK primitives. Chosen: port services
in example/chord/session, consumed by plain session/conversation logic.
Persistence here is chord policy, not terminal machinery; atomic replacement
would risk losing concurrent appends and unsupported original history. No lib
API or filesystem/queue/database package is added. SDK JSON conversion,
streamed file reads and append/flush/close passed native probes; existing path
is reused. Probe sources and limits remain under docs/design/evidence/CTUI-26.

## CTUI-26: original version-1 JSONL is the interchange boundary

Options: a Dart-specific serialized transcript, migration/copying original
records, or the original compact type-first v1 lines in its state store.
Chosen: original-shaped lines, independent UUID basenames and literal ACP ids
in headers; known records continue in place. Unknown fields/updates remain
raw and existing bytes are never rewritten. Result encoding explicitly keeps
nested error/message/string-code fields and historical completion status
independent of stopReason. In-memory EntryIdentity, drafts and selection are
not serialized. Legacy window files remain untouched. SDK codecs suffice;
no JSON parser/serializer package or schema migration is needed. Bidirectional
original-fake tests are implementation gates, not a design-time pass.

## CTUI-26: per-process append ordering matches the original

Options taken to main: original per-process serial appends with documented
parallel-open interleaving, or a coordinated interprocess lock protocol.
Main chose the original contract. One owned drain snapshots encoded entries
with their paths, handles writes arriving during a flush and preserves
per-path order through swaps. A Dart-only advisory lock could not exclude
original writers. No lock package/protocol is added. File completion is not
fsync durability or a transaction. Preserve torn-tail merging, uncertain
partial-write loss, once-only failure warning with fresh later-event retries,
and the original unbounded queue/flush-latency limits. No silent repair,
backpressure cap or shutdown deadline is authorized.

## CTUI-26: preserve deferred history and explain drawing omissions

Options taken to main: refuse records with later-feature history, or append
without changing any old bytes while drawing supported main history. Main
chose supported replay with one notice when meaningful content is omitted;
children, teams and monitors are never revived. The original child/monitor
notices describe named runtime state and do not fit arbitrary omissions, so
the approved plain line is `Some saved history is not shown in this version.`
It is window-only, after history, once per successful opening; it reaches
neither Recording nor ACP. Metadata intentionally lacking a row does not
trigger it. Consequence: useful main-session interchange now, with explicit
limits on later-feature history. No package is needed for domain projection.

## CTUI-26: reopen partitions traffic at the reply observation

Options: infer replay from all updates before an awaited load returns, or
partition synchronously at the matching JSON-RPC reply in the existing tap.
Chosen: synchronous SessionInbox method/session/request-id correlation and
pre/post partitions. One decoded read can contain history, reply and live
updates before any Future continuation. Raw parsed record presence drives
resume/load choice separately from supported projection. Load replay is
consumed or discarded; resume's early updates are live, applied after answer
seeding before post-reply updates. Failed opens publish no partial history.
Session prepares actions; Conversation emits a batch; StartConnection/AppState
folds a detached transcript and publishes once. Private replay accumulation
preserves occurrence identity without quadratic list copies or mutable escape.
No new transport scheduler/framework API or collection dependency; CTUI-15's
collection trials remain applicable. Same-read/split-read and reentrant
close/swap tests are mandatory implementation gates.

## CTUI-26: the resume picker composes existing widgets

Options: a new framework persistence/picker API, caller-prewrapped numbered
strings, or existing Picker with custom metadata/title content. Chosen:
existing numbered Picker, Row/Column/LayoutBuilder and Text; no new lib API.
The original number stays in a separate column through continuation lines.
A list-wide cell-width threshold chooses hanging versus stacked titles;
metadata stays one clipped nonwrapping line and titles use existing shaping.
Ctrl+A changes directory scope, not a query filter. Existing Actions/shortcuts
and startup/overlay machinery retain key ownership. Critic rejected the draft
caller-numbered composition because it lost continuation insets. Screen
captures are sanitized original/current-port observations; combined-state
parity and two-pass overflow convergence remain ship gates. Terminal layout
requires no new package.

## CTUI-26: UUID and XDG packages with an explicit home boundary

Tried under dart compile exe: uuid 4.6.0 and xdg_directories 1.1.0, with
retained resolved locks, sources and original xdg-basedir 5.1.0 oracle output.
UUID generated 10,000 distinct canonical v4 values per environment; only
xdg_directories' pure-Dart stateHome surface is proposed for the port.
Absolute/relative/empty/missing XDG override cases match with HOME present.
When both HOME and XDG_STATE_HOME are absent/empty, the Dart package throws
while the original resolves OS account home. Options taken to main: accept
this environment requirement, trial another OS-home provider, or defer the
shared default store. Main chose a clear error requiring HOME or
XDG_STATE_HOME. No native fallback or workaround is added. The package's
Linux metadata is not a claim of whole-package macOS support; the used surface
built and ran on the host. No production dependencies changed during design.

## CTUI-26: adapt only the optional resume argument before args

Existing args 2.7.0 was tried under AOT: bare --resume/-r requires a value,
and repeating an option accepts the last value. The original permits an
optional id and refuses repeats. Options taken to main: a bounded token
adapter for this flag before args, or trial/migrate the whole CLI parser.
Main approved the adapter. Keep other parsing/help/error conventions, option
value ownership and -- termination; preserve the original flag-name and
empty-value oddities captured in the checked-in Bun oracle fixtures. No
workaround was built before approval; no parser migration or unrelated option
support is added. Ship must test the adapter against those original outcomes.

## CTUI-26: fixed English relative ages follow the original

Tried timeago 3.7.1 under AOT: it builds but uses different rounding, thresholds
and English labels (59 seconds is a minute, 90 seconds is two minutes, and a
week is seven days). Locale hooks alone cannot recover the original policy.
Inspected intl 0.20.3: no relative-time formatter; it resolves in timeago's
trial. Reused the retained CTUI-23 intl4x 1.0.1 trial: native ICU4X hooks fail
dart compile exe; no new run is claimed. Options taken to main: accept visibly
different package ages, or port the original's six fixed units and English
numeric:auto labels. Main approved the bounded original port with checked-in
Bun boundary fixtures. No adapter around timeago or internationalization
subsystem is added. Ages freeze per picker scope opening, so a ticking clock
does not move row geometry under the highlight.

## CTUI-26: refuse unsupported record versions before opening

The original parses session headers without a runtime version guard. The
approved interchange boundary is version 1; a different version cannot be
assumed to share its history or append format. Options taken to main: refuse
before starting an agent, or resume without projecting local history and
append version-1 lines to the existing path. Main chose refusal. Name the
unsupported version in the error, start no process and leave the file
untouched. This is a deliberate guard the original lacks, not a migration or
repair. Missing and malformed-only records retain their separately specified
reopen behavior.

## CTUI-26: reopening retains the original capability refusal

The design's instruction to ask load when neither reopening operation is
advertised was ambiguous: the original session chooses load, but its ACP
connection rejects an unadvertised method before sending a request. Options
taken to main: retain that offer guard, or probe the wire despite the absent
capability. Main chose the original guard and refusal wording. Session still
selects load; the connection sends no RPC and reports that the agent does not
offer the method. No automatic fallback or new-session request is introduced.

## CTUI-26: historical timestamps retain fractional values

Record timestamps are numbers and may have fractional values. The reached
port transcript actions and working-state timestamp fields therefore carry
num, preserving historical values through projection and reduction. Live
DateTime timestamps remain integers. Conversion to integer units occurs only
at a UI API boundary that requires them; replay does not truncate saved
timestamps. This is port timestamp plumbing, with no framework API change.

## CTUI-26: failed startup keeps the existing error screen

The original permits resume commands after a failed startup. The port's
existing startup/protocol-error screen has no prompt or overlay anchor, and
this slice specifies that existing error surface for failed reopening.
Options taken to main: retain it, or add command-only input and an anchor
after failed initial startup or reopening. Main chose the existing error
screen for CTUI-26 and a separate task for resume after a failed start.
Connected and disconnected sessions retain this slice's resume commands;
failed startup does not gain a new input surface.

## CTUI-26: report observable worker cleanup without a new diagnostic seam

The approved cancellation package exposes operation-Future completion but
does not expose its physical isolate handle or exit notification. Options
taken to main: report measurable stream, pending-Future, OS-handle, temporary
root and process cleanup, or add a diagnostic seam to count and join isolates.
Main chose the observable metrics with no new seam. Cancellation latency is
measured from request to operation-Future settlement; physical isolate count
and physical exit latency remain explicitly unmeasured. Future settlement is
not evidence of physical isolate exit. Other scale and responsiveness gates
remain unchanged.

## CTUI-26: retain the unresolved scale end-handle observation

One default JIT scale run reported one owned file handle after cleanup,
despite zero pending operations and streams and removal of its temporary
root. That count-only observation did not identify the descriptor. One
bounded diagnostic rerun observed a transient records-directory handle after
scan-cancellation Future settlement, then zero at later stages and cleanup;
it did not reproduce or explain the earlier end-of-run observation.
Options taken to main: retain that unresolved observation and finish the
planned measurements, or require further diagnosis and an awaitable-cleanup
design first. Main chose to finish, preserving the failure and diagnostic
logs without an all-zero handle-cleanup claim. Any AOT recurrence must be
reported explicitly. Main owns a separate diagnosis task; no production or
package workaround is introduced by this acceptance.

## CTUI-53: cancellation cleanup is a final gate of CTUI-26

This supersedes the final disposition in "CTUI-26: retain the unresolved
scale end-handle observation". Further JIT and AOT evidence identified
record-file descriptors retained from scan cancellation through cleanup.
Main added CTUI-53 as the last unit of the same CTUI-26 branch and slice.
A cancelled scan must close its record files or end its isolate before its
Future completes. Own-handle regressions must run under JIT and AOT, then
the affected scale measurements must be repeated. Preserve all pre-fix and
diagnostic evidence. The earlier unresolved observation is no longer an
accepted final limit; no workaround or lifecycle implementation is selected
by this scope decision.

## CTUI-26: defer the large-picker redraw hitch to the framework

The separate 2,000-choice AOT picker measurement found roughly 25 ms
navigation redraws and 29–75 ms scheduled-to-accepted input delays, despite
submillisecond dispatch and steady-frame work. Options taken to main: retain
the measurements and defer all-item picker redraw work, or expand this port
slice into framework cache design. Main chose a separate framework task.
This is an explicit responsiveness limit, not a performance pass. Retain
the separate transcript first-layout and resize hitch figures as evidence;
they do not measure picker navigation. CTUI-53's cancellation cleanup gate
remains mandatory and is not deferred with this rendering work.

## CTUI-53: await cooperative file cleanup before cancellation completion

The direct package trials are retained with their pinned lock, sources and
JIT/AOT results in the [capability evidence](../example/chord/test/fixtures/records/ctui53_packages/manifest.json).
`cancellation_token` 2.0.1 completes its cancellation Future before invoking
its isolate-kill callback and exposes no awaited I/O-cleanup hook. In both
runtimes, a worker-owned regular-file descriptor remained open after its
exit notification. Joining a killed worker alone is therefore insufficient
for the observed file-cleanup problem.

`worker_manager` 7.2.9's direct gentle-cancellation Future also completed
while its worker still held a file. The independent cleanup acknowledgment
and descriptor closure arrived only after the deterministic test processing
gate was released. No timing delay or polling established either result.
The probes exited and removed their owned roots; the deliberately retained
current-package descriptor before process exit is failure evidence, not a
per-operation cleanup pass.

`squadron` 7.4.5 and `isolate_manager` 6.3.2 were source-inspected only, not
runtime- or AOT-probed. Their checked high-level cancellation/disposal paths
did not provide the awaited filesystem-cleanup barrier needed here. The
Squadron cancellation token wrapper used by its lower-level channel is
internal; no private API bypass was tried.

Options taken to main: a port-only cooperative SDK-isolate worker using the
existing public CancellationToken interface; an actor package with another
custom acknowledgment protocol; or waiting for an uncancelled full scan
before rejecting. Main conditionally chose the first if the direct trials
confirmed the package gap; the JIT/AOT results satisfy that condition.
Explicitly close and await directory/file streams, then acknowledge cleanup
before rejecting the caller's Future. Do not replace that barrier with an
isolate-kill request or exit notification. A short CTUI-53 design and lead
go-ahead precede implementation. Preserve the existing readRecords and
readRecordedHistory contracts, JSON projections, numeric values and
eight-stream scan bound, with no framework change or new deadline/queue cap.


## CTUI-54: exact-height navigation with measured cold-width projection

The large-picker diagnosis found highlight rebuilds invalidating every measured
extent, with additional all-item geometry and version scans. Exact heights for
arbitrary custom widgets cannot be recovered from visible rows after a width
change while preserving exact total rows, hidden counts and tall-row placement.
Options taken to main: a bounded exact-height fast path with cold-width scalar
projection, or an architected estimated/lazy geometry policy. Main approved
the exact-height path: navigation is bounded to visible rows; default rows
supply their exact height; custom rows keep conservative measurement unless
they supply exact heights. A cold width change may perform O(N) cheap height
projection and must be measured and documented separately from visible widget
work. No estimated heights or generic ListView behavior change is authorized.
Retain the CTUI-26 baseline and measure 2,000 and 10,000 choices under AOT.


## CTUI-54: count actual resume height projection without retaining inputs

Framework counters cannot measure the resume picker's private shared shaping
calls. Options: leave those port counts unmeasured, or add narrow numeric-only
internal diagnostics for choice construction and height projection. The lead
chose the counters to distinguish no-edge and edge-width passes in the required
AOT measurement. They retain no inputs, session objects or listeners, change
no layout policy and add no framework API. Reset/read is for tests and the
benchmark; counting stays active under AOT and its overhead is disclosed.
Process RSS remains process-only evidence, separate from current-generation
cache and mounted-row counts; no whole-heap claim follows.


## CTUI-54: keep the resume frame intact at narrow height

The paired all-directory resume picker at 32x10 showed the original painting
its wrapped `Esc to close` hint through the bottom frame row. The port clips
the hint to the available body and keeps the frame intact. The lead retained
that behavior under main's standing rule for small visible slips with no
owner-facing behavior and for layout-library quirks. Preserve both captures;
this is a narrow appearance difference, not evidence of a cache regression
or authority to change keys, choice visibility or acceptance. Required
120x40 and 80x24 local/all comparisons remain separate screen gates.


## CTUI-54: saturate capped resume sizing without shaping hidden rows

The first actual resume measurement retained three full shaping passes at a
cold width: no-edge frame sizing, edge frame sizing and final exact extents.
Wrapped 10,000-choice cold stages took roughly 165 to 207 ms. Every resume
choice has at least one metadata row. When choice count already exceeds the
listed-row budget, the capped frame-sizing result therefore equals that budget
without either preliminary shaping pass. The lead approved this exact arithmetic
shortcut; it changes neither uncapped helper semantics nor final geometry.
Keep the one full exact extent projection, preserve the earlier evidence and
rerun the same AOT corpora. Tests cover counts around the budget, empty and
tall titles, zero room and recovery. This does not authorize estimated rows
or claim that the remaining cold O(N) projection is viewport-bounded.


## CTUI-52: carry the opening step into startup failure words

The failed-start screen comparison exposed a preexisting wording gap: the
original says `it refused session/new: ` before the agent's refusal, while
the port kept only the raw message. The CTUI-52 design had retained existing
port failure wording. Options taken to main: document that limit, or add a
separate step-aware startup projection in this slice. Main chose the latter
because the newly opened command-capable screen should read as the original.

U52c carries initialize/new/load/resume context and structured refusal,
connection-closed and observed-exit facts through the existing opening path.
Original auth, method-not-found, exit, cancellation and stale-opening
precedence remain binding. Do not infer a step from words, prefix generic
RPC errors, or change settings/turn failures. No sign-in, pin or fork
subsystem is brought forward. Preserve the pre-fix wrapping captures and
replace the visible mismatch with exact-fix screen evidence. The short
contract is in docs/design/CTUI-52.md.


## CTUI-27: style TextArea content through its actual editor geometry

Reverse search needs the original's inverse literal matches inside the shown
prompt. TextArea currently styles whole fields, while a port-only overlay
would need to duplicate or guess editor row, cursor and viewport geometry.
Options taken to main: a narrow framework full-text style-span hook, or defer
inverse matches with a visible fidelity loss. Main approved the optional hook
as its own framework unit, with its API gate before the port consumes it.

Text, editing, geometry and selection remain unchanged. The span describes
identical controller text and contributes styling only, mapped through the
existing actual row and grapheme layout. Do not introduce a second editor,
wrapping engine, hidden measurement tree or port-specific search API. Existing
placeholder, cursor, focus, control and ANSI policies remain binding. Designer
settles the minimal contract and independent framework tests and public
fixture precede port integration. This supersedes the initial CTUI-27 plan's
assumption that no framework API would be needed.


## CTUI-27: taken begins at dispatch, not physical wire admission

Review found that the design's `held-before-wire` wording promised more
withdrawal than the original. The original marks a personal row taken at
dispatch/call entry, before asynchronous mention resolution or serialized
steering completes. Only explicit question/call holds put that row back
within the prompt's interrupt ownership. Options taken to main: retain that
boundary, or add prewire withdrawal and move taken to physical admission.
Main chose the original boundary and no prewire withdrawal token.

Esc leaves dispatched rows pending, including resolver/serialization waits;
explicitly held rows restore and cannot later send. The actual-wire callback
remains admission/link-recording information only. Preserve accepted-only
transcript/record publication and the original pending-label timer phase;
this is not authority for an early prompt echo. Tests pin cancellation during
a pending resolver, close retirement, serialized taken rows and explicit-held
restoration. The corrected CTUI-27 design supersedes its broader wording.


## CTUI-27: retain the leading-reply-space Markdown residual as CTUI-55

The replay fixture exposed an existing generic Markdown difference: a first
assistant chunk ` Late work1.` retains an extra leading space in the port,
while the original removes it. This is separate from personal into grouping,
self-started closure and the notice's scalar truncation. Options taken to main:
retain the measured residual, or add a framework Markdown/selection unit here.
Main chose to retain it and filed CTUI-55 for probes and its own framework gate.

Keep the before-pair behavior test and raw captures. The nominal CTUI-27 parity
fixture may start its first chunk without a leading space only with the reason
and CTUI-55 reference beside that input. Do not use it to claim leading-space
parity or change generic Markdown/selection in this run. The separate narrow
notice truncation correction uses the existing scalar helper and remains in
CTUI-27; it neither resolves nor hides the Markdown residual.


## CTUI-27: recover the steered row before reentrant observer work

Agent-free probes reproduced the same ordering bug in the port and original
commit 577b581. After a late steer starts an agent-owned turn, the original
removes its pending marker before cancel/closure observers and establishes
quiet plus original-row restoration afterward. A reentrant observer prompt
can therefore run before the restored steered row and stamp late work with
the observer's turn instead of the agent-owned turn. Preserve both red probes.

Options taken to main: keep that original behavior as a limitation, or reserve
a narrow recovery marker ahead of the observers through quiet and restoration.
Main approved the latter as a deliberate difference from ../chord. The port
keeps recovery owned before cancel/closure callbacks, restores the original
queue place before awaiting quiet, and releases the marker afterward in
finally with generation guards before advancing. No framework, public API or scheduler change is
authorized. Tests pin observer send/close/swap, original-row order and late
work ownership; retain exact before/after evidence and name this divergence
in the final handover.


## CTUI-27: connect search paste to the original filtering policy

The original's editedQuery documents first-line, control-stripped paste, but
its UI paste wiring only clears selection. Paired captures at both required
sizes and an explicit bracketed-paste control show the original ignoring
`ESC[200~alpha\nignoredESC[201~` during history search, while the port searches
for `alpha`. Preserve that before pair rather than claiming paste parity.

Options taken to main: retain the designed filtering as a small original UI
slip correction, or ignore search paste to match the original runtime. Main
approved the former as a deliberate difference from ../chord. Search consumes
only the first pasted line with control characters stripped; it does not send
or mutate the saved draft. Pin the bracketed input and those ownership facts
with a test. No generic editor change is authorized. List this difference in
the final handover.


## CTUI-55: strip a paragraph line's leading whitespace in our own syntax

The original drops the leading space of a reply's first chunk because
markdansi dedents each block before parsing and trims continuation lines at
soft breaks; marked itself keeps the space. CommonMark gives the same result
for paragraphs: each line's leading whitespace is removed before inline
parsing (examples 222 and 223), after a hard break too (example 636).
package:markdown 7.3.1 trims only the right end of a paragraph
(`ParagraphSyntax.parse` joins its lines and calls `trimRight`) and has no
option for it; its HtmlRenderer trims each line after `p`, `li` and `br`
while rendering, which is why its HTML looks right while the AST keeps the
spaces.

Options taken to main: strip the leading whitespace in our `_Paragraph`
subclass before inline parsing, trim the first parsed text instead, or file
upstream and keep the residual. Main chose the first, with the after-hard-
break strip. `_Paragraph` removes leading spaces and tabs from each line of
the paragraph's unparsed content, so top-level, quoted, list and streamed
paragraphs, drawing and selection all agree; code blocks, indented code and
list markers are not paragraphs and keep their indentation. An upstream
issue is drafted under `docs/design/evidence/CTUI-55/`, not filed; when the
package fixes it, the override can go.


## CTUI-29: settings are checked by our own code, in zod's words

The port's settings problems repeat the original's lines, which are zod
v4's issue messages lowered and wrapped (`"agent": invalid input: expected
string, received number, ignored`). Validation packages were probed
under Dart on the same inputs. acanthis 2.0.0 (zod-like) reports `Invalid
type: int, expected String`, adds `Field ... is required` for absent keys
and has no strict object, so unknown keys go unreported. json_schema 5.2.2
reports `/agent: type: wanted [string] got 1`, `minLength violated ( vs
1)`, `enum violated x` and `unallowed additional property zz`, without the
received type or the enum's values. luthor 1.1.0, also zod-like, was read
on pub.dev, not probed: it is built around code generation and words its
own messages. None can give zod's wording, the issue order or the refused
command's `got a list whose program is empty`; matching the original would
need a translation layer over any of them, so `lib/settings.dart` checks
the few keys itself. Two differences cannot be copied: a file that is
not JSON says the Dart parser's reason inside `not valid JSON (…)`, and an
unreadable file the operating system's inside `cannot be read (…)`, where
the original says bun's.

The keys the port reads but does not act on yet (`theme`, `editorMode`,
`mouse`, `preferredNotifChannel`, `mcpServers`, `agents.<name>.mcpServers`,
`teamSelection`) are known keys: never named as unknown, their values
checked in the original's words, and the user-only ones still a scope
problem in a project file. `teamSelection` is checked only as an object; its
inner schema is checked when teams land.

Original slips, fixed rather than copied (the lead's call): zod adds a
second line when a non-empty string meets an array (`{"agent": []}` also
gives `"agent": too small: expected array to have >=1 items, ignored`), and
when a command list's program is empty (`["", "x"]` also gives
`"agents.<name>.command.0": too small: …, ignored` before the refusal). The
port gives only the first line of the one and only the refusal of the
other.


## CTUI-29: quote command words as shell-quote does

A settings command given as a list (`"command": ["my agent", "--acp"]`) is
shown in `chord agents` and the start picker as one line, which the original
writes with shell-quote's `quote()`. Two Dart packages were probed on the
same words and shown not to fit. process_run 1.4's `shellArgument` quotes
`a b` as `"a b"` and the empty word as `""`, and leaves `$HOME` bare, where
shell-quote gives `'a b'`, `''` and `\$HOME`. shlex 2.0.2's `quote`, in
Python's style and with an SDK bound below 3.0.0, gives `'it'"'"'s'` for
`it's` and `'$HOME'`, where shell-quote gives `"it's"` and `\$HOME`. Main
chose a port of shell-quote 1.12.0's string branch, with its MIT notice, in
`example/chord/lib/shell_quote.dart`: the port's own concern, not the
framework's. Its tests pin the pairs the original prints.


## CTUI-29: vendor genai-prices 0.2.3's data and port its calcPrice

The original prices a turn's tokens and finds a model's context window with
@pydantic/genai-prices 0.2.3 (MIT), a pinned data snapshot and its
calcPrice; nothing is fetched. pub.dev has no port of it. tokencost 0.2.10,
the nearest, ports AgentOps' Python tokencost: it prices from litellm's
table, so its costs and context windows differ from the original's, and it
pulls in http, tiktoken, fpdart and money2 for token counting the port does
not need. It was shown not to fit. Main chose to vendor genai-prices.

`example/chord/tool/genai_prices.dart` writes
`example/chord/lib/session/price_data.dart` (generated, do not edit, with
the package's MIT notice) from the copy installed in ../chord's
node_modules, the version the original pins: it refuses any other version,
runs bun to read the package's providers through `waitForUpdate()` and its
unit table from the bundle, and keeps only what the port's pricing reads
(provider and model matches, fallbacks, prices with their date and time
constraints, context windows). Price variants are left out, as only a
price context reaches them and the original passes none.
`example/chord/lib/session/prices.dart` ports calcPrice for a model id
alone: provider and model matching, dated model ids, fallback providers,
constraints, the unit hierarchy, tiers and the leaf counts. Its tests
compare 90 prices and 18 models' context windows with what the original computed
for the same models and tokens, probed with bun in ../chord on the date the
probe records (`example/chord/test/fixtures/prices/original_probe.json`).


## CTUI-29: format report figures with package:intl, codes apart from amounts

`/cost` and `/context` write numbers, dates and costs as the original's
JavaScript Intl does: thousands grouped (`2,000`), an older record's day as
`Oct 12`, a cost in a known currency by its sign (`€3.00`). The port uses
package:intl 0.20.3 (`NumberFormat('#,##0', 'en_US')`, `DateFormat('MMM d',
'en_US')`, `NumberFormat.simpleCurrency`), maintained by the Dart team and
working under `dart compile exe`, rather than its own formatting. Main chose
it with one adjustment: for a three-letter code intl has no sign for, intl
prints the code against the amount (`XYZ3.00`), where JS Intl puts a space
between (`XYZ 3.00`); `formatCost` writes the code, a space and the amount
there, and a test pins it. A currency that is not a three-letter code is the
agent's own word after the amount (`3.00 credits`), as the original's
fallback writes it.


## CTUI-28: -p declines no forms until CTUI-33 brings elicitation

The original's `-p` declines a form an agent asks the person to fill in,
with a stderr line per question (`chord: <agent> asked: … — skipped (no one
to answer under -p)`), and cancels a link; it can, because its client
declares elicitation in `initialize` and routes `elicitation/create` to a
bridge. The port declares no elicitation, so a conforming agent sends it no
form, and its ACP layer answers any `elicitation/create` with `cancel` before
a session hears of it. Main chose to leave the decline and its lines out of
CTUI-28 rather than add the capability for `-p` alone, which every window
session would then advertise without honouring it; CTUI-33 (elicitation
forms) adds the `-p` bridge with the capability. dimcode's one-time notice
(CHD-434, said when its permission option leaves read-only) is left out the
same way: the port carries no notices yet. `skippedLines` is ported and
tested for when the bridge comes.


## CTUI-29: currency signs from CLDR 48, as bun's Intl writes them

Replaces the currency part of "CTUI-29: format report figures with
package:intl, codes apart from amounts". intl's `simpleCurrency` in en_US
writes some currencies with a sign another currency shares: CAD and AUD as
`$`, CNY as `¥`, where the original's JS Intl writes `CA$3.00`, `A$3.00` and
`CN¥3.00`; and the space it puts after a code with no sign is a no-break
space (U+00A0), not the plain space that entry named. Main chose a table of
en-US currency signs pinned to the ICU bun carries, 78.1 with CLDR 48, kept
in the port with the Unicode License V3: `tool/currency_symbols.dart` runs
bun's Intl over every code it knows (307), refuses another ICU, and writes
`example/chord/lib/ui/transcript/currency_symbols.dart` and the probe
`example/chord/test/fixtures/currency/original_probe.json`, which a test
compares `formatCost` with at two and four digits. `formatCost` writes USD as
before, a known code by its sign and intl's en-US grouping (`€1,234.50`), a
well-formed code CLDR does not know by the code and a no-break space
(`XYZ 3.00`, as JS Intl writes it), and anything else as the amount and the
agent's own word (`3.00 credits`). intl stays for the grouping and for
dates.


## CTUI-28: headless one-shot here, `chord acp` as CTUI-56

The original's `chord acp` (`src/acp_agent.ts` with `session/upstream.ts`)
is a multi-session ACP server: list, load, resume, close, queued prompts,
`$/cancel_request`, titles, `auth/status`, capability-gated updates, aliases
and the children, team and monitor extensions. That is a new subsystem of
the ACP layer, not a small feature. Main split it into CTUI-56 for the
architects team; CTUI-28 ports `-p` alone: piped input, `--output-format
text|json`, `--effort`, `--permission-mode`,
`--dangerously-skip-permissions` and the original's exit codes.


## CTUI-29: the slice of settings, usage and cost

Main approved the keys whose features the port has: `agent`,
`offeredAgents`, `agents.<name>.command`, `model`, `effort` and
`permissionMode`, and `copyOnSelect`, which replaces the window's
constructor seed. The window takes `-m`/`--model`, `--effort` and
`--permission-mode` as the original does. Left for the tasks that bring
their features: the keybindings file, the `settings` tool (chord's MCP
server), `offeredAgents` in `/new` completion (no `/new` yet), `chord
agents --json` and `-C`/`--cwd`, and `/cost`'s `This session` table (one
session in the port). Retired sessions' late usage is recorded in the old
record as the original does, with its wait before the old session closes.


## CTUI-29: a required starting value fails nothing yet

`askStarting` reports a refused `required` model or mode, but
`Conversation` does not fail the start on it as the original's does
(`conversation.ts`). Only the original's children and task agents
(`agents_host.ts`) ask for required values; the window and `-p` never do.
It is wired when task agents land.


## CTUI-29: long paths wrap at spaces until CTUI-57

At 80x24 the original breaks a settings warning after a `/` inside a path,
as OpenTUI's word wrap allows; the framework's `Text` breaks only at
spaces, so the port moves the whole path to the next row. The difference
is the framework's, not the settings', and reaches any row with a long
token. Main kept it out of this run and filed CTUI-57 for break
opportunities after `/` and OpenTUI's other break characters.


## CTUI-29: an autonomous cycle's cost joins the last turn until CTUI-58

The original opens a lane for an agent's own cycle (Claude's background
task results, codebuddy's unasked turns) and counts its cost as a row of
its own. The port has no cycle lanes: those updates go to the last turn, so
the session's total is the same and the cycle's cost is added to the
previous turn's figures. Main filed CTUI-58 for cycle lanes, their
transcript lines and their costs.


## CTUI-29: the native smoke fixtures follow the current start

Five `compile` smoke cases already failed on main: the start scripts waited
for `exited.`, which CTUI-52's failure words no longer end a row with, and
the resume fixtures recorded the temporary directory as `/var/...` while
the binary's working directory is `/private/var/...`, so exact directory
matching found no local session. Main chose to fix both fixtures here: the
scripts wait for the current words, and the fixture resolves its directory
with `resolveSymbolicLinksSync`. The product's exact matching is unchanged,
as the original's is.


## CTUI-29: fractional counts round as intl does

`/cost` and `/context` write a count as the original's default
`Intl.NumberFormat('en-US')` does, grouped with up to three fraction digits,
through intl's `NumberFormat('#,##0.###', 'en_US')`. They part only at a tie
past the third digit: ICU rounds the decimal a number prints as, so
1234567.8915 is `1,234,567.892` under bun, where intl rounds the binary
double, which lies just below the tie, to `1,234,567.891`. Main chose to
keep intl's rounding rather than write a decimal rounding of our own: such
counts reach the reports only from agents that report fractional tokens,
and a test pins today's output.


## No code generation for actions

The owner does not want code generation. Keys stay bound at run time through
`Actions`, with descriptions, as they are today; there is no `@Action`
annotation, no `build_runner` step and no analyzer plugin. Conflicts keep
failing when a scope mounts. A keybindings file that moves keys is read at
run time over the same bindings. README's open question on how actions are
generated is closed by this.


## CTUI-57: wrap-ansi is ported into the framework

The original wraps some strings itself with the npm package wrap-ansi
10.0.2 before drawing them (the crash screen, `chord agents`, start hints,
tool headlines and summaries through `wrapLine`, the permission dialog,
hanging picker choices, the resumed header title), and draws the rest
through OpenTUI's word wrap. The two break differently: wrap-ansi breaks
only at spaces and places an overlong word by its own rule. Until U1 the
framework's space-only wrap happened to match wrap-ansi at those sites.

Packages tried on pub.dev: ansi_wrap 0.1.2+2 is unmaintained (last
published 2023-10) and is not wrap-ansi's algorithm; textwrap 2.2.1 ports
Python's textwrap, which breaks after hyphens by default and places long
words differently. Neither reproduces wrap-ansi. Main chose a framework
port: `TextLayout.wrapAnsi` in `lib/src/text/wrap_ansi.dart`, carrying
wrap-ansi's MIT notice, with tests made of pairs probed from wrap-ansi
under bun (docs/design/CTUI-57.md, U1b).


## CTUI-57: text wraps where OpenTUI's word wrap breaks

Supersedes "CTUI-29: long paths wrap at spaces until CTUI-57" and the
long token on CTUI-52's failed-start screen. `Text`'s soft wrap breaks
where OpenTUI's word wrap does: after `/` and its other break characters,
Unicode spaces and CJK, as probed from OpenTUI 0.8.4 and read in its
`utf8.zig` (docs/design/CTUI-57.md). Two more of its rules came along,
since the original draws them and they live in the same function: a word
wider than the row starts a row of its own before it is cut, and a
whitespace run at a break is dropped whole. Code, Diff and TextArea keep
their spaces and their wrap; Markdown paragraphs take the break set only.


## CTUI-57: a combining mark on a space stays with it

wrap-ansi splits at U+0020 before it segments graphemes, so a space that
carries a combining mark is pulled apart: `'abcdef ́'` at 6 is one
row in the original and two in the port. Main chose to keep graphemes
whole, as the rest of the framework does; a test pins the two rows.


## CTUI-57: a tab in a line's indent counts its width

The original's `wrapLine` measures the indent with string-width, which
counts a tab as no cells, and OpenTUI then draws the tab wider, so a
tab-indented row runs past its room. That is a small slip of the
original's: the port counts the tab as the cells it draws, so
`wrapLine('\tabc', 5)` is three rows that fit, where the original's one
row overflows.


## CTUI-57: diff rows wrap by cell until CTUI-60

The original wraps a diff's code rows with `wrapLine`, at spaces, in the
transcript and in the permission dialog; the port draws them through the
framework's `Diff`, which keeps spaces and wraps by cell, and measures
the dialog's height the same way so that both agree. The difference
predates CTUI-57. Main filed CTUI-60 for a wrap-ansi mode on `Diff`, with
the heights kept in agreement.


## CTUI-59: the failed-start screen has no account line

The original's sign-in block opens with the account the agent reported
through `auth_status` (CHD-629). The port has no account state, so its
block reads as the original's does when no account was heard. The rest of
the block, the pin line and the stderr tail with zeroclaw's way on are
the original's, reusing CTUI-28's helpers for `-p`.


## CTUI-58: an agent's own cycle has a lane of its own

Supersedes "CTUI-29: an autonomous cycle's cost joins the last turn until
CTUI-58". As the original's conversation does, a cycle begins on its
start mark, or on work arriving between turns from an agent that starts
cycles of its own (Claude's adapter), and ends on its end mark, a cancel,
or a prompt taking it over. It is recorded as `cycle_started`, replayed,
and costed as a row of its own. The task's "start and result lines" are
what the original draws: the turn's working line runs through the cycle,
and the cycle ends as a turn's ordinary result; there are no lines of a
cycle's own. waits.ts and upstream_turns.ts have no counterpart in the
port, so nothing of theirs was carried.


## CTUI-56: `chord acp` serves the state and steer extensions, not agents or monitors

The original's `initialize` advertises four `_chord` extensions. `agents`
(send, close) and `monitors` (changed, stop) need children and monitors,
which wait for M4. `session/state` and `session/steer` concern main alone,
and the port already steers (CTUI-27). Options: serve the two main-only
extensions now and advertise only them; serve none until M4. Main chose the
first: `initialize` advertises `{"session/state": 1, "session/steer": 1}`,
and `_chord/agents/*` and `_chord/monitors/*` are -32601 until M4 adds them.


## CTUI-56: chord adds no commands of its own until M4 and M5

The original's only `chord acp` commands are `/team` and `/new`, which are
teams and children. Main put them on CTUI-35 (`/new`) and CTUI-37 (`/team`).
So `session/prompt` sends every slash command to the agent as typed, no
`chord/command` reply exists, and an agent that sends no command list gets
none from chord (the original's `commandsIfNone` exists only to show chord's
two). A `commandOf` hook that returns nothing stays as M4's seam.


## CTUI-56: the serving side of ACP is a dispatcher of ours

`json_rpc_2` 4.1.0's `Peer` and `Server` were checked for serving ACP to a
client and shown not to fit: a handler never sees its request's id, there is
no per-request cancellation for `$/cancel_request`, no hook for when an
answer has been written (the shutdown drain and a new session's held
updates need it), it serves batches ACP refuses, and its error words are not
the SDK's. Options: our own dispatcher; `Peer` with workarounds. Main chose
our own, in `rpc.dart`: one core shared by the existing `AgentRequests`
(refactored onto it in the same unit, its tests the guard) and a new
`ClientRequests`. `json_rpc_2`'s `Client` stays for chord's requests to the
client, as CTUI-12 chose for the agent side.


## CTUI-56: ACP params errors carry zod's issues in zod's words

The original's SDK checks each method's params with zod and answers -32602
with zod's issue list as `data`. Options: reproduce that list for the fields
chord reads; the same code and message with shorter data of our own. Main
chose the first, as CTUI-29 did for settings.

Correction, 2026-11-18: the SDK does not send the issue list. It answers
`RequestError.invalidParams(error.format())`: message `Invalid params`,
`data` zod's `format()` tree (`{"_errors": [], "<field>": {"_errors":
["<zod's words>"]}}`). Main chose to send that tree, as the original does;
a test pins it against a probe of the original.


## CTUI-56: the session layer gains what the server needs, in this task

The contract needs four things the port's `Session` and `Conversation` lack:
image and embedded-resource prompt blocks, renames (records are read, never
written), the agent's account for `auth/status`, and client MCP servers
filtered by the transports the agent takes (`servers.ts`'s `serversFor`,
with `chord/held_back`). Options: build them in CTUI-56; split them all into
prerequisite tasks; build these four here and leave settings' and
`.mcp.json` servers out. Main chose the last. They are session-layer units
before the server's, each with the window's tests kept green. Settings' and
`.mcp.json` MCP servers belong to CTUI-34 for the window, `-p` and `chord
acp` together; until then `chord acp` sends the client's servers alone, a
recorded difference from the original.


## CTUI-56: `chord acp` declares plan, compaction and notices toward the agent

The port declares no client capabilities toward an agent (CTUI-12), because
the window cannot draw what they bring. `chord acp` draws nothing; its
client does. Options: declare nothing, like the window; the original's full
set; the original's set without `subagents` and `terminal_output_delta`.
Main chose the last: `chord acp` sessions declare `plan`,
`session.compaction`, elicitation (next entry), and `session.notices` when
the client declared it. `subagents` and terminal deltas wait for M4. The
window and `-p` keep declaring nothing; a record `chord acp` writes may hold
kinds the window omits on replay.

Note, 2026-11-18: the design (section 8) put `capabilities`, `notices` and
the elicitation handler on the session's open options. They live instead on
the injected agent opener, which the host builds per open with the client's
declarations and a handler bound to that entry; the window's opener supplies
none. Main chose this seam, as it saves threading three fields through every
session opener, with no difference on the wire; a test pins that the
window's opener declares nothing and an acp open exactly the client-derived
set.


## CTUI-56: `chord acp` relays forms before CTUI-33

Supersedes, for `chord acp` sessions only, the part of "CTUI-28: -p declines
no forms until CTUI-33 brings elicitation" that cancels every
`elicitation/create`. Options: keep cancelling; declare elicitation (form
and URL) for `chord acp` sessions and relay `elicitation/create` and
`elicitation/complete` to the client; wait for CTUI-33. Main chose to relay
now: the client honours what chord advertises, so CTUI-28's objection
(advertised without being honoured) does not apply. As the original, a
request-scoped form or one naming an unannounced session is cancelled, an
error or unknown action answer is `cancel`, and a form is withdrawn on
`session/cancel` or close. The window keeps cancelling until CTUI-33.


## CTUI-56: plan approvals stay cancelled until CTUI-63

The original turns `cursor/create_plan` and `x.ai/exit_plan_mode` into
`session/request_permission`. The port answers both `cancelled` and has no
plan ask. Options: keep `cancelled` in `chord acp`; build plan asks for
`chord acp` alone. Main chose the first and filed CTUI-63 for plan approvals
in the window and `chord acp`. Until then cursor's and grok's plan modes do
not proceed for a `chord acp` client.


## CTUI-56: `chord acp --nope` is refused as an unknown option

The original's Cliffy reads an unknown flag after `acp` as the agent
argument: `--nope` is an unknown agent, and with `--agent-command` it
silently names the agent. The port's `args` refuses unknown options.
Options: mimic the quirk; refuse with `args`' own line. Main chose the
second, by the rule already applied to OpenTUI quirks: `Could not find an
option named "--nope".`, exit 2, empty stdout, and `--nope --agent-command x`
is refused too. The original's test (exit 2, empty stdout, stderr naming
`"--nope"`) still holds; the port's README states the port's line.


## CTUI-56: a malformed line does not stall reading

The original's SDK waits to write a parse error before reading on, so a
malformed line while stdout is full stops input; its guide lists it as a
limit. Options: reproduce it; not, and say so. Main chose not: the port's
reader queues the error and reads on, and the port's README says so.


## CTUI-56: chord's asks to the client are keyed per session

The port's permission ids are counted per session (`permission-1` in each),
where the original's are UUIDs, so the original's single connection-wide
ask map would let one session's answer or close settle another's. Each
session entry keeps its own asks by local id; the JSON-RPC id of the request
to the client is allocated separately. Main's `requires_action` is "this
entry has an ask open"; `host_fold` comes with M4's children. When chord
withdraws an ask it sends `$/cancel_request` to the client, as the
original's SDK does for an aborted request.


## CTUI-56: answers that order the wire are enqueued, not awaited

A turn's updates go before its answer and later ones after it; a load's past
goes before its answer. A Dart Future's completion runs a microtask later, so
an update enqueued right after completing it would overtake the answer.
`session/prompt`, `new`, `load` and `resume` are deferred handlers, answered
by the host through `respond`/`fail`, which enqueue the line synchronously.
A new session's held updates still wait for the answer's flush, as the
original waits for the write.


## CTUI-56: load replays a raw ACP past, from the record or the agent

The window's `HistoryReplayed` carries transcript actions that merge user
chunks and drop links and unsupported updates, so it cannot feed the
capability gate. `Session` gains a raw past beside that projection: the
record's `prompt` (with `from`), `update`, `renamed` and `left_open` events,
or, for an id chord never recorded, what the agent sends during its own
load; one source per open, never both.


## CTUI-56: no session is admitted once the way out has started

`session/new`, `load` and `resume` check for the way out at their start and
again after every `await` before an agent process starts, as the original
does after reading the place; once it has started they are -32603. An entry
is owned by the close steps from the moment its process starts, so no agent
starts after cleanup has taken its list.


## CTUI-56: settings per directory and shared records, as the original

The launch directory's settings are read once, other `cwd`s on each call,
as `place.ts` does. Two processes may append to one record, as the original
allows; no guarantee is made that their lines never interleave or tear,
since a buffered append is not one atomic write.


## CTUI-56: requests before `initialize` are refused, as the original's SDK

The design did not name it. The original's SDK answers every request other
than `initialize`, before one has been answered successfully, with -32600
`Invalid request: ACP connection must be initialized before '<method>'`,
keeping the id; notifications pass. The lead settled it as the original:
`ClientRequests` does the same, with a test.


## CTUI-56: zod's words come from a checker of ours

Reproducing zod's -32602 data needs zod v4's English words, its union and
intersection merging, and its `format()` tree. Three pub.dev packages were
tried: `zod` 0.0.1 is a seven-line stub; `zard` 1.4.0 and `zodart` 1.7.0
word their issues their own way (`Expected a string value`) and give no
`format()` tree nor zod's union semantics. So `lib/acp/params.dart` is a
small zod-shaped checker of ours, beside the schemas in `agent_app.dart`,
pinned by 55 cases whose expected trees come from probing the original's
schemas under zod 4.6.7.


## CTUI-56: an agent's `initialize` answer is read raw, as the original

A slip of the port, fixed in this task. The original keeps the agent's
`initialize` answer unparsed (the SDK has no response mapper for it) and
reads it with optional chaining and truthiness: `auth.status` and
`sessionCapabilities.title` are taken when truthy, and a value of the wrong
type reads as absent. The port threw on such shapes (`agentCapabilities: 3`
failed the open) and, for a while in this task, took only object markers.
The lead settled it as the original; tests pin truthy and falsy markers and
the wrong-typed shapes opening.


## CTUI-56: a withdrawn ask's request stays pending in `json_rpc_2` until answered

chord's requests to the ACP client go through `json_rpc_2`'s `Client`, which
has no per-request cancellation. When chord withdraws an ask it sends
`$/cancel_request` and settles the ask itself, but the `Client` keeps the
request pending until the client answers that id or the connection closes;
the original's SDK drops it at cancellation. Options: accept that and close
the `Client` on the way out; an outbound sender of ours; feeding the
`Client` a synthetic response. Main chose the first: the retention needs a
client that never answers a withdrawn request and is bounded by its asks. A
late answer is ignored, and tests pin both that and the release on close.


## CTUI-56: `session/cancel` between turns leaves an agent's ask pending

The design had `session/cancel` withdraw open asks; the original's is
`conversation.interrupt()` alone, and an agent's permission or form is
withdrawn only when a turn or cycle is cancelled, so between turns it stays
pending, in the window and in `chord acp` alike. Options: follow the
original; withdraw them, as a difference. Main chose the original: the ACP
client that sends `session/cancel` answers its own pending requests. Close
and the way out still withdraw. A window change made in this task on the
wrong premise, Esc withdrawing a held-back permission, was reverted after
comparison with the original.


## CTUI-56: `chord acp`'s refused startup command has no `chord: ` prefix

The design's CLI table gave the refusal of the launch directory's agent
command as `chord: <refusal>`. The original's `serveAcp` writes the refusal
line bare (`claude not started: agents.claude.command in
.chord/settings.json: ...`), while its window prefixes it. The lead settled
it as the original, following main's rule that the original wins where the
design departs from it without saying so; a test pins the line.


## CTUI-56: records with a counted `usage` line could not be read back

A slip of the port, found in this task: the record worker's action codec had
no `UsageAction`, so reading back any record holding a counted `usage` line
(the window writes one after a turn) failed with `Not a supported historical
action`, breaking a window resume and `chord acp`'s load alike. Fixed in this
task with a test; the original reads records without a worker and has no
such codec.


## CTUI-56: `chord acp` flushes stderr within the drain bound before it exits

Dart's `exit()` drops what an async `stderr` still holds, while the
original's Node writes stderr to pipes and files synchronously, so its last
lines (the connection closed, a crash, the deadline's names) arrive. The
lead settled a flush of stderr bounded by the 500 ms drain, then the exit;
a signal still exits at once. A stderr pipe that is full and unread blocks
chord in the write itself, as it blocks the original; the regression is the
original's, a stderr nobody reads with prompts still answered and EOF exiting
within the bound.


## CTUI-30: the clipboard's image is read through the platform's own tools

The original reads the clipboard's image with `@mariozechner/clipboard`
(clipboard-rs through N-API) and tells an image from its bytes with
`file-type`. For the bytes, `mime` fits: its header lookup gives PNG, JPEG,
GIF and WebP from the bytes alone, the bytes winning over a wrong name, and
it runs under `dart compile exe`. For the clipboard, no maintained pub.dev
package reads an image in a plain Dart program on macOS and Linux:
`super_clipboard`, `pasteboard`, `clipboard`, `imclipboard`,
`image_clipboard`, `flutter_image_clipboard` and `hyper_render_clipboard`
are Flutter plugins; `win32_clipboard` is Windows alone and hands raw
formats; `dart_clipboard` (Rust FFI, 2021) is unmaintained and reads text;
`sdl3` needs libSDL3 installed and SDL's video started, so a compiled chord
would not stand alone. Options taken to main: the platform's tools, our own
FFI bindings, a native clipboard-rs library of our own, or only images a
path names. Main chose the platform's tools, as a terminal service in the
framework: `osascript` asking for the clipboard as `«class PNGf»` on macOS,
`wl-paste` then `xclip` elsewhere on Unix, PowerShell's `Get-Clipboard
-Format Image` on Windows, which is tested only through a fake runner. Where
no tool is found the port says the original's failure note.


## CTUI-32: program status goes to the terminal unwrapped, as OpenTUI writes it

The lead's brief had OSC 7501 go through the tmux passthrough the
notifications use. The original writes it with OpenTUI's `setProgramStatus`,
which never wraps it for a multiplexer, as it writes the title. The lead
settled it as the original: the record is written bare, and a record OpenTUI
would refuse (its id, app, title and message bounds, progress or kind where
the state takes none) throws, as OpenTUI's does.


## CTUI-32: the window declares `session.notices`, and nothing else yet

CTUI-12 left the window declaring no client capabilities, and its note on
this task said this task declares `session.notices`. The window now declares it, as the
original's does, and folds and draws the agent's notices; `plan`,
compaction and the rest wait for the tasks that draw them. The original's
`-p` declares notices too; the port's `-p` does not yet, a difference left
low, for later.


## CTUI-32: keys typed while the agent starts are not kept yet

The original draws the prompt box under the splash while the agent starts
and keeps what is typed there for the window. The port's window, before this
task, draws no prompt box while starting and drops those keys, so the
splash's case of them cannot hold. The lead left it out of this task, and
main filed it as its own task; the splash, its drift, Esc to the window and
the slow hint are the original's.


## CTUI-63: plan approvals are asked in the window and relayed by `chord acp`

Supersedes "CTUI-56: plan approvals stay cancelled until CTUI-63".
`cursor/create_plan` and `x.ai/exit_plan_mode` are put to the person in the
plan box, kept in the session's record with their answers, and, in `chord
acp`, relayed to the client as `session/request_permission`, as the
original does. Asks from nested sessions wait for M4's children.


## CTUI-63: the plan's Note wraps by cells and does not page

The plan box's Note is the framework's `TextArea`, bounded to half the
window as the original bounds it and following its cursor. Two differences
were left, low, for later: it wraps by cells where the original's
`noteLines` wraps at spaces (the text area has no word wrap), and the page
keys do not scroll it apart from the cursor.


## CTUI-31: vim's normal mode is our own reducer, in the framework

The original plays `/vim`'s keys on `@replit/codemirror-vim-core`, which
has no Dart port. pub.dev has no maintained Dart vim engine: searches for
"vim", "vim emulation" and "vi editor keybindings" found `dart_nvim_api`,
a Neovim msgpack-RPC client that drives a real Neovim and needs `nvim`
installed, which the port cannot assume; `flutter_vimium`, vim-style link
navigation for Flutter pages, not an editor; and `xterm3` and
`novident_editor`, a terminal emulator and a rich-text editor with no vim
mode. Main chose our own reducer: `lib/src/foundation/vim.dart`, pure,
over a text area's value, covering the original's `NORMAL_KEYS` and pinned
by porting its `tests/ui/prompt/vim_test.ts`. codemirror-vim's other
commands are left out: visual modes (`v`, `V`, ctrl+v), ex commands (`:`),
search (`/`, `?`, `n`, `N`, `*`, `#`), `G` and `gg`, marks (`m`, `'`,
`` ` ``), macros (`q`, `@`), repeat (`.`), named registers (`"`), redo
(ctrl+r), `%`, and text objects other than words (`s`, `p`, brackets and
quotes).


## CTUI-66: keys typed while the agent starts are kept

Supersedes "CTUI-32: keys typed while the agent starts are not kept yet".
The window draws the prompt box while the agent starts and keeps what is
typed there, as the original does; ctrl+v says `X has not started yet`
until the agent starts or fails. `Starting X…` moves from a row above into
the status line under the box, where the original's `Status` draws it.


## CTUI-31: a key the file binds wins over the window's own keys

In the original, `!` is the bash prefix of the text and backspace an edit,
not bindings, and the keymap is consulted first, so a key the keybindings
file binds does its action there. The port's window handles both as fixed
keys; the lead settled that a file binding takes the key from them, with
no warning, rather than adding wording the original does not have.


## CTUI-31: a list over the prompt takes its keys first

The original's `bindings.ts` says a context that opens over the prompt,
such as `Autocomplete`, takes its keys first, but its `state.ts` checks
`chat:externalEditor` and other Chat actions before the autocomplete
actions, so an `Autocomplete` binding on a key Chat also uses (ctrl+g,
ctrl+v) is silently dead. The lead took this as the original's slip: in
the port, while a completion list or the `?` panel is open, the prompt
yields every key that context binds, and a list's keys act only while the
list is open, as the original's `bindings_test.ts` requires.


## CTUI-31: `agents:close` is read but bound to nothing until M4

The keybindings file accepts `agents:close` in `Agents`, as the original
does, but the port has no agents list or background view until M4, so the
binding has nothing to act on yet.


## CTUI-31: vim fixes two slips of the original

`r` followed by a character of more than one UTF-16 unit (🙂) leaves an
unpaired surrogate in the original; the port replaces one grapheme with
the whole grapheme (`🙂bc`), counts per grapheme. And the original's
`/clear` rebuilds the window's state without vim, so vim mode goes off for
the rest of the run while `editorMode` still says `vim`, against the
guide's "the choice is kept"; the port keeps vim on across `/clear`, the
box back in insert mode with nothing pending and the yank register kept.
Both were the lead's call.


## CTUI-31: the start page reads the keybindings file and the theme

As the original's `main.tsx`, the agent picker and the `--resume` picker
before the window take the keybindings file's keys and the theme setting;
the file is read once and its problems are reported as the window
reports them.


## CTUI-31: what was left, low or for later

Non-Latin layouts (the Russian-layout fallback and kitty's base-layout key)
are CTUI-67. Left low, recorded on the board: shifted punctuation (`#`)
as any key of a multi-key chord does not match, where a single shifted key
does; pending-chord hints omit the prompt's own chords that carry no
action id; a binding whose id alone changes does not notify `KeyHelp`
listeners; the settings writer writes an untouched `1` read as a double as
`1.0`; the prompt box border is drawn dim where the original uses colour
244; the shortcuts panel's order and a few rows differ from the original's
as designer listed; the `/` list offers `/help` where the original has
`/fork`; and with `/help` typed while the agent starts, Enter keeps it as a
draft, where the original runs it.


## CTUI-33: the scope of live output, subagents, forms and compaction

The task ports four of the original's features, in this order:
compaction notices, live terminal output, elicitation forms (with the
`-p` bridge) and nested ACP subagents. Each slice is built end to end
before the next. Subagents means the core only: routing child sessions,
cancelling them with their parent, the draft-shape enrichers, the
transcript fold, the `Agent(<title>)` block and the running tree. Left out:

- the Questions dialog and its question enrichers (CTUI-68);
- the window's plan fold and the id-addressed `plan` capability (CTUI-69);
- `logStep`, which only the background view uses (M4);
- the CHD-434 dimcode notice, since the port has no notices module yet;
- task agents and monitors (M4).

`chord acp` now declares `subagents`, as the window does, which lifts
CTUI-56's deferral to M4. The owner chose all of this.


## CTUI-33: a form's numbers past what Dart and JSON carry exactly

The original reads a form's number as a JavaScript Number, so it sends an
imprecise float for a whole number past 2^53 or a decimal too large to be
finite. The port's `NumberFormItem` refuses such a number instead, with
"Not a whole number", "Not a number" or the validator's own words. A Dart
`int` stops at 64 bits, and JSON cannot carry a non-finite number. This was
the lead's call.

## CTUI-33: a field taller than the form keeps the original's rows

The framework `Form` lays out rows as the original's `formRows` does. When
one field's block is taller than `maxRows`, only the count of fields below
it is drawn. The fix needs a viewport over part of a field's options, which
CTUI-70 holds (low, backlog). This was the lead's call, under the owner's
features-first rule.

## CTUI-33: form values checked by json_schema, the keyword found alone

The original checks a form's values with zod (`z.fromJSONSchema`) and puts
its own words on each finding by the finding's code. Two pub.dev packages
were tried. `json_schema_builder` 0.1.7 reports a structured error type,
but has no `uri` format, accepts a date such as `2026-13-01`, and checks
formats only in its strict mode, so "Not a URL" and "Not a date" could
never show. `json_schema` 5.2.2 (Workiva) checks every rule the forms use,
formats included, and works under `dart compile exe`, but its errors name
the schema that holds the failing rule, not the rule, which only its
English message says. Main chose `json_schema`, pinned at 5.2.2, with the
failing keyword found structurally: the value is checked against the whole
property schema, and, when it fails, against each keyword of it alone
(`{maxLength: 2}`, `{format: uri}`, …), the first that fails giving the
original's words. No message is parsed; a rule with no words of chord's
shows the package's message, as the original shows zod's.

## CTUI-33: a link's host is converted with punycoder

The link box shows the host as the original does, in its IDNA ASCII form
(`xn--bcher-kva.example`). The conversion uses punycoder 0.3.0's
`domainToAscii`. punycode 1.0.0 was also tried: it only encodes and has no
domain helper. One difference is left, recorded at low priority:
punycoder lowercases but does not apply UTS #46 mapping in full (fullwidth
letters, `ß`), which the original's WHATWG URL does.

## CTUI-68: what the Questions dialog leaves out

The port's Questions dialog, its five question enrichers, the timed-out
answer and the asked mark follow the original. Left out, by the lead under
the owner's features-first rule, each recorded on the board at low
priority:

- the shortcuts panel row `tab ← → ↑ ↓ space` "to answer forms", as
  CTUI-33 left it for forms: in the port's panel it overflows at 80x24, and
  space is bound only inside a question box; the box binds its keys
  through `Actions` with descriptions and names them in its hint line;
- a task agent's questions recorded under its own call, since the original
  takes `subagentId` only from task agents, which are M4;
- the asker's parts (`asker.ts`): the box names the launch's agent, or
  `main` between turns, as the port's form and link boxes do, since the
  port has no task agents, children or teams to name yet;
- leaving the box with ↓ for the agents list under the prompt: the reducer
  keeps the original's `leave`, the box ignores it, since the port has no
  such list (its plan box's Note is the same).

Parity edges found in review and left open: `trim()` strips U+0085 where
JavaScript keeps it; an explicit `"chord/questions": null` is filled where
the original keeps it; a schema with an invalid `pattern` still checks its
other fields where the original turns the whole check off.

## CTUI-67: chord's Russian layout table is its own

The original reads a key a Russian layout typed as the US key in its place
through npm's convert-layout 0.11.1 (`ru.toEn`), then Apple's `ё` on the
backslash key. pub.dev has no maintained Dart package that does this:
searches for "keyboard layout convert", "convert-layout", "russian
keyboard layout", "keyboard layout cyrillic", "wrong keyboard layout",
"transliterate keyboard", "qwerty jcuken", "punto" and "layout switcher"
found icon sets, on-screen keyboards (virtual_keyboard_custom_layout,
super_keyboard_layout) and transliteration (nepali_transliteration,
phonetic_typing), none mapping a character to a key. Main chose a table of
our own: `layoutKeys` in `example/chord/lib/ui/shortcuts/bindings.dart`,
convert-layout's 67 non-ASCII entries with its MIT notice and version, and
Apple's `ё`/`Ё`. The framework ships no table, only the `KeyLayoutFallback`
hook. A test runs convert-layout under bun from `../chord` and checks every
entry, skipped with a reason where bun or the checkout is missing.

## CTUI-35: the scope of chord's MCP server and children

The task takes the original's M4 row "chord's MCP server, children,
messages": the server, its seven tools `list_agents`, `list_sessions`,
`spawn_task`, `open_agent`, `send_message`, `close_agent` and
`clear_agent`, long-lived children and task agents, messages, the agents
list, children on resume, the live `@@` roster, and `chord acp`'s
`_chord/agents/*` with `agents: 1`. The original's server has more tools.
Main chose: `/new` both in the window and in `chord acp`, one parser
(`new_args.dart`); `get_budgets` with teams in CTUI-37; the `settings`
tool as CTUI-79; monitors and the background view in CTUI-36; `/fork` in
CTUI-74. The design is `docs/design/CTUI-35.md`.

## CTUI-35: chord's MCP server is mcp_dart behind a listener of ours

The original serves Streamable HTTP on the loopback with the TypeScript
SDK behind its own handler, which checks a bearer token per session launch
and builds one server per MCP session from the caller's role. Three
pub.dev packages were tried, each built with `dart compile exe` and driven
over HTTP: `mcp_dart` 2.4.4 serves per-session transports behind our own
`HttpServer`, gives each session its own tools, and ends calls in flight
and open streams within 2 s on revoke; a 200 s call completed. `dart_mcp`
0.5.2 has no HTTP transport, so all of Streamable HTTP would be ours.
`mcp_server` 3.1.1 owns the listener, lists every tool to every caller,
ties no session to a token, and leaves a call in flight hanging on revoke.
Not tried: `mcp` 0.0.1 (unlisted), `fastmcp` 0.1.14 (not published for a
year), `agentic_mcp`, `mcp_models` (models only), `dart_mcp_server` (an
application). Main agreed to `mcp_dart`, pinned at 2.4.4, behind an
admission layer of ours in `example/chord/lib/server/server.dart`. The
package has no `onsessionclosed`; our layer chains its own hook after
`connect()`. The trial is kept, reproducible, in
`docs/design/evidence/CTUI-35/mcp_trial/`.

## CTUI-35: where mcp_dart answers differently from the original's SDK

The trial sends 46 requests to `mcp_dart` 2.4.4 and to the original's
`@modelcontextprotocol/sdk` 1.32.2; `results/diff.md` lists every
difference. Admission, sessions, revoke and every valid tool answer agree.
Main chose, per group:

- Tool calls, accepted as the package answers them. A tool outside the
  caller's role, or unknown, is a JSON-RPC error `{"code": -32602,
  "message": "Tool 'close_agent' not found"}`, where the original answers
  a result with `isError: true` and `MCP error -32602: Tool close_agent
  not found`. A missing argument reads `Invalid arguments for tool
  'send_message': JsonSchemaValidationException: Required property is
  missing: text (at )`, where the original reads `MCP error -32602: Input
  validation error: Invalid arguments for tool send_message: Invalid
  input: expected string, received undefined at text`; a wrong type
  likewise. Checking names and arguments ourselves before the package was
  the rejected option. Nothing is filed upstream without the owner.
- What an agent reads at start, configured as the original:
  `tools.listChanged: true` in `initialize` and `"$schema":
  "http://json-schema.org/draft-07/schema#"` in each `inputSchema`,
  through the package's configuration, with a test.
- Transport edges, accepted: a JSON-RPC batch refused with 400 where the
  original serves it; other codes and words for a bad
  `MCP-Protocol-Version`, invalid JSON-RPC and parse errors; the request's
  `id` where the original sends `null`; `charset` in content types; JSON
  member order.

## CTUI-35: every ask gets a UUID, as the original's

The port numbered permissions and elicitations per session
(`permission-1`, `elicitation-1`); the original gives each a
`crypto.randomUUID()`. A task's asks are shown and answered in its
parent's view, routed back through a map of ids to tasks, so two tasks
under one parent, or a parent and its task, would collide with numbered
ids. The ids become UUIDs at their source. The parent's map is set when an
ask is relayed and cleared on settlement and on the task's end; a late
answer to an unknown id is ignored.

## CTUI-35: a task's plan is not relayed, and its ask at exit follows the original

The original's `TaskAgent` relays a task's permissions, forms and
questions to the parent, and no plan approval; the port follows. With an
ask open when a task's agent exits, the original's order of withdrawal and
exit is not plain from its code: ship checks it against the original's
fake and follows it, and a box left open there is treated as a small slip
of the original, fixed with a test and logged.

## CTUI-35: the host stays a class; the window has one event path

The original's `createAgentsHost` is a class over mutable maps whose race
fixes (CHD-476, CHD-373) are written against those maps. A reducer for the
host was considered and not taken: it would depart from the original's
shape for no behaviour. The pure parts (`window_agents`, `tasks`, tool
answers, `childEnded`, refusal words) are lifted out and tested directly.
`StartConnection` stops owning a `Conversation` and becomes the host's
opener; one `WindowFold` folds every session's events synchronously in
delivery order, shown or not. Results that land later carry `(key,
launch)` and are dropped when their agent is gone or was cleared, never
applied to the picked agent. The original's window reads an agent's state
with a lag until it next draws; the port's window folds synchronously, as
the original's `chord acp` does, so its state is fresher. Nothing seen
changes; main agreed.

## CTUI-35: `open_agent` and `spawn_task` ignore a cancelled request, as the original

The original passes no MCP request signal to `open_agent` and
`spawn_task`: a cancelled request neither refuses nor stops a child that
is starting. The port follows. Launch invalidation is separate: a caller
whose launch was let go, or whose session changed while the offer was
read, is answered `STALE` before anything starts; a call already in a
handler after revoke answers that its session was cleared or closed.

## CTUI-35: the scroll anchor moves into ScrollController

The window draws one transcript, keyed by the picked session, with that
session's retained `ScrollController`. Keeping every session's subtree
mounted offstage was rejected (CTUI-1 decided against keep-alive, and
hidden transcripts would still measure on every update), as was keeping
per-session item extents outside the viewport (machinery nothing needs
unless the switch is measured slow). The anchor, the item at the top and
the rows into it, moves from `RenderListViewport` into `ScrollController`
as an `@internal` field, and `ListAnchor` into
`lib/src/foundation/scroll_state.dart`, so a controller attached again
after a resize or ctrl+o comes back on the same entry, as the original's
per-session anchors do. A detached step that moves the view drops the
anchor; empty and zero-width layouts behave as before. No public API
changes. A switch costs a first frame, as a resumed session's; unit 33
measures it.

## CTUI-35: the agents list is the port's own

The original's list is rows of wrapped text counted against a line
budget, folding to one row and `… +N more`. `ListView` scrolls by rows of
known height and `Picker` draws numbered choices; neither fits, and a
general line-budget list would have one user. It is ported as
`example/chord/lib/ui/agents/` on `cellWidth` and `TextLayout.wrapAnsi`,
with nothing new in `lib/`. Its rows are not selectable, as the original's.

## CTUI-35: the room is computed before layout, and the plan box shares as Yoga does

The original reaches its footer's steady states with Yoga in two frames
and a latch. The port computes them before layout, in lines, in a pure
`agentsRoom`: the transcript gives way first, then the agents list down to
its floor, then a request's shrinkable part; each box's height arithmetic
is lifted into a pure function the window also calls. The permission body
gives way only after the list, as CHD-464's `givesWay` says. The plan box
has no such gate in the original: its Note and the list shrink together
by their natural heights, the list folding only when its share brings it
to its floor. The framework architect proposed giving the plan the
permission's order; it was not taken, being a departure from the original.
The port computes Yoga's proportional share and checks it against a
capture of the original.

## CTUI-35: the prompt box's named top is drawn by the port

The original draws `╭─ docs ───╮` as a row of its own, because its
framework's border title takes no colour. The port's `Box.title` draws
`╭ docs ───╮` in the border's style. Changing `Box` for one row the
original itself draws by hand was rejected; the port lays a one-line
`Text.rich` over the prompt box's top border in a `Stack`.

## CTUI-35: what waits for CTUI-36, CTUI-74 and CTUI-37

Main chose: until CTUI-36, the shortcuts panel says `↑ ↓ for prompts,
agents` and `x to close an agent`, without the original's `, background`
and `, stop background`, and a task that outlives its turn shows only in
the status line and in its own block, with no summary row under the list.
CTUI-36 restores both. The lead chose to carry only what records already
hold (`team`, `lead`, `forkedFrom`) and the caller's role, and no code
nothing can reach: no fork refusals, team rows or branches, monitor
registry or summary stop. `chord acp` lists `new` now and `team` with
CTUI-37, as CTUI-56 split its commands; main agreed. This replaces
CTUI-56's "chord adds no commands of its own until M4 and M5" for `new`.

## CTUI-35: tests reach no real agent through a closed runtime catalog

The original's fake opens children on `codex` by default
(`CHILD_RUNTIME`), and the port's fake opener runs whatever command it is
given, so a scenario name alone does not keep a real agent out. Tests use
one catalog that maps every runtime they admit to the fake or a scripted
opener and throws on any other name before a process starts, with `HOME`,
`XDG_*` and settings isolated and `CHORD_FAKE_CHILD_RUNTIME=fake` set; a
test checks that asking for `codex` starts nothing. The fake's
`agentmentions` calls `run_team` (CTUI-37) and is replaced by a scripted
roster.

## CTUI-35: the person's close note names the child's current model

When the person closes a child, the original's `closeByPerson` drops the
child and only then looks up its conversation for the current model, so
the lookup always misses: the note names the model asked for at opening,
or none for a child opened on its default. That is a slip; the lookup is
there to name the model the child runs. The port reads the current model
before dropping the child, so `The person closed parser (codex · <model>,
id <id>)` names the model in use, the default one included. The lead
settled it under the rule that small slips of the original are fixed and
logged.

## CTUI-35: `x` on main says how to quit

The design says `x` on main does nothing; the original's `closePicked`
shows `main is the session · ctrl+d quits` instead, and the design does
not list the difference. The lead followed the original.

## CTUI-35: a task's ask at its agent's exit, checked against the original

Run on the original's fake (`taskchild`, its agent killed while its write
waits), the original's task conversation withdraws the ask first, then
reports `disconnected`, then the failed turn; its `TaskAgent` relays the
withdrawal, ends `disconnected` and tells the parent `fake exited`. No box
is left open, so there is no slip of the original to fix. The port
withdrew the ask in the same place but failed the turn before it said the
agent had gone, so the task ended `failed` with `The agent exited.`: a
slip of the port. A session's turn that failed because its agent went now
waits for the agent's exit to be told first, as the original's order is;
`test/session/tasks_fake_test.dart` checks it. The port also took a
subagent's or task's `session_info_update` as its parent's title, which
the original never does (Q200's `tasktitled`); only the session's own now
titles it.

## CTUI-35: a task's asks are withdrawn when the task is forgotten

In the original, `Conversation`'s `#forget(task)` drops the task's foreign
asks without settling them, and the transcript removes an asking box only
on its own settlement, so a task whose turn ends before its agent
withdraws an ask leaves a box in the parent that nothing can answer. The
design names this a small slip to fix and log. The port withdraws those
asks as it forgets the task (permissions as withdrawn, forms and links as
withdrawn elicitations), except while the parent's session is down or
closing.

## CTUI-35: listeners hear a closing session's late usage

CTUI-29 kept a closing session's late `RetiredUsage` from its listeners.
The window's spend now needs it (CTUI-35's closing spend, CHD-373), and
the original's `#emit` tells every event to its listeners with no closing
gate, the quit-time `retired_usage` included. The port now does the same;
the figures still land only in the old session's own record.

## CTUI-35: `chord acp` reads main's state from its own asks

The runtime draft (section 8) reads main's `_chord/session/state` from the
host fold. In the port, main's own forms go to the client directly and
never enter the fold, so the fold alone would miss `requires_action` while
one of main's forms waits. The lead kept CTUI-56's source, main's own asks
out with the client, beside the fold for children, whose asks never touch
main's state. What goes on the wire is the original's; tests hold both
cases.

## CTUI-35: the switch hitch is accepted

Main chose, on the switch frame measured above: the hitch of a switch to a
long session is accepted, as CTUI-1 accepted it for resize and resume.
The fallback, per-session extents kept outside the viewport, is CTUI-80 in
the backlog.

## CTUI-36: monitor counts through intl, lists by hand

The original formats monitor counts with `toLocaleString('en-US')` and
names lists with `Intl.ListFormat('en-GB')`. Counts use package:intl's
en-US decimal pattern, as CTUI-29's report figures do. intl 0.20.3 has no
list formatter, so `a, b and c` stays a small function, as CTUI-35's
`_andList` in the agents host.

## CTUI-36: a shell that fails exec after the launcher starts it

The original refuses `monitor` at once when the shell does not start. The
port refuses a missing shell and a missing directory the same way, but the
group launcher (`lib/platform/group_exec.dart`) frames only a failure and
reports `ok` before `execv`, so a shell binary that resolves and then
fails to exec is seen only after the monitor has started. The lead chose
to let such a monitor end at once with the launcher's 127 or 126, so its
end sentence reads `(command not found)` or `(not executable)`, over a
second success channel in every group spawn or a timed wait. A command
that fails inside the shell is the shell's own 126 or 127 in both.

## CTUI-36: Enter in a background detail goes to the entry's top

The original scrolls the owner's transcript so the call's own box is the
top line, found inside its entry by OpenTUI's per-box ids. The port's
transcript knows rows only per entry, so Enter puts the top of the entry
holding the call on the top line: exact for a monitor's call and a lone
task block, the group's first row for a task further down a group of
tasks. Calls inside an adapter subagent's work come with CTUI-83. Row
targets inside an entry are CTUI-85 in the backlog.

## CTUI-79: the settings tool's home and save errors

The original shortens paths in the tool's answers with `os.homedir()`,
which reads the password database when `HOME` is unset. The port follows
its own `configHome`: no `HOME`, or an empty one, means no home to
shorten, and paths show as they are; the user's file then exists only
through `XDG_CONFIG_HOME`. A save that fails answers with dart:io's OS
error text, the home shortened as the original shortens it; Node's
`EACCES`-style wording is not available from Dart.

## CTUI-79: teamSelection is checked with settings, ahead of teams

The tool reads only what the settings check passed, and the original
checks `teamSelection` strictly and merges its layers deeply. The port's
settings check and merge now cover `teamSelection` as the original's do,
on the parser CTUI-29 chose; budgets and team selection stay with CTUI-37.

## CTUI-37: team files read with `yaml` 3.1.4, our own check

The original reads frontmatter through vfile-matter and npm `yaml` 2.9.1
(not `@std/yaml`, as M5-teams.md says). `package:yaml` 3.1.4, already in
the lock, read every trial input to the same data, the repository's two
team files included, and becomes a direct dependency of the port. The
team check is our own in zod's words and order, as CTUI-29 settled for
settings; the test reads the original's problem table.

## CTUI-37: team files written by our own emitter

No Dart writer matches npm `yaml` 2.9.1's `stringify`, which the original
writes team files with (plain scalars, its quoting, `|` blocks with
chomping and indentation indicators, folding at 80 columns). Tried and
shown not to fit: `yaml_writer` 2.1.0 loses data (leading spaces, `|+`
written as `|`); `yaml_edit` 2.2.4 reads back the same in both programs
but writes every multi-line string as one double-quoted line with `\n`,
in either style setting. People read and edit team files, so multi-line
instructions must stay block scalars. The owner chose our own emitter,
`example/chord/lib/yaml_stringify.dart`, byte-identical to npm `yaml` for
what chord writes, tested on fixtures recorded from npm `yaml` and live
against it under bun where present.

## CTUI-37: Claude's usage read spoken from Dart, with no worker

The original runs the TypeScript Agent SDK's experimental usage getter in
a worker re-exec of its own binary. Dart has no Agent SDK. Recorded
against a fake executable (no real `claude`, no network): the getter is
two stream-json control requests (`initialize`, then `get_usage` with
`skip_behaviors`) on fixed argv and env, which the original's own fixture
provider speaks. Options were: speak them from Dart with no worker; keep
the re-exec for parity; run the SDK through a JS runtime; report Claude
unavailable. The owner chose the first: `claude` is spawned in its own
process group, the original's failure words are kept and its three
worker-only words never produced, and the 256 KiB bound is on `claude`'s
stdout in total where the original bounds the worker's printed result.

## CTUI-37: Codex's app-server answers through an adapter

`json_rpc_2` 4.1.0's client drops every response lacking
`"jsonrpc": "2.0"`, and Codex's app-server never sends it. Options were a
channel adapter, a sequential reader of our own, or Codex unavailable.
The owner chose the adapter: it adds the member to what Codex sends and
strips it from what chord sends, and `json_rpc_2` keeps ids, timeouts and
stream end.

## CTUI-37: a team file's YAML error and the native check

A frontmatter that does not parse says `the frontmatter is not valid YAML
(…)` with Dart `yaml`'s message inside (`Duplicate mapping key.` where
npm yaml says `Map keys must be unique`); a test pins one. The resource
executable's Mach-O/ELF check is `file-type` 22.3.0's two rules in about
twelve lines of our own: `file_magic_number` 2.1.0 and `file_signature`
1.0.1 need Flutter, `file_type_plus` 1.1.0 and `mime` know neither
format. The owner accepted both.

## CTUI-37: cliffy's rows in a port-local helper, graphemes whole

The proposal table and `/team show`'s running table are printed by
`@cliffy/table` 1.3.1, whose wrapping matches neither of the framework's
wrappers. A generic table in `lib/` was rejected (one library's rule, two
chord callers, as CTUI-35 judged the agents list); the port gets
`ui/teams/cliffy_row.dart` with cliffy's word, span and padding rules.
Cliffy cuts overlong words by code point and counts widths per code point
(a ZWJ emoji is 4 and can be cut after its joiner). The owner chose
graphemes whole with the framework's widths, as in CTUI-57: the nineteen
cases recorded from cliffy under bun stay in the test, the differing ones
(ZWJ sequences, combining marks at a cut) pinned with the port's lines.

## CTUI-37: the tables' column widths use `cellWidth`

The original measures the two tables' column widths with string-width
8.3.0. The port uses the framework's `cellWidth`, as every other port of
a string-width call does; they differ on about 7,100 lone code points
(mostly lone marks, and symbols such as the trigrams from U+2630), so a
team string holding one can wrap a cell differently. Porting
string-width's data for two tables was rejected as polish; a test pins
one differing case.

## CTUI-37: a wide character in a one-cell column pads by zero

Cliffy takes at least one code point even when it is wider than its
column, then pads by a negative count and throws `RangeError`, so the
original's proposal row fails to draw (reachable after ctrl+o in a window
about 30 columns wide with a wide model name). The original's slip,
fixed: the port pads by `max(0, …)` and the row is one cell wider; a test
pins the line.

## CTUI-37: the proposal's unreachable folding is not ported

Since CHD-422 the original draws a proposal's instructions, body and
change diff whole; `bodyLines`, `changeRows` and `bodyChange`'s folded
branch are exported and tested but nothing draws them. Following
CTUI-35's "no code nothing can reach", they are not ported; their tests
are left out with them. `proposalBody` is ported, as `/team show` folds
through it.

## CTUI-37: selected-run receipts are appended to the captured record

The original appends each receipt update to the record captured when the
run was admitted (`captureServed`), so a late confirmation or cleanup
warning after `/clear`, resume or close reaches the right record, and a
refused attempt with no prompt keeps its record. The port ports that
capture API and appends; replay keeps the latest update per run id. A
rewrite of the recorded call, which the runtime draft first proposed, was
rejected after review.

## CTUI-37: a team closes concurrently

Closing a lead starts every member's close and then the lead's at once,
joined later with one aggregate error, as `agents_host.ts` does. Awaiting
members before the lead, first proposed, was rejected after review: the
ladders would run in series and the window's close would no longer be
bounded by its longest single close.

## CTUI-37: `--fake` forces fixture resources

The original's dev tools force fixture resource readers with `--fake`.
The port defines `CHORD_RESOURCE_FIXTURE` at compile time from
`tool/dev.dart --fake`, which also takes a staged working directory and
isolated state and config for captures; a test proves that route never
resolves an official reader. It is the first unit, as every capture runs
through it.

## CTUI-37: rendered Markdown lines are public in the framework

The design said nothing new goes into `lib/` for teams. `/team show`
folds a team's body to a preview with a `+N lines` count, and the
original builds both from its Markdown renderer's rendered blocks
(`Teams.tsx` through `proposalBody`). The framework exposed only the
`Markdown` widget, so the port's first build split blocks with its own
expressions, which differ on valid bodies (a fence with a blank line
inside, `__` in inline code). The owner chose a small public call in
`lib/` over the existing parser and layout, giving rendered lines per
block at a width and theme, with tests of its own: any app that folds
Markdown needs it. The port takes the preview and the count from it; the
block splitter is dropped. Laying out the widget and clipping its rows,
and keeping the approximation as a recorded difference, were the
rejected options.

## CTUI-101: dimcode's notice waits while the shortcuts help is open

The original's `noticeShown` does not look at the shortcuts help, so with
help open when dimcode's notice comes due it draws both: help in the
completion slot and the notice among the framed pickers. The port's help
panel floats at the same anchor as the framed pickers, where the two would
overlap. The owner chose that the notice waits while help is open and shows
once help closes; it stays due meanwhile, so nothing is lost. Stacking them
as the original does needs the help panel anchored apart, and is left for a
backlog task. Letting the notice take precedence over help was the other
option rejected.

## CTUI-80: item extents live on the ScrollController

A switch to a long session cost one measurement of every entry (CTUI-35's
switch frame). The heights now live on the list's `ScrollController`, as
an `@internal` field beside the anchor, so a session's retained controller
brings them back when a new viewport attaches; no public API changes.
Reuse goes only through `itemVersion`: the mount checks every kept height
against its item's version, a list without `itemVersion` still drops them
on every rebuild, a new width drops them all, and the exact-height
builder keeps its own path. Under `dart compile exe`, two sessions of
10 000 entries, 40 round trips, on the same busy machine back to back: a
switch to the following session went from 425.50 ms median (452.52 ms at
most) to 0.36 ms (0.51), to the scrolled-back one from 433.63 ms (451.56)
to 0.38 ms (0.60), a round trip from 862.01 ms to 0.75 ms. The scrolled-
back session still lands on entry 5 000 in 40 of 40. A switch back after
a resize to 80x24 still measures every entry (456.67 ms before, 448.49 ms
after), as a new width must; first frames, resizes and streaming are
unchanged. Since kept heights now outlive the viewport, the port's
transcript version gained the three inputs its rows were drawn from but
it left out: `chordServer` and `agent` for every entry, and `windowRows`
for team entries only, so a resize that keeps the width does not
re-measure every entry. Keeping every session's subtree mounted offstage
stays rejected, as CTUI-35 settled.

## CTUI-61: a fake closed to exit 0 gets the original's close bound

`fake_agent_test`'s "a close ends the agent with code 0" exited 143 once
under the whole port suite. Nothing else signalled the agent: the stop
ladder sends SIGTERM when the agent has not exited within the bound's
`exit` after stdin ends, and the port's harness gave every fake test the
100 ms of the original's `tests/acp/process_test.ts`, which exists to keep
wedged-agent tests quick. The original asserts a clean close in
`tests/acp/connection_test.ts` under `exitMs` 300. The lead settled that
the assertions that a close exits 0 take the original's 300 ms close
bound, and the wedged-agent tests keep 100 ms; this is the original's
bound restored, not a timeout raised to hide a race. A fake held stopped
across the close exits 143 under 100 ms and 0 under 300 ms; 20 runs under
eight `yes` processes passed. The whole-suite failure itself was not
reproduced. Chord's own 2 s default was the other bound considered.

## CTUI-73: a hung-up terminal leaves the exit to SIGHUP

When the pty closed, two chains raced on the port's leave: the SIGHUP
owner (leave, then die by the signal) and runApp (input ended, the bounded
flush timed out on the dead output, then its own exit), so under load the
process could exit 1 or 255 instead of dying by SIGHUP. On a
`StdioTerminal` that hung up (its own tty input ended and the output flush
then failed or timed out), the flush failure is no longer reported, and
runApp no longer ends the process ahead of SIGHUP: with `handleSignals` it
re-raises SIGHUP itself; without it, it waits up to 2 s for the embedder's
handler before its usual exit, so it never hangs. Every other runApp exit,
and the reported bounded flush for supplied or non-tty input, are
unchanged. The check is package-internal, so no public API changed.
Swallowing the timeout alone was rejected: it turns exit 1 into exit 0.

## CTUI-71: reply code blocks are drawn as the original's

This supersedes "CTUI-4: code blocks in Markdown wrap, unlike chord's" for
code blocks in replies. That entry rested on chord's code boxes cutting a
long line; the original now wraps them, by character (OpenTUI's
`wrapMode: 'char'` in `Reply.tsx`), with no continuation mark. The
owner, through main, chose to match it exactly: the code inset one cell,
the box as wide as the original's, the title `┌─ <lang> `, rows wrapped
by character as the original's and no `↪`. Code shown outside
replies (the `Code` widget, diffs) keeps its own behaviour unless the
original differs there too.

## CTUI-75: an MCP server's URL is checked over `Uri`, not by a WHATWG parser

The original checks a remote server's `url` with zod's `url()` and an
http(s) protocol: trimmed, `http://` or `https://` written out, parsed by
the WHATWG URL parser, and sent on without tabs or line breaks. No
maintained WHATWG URL parser exists on pub.dev: searches for "whatwg",
"url parser" and "url standard" found none, `whatwg_url`, `ada_url` and
`url_parser` do not exist, `url` is discontinued and Dart 2 only, and
`uri` builds URI templates over `Uri`. So `example/chord/lib/mcp.dart`
parses with `Uri` and refuses what `Uri` takes that WHATWG refuses: a port
above 65535, a host whose last label is a number but is not an IPv4
address WHATWG takes, and a host holding a forbidden domain code point,
also once percent-decoded. A label IDNA rejects, such as `xn--a`, is the
one difference kept on purpose: refusing it would need an IDNA and
punycode checker of our own. The owner, through main, chose this check.

## CTUI-114: a kept future is kept as its outcome

A future made in one error zone that fails delivers its error to that
zone, so an await on it from another zone never resumes. chord's leaves
run in more than one zone (main's, `runApp`'s, the ACP server's), and
several closes were memoised as futures and awaited later from another
zone: a failed agent close left chord alive after SIGHUP, crashed the ACP
leave, or held it to its 15 s deadline. `runApp` itself awaited its
guarded body from outside that body's zone, so a terminal that could not
enter, or a first frame that could not be written, hung it for good.
`runApp` now completes in the caller's zone, and the port keeps every
such future through `example/chord/lib/kept.dart`'s `Kept<T>`, built on
package:async's `Result.capture` and `Result.release` (async is now a
direct dependency of the port): a waiter in the zone that made it gets
the original future, so identity holds; any other zone gets the released
outcome. Closes that cannot fail (monitor ends, the terminal's leave,
shell commands) are kept the same way for uniformity and unit-tested
only. To prove the leaves on a compiled binary, the compile-time define
`CHORD_AGENT_CLOSE_FAILS` (off by default, compiled out of every other
build) makes an agent's close fail after the agent has really stopped;
only `example/chord/test/leave_zones_compile_test.dart` builds with it.

## CTUI-105: the shortcuts help and dimcode's notice are drawn together

This supersedes "CTUI-101: dimcode's notice waits while the shortcuts
help is open". As the original does, the two are drawn at once: the
notice on top, the help below it taking the rest of the room. The
framework's overlay links targets only in the page layer (CTUI-2), so a
notice cannot follow a target inside the help's layer; rather than
amending CTUI-2, while both are open the notice's layer draws both
panels stacked at the help's anchor and the help's own layer stands
down. The notice's picker passes the page and scroll keys through to the
help, so the help still scrolls; its own choices keep their keys, and
Esc closes the help first, as in the original.

## CTUI-70: a form block taller than `maxRows` keeps the focus in view

The original's `formRows` ends the view at a block that does not fit, so
an open list longer than the limit hides the focused field. The owner,
through main, asked for the fix: `docs/design/CTUI-70.md` replaces only
the scrolling paragraph of CTUI-33 §1 with a bounded view of the open
list's options, and where every block fits the rows are the original's.

## CTUI-94: team proposal rows stay unselectable

The task asked for the `propose_team` proposal rows to select, on the
word of a board comment. The original's source does not: `Proposal`
(src/ui/transcript/tools/Tool.tsx) draws them all with `FILL`, which
`src/ui/theme/text.ts` makes unselectable. The port follows the source;
the expanded instructions of a member's first prompt do select, their
header does not, as `TeamPartLine` draws them.

## CTUI-97: the teams picker's reset after a tiny resize is the original's

After a resize through a window too small for the list, the original's
`/team` picker remounts its list on the first row while the hint keeps
the row it had (src/ui/pickers/Pickers.tsx). Captures of both at 120x40
and 80x24 (`docs/design/evidence/CTUI-97/`) show the port doing the same,
and a window test pins it; the task was closed as the original's slip.

## CTUI-111: our own Levenshtein for chord agents' nearest option

`chord agents` refuses an unknown option with Cliffy's nearest-option
line, which @std/text's `closestString` picks through its
`levenshteinDistance` over code points (`[...string]`). The maintained
packages on pub.dev were tried: `edit_distance`, `levenshtein`,
`dart_levenshtein` and `woozy_search` are Dart 2 only,
`string_similarity` is Dice's coefficient, `text_similarity` an
automaton, `fuzzywuzzy` ratios. `did_you_mean` 1.0.1 picks the first
nearest as the original does, but counts UTF-16 units: `chord agents
--d😀` suggests `-h` in the original (both `-h` and `--cwd` are three
code points away, `-h` first) and `--cwd` with the package (four units
from `-h`). The owner, through main, chose our own distance over code
points, `example/chord/lib/closest_string.dart`, matching @std/text's
with Cliffy's ranking: case ignored, the first of equals, no limit.

## CTUI-126: the expect driver's reuse guard checks exact start times

The teardown that reaps what an expect driver spawned compared start
times at one-second resolution, so a process given a recorded PID within
the same second passed. The lead chose a per-platform check, with no
package, over keeping the limit documented: on macOS the spawn hook
records microseconds and teardown reads the process's own microsecond
start time through dart:ffi (sysctl KERN_PROC_PID), killing only if it
started no later than recorded; on Linux the hook records
`/proc/<pid>/stat` start ticks and teardown kills only on equality. What
stays open on macOS is the window between fork and the record, and a
wall clock stepped between spawn and teardown. The Linux branch's test
runs on Linux only.

## CTUI-102: chord upgrade, channels and three distributions, designed in the port

`chord upgrade`, release channels and the npm, Homebrew and GitHub
Releases distributions (the owner's decision of 2026-11-22) are designed in
`docs/design/CTUI-102.md`, units U1 to U9 on CTUI-130 to CTUI-138. Options
considered for where the code sits: a distribution package in `lib/`, or
the port. Chosen: the port, `example/chord/lib/` for the command and
`example/chord/tool/` for the release; nothing in `lib/`, which knows
nothing of chord, and no other program here has a version to upgrade.
The owner's questions are Q358 to Q373, each on the task it blocks.

## CTUI-102: pub_semver orders, but does not validate as npm semver

Packages tried for the original's `semver` (`valid`, `prerelease`,
`validRange`, `gt`, `inc`): pub_semver 2.2.1 (pure Dart, builds under
`dart compile exe`) orders pre-releases exactly as semver on every pair
tried, and differs on validation in twelve measured ways: it takes
`1.0.0-next.01`, leading zeros, components above 2^53−1 and versions over
256 characters, refuses the `v` and whitespace semver normalises, keeps
and orders build metadata, and has no npm range check or pre-release
increment; its `VersionConstraint.parse` takes `any` and refuses `x`. On
pub.dev, `semver` 0.2.1 (2015) and `semver_parser` 0.2.0 are Dart 1,
`version` 3.0.2 is Dart 2 only, `version_manipulation` extends pub_semver
without validation, `app_version_compare` compares only. Within the channel
alphabet npm's `validRange` accepts exactly `^v*(x|0|[1-9][0-9]{0,15})$`
up to 9007199254740990, evaluated exhaustively. Whether the port writes
its own semver grammar beside pub_semver, guards pub_semver, or accepts
the differences is the owner's (Q358).

## CTUI-102: Dart AOT builds, measured, and the macOS entitlement

Dart 3.13.5 on an arm64 Mac builds darwin-arm64 (`minos 14.0`) and
cross-compiles linux-x64 and linux-arm64, and refuses darwin-x64; how the
Intel binary is built is the owner's (Q362). Under the hardened runtime a
Dart AOT binary signed with the original's only entitlement,
`com.apple.security.cs.allow-jit`, is SIGKILLed; with
`com.apple.security.cs.allow-unsigned-executable-memory` it runs. The
port's entitlements file carries the latter, and a `compile`-tag test
signs ad hoc and runs the binary so the kill cannot return unseen.
Notarisation of a Dart binary stays unproven until the owner's first
submission.

## CTUI-102: one archive contract for every distribution

Options: versioned names (`chord-<version>-<os>-<cpu>.tar.gz`) or not.
Chosen: `chord-<os>-<cpu>.tar.gz` with `chord`, `LICENSE` and `NOTICES` at
the top, `SHA256SUMS` beside in sha256sum's format, tag `v<version>`,
draft, `--prerelease` exactly when the version has a channel; the tag
carries the version, and one name per target serves the shim, the
archives, the formula and the upgrade's hints. Archives and npm packages
are made only from signed and notarised darwin binaries and kind-checked
linux ones. NOTICES (Dart SDK, every compiled pub package, the
repository's retained credits) are required, not optional, as the binary
compiles that code in.

## CTUI-102: the release keeps branch and npm tag apart, and teams never run it

A stable version publishes from `main` with no `--tag`, so npm's `latest`
moves; a channel's from the branch named after it with `--tag <channel>`,
as `scripts/dev/release/publish.ts`. The original's `--dry-run`
authenticates npm, reads the registry and submits to Apple, so it is the
owner's alone; teams check every stage through a recording runner, CI is
check-only with read permissions and an allow-listed runner, and no
release workflow is written before the owner says where a release runs
(Q363).

## CTUI-102: chord upgrade -l does not die on a failed read

In the original, `-l` runs as an option action outside the action's error
handling, so a failed registry read or a channel without a tag escapes
`main.tsx`'s catch and dies with an uncaught error and a stack. A slip of
the original: the port prints the same registry message on stderr and
exits 1, with a test. Two deliberate departures (no stack under `-v`, a
sentence for a malformed registry document) are the owner's (Q370).

## CTUI-130: pre-release counters above 2^53−1 order as pub_semver does

The owner chose our own `node_semver.dart` for validation and pub_semver for
ordering (Q358). npm's semver compares numeric pre-release identifiers as
JavaScript numbers, so above 2^53−1 two different counters compare equal
(`1.0.0-next.9007199254740992` and `…0993`); pub_semver compares them
exactly, and beyond Dart's int range as strings. Options: guard the
comparison to round as JavaScript does, or accept the difference. Chosen by
the lead: accept it, pinned by a test as a known difference. A release
counter starts at 0 and goes up by one, so no release reaches it.

## CTUI-134: the formula's desc in Homebrew's form

The design gave the formula the original's npm description, "A full-screen
terminal client for ACP coding agents.". `brew style` refuses a desc that
starts with an article or ends with a full stop, and the tap's `brew audit`
would refuse it too. Options: keep the design's text and accept the
offences, or Homebrew's form. Chosen by the owner: "Full-screen terminal
client for ACP coding agents". The npm description keeps the original's.

## CTUI-136: signing and notarisation fail closed where the original does not

Two slips of the original's `scripts/dev/release/` are fixed in the port,
with tests. A notarisation answered Accepted without a submission id does
not fetch its log, so a stale `notarytool-log.json` from an earlier run
could certify the current binary; the port refuses it. The output of
`security find-identity`, `plutil` and `codesign` was trusted even when the
tool exited with a failure; the port refuses a failed status before reading
the output.

## CTUI-138: CI runners after macOS 14's retirement

The design put darwin-arm64 on `macos-14`, whose GitHub Actions images
retired on 2026-11-02. Options: `macos-15` or `macos-26` for arm64, or keep
the retired label. Chosen by the owner: darwin-arm64 on `macos-15`,
darwin-x64 on `macos-15-intel` (Q362's fallback runner), linux on
`ubuntu-24.04` and `ubuntu-24.04-arm`.

## CTUI-137: a resumed release takes the version commit's parent only at it

A slip of the original's `scripts/dev/release/continue.ts`, fixed in the
port with a test. Once the version commit is made, the original accepts the
built origin as that commit or its parent whatever HEAD is, so a branch two
or more commits past it still resumes into publishing and its push carries
unrelated commits. The port takes that exception only while HEAD is the
version commit; otherwise the origin must be HEAD, under the usual rules.

## CTUI-137: preflight refuses failed git queries; the lock stays the original's

A slip of the original's `scripts/dev/release/preflight.ts`, fixed in the
port with a test: the statuses of the local `git tag` and `git rev-parse`
queries were ignored, so a failed query read as an empty answer; the port
refuses a failed status. The release lock was first written as an operating
system lock released by a crash; the lead returned it to the original's
policy, a lock that is never stale and is removed by hand after a crash,
which the original records as the owner's choice (CHD-623).

## CTUI-137: the release tags and drafts in origin, which must be IKatsuba/chord

Releases go to IKatsuba/chord (Q361), whose code the port is to replace.
The original pushes tag `v<version>` to origin and creates the draft in
origin's repository with `gh release create --verify-tag`. Options: run as
the original and refuse unless origin is IKatsuba/chord; have the release
push this tree there first; or draft there against its default branch,
which is not the built commit. Chosen by the owner: as the original, with
preflight refusing any other origin, so a release runs only once the port's
code lives in that repository.

## CTUI-137: the release destination checked where git and gh really send it

A hole of the original, closed in the port with tests. Checking origin's
fetch URL alone leaves two ways around the IKatsuba/chord rule: a separate
push URL on origin redirects `git push`, and `GH_REPO` (or `GH_HOST`)
redirects `gh release view` and `create`. The port's preflight also checks
origin's push URL and refuses when `GH_REPO` names another repository or
`GH_HOST` another host, naming the variable.

## CTUI-131: `chord upgrade` parses as `args` does where Cliffy's accidents differ

The original's Cliffy takes the next word as `--version`'s value even when
it is an option (`--version --help` looks for a version named `--help` and
says it is not found), and checks an invalid value before a repeated flag
(`--force=x --force`). The port's `args` refuses the missing value and the
repeated flag. Options: copy Cliffy by rewriting the words before `args`, or
leave them. Chosen by the owner, through main: leave them, as for `--nope`
and CTUI-13; they are accidents of Cliffy's, not something chord means.

## CTUI-143: a release binary upgrades itself from the GitHub release list

`chord upgrade` on an official, row-less binary (Q366 a) is designed in
`docs/design/CTUI-143.md`, units U1 to U5. Options considered for the
versions: GitHub's `releases/latest`, `releases/tags/v<v>`, the bare
`releases/download` URLs, or the paged release list. Chosen: the list,
read once per run, for `-l`, `latest` and the asset check; downloads by
the constructed `releases/download/v<to>/<asset>` URL, which has no API
quota, so `--force --version` reads no list. `latest` is the highest kept
version of the running channel (stable: not a pre-release and no channel;
channel: a pre-release on that channel, never moving to a stable), not
GitHub's date-based flag. A `latest` below the running version is
installed as cliffy would. The client is the owner's (Q382): `github`
9.26.0 builds under AOT but loses rate-limit answers, throws a `TypeError`
on an error without a content type, and has no `digest` or `immutable`.

## CTUI-143: verification before the swap, and what is the owner's

SHA256SUMS sits beside the archive, so it proves only the absence of
corruption. On darwin the downloaded binary must also pass `/usr/bin/codesign
--verify --strict` against a requirement pinning the Developer ID anchor,
Team ID and identifier of `tool/release/sign.dart` (measured: 0 genuine,
1 tampered, 3 another signer, under half a second), and every binary must
pass a bounded smoke run printing `chord <to>` before the rename. Rejected
as gates: `spctl` and `--check-notarization` (an unstapled Mach-O makes
them online lookups, and chord's download carries no quarantine) and
GitHub attestations (no Dart Sigstore client; the release builds on the
owner's Mac). A signature the GitHub account alone cannot forge, and
immutable releases, change the release and are the owner's (Q381);
`cryptography` 2.9.0, `pinenacl` 0.6.0 and `ed25519_edwards` 0.3.2 were
tried against real minisign 0.12 vectors under AOT and all agree.

## CTUI-143: the tar is read with archive 4.7.1, bounded by inflating first

Packages tried: `archive` 4.7.1, `posix` 6.5.4, the system `tar`. The
callback's `ArchiveFile.isFile` is true for FIFOs and devices, and links
with an empty target are not flagged, so the entry type is taken from the
public `TarDecoder.files.last`, which 4.7.1 appends before the callback:
behaviour, not documentation, and its acceptance is the owner's (Q383;
alternatives: our loop over `TarFile.read`, our own ustar and pax reader,
the system `tar`). Metadata records are capped per record by the package
but not counted, so the archive is inflated first with `maxOutputSize`
(260 MiB) into a temporary tar: a matching-sum 1 GiB pax flood stops in
0.4 s at 11.7 MB RSS. Release archives carry a pax header before every
member, so pax must be accepted. `posix` supplies `stat` ownership,
`geteuid`, `chmod` and directory `fsync`, which `dart:io` lacks.

## CTUI-143: the rename is the commit point; no rollback copy, no lock

Options for the swap: write in place, copy over, rename aside then in, or
stage beside the target and `rename(2)`. Chosen: stage beside the real
path (links resolved and kept) and rename. Measured on macOS: an in-place
copy over a running signed binary gets the next exec SIGKILLed; rename
leaves the running process its inode and the signature valid. Every check
runs on the staged file before the rename, so nothing after it needs a
rollback; later cleanup failures are warnings and the outcome stays
installed. A foreign owner (root included: no `chown`) and a directory
writable by others or a foreign group are refused; setuid bits are never
set. Concurrent upgrades: last writer wins, each reporting its own commit;
a lock and a post-rename inode check were rejected (the check cannot tell
who won). No signal handler, as U2, except during the smoke run, whose
child leads its own session; leftovers after a signal are documented, not
swept.

## CTUI-143: GitHub reads use no token and no timer

Options: no token, `GH_TOKEN`/`GITHUB_TOKEN` to the API host only, or a
chord variable. Chosen: none, and no base or host variable is read, so the
environment cannot redirect the upgrade; the repository is public and the
rate-limit message names the reset time. Q367's "as the original, no
timeout" is carried over to GitHub reads and the download; only the smoke
run, a local child, is bounded (30 s over exit and pipe drain, 64 KiB of
output, the group killed).

## CTUI-139: the framework is chord_tui and shares the port's version

The framework's package is renamed from `chorded_tui` to `chord_tui`
(owner, Q374); designs and decisions written before keep the old name as
history. It carries the port's version, one value in
`example/chord/pubspec.yaml`, the root `pubspec.yaml` and
`example/chord/lib/version.dart`, held together by a test and written
together by the release bump into its one version commit (Q375). 0.0.1 is
today's placeholder; the next release goes above 0.71 (Q360). The
repository is github.com/IKatsuba/chord (Q376), and the package is
published later from the owner's personal account (Q377), never by a team.

## CTUI-141: highlighting's published range is 0.9.0 patches only

`dart pub publish --dry-run` warns that a dependency pinned to one exact
version "should allow more than one version", and the published archive
must validate with no warnings. CTUI-5's exact pin of `highlighting`
0.9.0+11.8.0 is therefore superseded for the published range by
`'>=0.9.0+11.8.0 <0.9.1'` (main): only 0.9.0 patches are admitted, which
clears the warning, while both pubspec.lock files still pin
0.9.0+11.8.0, so what chord builds and tests is unchanged. The narrower
range was chosen over `^0.9.0+11.8.0` because only that release has been
checked to draw as chord draws.

## CTUI-139: the app at the root, the framework in packages/chord_tui

The owner chose the layout (option 2): the chord app takes the
repository's root, as the original does, and the framework moves to
`packages/chord_tui/`, as the original keeps `packages/cursor-cloud-acp/`.
The root holds the app's `pubspec.yaml` (name `chord`), `pubspec.lock`,
`bin/`, `lib/`, `test/`, `tool/`, `benchmark/`, `analysis_options.yaml` and
`dart_test.yaml`, with `chord_tui: path: packages/chord_tui`, beside what
belongs to the repository: `docs/`, `.chord/`, `.github/`, AGENTS.md, the
LICENSE and the community files. `packages/chord_tui/` holds everything the
published package is built from: its pubspec and lock, `lib/`, `test/`,
`benchmark/`, the examples, CHANGELOG.md, README.md, its analysis options
(with `public_member_api_docs`), `dart_test.yaml`, `.pubignore`, and a copy
of the LICENSE, since pub reads the licence from the package's own folder.
Files moved with `git mv`, so history follows them. There are two lock
files, not a pub workspace: the framework resolves on its own, as a pub
user's project resolves it, and the app pins what it ships; a workspace
would merge both into one resolution and one lock. Root `dart analyze` and
`dart format` cover both packages, each with its own analysis options;
`dart test` runs per package. The release bump writes the app's pubspec,
lock and `lib/version.dart` and the framework's pubspec, and the release's
NOTICES take the retained notices from both READMEs' Credits, each link
read from its README's folder. Designs and decisions written before keep
the old paths as history.

## CTUI-146: Ubuntu CI, Linux release targets, Darwin built locally

Chosen by the owner through main (Q380): CI runs on `ubuntu-latest` only.
Its release-target checks build linux-x64 natively and cross-compile
linux-arm64; the cross-compiled binary is checked for its kind, not run.
`.github/workflows/ci.yml` replaces `chord.yml`. Darwin builds stay with
the maintainer's local release. The required aggregate `check` (Q379)
passes only when static checks, both sharded suites, both compile tags,
the npm shim test and the Linux release-target checks pass.

## CTUI-147: the Dart fake serves ACP with its own dispatcher

The fake uses `json_rpc_2`'s `Client` for requests of its own and a small
serving dispatcher, as settled for CTUI-56. Incoming requests keep their
ids, and errors use the original ACP SDK's shapes and words. The fake
lives under `test/fixtures/fake_agent/`; ordinary tests and `--fake` need
neither Bun nor the original checkout. Optional parity and original-oracle
tests keep those prerequisites and skip with a reason when unavailable.

## CTUI-147: the fake's team-file reader is the app's

The fake imports no app code except `scenarios/teams.dart`, which imports
`package:chord/teams.dart` to read `--propose-team` files. This follows the
original fake's import of `src/teams`, so proposed teams use the same
parser as the app. The cached kernel snapshot's key includes the app and
framework sources reached by this import, the fake's sources, the lock
file and the SDK, so a parser change rebuilds it.

## CTUI-147: accepted differences in malformed bursts and transport errors

Replies to a burst containing malformed lines may be ordered differently:
the TypeScript SDK's line reader writes parse and invalid-request errors
ahead of queued answers. This stream artefact is not imitated or compared
by parity, which sends one request at a time. Transport failures outside
JSON-RPC keep Dart's wording rather than Node's `fetch failed`.

## CTUI-161: `-p` declares `session.notices`

Closes the remark in "CTUI-32: the window declares `session.notices`, and
nothing else yet" that `-p` did not declare notices. `-p` now declares
`session: {compaction, notices}`, as the original's does, and writes every
agent notice to stderr as `chord: <title>: <description>`, in text and json
alike, so a notice can never reach the reply on stdout.

## CTUI-160: the account reaches `/status` and the sign-in block

Supersedes the account omission in "CTUI-23: only commands with an
available feature are offered" and "CTUI-59: the failed-start screen has
no account line". `/status` shows the original's Account rows after
`Agent:`. The sign-in block opens with the account line, both at start
(the start waits up to 1000 ms for a pending `auth_status`, as the
original's does) and mid-session, when a prompt refused with -32000 puts
the sign-in on the turn's error. A failed turn's sign-in is recorded as
the original's record writes it, `{message, ways}` without the account,
and replay redraws it without the account line.

## CTUI-159: the session variable is held while the terminal is away

The original's `useSessionVar` writes when a record write settles, with no
check that the window is still there. The port drops a settled write once
the window is closing or disposed, as the task asks for nothing written on
exit, signal or crash. While the terminal is lent to the editor, the
latest main session is kept as wanted. On return it is sent if it differs
from what the terminal was last told, so an earlier id is never sent
after a `/clear` or `/resume` made while the editor had the terminal.

## CTUI-162: setting commands typed while starting follow the original

The task asked for `/effort` with no argument, typed while the agent
starts, to open its picker once ready. The original does not do that, and
the task did not list it as a difference, so the port follows the
original. `/model` and `/config` keep their request and open once ready.
`/effort` notes at once that the agent offers no effort. `/effort <id>`
and `/fast` do nothing while starting. Closing drops every kept request;
a failed start keeps them, but no picker ever shows.

Two of the original's slips are fixed. With no model name known yet, the
note reads `<agent> offers no effort.` instead of ending in `for .`. When
both `/model` and `/config` are typed while starting, the original draws
both pickers stacked under the same keys. The port shows one, the one
asked for last.

## CTUI-163: the Note takes no ctrl+a/e

super+left/right move to the start or end of the displayed row in the
prompt and in the question Note editor. ctrl+a/e keep the logical line in
the prompt only, as the original's prompt does. The original's Note is
not given ctrl+a/e, so the port's is not either (docs/design/CTUI-163.md,
amendment). The Note's 80x24 drawing of wrapped rows, which predates this
run, is CTUI-174.

## CTUI-154, CTUI-157, CTUI-158: loaded runs, and the cancel order

A loaded test run counts only if the host stayed awake. The first baseline
of the root suite under load failed 25 cases, 23 of which ended in five
simultaneous waves, each lasting 8 to 15 minutes against 30 s timeouts:
the machine had slept. Loaded runs now go under `caffeinate -dimsu`, and
a run whose cases last far past their timeouts is void, not failed. Run
awake, the same suite at the same load failed only the cases fixed here.

A test's compile is not its runtime. A case that compiled a snapshot
inside its 30 s budget starved under a parallel build; the snapshot is now
built once in setup, under its own compile allowance, and the case keeps
its runtime budget. A real-command case that needs its shell to exit
before a short timeout retries, at most four times and with each try's
timings in its failure, when load kept that case from being set up at
all; it never loosens what it asserts.

On cancel, the connection sends `session/cancel` before it answers the
agent's pending forms and permissions as cancelled. The original's
`acp/connection.ts` answers them first. Under load, the agent read the
answer before the cancel and ended the turn as answered, not cancelled;
a real agent can do the same. ACP orders the cancel first (main's ruling;
the owner may reverse it). Plans keep the original's order: the ruling
names forms and permissions, and plans already end cancelled. The fake
agent keeps forms.ts's behaviour, and parity holds.

## CTUI-164: the prompt keeps the original's reach of OpenTUI's keys

This supersedes the first answer to Q386 ("all inherited editing keys,
selection included, listed in the shortcuts panel"). That answer rested on
the audit's premise that the original's prompt reaches OpenTUI's default
textarea keys. It does not: `src/ui/prompt/prompt.ts` lets only its own
allowlist reach the textarea, and every other key is the window's
(captures in `docs/design/evidence/CTUI-164/`). The owner's second answer
is option A, follow the original:

- The framework's `TextArea` binds OpenTUI's whole default set and has an
  in-editor selection, as a generic editor; an app leaves the keys it does
  not want through `TextArea.editingKeys`.
- The prompt adds the keys the original's prompt does reach and the port
  lacked: super+a selects all, super+z undoes, super+shift+z redoes. It
  loses shift+backspace, which deletes nothing in the original's prompt.
- The question Note and the plan box Note keep the original's reach.
- The shortcuts panel keeps the original's list and adds only the three
  new keys, after "cmd + ← →"; the readline keys stay unlisted, as there.

Settled by the lead, following the original: the editor's selection has no
copy key (in the original, super+a then ctrl+c clears the draft); ctrl+u and
ctrl+k ignore the selection as OpenTUI's do, so it goes with the text a
deletion takes and stays when nothing is deleted. The original's line-edge
moves are taken as the port's slips and fixed in the framework: ctrl+a at a
line's start goes to the previous line's end, ctrl+e at a line's end to the
next line's start, and ctrl+u at a line's start joins the lines.

## CTUI-176: the record scan finds lines and needles with byte_search

The full record scan (`readRecords`) now reads bytes and decodes only the
lines a summary reads. Testing each line's type and its `"run_team"` or
`"session_info_update"` needle needs a byte substring search, which the SDK
does not have. Measured AOT with `benchmark/record_scan.dart` on the same
generated set (2003 records, 3.88 GB), median of three:

- the port before: 26.1 s;
- the original's `readRecords` under bun: 6858 ms;
- bytes with the `byte_search` package: 4192 ms;
- SDK only (a byte loop for line ends, prefixes compared byte by byte,
  matched `served` and `update` lines decoded for `String.contains`):
  25116 ms. Update lines are most of a record's bytes, so decoding them to
  search loses nearly all the gain. A search of our own was ruled out.

`byte_search` 0.1.0 is taken (main's ruling) though it has a single release
and little use: its licence is BSD and it has no dependencies. It is pinned
exactly in the root `pubspec.yaml`, never in `packages/chord_tui`, and only
`lib/session/sessions.dart` imports it (`BytePattern`, `ByteSet`,
`startsWithBytes`, `indexOfAnyByte`), so swapping it touches one file.

## CTUI-176: chord prints its own record id to resume with

A departure from the original, decided by the owner. The original prints
the agent's session id in the quit line ("Resume this session with: chord
<agent> --resume <id>") and in the refusal to open a session from another
directory. The port prints chord's own record id there: the record file's
name without `.jsonl`. The agent's session id stays in what scripts read:
headless `--output-format json`'s `session_id`, the terminal's session user
variable, and ACP.

`chord --resume <id>` first looks for `records/<id>.jsonl`. When it is a
readable record with a session header, that record's session is resumed,
with or without a prompt in it (the lead's ruling: a quit line can follow
a resumed session with no new prompt), refused for another agent as
`sessionById` refuses. Otherwise (no such file, an unreadable one, no
session header, or an id
that is not a plain file name: empty, holding a separator or `..`) the id
is looked up as an agent's session id from the records' first lines, so
the original's ids, the agents' and `w-…` ids keep working. ACP's
`session/load` and `session/resume` take only the agent's session id.
`--continue` is unchanged.

## CTUI-150: `--chord-group-exec` is a contract between versions

A running chord starts every agent through `Platform.resolvedExecutable
--chord-group-exec` (`lib/platform/process.dart`, `defaultLauncher`). After
an upgrade by npm or Homebrew that path names the new binary, so a window of
the old version launches its agents through the new version's launcher. The
call is therefore an interface between versions, and it is kept fixed
rather than reached through the running inode:

- `bin/chord.dart` dispatches the flag before anything else of chord runs,
  when it is the first argument.
- The argv is `<executable> --chord-group-exec <nonce> <absolute program
  path> -- <argv0> <args…>` (a JIT run puts `--packages=<config>
  <group_exec.dart>` before the flag). The nonce is lower-case hex; the
  launcher accepts `^[0-9a-f]+$`, a path starting with `/`, `--` at index 3
  and at least `argv0`.
- The launcher restores SIGPIPE, calls `setsid`, writes
  `chord-exec <nonce> ok\n` on fd 2 and `execv`s the program. A failure is
  `chord-exec <nonce> fail setsid <errno>\n` (exit 126) or, after `ok`,
  `chord-exec <nonce> fail exec <errno>\n` (127 for ENOENT, else 126). A
  malformed call prints `chord: malformed --chord-group-exec call\n` and
  exits 126. The parent reads exactly these frames off the front of stderr
  and passes the rest through.

`test/platform/group_exec_contract_test.dart` pins all of it. Changing any
part needs a new flag beside the old one, kept for as long as an older
window may still be running.

## CTUI-155: chord_tui's SDK floor is Dart 3.11.0

`packages/chord_tui/pubspec.yaml` declared `sdk: ^3.9.0`, but no Dart 3.9
could resolve it: `test` 1.33.0 and `test_api` 0.7.15 need `^3.11.0`,
`matcher` 0.12.20 needs `^3.10.0`, `dartdiff` 1.0.0 needs `^3.9.2`. pana
checks only the latest SDK, so the gap went unseen. The owner chose to raise
the floor to `^3.11.0` rather than lower those dependencies.

Checked with a Dart 3.11.0 SDK downloaded beside the system one, a separate
pub cache and a copy of the package: `dart pub get` resolves, `dart analyze`
is clean, `dart test` passes (tagged tests skipped), and an app depending on
`chord_tui` by path resolves and analyzes clean. The root `pubspec.yaml`
(`^3.12.0`) and both lock files are unchanged. A lower floor needs the same
check on that SDK before it is declared.

## CTUI-103: SIGUSR2 writes Dart's heap snapshot only under JIT

A departure from the original, decided by the owner. The original's
`kill -USR2 <pid>` writes a V8 `.heapsnapshot` through
`Bun.generateHeapSnapshot`, for Chrome's DevTools and memlab, and a `.json`
of the process's memory and `bun:jsc`'s per-type counts. Dart has neither:
`NativeRuntime.writeHeapSnapshotToFile` writes Dart's own format (opened by
Dart DevTools' memory view), and only in a non-product VM. A
`dart compile exe` binary, which is how chord ships, throws "Heap snapshots
are only supported in non-product mode", and no non-product AOT build
exists. An AOT binary has no VM service, so no per-type counts either.

`lib/platform/heap.dart` keeps the original's shape: SIGUSR2 is always
handled, so it never kills chord; each signal writes into `heaps/` in
chord's state directory, named by the pid and the time, through `.part`
files renamed into place, nothing on the terminal; a signal during a write
is dropped. The snapshot comes first, as in the original, but the `.json`
(pid, time, current and peak RSS, the AOT build id) is written whether or
not the snapshot could be. A failure, including the shipped binary's
unsupported snapshot, overwrites `heap-error.txt` there, as the original
does. Under `dart run` or `tool/dev.dart` the Dart-format snapshot is
written too.

## CTUI-190: the swap lands as four commits on TS main, history not imported

Options: import this repository's history into `../chord` (a merge of
unrelated histories), replace `../chord`'s main outright, or add the port
on top of TS main as new commits. Chosen, as the owner set it: TS main is
tagged `ts-final` (signed, on `577b58167`, v0.71.0) and a branch `dart`
adds four signed commits: the TS root reduced for cursor-cloud-acp, the
port's tracked tree by `git archive` of a pinned commit, one CI workflow,
the docs. `git archive` was chosen over a filesystem copy because it takes
tracked, committed files only: build output, `.dart_tool`, worktrees,
local settings and uncommitted edits cannot leak, and the commit names its
source. Consequences: the TS history and every blob stay in the clone;
this repository's history stays here; main lands by a local fast forward,
since GitHub's rebase and squash would rewrite the signed commits (Q399).
Design: `docs/design/CTUI-190.md`.

## CTUI-190: cursor-cloud-acp keeps a reduced TS root, the release engine whole

Options: move the package's tooling under its own folder; reduce the root
and also prune the release engine to the package (L2); reduce the root and
keep the release engine as it is (L1). Chosen: L1. The package's files
import `../../eslint.config.ts` and `scripts/dev/release/*` by relative
path and rely on the hoisted root `node_modules`, so moving would edit the
package; `stages.ts` imports chord's stage modules, so pruning is a larger
change better made alone. Three breaks the reduction must fix, proven in a
scratch export: the workspace list names `packages/cursor-cloud-acp` alone
(the `bun dev` finder reads every `packages/*` folder's `package.json` and
dies on `packages/chord_tui`); `bunfig.toml`'s test preload into `tests/`
goes; the finder's root `'.'` entry is removed, so the root is never a
package. `src/channel.ts` survives as `scripts/dev/release/channel.ts`. The
release engine's tests stay and run as `bun test ./tests/scripts ./lint`
in the package's CI job (612 pass in the trial); dropping them would leave
the changed finder and the release the package depends on untested.
Packages: none new; the root keeps 7 of its dependencies and 14 dev
dependencies. Follow-up: L2 and the dead ESLint blocks.

## CTUI-190: the oracle after the swap is a ts-final checkout at ../chord-ts

Once the Dart tree is the chord repository, the parity lookup's default
sibling `../chord` is the repository itself and parity would skip with
wrong advice. Options: `CHORD_SOURCE` only; a default sibling
`../chord-ts`; a CI job that fetches the tag. Chosen: `CHORD_SOURCE`
(refused when it is this repository), else `../chord-ts`, a detached
worktree of `ts-final`; CI skips with that reason unless the owner asks
for a parity job (Q397). The change ships in this repository before the
swap, so the swap copies tested code; the swap's verification runs the
twelve parity files against `ts-final` with no skip allowed. Consequence:
`../chord-ts` replaces `../chord` as the one outside path documents may
name.

## CTUI-190: the shared version starts at 0.71.0 in the swap

The release's preflight refuses a new version while the held one is not
on npm, and the port holds 0.0.1. Options: teach the release a first-run
exception, or set the held version to the published 0.71.0 in the swap.
Chosen (pending Q396): 0.71.0 in both pubspecs, `lib/version.dart` and
`pubspec.lock`, so `--bump 0.72.0` runs as any release. `chord_tui`
follows, since the two share a version. Tests that compare live output
with a literal version read `version` instead, made in the pre-swap task.

## CTUI-191: screenshot frames read with ansi_escape_codes and ansi_up's palette

`tool/screenshots.dart` draws a captured tmux frame as HTML the way the
original's ansi_up does. Tried: `ansi_up` 2.1.0, DevTools' Dart port of
the same library, which worked but is discontinued on pub.dev;
`ansiparser` 1.0.3, which throws on SGR 38/48 and 39/49 and writes CSS
classes, so it cannot draw chord's truecolor frames; `ansi_escape_codes`
4.0.1, whose parser gave byte-identical HTML on all twelve shots' frames,
but carries palette colours (`38;5;n`, as the prompt's 244 border) as an
index with no RGB. Chosen by the owner: `ansi_escape_codes` as a dev
dependency, with a palette function in the tool that gives ansi_up's
values (its sixteen named colours, the 6×6×6 cube, 24 greys), pinned by a
test. Its pictures are taken by `puppeteer` 3.28.0 with the system Chrome.

## CTUI-191: the pre-swap gate, the lead's choices

The owner's answers to Q387-Q400 change the CTUI-190 entries above where
they differ: `ts-final` is history only, and the parity and oracle tests
are removed rather than pointed at `../chord-ts` (Q397), so nothing in
`lib/`, `test/`, `tool/` or `benchmark/` needs the TypeScript chord or
Bun to run. What still matches `CHORD_SOURCE`, `../chord` or `bun ` is
history notes, fixture and fake-scenario text, strings only shown or
asserted, and the upgrade path for Bun-installed copies, a real feature.

- The pinned-data generators run with Node, not Bun:
  `tool/genai_prices.dart` takes a required `--package <dir>` (an
  installed `@pydantic/genai-prices` 0.2.3) and has no `../chord`
  default; `tool/currency_symbols.dart` checks its ICU pin against
  Node's and refuses on another one, leaving the pinned table as it is.
- `tool/screenshots.dart` starts `bin/chord.dart` as `chord claude`
  with the fake as `--agent-command`, under the dev runner's
  fake-runtimes define, so every start (children, teams, forks) is the
  fake, and the images name claude and codex as the original's do. It
  refuses a shot without that define, and runs on its own HOME and XDG
  folders.
- The main prompt's plain border is palette colour 244, as the
  original's and CTUI-22's design: the difference CTUI-31 left
  recorded is fixed here, so the README images do not ship it.
- `test/ui/app/wheel_window_test.dart` and
  `test/ui/app/error_window_test.dart` keep `v0.0.1`: it comes from
  fixture launches, not the live version. The framework's CHANGELOG
  heads its one entry `0.71.0`, so the publish dry run stays clean.
- `chord acp` refuses an unknown option with or without
  `--agent-command`; `ts-final`'s guide said it then became the agent's
  name. The guide says what chord does. Its other corrections were
  slips of the original guide against the original's own code: Ctrl+D
  quits only on an empty prompt; a deleted image placeholder's image is
  not sent; `selection:copy` is listed; the README promises saved
  teams, not a team file format.
- CI already ran on pushes to main and on pull requests (Q398); it is
  unchanged.

## CTUI-190: chord and cursor-cloud-acp share the repository

chord and chord_tui are Dart; `packages/cursor-cloud-acp/` stays TypeScript,
with Bun tooling for the adapter only. The TypeScript chord is preserved
at `ts-final` as reference history, not a specification for new behaviour.
Before the swap, `../chord` and "the original" in this log and the designs
mean that TypeScript app. Its own decisions log stays at `ts-final`.

## CTUI-192: a pipe the agent closes while chord writes, on Linux

When an agent closes its stdin while a write to it is blocked on a full
pipe, dart:io on macOS fails that flush with a broken pipe; on Linux it
takes the hangup as a silent close: that flush and every later write
complete with no error, the bytes dropped, and the sink's `done` never
completes. chord does not rely on the write error either way: the
agent's exit is what tells of it. `test/acp/process_test.dart` drives
that full-pipe shape deterministically (the agent closes on a signal
chord sends once its 4 MiB flush is held unread) and asserts each host's real
behaviour, a write error on macOS and none on Linux, with the exit
observed and a clean stop on both (main's decision; not a loosening).

## CTUI-192: on Linux the by-hand note names Ctrl-C alone

On a Linux terminal, dart:io never ends stdin at Ctrl-D: with the
terminal in canonical mode, typed lines arrive, but `stdin`'s `onDone`
never fires after ^D (a bare AOT probe on a pty shows it; macOS ends
the stream). So `chord acp` run by hand cannot be left with Ctrl-D on
Linux. The owner chose to leave the stdin code as it is and say so: on
Linux the by-hand note reads "Ctrl-C leaves", on macOS it keeps "Ctrl-D
or Ctrl-C leaves". The compiled note case sends Ctrl-C on Linux and
checks chord ends by SIGINT, and keeps the Ctrl-D path on macOS.

## CTUI-192: a hung-up tty's error is its end, not the app's failure

On Linux, when a terminal hangs up, dart:io reports the tty's stdin
with an error event ("Error event raised in event handler"), then ends
it; macOS ends it plainly. StdioTerminal forwarded that error, runApp
recorded it as a failure, and a hung-up app with no signal owner exited
1 instead of 0. The terminal's own tty input failing now counts as that
input's end: it marks the terminal hung up and forwards nothing.
Supplied and non-tty inputs still report their errors.

## CTUI-192: dart:io stdin can stall an app after an inheritStdio child

After `StdioTerminal.runEditor` lends the terminal to an editor child
(`ProcessStartMode.inheritStdio`) and takes it back, the app's isolate
can stall inside dart:io's terminal-stdin read until the next byte
arrives: the window does not redraw, and timers and microtasks do not
run. One key releases it (four of four stalls on native linux/arm64
under load, a right-arrow each time). This is the user-facing effect:
after the external editor returns, the window may freeze until the next
key. It stays; the owner chose to record it, not work around it.

Seen in chord_tui's `terminal_services_example_pty_test`: native
linux/arm64, Dart 3.13.5, 8 CPU burners at nice 19: 8 of 10 runs failed,
the frame after the editor drawn only when the test's expect closed the
pty 15 s later. gdb at the stall: the main thread waits in
`Dart_RunLoop`; a worker running the isolate is in `read(fd=0, buf, 1)`
on the blocking tty, called from Dart code through dart:io's stdin
native read path. dart:io reads a terminal stdin as
`_Socket._readPipe(0)`; the likely cause is a readiness report for
bytes the child already consumed. That case is skipped on Linux, in
its body, with this reason; macOS still runs it.

A minimal program, fit to file upstream (filing is the owner's), run
on a pty (expect spawns it, waits for `CHILD READY`, sends a line):

```dart
import 'dart:async';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.contains('--child')) {
    stdout.writeln('CHILD READY');
    stdin.readLineSync();
    return;
  }
  final sub = stdin.listen((_) {});
  sub.pause();
  final child = await Process.start(
    Platform.resolvedExecutable,
    [Platform.script.toFilePath(), '--child'],
    mode: ProcessStartMode.inheritStdio,
  );
  await child.exitCode;
  sub.resume();
  final watch = Stopwatch()..start();
  Timer(Duration.zero, () {
    stdout.writeln('FIRED ${watch.elapsedMilliseconds} ms');
    exit(0);
  });
}
```

Dart 3.13.5: the timer never fired within 20 s on native linux/arm64,
linux/amd64 (emulated) and macOS arm64; it is timing-sensitive on
linux/arm64, where one run of several fired. Without `sub.resume()` it
fired at 0-3 ms. Tried and not taken: drawing the post-resume frame by
microtask (7 of 10 still failed: the isolate itself is stuck), and fd 0
non-blocking while the app owns it and blocking while the child has it
(released the program on macOS, 1 ms; on linux/arm64 5 of 5 still
stalled, gdb then in the same native read path, signal mask step).
chord_tui's own fd-0 reader, in place of dart:io's stdin, is CTUI-193.

## CTUI-192: no decision rests on errno read by a second FFI call

chord reads errno through `__errno_location`/`__error`, a second FFI call
after the syscall, and the VM may make syscalls of its own in between, so
the errno seen need not be the call's. Two decisions rested on it and
failed under the whole native linux/arm64 suite's load: `signalGroup`
fell back to the launcher's pid only on ESRCH, so a launcher before its
`setsid` could miss the stop (a close that never settled, and a launcher
left after a run that went on to exec `sh -c sleep 600`); and the
launcher chose 127 over 126 from ENOENT. Now a failed group kill falls
back to the pid alone whenever the process has not exited, and a failed
`execv` exits 127 when the program, or a script's `#!` interpreter, is
proven not there by the files (a searchable directory without that name,
or a missing directory on the way); the errno it reports is ENOENT or
EACCES where the files show it, and both come from the errno read where
they cannot, as under a directory that may not be searched or through a
link that does not resolve, where a stat fails as if nothing were there
(errno was seen reading 22 for an EACCES under that load). `GroupProcess.alive` still
reads EPERM: on macOS it is a group left only with unreaped processes,
and on Linux a group whose members are all another user's, such as a
root process an agent started through sudo, so EPERM cannot be read as
gone on either; it decides only how long a stop waits.

## CHD-633: runApp merges a read's wheel reports into one

Routing a mouse report needs current geometry, so `AppHost.handleMouse`
builds and lays out first whenever the tree is dirty, and every wheel step
dirties it. A fast wheel or trackpad flick arrives as many reports in one
terminal read, so each paid a full build and layout: 60 reports in one
read took 177 ms in the real window on the fake, about 3 ms each, while
one report spaced from the next cost 0.05 ms. `runApp` now merges each run
of adjacent wheel reports from one read that share a cell, the modifiers
and a direction into one report with the summed `scrollDelta`; the same
60 reports took 0.2 ms and one frame. A report's delta can therefore be
more than one cell, and every wheel consumer scrolls by its size. Reports
that differ, or that a key, paste or button separates, stay apart in
order. Routing wheel reports on the last laid-out geometry without a
rebuild was the other option; it was not taken because it gives up the
host's rule that a report is hit-tested against current geometry.

## CHD-635: the release fetches its own x64 Dart SDK

darwin-x64 is built by an x64 Dart SDK of the host's version under Rosetta
(Q362), and the release used to stop until `CHORD_DART_X64` named one. The
owner decided the release finds that SDK itself and downloads it when it is
missing, with no variable to set; `CHORD_DART_X64` is removed (Q415). The
SDK is kept in the user cache by version, `~/Library/Caches` (or
`$XDG_CACHE_HOME`) under `chord-release/dart-sdk/<version>/macos-x64`, so
every checkout reuses it and old versions stay until deleted by hand (Q412).
The version and channel are the running Dart's (Q413). The zip is checked
against the `.sha256sum` the Dart archive publishes beside it, over HTTPS,
and the unpacked `bin/dart` must still say that version under
`arch -x86_64` (Q414). An SDK is unpacked beside its cache folder and
renamed into place only once it passes, so an interrupted download is never
taken for a cached one. The download goes through a fetcher the tests
replace, so no test reaches the network.
A cached SDK that does not run under `arch -x86_64` is refused with the
error and its path, not downloaded again: a cache entry exists only after
passing both checks, so the host cannot run it (no Rosetta, say) and a new
copy would fail the same way. One that runs but says another version, or
none, is damaged; it is replaced by a fresh download, and the release says
so. A fresh download that fails either check is refused and nothing of it
is kept.

## CHD-638: the site has no size budget

The design held the site's first load (the page, the app's Wasm and
loader, wterm and the font) to 1.5 MB brotli, checked in its build
(question 9). No maintained Dart brotli encoder fits under `dart run`:
package:brotli decodes only, and es_compression's brotli needs a native
library through FFI. Asked about that, the owner dropped the budget: the
site has no size budget, and `site/tool/build.dart` and CI measure,
print and check no sizes.

## CHD-638: chord_tui draws giant text from its own block-glyph table

The site's hero and its 404 page draw text far larger than a cell, and the
rule is a maintained package before our own code for what is not about the
terminal. Two were tried. `oled_font_57` is a 5x7 bitmap font as a const
Dart list, MIT and free of dependencies, which fits the shape; but it is a
single 2021 release with no maintenance since, and it would become a
dependency of the published chord_tui. `enough_ascii_art` is maintained
and wasm-ready, with a FIGlet renderer; but FIGlet gives each font's fixed
character art, not a bitmap the framework can scale to its sizes, its fonts
sit outside its `lib/` and would have to be embedded by hand, and it pulls
`package:image` into the framework. Asked, the owner chose our own table
(Q434): chord_tui keeps its own 5x7 block-glyph table, and its
`DisplayText` (unit F10) draws every piece of giant text with it, `CHORD.`
included. The site no longer draws chord's wordmark.

## CHD-638: the site's accent is chord's green

Direction C drew its one loud colour in a signal orange, `#ff5a1f`. The
owner changed it before the merge: the site's accent, links, focus, band,
numerals, full stops, FIG. captions and buttons use chord's own dark
accent, `#47e7a5` from `lib/ui/theme/theme.dart`, so the site reads as
chord's. Ink, cream and the rest of direction C stay. A site test holds
`SiteColors.accent` to chord's dark palette.

## CHD-638: the site's cell is 7 px within 1/64

The site promises a 7 px cell (Q436), and Chrome on macOS measures exactly
that. Chrome on Linux rounds JetBrains Mono's 7.5 px advance at 12.5 px up
to 7.515625, so with -0.5 px spacing wterm measures 7.015625 and an 820 px
window gets 116 columns, not 117. The owner accepted the Linux cell (Q438,
option 1) over snapping the spacing per machine or a wterm issue: the
browser test checks the cell wterm measures is 7 px within 1/64 and
expects the columns that cell gives. Linux shows no box-line or glyph
seams at DPR 1 and 2.
