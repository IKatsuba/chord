# Fake agent scenarios

- `tests/fixtures/fake_agent/` — a scripted ACP agent on the SDK's agent side.
  `main.ts` is the agent, which `bun dev chord --fake` and
  `tests/fixtures/fake.ts`'s `fakeAgentCommand` start: the scenario chosen,
  every request answered, sessions listed, loaded and resumed, and a turn's
  usage; it plays one table spread from a module per family under
  `scenarios/`: `text.ts`
  (`text`, `thought`, `todos`, `mcp`, `markdown`, `slow`, `long`),
  `tools.ts` (`tools`, `steps`, `stepslater`, `calls`, `longresults`,
  `overlap`, `overlapfail`,
  `unordered`, `edit`, `rewrite`, `headlines`, `heredoc`, `longcommand`,
  `mcpnote`, `codexmcpnote`),
  `permissions.ts` (`permission`, `twins`, `mcpask`, `bigask`, `bigasktwice`,
  `overlapask`),
  `plans.ts` (`plan`, `planshrink`, `proposal`), `forms.ts` (`form`, `link`),
  `shell.ts` (`shell`,
  `shellcut`, `bash`), `compaction.ts` (`compact`, `codexcompact`,
  `compactfail`), `modes.ts` (`status`, `exitplan`, `mode`, `lock`),
  `soak.ts` (`soak`, `soaklead`, `soakturn`),
  `subagents.ts` (`subagent`, `subagentupdate`, `subagentstates`, `subagentcall`),
  `chord_tools.ts`
  (`chordtools`, `cutcalls`, `cutcallsback`), `tasks.ts` (`codexchordcalls`) and
  `misbehaving.ts` (`error`, `late`, `unknown`). Beside it, what the
  scenarios read too:
  `options.ts` its flags and environment variables, `turn.ts` a turn and
  its call ids, `client.ts` what the client declared at `initialize`, and
  `sessions.ts` each session's directory, MCP servers, model, mode and
  effort with the config options that offer them.
  A prompt that is exactly a scenario name (`text`, `thought`, `tools`, `steps`, `stepslater`, `calls`,
  `longresults`, `unordered`, `edit`, `rewrite`, `headlines`, `heredoc`,
  `longcommand`, `overlap`, `overlapfail`, `overlapask`, `subagentcall`,
  `cutcalls`, `cutcallsback`,
  `mcpnote`, `codexmcpnote`, `markdown`, `permission`, `plan`, `proposal`,
  `shell`, `shellcut`, `bash`, `compact`, `codexcompact`, `compactfail`, `status`,
  `error`, `slow`, `long`, `todos`, `exitplan`, `lock`, `mcp`, `form`, `link`,
  `mode`, `late`, `twins`, `mcpask`, `bigask`, `bigasktwice`, `unknown`,
  `subagent`, `subagentupdate`, `subagentstates`, `chordtools`, `codexchordcalls`)
  plays that scenario; `steps` makes 150 calls, a transcript longer than
  its mounted tail in one turn, and `stepslater` the same after a second;
  `longresults` plays an MCP result, command output, an edit and terminal
  output with long lines, to check wrapping;
  `overlap` opens two calls in turn, then ends the first while the second
  still runs; `overlapfail` fails the first instead; `overlapask` asks for
  a write's permission while another call stays open; `subagentcall` runs
  one subagent's call with no call of the parent's open;
  `headlines` plays a heredoc, a long one-line command, an MCP call and a
  300-line heredoc; `heredoc` and `longcommand` play the Bash calls from
  the Claude Code capture in `docs/design/CHD-393.md`, and `mcpnote` its
  MCP note, with arguments first empty, then whole; `codexmcpnote` plays
  the same note as Codex sends it, with server, tool and arguments wrapped
  in `rawInput`;
  `form` asks for a form with a field of each kind and
  `link` for a link to open (`tests/fixtures/forms.ts`), `askclaude`,
  `askclaudeone`, `askcodex`, `askdroid`, `askopencode` and `askdimcode`
  each adapter's question form (`tests/fixtures/questions.ts`), claude's
  after AskUserQuestion's tool call as claude-agent-acp sends it,
  `askcodexwait` codex's with a wait of 300 ms, withdrawn 50 ms after it
  runs out, as codex-acp withdraws it once it does, and each says what came back, and
  an accepted link is followed by `elicitation/complete`; `twins` asks a
  permission with two `allow_once` options and says the id picked; `mcpask`
  asks for an MCP call as claude-agent-acp does, by the tool's name with the
  arguments only in `rawInput`; `bigask` asks for an MCP file write with
  multiline content and a long line, to scroll and wrap in the permission
  box; `bigasktwice` asks for two such writes at once, the second waiting
  behind the first; `late`
  sends a chunk after answering the prompt; `unknown` sends an update of a
  kind ACP does not have and a notification of its own;
  `mcp` answers with the MCP servers its session was opened with, as JSON;
  `chordtools` connects to chord's own, through the MCP SDK's client, calls
  `list_agents` and `list_sessions` and answers with what came back, as
  JSON; `chordcalls` makes the same calls as tool calls, titled as Claude's
  adapter titles them, then a `spawn_task` on a runtime chord does not
  know; `codexchordcalls` lists agents and sessions as Codex does, after
  another server's call with the same arguments as the first;
  `cutcalls` cuts off `send_message` and `open_agent` before they reach
  chord, with empty errors, and cancels a command beside them;
  `cutcallsback` adds `list_sessions`, ends the calls in reverse order and
  repeats the message's failure. A prompt preceded by chord's note about
  cut calls is answered with `Received chord's note:` and its first line,
  then plays the prompt as if it came alone;
  `task` starts `taskchild` as a task agent on the fake runtime and
  works on a while, and `taskask` one whose job is `askclaude`, after a
  call of its own that, played first, shares the task's call id `ask-1`; `taskchild` makes two calls, asks permission to edit,
  messages its parent through `send_message`, runs the tests and reports;
  `agents` opens `parser` on `agentchild` and `docs` on `permission`, both
  long-lived on the fake runtime, and messages `parser` twice;
  `agentcall` opens `parser` on `callchild` and messages it during its
  running call; `agentcalltwice` sends two messages during that call, to
  check their queue order. `callchild` runs one call for about three
  seconds, then reports that the tests pass;
  `agentsend` and `codexagentsend` open `parser` on `agentchild` and send
  it a short message and a long markdown one, as Claude and Codex do;
  `agentsendrefused` sends the long one to `parser` without opening it,
  so chord refuses it;
  `agentprose` and `codexagentprose` open `parser` on `prosechild` and
  `codexprosechild` and send it long Cyrillic and ASCII paragraphs, as
  Claude and Codex do; both child scenarios send those paragraphs back;
  `agentchild` runs the tests twice, messaging its parent after each;
  `agentsheld` opens `docs` alone and messages it while it waits on its
  permission; `agentclose` closes `parser` and then messages it, which chord refuses;
  `agenttask`, `agentexit` and `agentfail` open `parser` on `task`, on
  `crash`, whose agent writes its last words to stderr and exits mid-turn,
  and on `error`; `taskeffort` and `agenteffort` start a task and open an
  agent on `text` on high effort, `taskmaxeffort` and `agentmaxeffort` on
  max, which the fake does not offer, and each says the effort chord's
  answer says it started on, and its note; `team` and `team2` call `list_teams`, then `run_team` on
  `bugfix` (`tests/fixtures/teams/fake/bugfix.md`, all on the fake runtime)
  with an issue's job; a team agent's first prompt plays its role, read off
  its team part, unless its message names a scenario, which it plays: `teamlead` opens `tester` and `coder`, asks the other runs'
  leads which files they hold and reports to main, `teamtester` writes a
  test, reports to its lead, messages `coder` directly and asks the person
  to run the suite, and `teamcoder` messages `tester`; `propose`, or the
  prompt `/team new` sends, behind any notes chord held for
  main's next prompt, proposes `bugfix` on claude and codex through
  `propose_team` and says where it was saved, and the next prompt after a
  proposal, whatever it says, is `proposeagain`: the same team with the
  reviewer on codex and tester in `bypassPermissions`; `soak` hands
  `bugfix` the job `soaklead`, whose lead opens `tester` and `coder` on
  `soakturn` and sends main `soakturn`, and each `soakturn` streams a
  30-line reply and a call, then sends `soakturn` back to its sender, so
  the four take turns until chord quits (`bun dev memory`); a
  prompt that is a wrapped message is answered with who it was from, or,
  when what it says is a scenario's name, plays that scenario, as a child's
  first prompt is its parent's message; and `--no-http` or `CHORD_FAKE_NO_HTTP=1` leaves HTTP out of its
  `mcpCapabilities`, so chord gives it no server of its own; `long` streams 200
  numbered lines about 100 ms apart, to scroll back through by hand; `plan`
  moves its three steps along about 2 s apart, to see the list mid-turn;
  `proposal` sends Codex's proposed plan by id about 2 s a step: markdown
  rewritten then grown, a file plan, then the markdown one removed;
  `shell` runs a command as Codex's adapter does, to any client: its
  terminal named up front, its output (`tests/fixtures/terminals.ts`) in pieces about
  half a second apart, then a failing exit with the last piece, and
  `shellcut` the same with a hyperlink whose URL runs past the output bound
  and whose end comes in a later piece; `bash` as
  Claude's does: to a client that asks for terminal output in `_meta`, the
  terminal up front and the whole output, then the exit, once it is done
  about half a second later, and to any other a `console` code block;
  `compact` compacts as Claude's adapter does, to a client that declares
  `session.compaction`: a `compaction_update` in progress, its summary in
  chunks over about 2 s, then completed (cancelled when its turn is);
  `codexcompact` as Codex's does, with no summary, and `compactfail`
  fails with Claude's error; to any other client each is a `Compact
  conversation` tool call of kind `think`;
  `todos` says whether Claude's task list tools reached it turned on;
  `status` moves to plan mode by `current_mode_update` alone, reports a cost
  and answers with token usage of its own, and `exitplan`
  leaves a mode for the default as Claude does once a plan is approved;
  `lock` moves to plan the same way and refuses every mode asked for after;
  `mode` says the mode the turn runs in;
  `subagent` runs subagents as Claude's and Codex's adapters send them to a
  client that declares `clientCapabilities.subagents` (`subagent_spawned`,
  `subagent_state_update`, each subagent's work under its own session id,
  opaque and never one an earlier fake process gave, as after a resume):
  two spawned back to back, one with a plan, five calls, a subagent of its
  own and a write it asks permission for, the other failing, then, after a
  line of the parent's, a third alone that runs on about 2 s past the turn's
  answer; a cancel ends each still
  open `cancelled` before the answer; `subagentupdate` sends one in ACP's
  own `subagent_update`, running then idle; `subagentstates` reaches what
  `subagent` does not: the parent's own plan beside a lone subagent with a
  plan of its own and five calls, held about 2 s, then a pair spawned back
  to back that the parent waits on with a call of its own, as Codex's
  adapter does, both finishing. `--step-ms <ms>` or
  `CHORD_FAKE_STEP_MS` sets the pace of every scenario (5 ms a step by
  default). Every
  session offers two models, `Fake Large with a 1M context window` (in use
  until switched) and `Fake Small`, and three modes, `default`, `acceptEdits`
  and `plan`, and an effort, `low`, `medium` (until set) or `high`, through
  config options; `--no-config` or `CHORD_FAKE_NO_CONFIG=1` leaves the effort
  out and `--refuse-config` or `CHORD_FAKE_REFUSE_CONFIG=1` refuses every
  change to it; `--no-modes` or `CHORD_FAKE_NO_MODES=1` offers no modes and
  refuses `session/set_mode`. `--hang <step>` or `CHORD_FAKE_HANG=<step>`
  wedges it: `start` never answers `initialize`, `config` never answers a
  config, mode or model change, `turn` never ends a prompt, cancelled or not.
  It ignores SIGTERM and stdin closing, but exits on SIGKILL or parent loss.
  It also exits when started under PID 1, even if that parent is alive. It
  switches its model, mode and effort through
  `session/set_config_option` and answers `session/set_mode` as Claude's
  adapter does, or, with `--silent-set-mode` or
  `CHORD_FAKE_SILENT_SET_MODE=1`, answers both, for the mode, as Codex's
  does: an empty answer and no update, though the mode moves. With
  `--plan-capability-only` or `CHORD_FAKE_PLAN_CAPABILITY_ONLY=1`, the
  `plan` scenario sends its plan as Codex's adapter does: as a `plan_update`
  with an id to a client that declares `clientCapabilities.plan`, and as
  reply text to any other. Every session
  advertises two slash commands, `greet` and `echo` (`tests/fixtures/commands.ts`), just
  after `session/new`, as Claude's adapter does; a prompt starting with one
  plays it. Shell output sent ahead of a prompt is answered first with a
  `Received` line naming each command and its first line of output, and
  each image in a prompt with one naming its media type and size in bytes,
  and each `resource_link` with one naming it and its URI;
  `--no-images` or `CHORD_FAKE_NO_IMAGES=1` says in `promptCapabilities`
  that it takes none. Any
  other scenario's turn that ends on its own reports usage as Claude's adapter does: a
  `usage_update` with the context used so far (2,000 tokens a turn), the
  model's window and the session's cost ($0.0125 a turn), and the turn's
  tokens in its answer; `--no-usage` or `CHORD_FAKE_NO_USAGE=1` reports none,
  and `--tokens-only` or `CHORD_FAKE_TOKENS_ONLY=1` only the tokens, no cost
  and no window, on two real models chord's price data knows,
  `gpt-5.3-codex` (in use until switched) and `claude-haiku-4-5`. `session/list` gives the sessions the process created,
  newest first, and `session/set_model` takes either model. `session/load` takes any UUID and replays a short past (the
  `tools` and `text` scenarios) before it answers; any other id is not found,
  and `CHORD_FAKE_REFUSE_LOAD=1` refuses every load; `--resume-only` also
  offers `session/resume`, which takes the same ids and replays nothing.
  `--steering claude` or `--steering codex` (`CHORD_FAKE_STEERING`)
  advertises `_session/steering` and answers it as that adapter does: into
  the turn playing, `injected`, read at its next step or as it ends with
  `Read the message from <sender>.`; with none, Claude's `promptRequired`
  where the request asks for it, else, and always for Codex, a turn of the
  agent's own, `startedNewTurn`, answered before that turn says anything,
  as Codex's adapter answers once it has started. Without the flag it advertises nothing and
  refuses the method. `--steer-late` (`CHORD_FAKE_STEER_LATE=1`) lands a
  steer only once the turn playing has answered, as one that meets a turn's
  end does, Codex's answering a while after; as Codex's, a prompt that comes
  while a turn plays opens with `Started alongside a turn still playing.`.
  `tests/fixtures/recorder.ts`
  plays one through the session layer and returns what the interface would
  hand the transcript reducer, and `run` gathers a prompt's updates and its
  answer. `tests/fixtures/records.ts` leaves a session record as the window does, through a
  recording conversation, for the resume tests to find.
