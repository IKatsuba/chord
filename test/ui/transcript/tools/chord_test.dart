// chord's own calls read as verbs, with what was said or answered under
// them, never as `chord - send_message (MCP)(…)`. The original's
// tests/ui/transcript/tools/chord_test.ts, tests/ui/app/tasks_test.ts and
// the chord cases of tests/ui/transcript/tools/tools_test.ts.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/theme/theme.dart';
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord/ui/transcript/tools/chord.dart';
import 'package:chord/ui/transcript/tools/tool.dart';
import 'package:chord/ui/transcript/tools/tools.dart';
import 'package:chord_tui/chord_tui.dart' hide Folded;
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const _cutSend =
    'Not delivered: cut off before it reached chord. chord tells the agent '
    'at its next turn.';
const _cutOther =
    'Cut off before it reached chord, so it did nothing. chord tells the '
    'agent at its next turn.';

ChordCall _call(
  ChordTool tool, [
  Map<String, Object?> input = const {},
  Object? answer,
  String? error,
  bool queued = false,
]) => ChordCall(
  tool: tool,
  input: input,
  answer: answer,
  error: error,
  queued: queued,
);

Map<String, Object?> _headline(Headline line) => {
  'name': line.name,
  'arg': ?line.arg,
  'note': ?line.note,
  if (line.sent) 'sent': true,
};

acp.ToolCallContent _text(String value) => acp.ToolCallContent.fromJson({
  'type': 'content',
  'content': {'type': 'text', 'text': value},
});

/// The rows of [t]'s screen, their trailing blanks cut.
List<String> _rows(WidgetTester t) => [
  for (final row in t.screen.lines) row.trimRight(),
];

