#!/bin/bash
# usage: run.sh <tree> <label> <cols> <rows> <scenario>
TREE=$1; LABEL=$2; X=$3; Y=$4; SC=$5
OUT=/tmp/chord-cmp/$SC-${X}x$Y; mkdir -p $OUT
W=/tmp/chord-qa.cmp; mkdir -p $W
S=chd-cmp-$LABEL-$RANDOM
tmux new-session -d -s $S -x $X -y $Y -c $TREE "deno task chord:fake -C $W"
sleep 5
cap() { sleep ${2:-1}; tmux capture-pane -t $S -p > $OUT/$LABEL-$1.txt; }
say() { tmux send-keys -t $S -l "$1"; sleep 0.3; tmux send-keys -t $S Enter; }
case $SC in
  start) cap 0 0 ;;
  text|tools|edit|markdown|thought|calls) say $SC; cap 1 3 ;;
  status) say status; cap 1 3; say /cost; cap 2 1.5; say /status; cap 3 1.5 ;;
  permission) say permission; cap 1 2; tmux send-keys -t $S Enter; cap 2 2 ;;
  plan) say plan; cap 1 3; cap 2 6 ;;
  form) say form; cap 1 2; tmux send-keys -t $S Escape; cap 2 2 ;;
  link) say link; cap 1 2; tmux send-keys -t $S Escape; cap 2 2 ;;
  mode) tmux send-keys -t $S BTab; cap 1 1.5; say mode; cap 2 2; tmux send-keys -t $S BTab; cap 3 1.5 ;;
  long) say long; cap 1 4; cap 2 22 ;;
  slow) say slow; cap 1 2; say text; cap 2 1; tmux send-keys -t $S Escape; cap 3 2 ;;
  interrupt) say slow; cap 1 2; tmux send-keys -t $S Escape; cap 2 2; say text; cap 3 3 ;;
esac
tmux kill-session -t $S
