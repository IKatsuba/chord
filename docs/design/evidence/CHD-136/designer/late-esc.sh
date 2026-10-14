#!/bin/bash
TREE=$1; LABEL=$2; X=$3; Y=$4
OUT=/tmp/chd-design/out/late-esc-${X}x$Y; mkdir -p $OUT
W=$(mktemp -d /tmp/chord-qa.XXXX)
S=chd-des-$LABEL-$RANDOM
tmux new-session -d -s $S -x $X -y $Y -c $TREE "CHORD_FAKE_STEP_MS=300 deno task chord:fake -C $W"
sleep 6
cap() { sleep ${2:-1}; tmux capture-pane -t $S -p -e | sed -E "s#$W#/W#g" > $OUT/$LABEL-$1.ansi; }
say() { tmux send-keys -t $S -l "$1"; sleep 0.3; tmux send-keys -t $S Enter; }
say late; sleep 0.2; say text
cap 1 1.2; tmux send-keys -t $S Escape; cap 2 0.4; cap 3 3
tmux kill-session -t $S