void main() {
  _testerSentBodyParity();

  group('tester team row boundaries', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'team job retains Unicode and ANSI after tiny room and resize $size',
        (t) async {
          final widget = Theme(
            data: themeData('dark'),
            child: const Tool(
              ToolCall(
                'tester-team',
                status: 'completed',
                chord: ChordCall(
                  tool: ChordTool.runTeam,
                  input: {
                    'team': 'bugfix',
                    'job': '\x1b[31m界🙂e\u0301\x1b[0m\nsecond line',
                  },
                  answer: {
                    'name': 'bugfix 2',
                    'agent': 'fake',
                    'model': 'small',
                  },
                ),
              ),
              expanded: false,
            ),
          );
          await t.pumpWidget(widget, size: const Size(0, 1));
          await t.pumpWidget(widget, size: const Size(1, 1));
          await t.pumpWidget(widget, size: size);
          await t.pump();
          final text = t.screen.lines.join('\n');
          expect(text, contains('Team(bugfix 2)'));
          expect(text, contains('界🙂e\u0301'));
          expect(text, contains('second line'));
        },
      );
    }
  });
  test("run_team draws as Team(<run>) on the lead's runtime and model, "
      'the job under it', () {
    final call = _call(
      ChordTool.runTeam,
      {'team': 'bugfix', 'job': 'Issue 214.\nReport when done.'},
      {
        'id': '7f3a9c2e',
        'name': 'bugfix 2',
        'team': 'bugfix',
        'agent': 'claude',
        'model': 'opus',
        'mode': 'default',
      },
    );
    expect(_headline(chordHeadline(call)), {
      'name': 'Team',
      'arg': 'bugfix 2',
      'note': ' · claude · opus',
    });
    expect(chordLines(call), ['Issue 214.', 'Report when done.']);
    expect(
      _headline(
        chordHeadline(_call(ChordTool.runTeam, {'team': 'bugfx', 'job': 'x'})),
      ),
      {'name': 'Team', 'arg': 'bugfx'},
    );
  });

  test("a lead's open_agent draws the member on the file's runtime, model "
      'and mode', () {
    expect(
      _headline(
        chordHeadline(
          _call(
            ChordTool.openAgent,
            {'member': 'tester', 'prompt': 'Write the test.'},
            {
              'id': 'a1',
              'name': 'tester',
              'agent': 'claude',
              'model': 'sonnet',
              'mode': 'acceptEdits',
            },
          ),
        ),
      ),
      {
        'name': 'Open',
        'arg': 'tester',
        'note': ' · claude · sonnet · acceptEdits',
      },
    );
  });

  test('list_teams draws as List teams with their names', () {
    final call = _call(ChordTool.listTeams, const {}, {
      'teams': [
        {'name': 'bugfix'},
        {'name': 'review'},
      ],
    });
    expect(_headline(chordHeadline(call)), {'name': 'List teams'});
    expect(chordLines(call), ['2 teams · bugfix, review']);
    expect(chordLines(_call(ChordTool.listTeams)), isEmpty);
  });

  test('the monitor tools read as Monitor, Stop monitor and List '
      'monitors, with what runs and what came of it', () {
    final started = _call(
      ChordTool.monitor,
      {'command': 'tail -f log', 'description': 'errors'},
      {'id': 'm1', 'description': 'errors', 'timeout_ms': 600000},
    );
    expect(_headline(chordHeadline(started)), {
      'name': 'Monitor',
      'arg': 'errors',
    });
    expect(chordLines(started), [r'$ tail -f log', 'm1 · times out after 10m']);
    expect(
      chordLines(_call(ChordTool.monitor, {'command': 'x'}, null, 'refused')),
      ['refused'],
    );
    final stopped = _call(
      ChordTool.stopMonitor,
      {'id': 'm1'},
      {'id': 'm1', 'description': 'errors', 'events': 3, 'ran_ms': 252000},
    );
    expect(_headline(chordHeadline(stopped)), {
      'name': 'Stop monitor',
      'arg': 'errors',
    });
    expect(chordLines(stopped), ['Stopped after 4m 12s · 3 events']);
    expect(
      _headline(chordHeadline(_call(ChordTool.stopMonitor, {'id': 'm2'}))),
      {'name': 'Stop monitor', 'arg': 'm2'},
    );
    expect(
      chordLines(
        _call(
          ChordTool.stopMonitor,
          {'id': 'm1'},
          {'id': 'm1', 'description': 'e', 'events': 0, 'ran_ms': 0},
        ),
      ),
      ['Stopped after 0s · no events'],
    );
    expect(_headline(chordHeadline(_call(ChordTool.listMonitors))), {
      'name': 'List monitors',
    });
    expect(chordLines(_call(ChordTool.listMonitors)), isEmpty);
    expect(
      chordLines(_call(ChordTool.listMonitors, {}, {'monitors': <Object>[]})),
      ['None running'],
    );
    expect(
      chordLines(
        _call(ChordTool.listMonitors, {}, {
          'monitors': [
            {'description': 'a'},
            {'description': 'b'},
          ],
        }),
      ),
      ['2 running · a, b'],
    );
  });
  group('verbs', () {
    test('list_agents names the runtime asked about, if one was', () {
      expect(_headline(chordHeadline(_call(ChordTool.listAgents))), {
        'name': 'List agents',
      });
      expect(
        _headline(
          chordHeadline(_call(ChordTool.listAgents, {'agent': 'codex'})),
        ),
        {'name': 'List agents', 'arg': 'codex'},
      );
    });

    test('list_sessions is a bare verb', () {
      expect(_headline(chordHeadline(_call(ChordTool.listSessions))), {
        'name': 'List sessions',
      });
    });

    test('open_agent is Open(name) with runtime, model and effort after it, '
        'the name chord answered with first', () {
      const input = {
        'agent': 'fake',
        'model': 'fake-small',
        'prompt': 'agentchild',
        'name': 'parser',
      };
      expect(_headline(chordHeadline(_call(ChordTool.openAgent, input))), {
        'name': 'Open',
        'arg': 'parser',
        'note': ' · fake · fake-small',
      });
      expect(
        _headline(
          chordHeadline(
            _call(ChordTool.openAgent, input, {
              'id': 'a1',
              'name': 'parser 2',
              'agent': 'fake',
              'model': 'fake-small',
            }),
          ),
        ),
        {'name': 'Open', 'arg': 'parser 2', 'note': ' · fake · fake-small'},
      );
      // With no name, the runtime names it until chord answers.
      expect(
        _headline(
          chordHeadline(
            _call(ChordTool.openAgent, {
              'agent': 'codex',
              'model': 'gpt',
              'prompt': 'go',
            }),
          ),
        ),
        {'name': 'Open', 'arg': 'codex', 'note': ' · codex · gpt'},
      );
    });

    test('the effort asked for shows until chord answers with the one it '
        'started on, which a refusal leaves at the runtime own', () {
      const input = {
        'agent': 'codex',
        'model': 'gpt',
        'effort': 'high',
        'prompt': 'Fix it',
      };
      expect(
        chordHeadline(_call(ChordTool.spawnTask, input)).note,
        ' · codex · gpt · high',
      );
      expect(
        chordHeadline(
          _call(ChordTool.spawnTask, input, {
            'id': 't1',
            'name': 'Fix it',
            'agent': 'codex',
            'effort': 'medium',
          }),
        ).note,
        ' · codex · gpt · medium',
      );
      expect(
        chordHeadline(
          _call(ChordTool.spawnTask, input, {'id': 't1', 'name': 'Fix it'}),
        ).note,
        ' · codex · gpt',
      );
    });

    test('spawn_task is Agent(name), or its prompt first line', () {
      expect(
        _headline(
          chordHeadline(
            _call(
              ChordTool.spawnTask,
              {'agent': 'codx', 'prompt': 'Fix it\nall', 'model': 'm'},
              null,
              'No agent named codx',
            ),
          ),
        ),
        {'name': 'Agent', 'arg': 'Fix it', 'note': ' · codx · m'},
      );
      expect(
        chordHeadline(
          _call(ChordTool.spawnTask, {
            'agent': 'codex',
            'prompt': 'x',
            'name': 'Fix the tokenizer',
          }),
        ).arg,
        'Fix the tokenizer',
      );
    });

    test('send_message is → to its recipient, main for a child, queued '
        'when it waited', () {
      expect(
        _headline(
          chordHeadline(
            _call(ChordTool.sendMessage, {'text': 'hi'}, null, null, true),
          ),
        ),
        {'name': 'main', 'note': ' · queued', 'sent': true},
      );
      expect(
        _headline(
          chordHeadline(
            _call(ChordTool.sendMessage, {'to': 'parser', 'text': 'hi'}),
          ),
        ),
        {'name': 'parser', 'sent': true},
      );
      // The recipient chord answered wins over the alias asked for.
      expect(
        chordHeadline(
          _call(
            ChordTool.sendMessage,
            {'to': 'a1', 'text': 'hi'},
            {'delivered': 'sent', 'to': 'parser'},
          ),
        ).name,
        'parser',
      );
    });

    test('close_agent names what it closed, and a task already ended says '
        'so', () {
      final closed = _call(
        ChordTool.closeAgent,
        {'to': 'a1'},
        {'closed': 'Watch the build'},
      );
      final ended = _call(
        ChordTool.closeAgent,
        {'to': 'a1'},
        {'ended': 'Watch the build'},
      );
      expect(_headline(chordHeadline(closed)), {
        'name': 'Close',
        'arg': 'Watch the build',
      });
      expect(chordLines(closed), ['Closed']);
      expect(_headline(chordHeadline(ended)), {
        'name': 'Close',
        'arg': 'Watch the build',
      });
      expect(chordLines(ended), ['Already ended']);
      expect(
        chordHeadline(_call(ChordTool.closeAgent, {'to': 'a1'})).arg,
        'a1',
      );
    });

    test('clear_agent is Clear(name): a fresh session, its id, and the '
        'messages dropped', () {
      final cleared = _call(
        ChordTool.clearAgent,
        {'to': 'a1'},
        {
          'cleared': 'parser',
          'id': 'a1',
          'dropped': '2 queued messages from main and docs were not delivered.',
        },
      );
      expect(_headline(chordHeadline(cleared)), {
        'name': 'Clear',
        'arg': 'parser',
      });
      expect(chordLines(cleared), [
        'Fresh session · id a1',
        '2 queued messages from main and docs were not delivered.',
      ]);
      expect(
        chordLines(
          _call(ChordTool.clearAgent, {'to': 'a1'}, {'cleared': 'parser'}),
        ),
        ['Fresh session'],
      );
    });
  });

  group('lines', () {
    test('list_agents counts runtimes, or a runtime models, four named', () {
      final agents = [
        for (var n = 0; n < 7; n++) {'name': 'r$n'},
      ];
      expect(chordLines(_call(ChordTool.listAgents, {}, {'agents': agents})), [
        '7 runtimes · r0, r1, r2, r3, +3 more',
      ]);
      expect(
        chordLines(
          _call(
            ChordTool.listAgents,
            {'agent': 'codex'},
            {
              'agents': [
                {
                  'name': 'codex',
                  'models': [
                    {'id': 'a'},
                    {'id': 'b'},
                  ],
                },
              ],
            },
          ),
        ),
        ['2 models · a, b'],
      );
      expect(
        chordLines(
          _call(
            ChordTool.listAgents,
            {'agent': 'codex'},
            {
              'agents': [
                {
                  'name': 'codex',
                  'note':
                      'models and modes not read yet; list_agents with agent '
                      '"codex" reads them',
                },
              ],
            },
          ),
        ),
        [
          'models and modes not read yet; list_agents with agent "codex" '
              'reads them',
        ],
      );
      expect(
        chordLines(
          _call(
            ChordTool.listAgents,
            {'agent': 'codex'},
            {
              'agents': [
                {'name': 'codex'},
              ],
            },
          ),
        ),
        ['No models'],
      );
    });

    test(
      'list_sessions counts the sessions, by runtime, with their agents',
      () {
        expect(
          chordLines(
            _call(ChordTool.listSessions, {}, {
              'sessions': [
                {'runtime': 'claude', 'you': true},
                {'runtime': 'codex'},
              ],
            }),
          ),
          ['2 open · claude (you), codex'],
        );
        expect(
          chordLines(
            _call(ChordTool.listSessions, {}, {
              'sessions': [
                {
                  'runtime': 'claude',
                  'you': true,
                  'agents': [
                    {'id': 'a', 'name': 'parser', 'runtime': 'codex'},
                    {'id': 'b', 'name': 'docs', 'runtime': 'claude'},
                  ],
                },
              ],
            }),
          ),
          ['1 open · claude (you), 2 agents'],
        );
        // Before the answer, nothing of its own: the call says it runs.
        expect(chordLines(_call(ChordTool.listSessions)), isEmpty);
        expect(chordLines(_call(ChordTool.listAgents)), isEmpty);
      },
    );

    test('a message lists what it said; a launch its prompt, whole or six '
        'lines for a task; a refusal says itself', () {
      expect(chordLines(_call(ChordTool.sendMessage, {'text': 'one\ntwo'})), [
        'one',
        'two',
      ]);
      expect(chordLines(_call(ChordTool.sendMessage, {'text': '  '})), isEmpty);
      final prompt = [for (var n = 1; n <= 8; n++) 'line $n'].join('\n');
      expect(
        chordLines(_call(ChordTool.openAgent, {'prompt': prompt})),
        hasLength(8),
      );
      expect(
        chordLines(_call(ChordTool.spawnTask, {'prompt': prompt})),
        hasLength(6),
      );
      expect(chordLines(_call(ChordTool.openAgent, {'typed': '/new codex'})), [
        'opened with /new codex',
      ]);
      expect(
        chordLines(
          _call(
            ChordTool.openAgent,
            {'prompt': 'x'},
            null,
            'This session has 8 agents open; close_agent one first',
          ),
        ),
        ['This session has 8 agents open; close_agent one first'],
      );
    });
  });

  group('calls', () {
    test('a call served reads by its verb; one to chord own server by its '
        'name, even before it is served; another server stays MCP', () {
      const tied = ToolCall(
        'c',
        title: 'mcp__chord__list_agents',
        chord: ChordCall(tool: ChordTool.listAgents, input: {}),
      );
      expect(_headline(headline(tied)), {'name': 'List agents'});
      const titled = ToolCall(
        'c',
        title: 'mcp__chord-2__close_agent',
        rawInput: {'to': 'parser'},
      );
      expect(_headline(headline(titled, chordServer: 'chord-2')), {
        'name': 'Close',
        'arg': 'parser',
      });
      expect(
        headline(titled, chordServer: 'chord').name,
        'chord-2 - close_agent',
      );
      expect(headline(titled).tag, ' (MCP)');
      const wrapped = ToolCall(
        'c',
        mcp: McpCall('list_sessions', {}, server: 'chord'),
      );
      expect(headline(wrapped, chordServer: 'chord').name, 'List sessions');
    });

    test("chord's refusal fails the call whatever the adapter said", () {
      expect(
        toneOf(
          const ToolCall(
            'c',
            status: 'completed',
            chord: ChordCall(
              tool: ChordTool.closeAgent,
              input: {'to': 'x'},
              error: 'No agent x',
            ),
          ),
        ),
        Tone.failed,
      );
      expect(
        toneOf(
          const ToolCall(
            'c',
            status: 'completed',
            chord: ChordCall(tool: ChordTool.closeAgent, input: {'to': 'x'}),
          ),
        ),
        Tone.done,
      );
    });

    test('lines are read from what chord served, not the answer JSON; its '
        'refusal said as it is', () {
      final call = ToolCall(
        'c',
        status: 'completed',
        content: [_text('{\n  "closed": "parser"\n}')],
        chord: const ChordCall(
          tool: ChordTool.closeAgent,
          input: {'to': 'a1'},
          answer: {'closed': 'parser'},
        ),
      );
      expect(summary(call, false).lines, ['Closed']);
      final refused = ToolCall(
        'c',
        status: 'failed',
        content: [_text('No agent a1')],
        chord: const ChordCall(
          tool: ChordTool.closeAgent,
          input: {'to': 'a1'},
          error: 'No agent a1 is open in this session',
        ),
      );
      expect(summary(refused, false).lines, [
        'No agent a1 is open in this session',
      ]);
    });

    test('a chord call cut off before it reached chord keeps what it asked '
        'for and says it did nothing, read on chord server alone', () {
      ToolCall cut(String tool, Map<String, Object?> input) => ToolCall(
        'a',
        title: 'mcp__chord__$tool',
        status: 'failed',
        rawInput: input,
        cut: true,
        content: [_text('Error calling tool (mcp__chord__$tool): ')],
      );
      final sent = sentBody(
        cut('send_message', {'to': 'main', 'text': 'Hi'}),
        chordServer: 'chord',
      )!;
      expect((sent.text, sent.ending), ('Hi', _cutSend));
      expect(cutLine(ChordTool.sendMessage), _cutSend);
      expect(
        summary(
          cut('open_agent', {'name': 'parser', 'prompt': 'agentchild'}),
          false,
          chordServer: 'chord',
        ).lines,
        ['agentchild', _cutOther],
      );
      // Not chord's server: the agent's own error, as any failed call.
      expect(
        summary(
          cut('open_agent', {'name': 'parser', 'prompt': 'agentchild'}),
          false,
          chordServer: 'chord-2',
        ).lines,
        ['Error: Error calling tool (mcp__chord__open_agent):'],
      );
    });

    test('a sent body is its text in every state, a refusal or Failed '
        'after it; none for an empty text or another call', () {
      ToolCall sent(ChordCall chord, [String status = 'completed']) =>
          ToolCall('c', status: status, chord: chord);
      const input = {'to': 'parser', 'text': 'Run the parser tests.'};
      for (final status in ['pending', 'in_progress', 'completed']) {
        final body = sentBody(
          sent(
            const ChordCall(tool: ChordTool.sendMessage, input: input),
            status,
          ),
        )!;
        expect((body.text, body.ending), ('Run the parser tests.', null));
      }
      final refused = sentBody(
        sent(
          const ChordCall(
            tool: ChordTool.sendMessage,
            input: input,
            error: 'parser is closed; it takes no more messages',
          ),
        ),
      )!;
      expect(refused.ending, 'parser is closed; it takes no more messages');
      expect(
        sentBody(
          sent(
            const ChordCall(tool: ChordTool.sendMessage, input: input),
            'failed',
          ),
        )!.ending,
        'Failed',
      );
      expect(
        sentBody(
          sent(
            const ChordCall(
              tool: ChordTool.sendMessage,
              input: {'to': 'parser', 'text': ' '},
            ),
          ),
        ),
        isNull,
      );
      expect(
        sentBody(
          sent(const ChordCall(tool: ChordTool.closeAgent, input: {'to': 'p'})),
        ),
        isNull,
      );
    });
  });

  group('rows on screen', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('Open(parser) · fake · fake-small and its prompt, at '
          '$size', (t) async {
        await t.pumpWidget(
          Theme(
            data: themeData('dark'),
            child: const Tool(
              ToolCall(
                'c',
                status: 'completed',
                chord: ChordCall(
                  tool: ChordTool.openAgent,
                  input: {
                    'agent': 'fake',
                    'model': 'fake-small',
                    'name': 'parser',
                    'prompt': 'agentchild',
                  },
                  answer: {
                    'id': 'a1',
                    'name': 'parser',
                    'agent': 'fake',
                    'model': 'fake-small',
                  },
                ),
              ),
              expanded: false,
            ),
          ),
          size: size,
        );
        expect(_rows(t).take(3), [
          '',
          '⏺ Open(parser) · fake · fake-small',
          '  ⎿  agentchild',
        ]);
        // The verb bold, the note dim, the argument as the text is.
        expect(t.screen.styleAt(2, 1).isBold, isTrue);
        expect(t.screen.styleAt(7, 1).isBold, isFalse);
        expect(t.screen.styleAt(7, 1).isDim, isFalse);
        expect(t.screen.styleAt(15, 1).isDim, isTrue);
      });

      testWidgets('→ to @parser · queued, its text whole under ⎿, at $size', (
        t,
      ) async {
        const text =
            'I changed how a string at the end of a line is read. Run the '
            'parser tests now and tell me only what fails.';
        await t.pumpWidget(
          Theme(
            data: themeData('dark'),
            child: const Tool(
              ToolCall(
                'c',
                status: 'completed',
                title: 'mcp__chord__send_message',
                chord: ChordCall(
                  tool: ChordTool.sendMessage,
                  input: {'to': 'parser', 'text': text},
                  answer: {'delivered': 'queued', 'to': 'parser'},
                  queued: true,
                ),
              ),
              expanded: false,
            ),
          ),
          size: size,
        );
        final rows = _rows(t);
        expect(rows[1], '→ to @parser · queued');
        expect(rows.join('\n'), isNot(contains('⏺')));
        expect(rows.join('\n'), isNot(contains('MCP')));
        if (size.width == 120) {
          expect(rows[2], '  ⎿  $text');
        } else {
          expect(rows.sublist(2, 4), [
            '  ⎿  I changed how a string at the end of a line is read. Run '
                'the parser tests',
            '     now and tell me only what fails.',
          ]);
        }
        // `→` as the text is, `to ` dim, `@parser` bold, the note dim, the
        // body dim.
        final arrow = t.screen.styleAt(0, 1);
        expect((arrow.isDim, arrow.isBold), (false, false));
        expect(t.screen.styleAt(2, 1).isDim, isTrue);
        expect(t.screen.styleAt(5, 1).isBold, isTrue);
        expect(t.screen.styleAt(5, 1).isDim, isFalse);
        expect(t.screen.styleAt(14, 1).isDim, isTrue);
        expect(t.screen.styleAt(5, 2).isDim, isTrue);
      });

      testWidgets('a → dim while it goes, red once refused with the refusal '
          'after its text, at $size', (t) async {
        final theme = themeData('dark');
        const input = {'to': 'parser', 'text': 'Run the parser tests.'};
        await t.pumpWidget(
          Theme(
            data: theme,
            child: const Tool(
              ToolCall(
                'c',
                status: 'in_progress',
                chord: ChordCall(tool: ChordTool.sendMessage, input: input),
              ),
              expanded: false,
            ),
          ),
          size: size,
        );
        expect(_rows(t).sublist(1, 3), [
          '→ to @parser',
          '  ⎿  Run the parser tests.',
        ]);
        expect(t.screen.text, isNot(contains('Running…')));
        expect(t.screen.styleAt(0, 1).isDim, isTrue);
        await t.pumpWidget(
          Theme(
            data: theme,
            child: const Tool(
              ToolCall(
                'c',
                status: 'completed',
                chord: ChordCall(
                  tool: ChordTool.sendMessage,
                  input: input,
                  error: 'parser is closed; it takes no more messages',
                ),
              ),
              expanded: false,
            ),
          ),
          size: size,
        );
        expect(_rows(t).sublist(1, 4), [
          '→ to @parser',
          '  ⎿  Run the parser tests.',
          '     parser is closed; it takes no more messages',
        ]);
        expect(t.screen.styleAt(0, 1).fg, theme.error.fg);
        expect(t.screen.styleAt(0, 1).isDim, isFalse);
        expect(t.screen.styleAt(5, 3).fg, theme.error.fg);
      });

      testWidgets('a send cut off says it was not delivered, at $size', (
        t,
      ) async {
        await t.pumpWidget(
          Theme(
            data: themeData('dark'),
            child: const Tool(
              ToolCall(
                'c',
                status: 'failed',
                title: 'mcp__chord__send_message',
                rawInput: {'text': 'Found it.'},
                cut: true,
              ),
              expanded: false,
              chordServer: 'chord',
            ),
          ),
          size: size,
        );
        expect(_rows(t)[1], '→ to @main');
        expect(_rows(t)[2], '  ⎿  Found it.');
        expect(
          t.screen.text.replaceAll(RegExp(r'\s+'), ' '),
          contains(_cutSend),
        );
      });
    }
  });
}

