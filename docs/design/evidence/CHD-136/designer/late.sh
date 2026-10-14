#!/bin/bash
# late.sh <tree> <label> <cols> <rows> <variant>
TREE=$1; LABEL=$2; X=$3; Y=$4; V=$5
OUT=/tmp/chd-design/out/late-$V-${X}x$Y; mkdir -p $OUT
W=$(mktemp -d /tmp/chord-qa.XXXX)
S=chd-des-$LABEL-$RANDOM
tmux new-session -d -s $S -x $X -y $Y -c $TREE "CHORD_FAKE_STEP_MS=300 deno task chord:fake -C $W"
sleep 6
cap() { sleep ${2:-1}; tmux capture-pane -t $S -p -e | sed -E "s#$W#/W#g" > $OUT/$LABEL-$1.ansi; }
say() { tmux send-keys -t $S -l "$1"; sleep 0.3; tmux send-keys -t $S Enter; }
say late; sleep 0.2; say text
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do cap $i 0.25; done
if [ "$V" = esc ]; then :; fi
cap 99 4
tmux kill-session -t $S
