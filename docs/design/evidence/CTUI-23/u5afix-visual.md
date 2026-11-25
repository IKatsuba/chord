# U5a fixture correction: visual/API pass

Exact signed fixture fix159f0b00f292ca57d648a8360c220a6aa392c0c6 on API
unite218fab864fc5ba5138c925ede6bcb8f8b6cb0c0. Isolated archive run; no U5
port WIP used. Retained648f2ec covers initial API/runtime behavior and
prior help-row finding. Result: pass, hand U5a to reviewer then tester.

At120x40 and80x24 all three actual action descriptions now fit the help row:
Tab Complete visible word, Ctrl+R Reset draft, Ctrl+Q Quit. At120x40 Tab
completes status; Ctrl+R restores sta. Resize80x5, Tab retains sta and records
ignored while all three action descriptions remain visible. Ctrl+Q exits.
No new palette/layout issue; API is unchanged. Prior room-return/focus
behavior evidence remains applicable. Capture txt/ansi u5afix-help-tab-120x40,
u5afix-help-80x24 and u5afix-help-hidden-tab-80x5.

Public API call site and runtime gate pass, with no implementation review
or lifecycle/test claim by designer. Framework fixture has no original
port screen comparison. Current run inherited NO_COLOR. Owned fixture
session/process checked clean; exact archive removed after captures.
