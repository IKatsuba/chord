# U14a chord-timeout visual and API look

Developer unit76e496b passes at120x40 and80x24. Exact commit exported under
ignored build/ with root package metadata copied; run `dart run
example/key_help.dart` inside the export. U14 port WIP was excluded.
Framework fixture, so no original port screen comparison applies.

Both sizes retain the heading and complete bindings list. Ctrl+X shows
`Pending: ctrl+x`; a capture after a further3.1-second wait shows it gone.
Ctrl+X then literal a completes and leaves the ordinary list. q exits.
Captures u14a-{idle,pending,expired,completed}-{120x40,80x24} preserve plain
and ANSI panes. This is visible timeout behavior, not an exact millisecond
boundary measurement; developer's fake_async tests cover exact timing and
lifecycle separately. No extra tests, suite or AOT run.

Public API matches the lead's shape: named Duration chordTimeout on
runApp, defaultChordTimeout of three seconds, forwarded consistently to
AppHost/BuildOwner/FocusManager. No new app action or shortcut is needed.
The fixture session closed and its exact-commit export was removed.
