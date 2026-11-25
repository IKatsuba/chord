# CTUI-9 U5 text-area visual pass

Handed implementation: signed `1774547`. Designer ran the named
`dart run example/text_area.dart` in owned tmux at 120x40, then resized the
same live draft to 80x24. The two literal lines are 152 and 148 characters.
Shift+Enter was injected as CSI 13;2u between them, independently of the
literal text. The fixture kept a two-line draft without submitting it.

At both sizes injected CSI 1;9D moved to logical line 2 column 1, and
CSI 1;9C returned to column 149. The line spans multiple visual rows,
so this demonstrates logical rather than painted-row boundaries. Captures
u5-before-*, u5-super-left-* and u5-super-right-* retain plain and ANSI
screens. The source text is unchanged by either move. At 80 columns the
TextArea viewport keeps the second line and caret in view, with its existing
max-height scrolling and an end caret on a blank continuation row when the
text exactly fills two rows. No raw sequence text was inserted.

The framed input, line/column report and viewport counts remain readable.
Existing text_area.dart KeyHelp is one clipped line: the repeated newline
bindings fill it before the Super bindings. Their on-screen labels are
therefore NOT proved here. The lead accepted this intermediate limitation;
U6 must show service actions and Super bindings visibly at both sizes from
the real active KeyHelp snapshot, without a manually duplicated catalog.
This visual pass does not waive that final requirement.

Result: pass for U5's handed movement behavior, with the help limit above.
This framework widget look has no port screen to compare. Parser and
negotiation correctness, fallback, timing/races, modifier fields and help
snapshots remain reviewer/tester work. Injected raw bytes do not establish
physical Command-key delivery or host kitty negotiation acceptance.
Ctrl+Q quit; the owned session was checked absent or killed. No real agent,
model, editor, heavy command or automated suite was run by designer.
