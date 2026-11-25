# U2b: Picker highlighted-value notification

Handed unit: signed `93fbb5a25efed0f22db40b3f6f822207c061d7f5`.
Design: CTUI-22 U2b, including timing clarification `2c48f6b`.
This is a framework fixture, so no original port screen comparison applies.

Ran `dart run example/picker_preview.dart` in owned tmux sessions at
120x40 and 80x24. Down previews Choice 2 while Accepted remains Nothing yet;
Enter sets Accepted to Choice 2. Slash followed by literal `30` previews
Choice 30, while Accepted stays Choice 2. Esc restores navigation without
accepting. At 80x24, ten further Down reports reveal Choice 12 with correct
upper/lower edge markers and hidden count; preview changes, acceptance does
not. All captured screens remain legible with their footer rows visible.
Text was sent literally, separate from navigation/Enter calls.

Plain and ANSI captures named `u2b-preview-*` retain both required sizes,
including before/after acceptance and filtering; compact overflow has its
own capture. Default theme reached only: the callback adds no styling or
default pixel changes. This visual gate verifies the fixture's interaction,
not the developer's lifecycle/reentrancy test claims.

Public call site reads naturally: onChanged previews the highlighted value,
onSelected accepts it, initialValue remains a seed. No new selection
controller, key syntax or frame hook is exposed. Visual/API pass; hand to
reviewer for implementation review before testing. Both fixtures exited
through Ctrl+Q; owned sessions/processes checked after exit.
