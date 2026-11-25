# U14b printable-key filter visual and API look

Developer unit580eab5 passes at120x40 and80x24. Exact commit exported under
ignored build/ with copied root package metadata; run `dart run
example/text_area_key_filter.dart` inside it. Port U14 WIP was excluded.
API call site matches CTUI-21 section5: nullable shouldHandleKey reads
live controller state, and the app's ? binding remains registered.
This is a framework fixture; an original port comparison does not apply.

At both sizes, empty ? toggles the help label and leaves the input empty.
A literal `draft?` sent in one call appears intact without toggling help.
Ctrl+Z removes only the question mark; Ctrl+Y restores it. Ctrl+C followed
immediately by a literal ? clears the draft and toggles the app label,
with no inserted question mark. Ctrl+Q exits. The heading, input and
existing ellipsized KeyHelp row remain readable and do not overlap.
Captures u14b-{empty,empty-help,native-draft,undo,redo,clear-then-help}-*
include plain and ANSI panes at both sizes.

Live input bursts verify the visible outcome, not an exact frame boundary;
developer's tests cover same-frame processing and null typing/paste.
No additional tests, source audit, whole suite, package trial or AOT run.
Owned tmux session was confirmed closed and its temporary export removed.
