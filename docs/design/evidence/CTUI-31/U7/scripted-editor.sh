#!/bin/sh
sleep 1
printf "%s\nedited in the editor" "$(cat "$1")" > "$1"
