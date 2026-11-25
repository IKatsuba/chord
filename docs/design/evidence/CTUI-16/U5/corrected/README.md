# U5 corrected visual pass

Developer commit `ef2d78f`, building on `9ce1556` and framework `ae35835`.
Ran the handed-over transcript_tools.dart fixture with --wrap and --narrow
in owned tmux at 120x40 and 80x24. Same color environment as the initial
look. Home/End exposed both ends, ctrl+o toggled details, ctrl+q exited.
Captured only after the first rendered frame; startup-only blank captures
were replaced. Each owned session exited and was removed.

Pass: normal long tool headlines and long Updated/path/count headlines
wrap whole, keeping continuation columns. Diff content stays full and
keeps its source gutters/tints. The 22-cell tool region shows Folded as
`… +2 l...xpand)` and Guardian as `Guardia...viewing…`, preserving both
ends with the general middle mode. Those rows stay one line; terminal and
diff source text keep their existing wrapping. Expansion still reveals
all Read/terminal rows and removes fold hints. Initial original
calls/shell/edit comparisons remain applicable; there is no new U5
visual finding. U4's separate completed-plan marker style issue does not
affect this pass. Live integration remains U7.
