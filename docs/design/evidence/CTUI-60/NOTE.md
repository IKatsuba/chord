# Captures

Each pair is `../chord` (`bun dev chord --fake`, the original) beside the
port (`dart run example/chord/tool/dev.dart chord --fake`) in tmux at the
size in the file name, with the scenario named in the file name typed as the
prompt. `.txt` is `capture-pane -p`; `.ansi`, where present, is
`capture-pane -p -e`. The startup header's working directory is relabelled
`<working directory>`; the version line differs (chord v0.71.0 against the
port's v0.0.1) and is not a finding. `/tmp/screen.txt` in CTUI-71's
captures is text from the fake agent's reply, not a path of this machine.
