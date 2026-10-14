#!/bin/zsh
# capture.sh <repo> <label> <cols> <rows> <outdir>, with $XDG a config home
# whose chord/keybindings.json binds ctrl+k to chat:submit in Chat, and
# $XDG_VIM one whose chord/settings.json sets editorMode to vim.
REPO=$1; L=$2; X=$3; Y=$4; OUT=$5
mkdir -p $OUT
start() { S=chd306-$RANDOM; W=$(mktemp -d /tmp/chord-qa.XXXX); tmux new-session -d -s $S -x $X -y $Y -c $REPO "XDG_CONFIG_HOME=$1 bun run chord:fake -C $W"; sleep 4; }
cap() { f=$OUT/$L-$1-${X}x${Y}; tmux capture-pane -t $S -p > $f.txt; tmux capture-pane -t $S -p -e > $f.ansi; echo "cursor $(tmux display -p -t $S '#{cursor_x},#{cursor_y} visible=#{cursor_flag}')" >> $f.txt; }
stop() { tmux kill-session -t $S; }
k() { tmux send-keys -t $S "$@"; sleep 0.5; }
t() { tmux send-keys -t $S -l "$1"; sleep 0.6; }

# ctrl+r with a match
start $XDG
t 'say hello world'; k Enter; sleep 3
k C-r; t 'wor'; sleep 0.5; cap search
stop

# vim normal mode
start $XDGvim
t 'keep this line'; k Escape; sleep 0.5; cap normal
k b; k b; cap normal-bb
stop

# a textarea key rebound by the keybindings file: ctrl+k sends, where it cut to the line's end
start $XDG
t 'one two'; k Left; k Left; k Left; cap rebound-before; k C-k; sleep 2; cap rebound
stop

# gutter marks
start $XDG
printf 'row %s\n' {1..13} | sed '$ s/$//' > /tmp/chd306/rows.txt; printf 'row 14' >> /tmp/chd306/rows.txt
tmux load-buffer -b chd306 /tmp/chd306/rows.txt; tmux paste-buffer -p -b chd306 -t $S; sleep 1; cap gutter-end
for i in {1..14}; do tmux send-keys -t $S Up; sleep 0.1; done; sleep 0.8; cap gutter-start
stop

# undo and redo
start $XDG
t 'one'; t ' two'; sleep 1; cap undo-typed
k C-z; sleep 0.5; cap undo-1
k C-z; sleep 0.5; cap undo-2
k C-y; sleep 0.5; cap redo-1
stop
