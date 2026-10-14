#!/bin/sh
# Plays the CHD-241 splash mock-up in this terminal: the drift around its
# small ellipse, counter-clockwise, at 300 ms a step, then the cut to the window.
# Usage: sh play.sh [120x40|80x24|44x12]
size=${1:-80x24}
cd "$(dirname "$0")" || exit 1
printf '\033[?1049h\033[?25l'
trap 'printf "\033[?25h\033[?1049l"' EXIT INT
for _ in 1 2 3 4; do
  for step in 0 1 2 3 4 5 6 7; do
    printf '\033[H\033[2J'
    cat "$size-float-$step.ans"
    sleep 0.3
  done
done
printf '\033[H\033[2J'
cat "$size-after-connect.ans" 2>/dev/null || cat 80x24-after-connect.ans
sleep 2
