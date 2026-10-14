#!/bin/bash
# look.sh <tree> <label> <cols> <rows> <scenario>
TREE=$1; LABEL=$2; X=$3; Y=$4; SC=$5
OUT=/tmp/chd-design/out/$SC-${X}x$Y; mkdir -p $OUT
W=$(mktemp -d /tmp/chord-qa.XXXX)
S=chd-des-$LABEL-$RANDOM
tmux new-session -d -s $S -x $X -y $Y -c $TREE "deno task chord:fake -C $W"
sleep 6
cap() { sleep ${2:-1}; tmux capture-pane -t $S -p -e | sed -E "s#$W#/W#g" > $OUT/$LABEL-$1.ansi; }
say() { tmux send-keys -t $S -l "$1"; sleep 0.3; tmux send-keys -t $S Enter; }
case $SC in
  start) cap 0 0 ;;
  tools) say tools; cap 1 3 ;;
  edit) say edit; cap 1 3 ;;
  permission) say permission; cap 1 2; tmux send-keys -t $S Down; cap 2 0.6; tmux send-keys -t $S Enter; cap 3 2 ;;
  slow) say slow; cap 1 0.4; cap 2 1; say text; cap 3 0.6; tmux send-keys -t $S Escape; cap 4 1; tmux send-keys -t $S Escape; cap 5 2 ;;
  mode) tmux send-keys -t $S BTab; cap 1 1.5; tmux send-keys -t $S BTab; cap 2 1.5 ;;
  plan) say plan; cap 1 1.5; cap 2 6 ;;
  form) say form; cap 1 2 ;;
  model) say /model; cap 1 1.5 ;;
  help) say /help; cap 1 1.5 ;;
esac
tmux kill-session -t $S
