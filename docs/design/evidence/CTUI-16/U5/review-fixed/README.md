# U5 reviewed tool marker fix

Designer visual pass for fix `59c4f95`, over the earlier U5 evidence.
Ran transcript_tools.dart --review in owned tmux at 120x40 and 80x24,
with the same color environment as prior captures. -p captures retain text;
-p -e captures retain ANSI. ctrl+q exited and removed the owned session.

The reviewed terminal and reviewed diff now each draw `⎿ Reviewed: caution`
followed by another `⎿` for the first terminal or diff output. The output
rows and headline remain aligned at both sizes. `original-reviewed-tools.txt`
records the original Tool component rendered read-only through its own
harness with equivalent calls; these reviewed blocks match the port text
at both widths. No original file was edited or live permission exercised.
The reviewer's double-marker finding is resolved visually. Existing long
headline, narrow overflow, terminal and diff captures remain applicable.
No new U5 visual finding remains; source review/tester handover is next.