void _testerSentBodyParity() {
  group('CTUI-35 tester: sent and received body parity', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'escapes, indented and fenced code render equally in both directions at $size',
        (t) async {
          const text =
              '    const answer = 42;\n\n\x1b[31m**Read this**\x1b[0m and `keep` it.\n\n```ts\nconst tail = 7;\n```\n\nThe last paragraph is still here.';
          for (final expanded in [false, true]) {
            await t.pumpWidget(
              Theme(
                data: themeData('dark'),
                child: Tool(
                  const ToolCall(
                    'c',
                    status: 'completed',
                    chord: ChordCall(
                      tool: ChordTool.sendMessage,
                      input: {'to': 'parser', 'text': text},
                    ),
                  ),
                  expanded: expanded,
                ),
              ),
              size: size,
            );
            final outgoing = t.screen.lines
                .skip(2)
                .takeWhile((line) => line.isNotEmpty)
                .toList();
            // Include the blank rows inside code and paragraphs, up to the last text.
            final out = t.screen.lines.skip(2).toList();
            final lastOut = out.indexWhere(
              (l) => l.contains('The last paragraph'),
            );
            expect(lastOut, isNonNegative);
            await t.pumpWidget(
              Theme(
                data: themeData('dark'),
                child: TranscriptEntry(
                  const UserEntry(
                    't',
                    text,
                    from: MessageFrom('parser', reachable: true),
                  ),
                  expanded: expanded,
                ),
              ),
              size: size,
            );
            final incoming = t.screen.lines.skip(2).toList();
            final lastIn = incoming.indexWhere(
              (l) => l.contains('The last paragraph'),
            );
            expect(incoming.take(lastIn + 1), out.take(lastOut + 1));
            expect(outgoing, isNotEmpty);
            expect(t.screen.text, isNot(contains('[31m')));
          }
        },
      );
      testWidgets(
        'long ASCII and Cyrillic messages keep every word and the final refusal at $size',
        (t) async {
          for (final phrase in [
            'Read every parser branch before changing the tests.',
            'Проверь все ветви парсера перед изменением тестов.',
          ]) {
            final text = '${List.filled(12, phrase).join(' ')} Final sentence.';
            await t.pumpWidget(
              Theme(
                data: themeData('dark'),
                child: Tool(
                  ToolCall(
                    'c',
                    status: 'failed',
                    chord: ChordCall(
                      tool: ChordTool.sendMessage,
                      input: {'to': 'parser', 'text': text},
                      error: 'Refused after text.',
                    ),
                  ),
                  expanded: false,
                ),
              ),
              size: size,
            );
            final rows = t.screen.lines
                .skip(2)
                .where((l) => l.trim().isNotEmpty)
                .toList();
            expect(rows.last.trim(), 'Refused after text.');
            final plain = rows
                .take(rows.length - 1)
                .map((line) => line.replaceFirst(RegExp(r'^\s*(?:⎿\s*)?'), ''))
                .join('')
                .replaceAll(RegExp(r'\s'), '');
            expect(plain, text.replaceAll(RegExp(r'\s'), ''));
            expect(t.screen.text, isNot(contains('to expand')));
            expect(t.screen.text, isNot(contains('… +')));
          }
        },
      );
    }
  });
}
