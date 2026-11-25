# S1 designer acceptance

Implementation: `284158cb02ee7f210987bc87e0e3e3efaad0a2fd` on CTUI-48.
Developer held the clean shared worktree at this commit for the whole runtime
check. No archive, alternate checkout or S2 implementation was used.

Public surface matches the approved S1 design: MouseEventKind move/cancel,
Listener onPointerMove/onPointerCancel/captureController and
PointerCaptureController capture/release/isCaptured/dispose. The optional
Listener callbacks retain the established Flutter-shaped call site.
This is API/design acceptance, not code review or a substitute for tests.

## Setup and observations

Command: `dart run example/mouse.dart` from the assigned task worktree.
Owned tmux socket label: `ctui48-designer`; sessions `designer-s1-120`
(120x40) and `designer-s1-80` (80x24). Both used the default dark theme.
Initial socket creation was denied by the sandbox, then succeeded with tool
approval; no app failure or visual fix was required. No compile or soak ran.

For each size, capture-pane -p and capture-pane -p -e retained initial,
held, wheel-held and released-draft states as .txt and .ansi.
Reports were sent literally with send-keys -l, in this order:

```text
ESC[<0;1;3M       primary down
ESC[<32;15;5M    held primary motion
ESC[<64;15;5M    wheel up while held
ESC[<0;15;5m     primary release
```

Then send-keys -l sent ` typed` without Enter. The draft changed from
`draft stays here` to `draft stays here typed`; keyboard focus stayed there.
Both screens show reports 2 with move at (14,4), reports 3 with wheel
(0,-1) and first sample row changing 5 to 4, then reports 4 with primary
release at (14,4). The event summary, draft border and wrapped help remain
readable at both sizes. No finding. No original pairing is required for
this framework-only demo; port acceptance remains S5-S7.

No clipboard code was exercised; no clipboard stub or real clipboard was
needed for S1. These byte-injection captures do not prove a physical mouse,
trackpad, native pointer capture outside the terminal, or cursor appearance.
Dark/light/plain selection contrast is future selection acceptance.

Both demos exited normally through C-q. A subsequent list-sessions reported
no owned server, and process inspection showed no surviving mouse demo or
owned tmux process. No fake agent was started. Captures contain no private
filesystem path. Only this S1 evidence directory was written.
