# CTUI-113 evidence: /status names the title

Commit e6ac1d6b. The original and the port side by side in tmux at 120x40
and 80x24, each on the fake with an isolated, empty XDG_STATE_HOME:

    (cd ../chord && bun dev chord --fake --qa status113)
    dart run example/chord/tool/dev.dart chord --fake --qa status113

Typed `/status`, then `/rename the parser`, then `/status` again
(`*-1-status.txt` after the first, `*-2-renamed.txt` after the last).

Both draw `Title:     not given` after `Agent:`, then `Title:     the parser`
after the rename, with the same rename note and wrapping. The qa directory
is relabelled `<project>` (the box rows holding it no longer line up);
the version in the header and the session ids differ by nature.
