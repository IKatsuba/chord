U8 at c0d88a57. Both apps ran `chord fake --agent-command` with the fake behind a
shell loop that waits for a gate file, isolated XDG_STATE_HOME. While held:
esc to the window, `/model` Enter: both show only "Starting fake…", no picker.
Gate opened: both open the same Select model picker once the session is up
(model-opens-when-ready-*). Paths relabelled <workspace>.
