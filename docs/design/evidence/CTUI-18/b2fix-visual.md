# B2 corrected choices: visual recheck

Handed fix: `e889f76`, using B0b `6c23d36`.

Ran `dart run example/chord/tool/permission.dart long` at 80x24 and
120x40, then 40x24. Ran the original fake bigask in an owned tmux session
at 40x24 to force its existing option labels to wrap. The initial B2
captures already cover that original scenario at both standard sizes.

Pass for the corrected choice presentation. At 80 columns all three
synthetic long labels wrap beneath the number, not the text after it.
At 120 columns they fit on one line. Up from the first selects the last;
down returns to the first. k and j repeat those endpoint transitions.
At 40 columns, each synthetic option takes three rows and remains fully
visible; the request yields rows first. PageDown changes only the request
above the question/choices. The original's narrower bigask options show
the same continuation alignment and first-to-last wrap on Up.

This supplements and supersedes the initial b2-visual.md acceptance for
endpoint navigation and multiline number placement. Reviewer separately
cleared all three code findings, including CUT middle overflow. These
fixtures do not expose a long CUT title; no additional live claim about
that case is made here. Port synthetic and original fake label strings
still differ, as explicitly noted in the initial B2 report.

No remaining visual finding on corrected B2. No suite was run by designer.
Fixtures exited by their quit keys and the original by its two-press quit;
no owned session or fake process remained.
