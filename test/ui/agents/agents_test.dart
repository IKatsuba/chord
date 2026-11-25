import 'package:chord/notify.dart';
import 'package:chord/session/transcript/types.dart' show LeftOpen;
import 'package:chord/session/waits.dart';
import 'package:chord/ui/agents/agents.dart';
import 'package:chord_tui/chord_tui.dart' show cellWidth, stripAnsi;
import 'package:test/test.dart';

const now = 100000;

AgentRow row(
  String name, {
  int? key,
  String runtime = 'codex',
  String? model = 'gpt-5.3-codex',
  String? effort,
  bool picked = false,
  bool failed = false,
  AgentWait wait = idle,
}) => AgentRow(
  key: key ?? name.length,
  name: name,
  runtime: runtime,
  model: model,
  effort: effort,
  picked: picked,
  failed: failed,
  wait: wait,
);

/// [from] with the fields given changed, as the original spreads a row.
AgentRow copy(
  AgentRow from, {
  bool? picked,
  bool? failed,
  String? effort,
  AgentWait? wait,
}) => AgentRow(
  key: from.key,
  name: from.name,
  runtime: from.runtime,
  model: from.model,
  effort: effort ?? from.effort,
  colour: from.colour,
  picked: picked ?? from.picked,
  failed: failed ?? from.failed,
  wait: wait ?? from.wait,
);

Asking permission(num since) => (on: const PermissionAsk(), since: since);

/// The rows as the list draws them, without the colours.
List<String> drawn(
  List<AgentRow> rows, {
  int limit = 4,
  int width = 116,
  bool focused = false,
  AgentsView? view,
}) {
  final layout = agentsLayout(
    rows,
    limit: limit,
    width: width,
    focused: focused,
    now: now,
    view: view,
  );
  return [
    for (final laid in layout.rows)
      for (final (:at, :gutter) in laid.lines)
        if (at == 0)
          '$gutter${laid.name}  ${laid.detail}'
                  '${laid.state == null ? '' : '  ${laid.state!.text}'}'
                  '${laid.unseen == null ? '' : '  ${laid.unseen!.text}'}'
              .trimRight()
        else
          // A wrapped row's further lines: the name's, then what went under
          // the detail.
          () {
            final name = at - 1 < laid.names.length ? laid.names[at - 1] : null;
            final below = at - 1 < laid.below.length
                ? laid.below[at - 1].map((run) => run.text).join()
                : '';
            return '$gutter${name ?? ' ' * laid.nameWidth}'
                    '${below.isEmpty ? '' : '  $below'}'
                .trimRight();
          }(),
    if (layout.more > 0) '  … +${layout.more} more',
  ];
}

final main_ = row('main', runtime: 'claude', model: 'Opus', picked: true);
final parser = row('parser', wait: const AgentWait(working: now - 41000));
final docs = row(
  'docs',
  runtime: 'claude',
  model: 'Sonnet',
  wait: const AgentWait(
    unseen: Unseen(UnseenKind.message, from: '@main', since: now),
  ),
);

String compact(String text) => text.replaceAll(RegExp(r'\s'), '');

void main() {
  testerAgentLayoutBoundaryTests();
  test(
    'each agent is a row of its name, runtime and model, and state, in columns',
    () {
      expect(drawn([main_, parser, docs]), [
        '  main    claude · Opus          ◦ idle 0s',
        '  parser  codex · gpt-5.3-codex  ✻ working 41s',
        '  docs    claude · Sonnet        ◦ idle 0s      ← new message',
      ]);
    },
  );

  test('the picked row is marked while the list has the keys', () {
    expect(
      drawn([
        copy(main_, picked: false),
        copy(parser, picked: true),
      ], focused: true),
      [
        '  main    claude · Opus          ◦ idle 0s',
        '❯ parser  codex · gpt-5.3-codex  ✻ working 41s',
      ],
    );
  });

  test('an agent always has one state, most urgent first, and what is not yet '
      'seen is a mark beside it (CHD-471)', () {
    String state(AgentWait wait, {bool failed = false}) =>
        agentState(row('x', wait: wait, failed: failed), now).toString();
    String? mark(AgentWait wait) => agentMark(row('x', wait: wait))?.toString();

    expect(
      state(AgentWait(asking: permission(now - 12000))),
      '● permission 12s (AgentTone.warning)',
    );
    expect(
      state(const AgentWait(asking: (on: InputAsk('Go?'), since: now))),
      '● input 0s (AgentTone.warning)',
    );
    expect(state(idle, failed: true), '✗ failed to start (AgentTone.error)');
    expect(state(const AgentWait(exited: true)), '✗ exited (AgentTone.error)');
    expect(
      state(const AgentWait(working: now - 62000)),
      '✻ working 1m 2s (AgentTone.working)',
    );
    // Idle since it last stopped, in its first unit.
    expect(
      state(const AgentWait(stopped: now - 190000)),
      '◦ idle 3m (AgentTone.dim)',
    );

    // A failed turn leaves the agent open and idle: the failure is a mark.
    const failed = AgentWait(
      stopped: now - 12000,
      unseen: Unseen(
        UnseenKind.failed,
        since: now - 12000,
        failure: Failure.turn,
      ),
    );
    expect(state(failed), '◦ idle 12s (AgentTone.dim)');
    expect(mark(failed), '✗ turn failed (AgentTone.error)');
    expect(
      mark(const AgentWait(unseen: Unseen(UnseenKind.replied, since: now))),
      '✓ new reply (AgentTone.dim)',
    );
    expect(
      mark(
        const AgentWait(
          unseen: Unseen(UnseenKind.message, from: '@main', since: now),
        ),
      ),
      '← new message (AgentTone.dim)',
    );
    // Its state says it is gone; that is no mark.
    expect(
      mark(
        const AgentWait(
          exited: true,
          unseen: Unseen(
            UnseenKind.failed,
            since: now,
            failure: Failure.exited,
          ),
        ),
      ),
      isNull,
    );
    expect(mark(idle), isNull);
  });

  test('past its rows the list ends in … +N more, and moves so the picked row '
      'shows while it has the keys', () {
    final rows = [
      for (final (index, name) in ['main', 'a', 'b', 'c', 'd', 'e'].indexed)
        row(name, key: index, picked: name == 'e', model: null),
    ];

    expect(agentsRowLimit(24), 4);
    expect(agentsRowLimit(40), 6);
    expect(drawn(rows, limit: 4), [
      '  main  codex  ◦ idle 0s',
      '  a     codex  ◦ idle 0s',
      '  b     codex  ◦ idle 0s',
      '  … +3 more',
    ]);
    expect(drawn(rows, limit: 4, focused: true), [
      '  c     codex  ◦ idle 0s',
      '  d     codex  ◦ idle 0s',
      '❯ e     codex  ◦ idle 0s',
      '  … +3 more',
    ]);
  });

  // CTUI-124: the original's AgentsList draws `  … +N more` after the rows
  // whatever side the hidden rows are on (../chord/src/ui/agents/Agents.tsx
  // :196-200), N being every row not drawn: `more: rows.length -
  // shown.length` in agentsLayout (../chord/src/ui/agents/agents.ts).
  test('hidden rows above or on both sides of the picked one are still '
      'counted on a last … +N more line', () {
    final names = ['main', 'a', 'b', 'c', 'd', 'e', 'f', 'g'];
    List<AgentRow> picking(String picked) => [
      for (final (index, name) in names.indexed)
        row(name, key: index, picked: name == picked, model: null),
    ];

    expect(drawn(picking('g'), limit: 4, focused: true), [
      '  e     codex  ◦ idle 0s',
      '  f     codex  ◦ idle 0s',
      '❯ g     codex  ◦ idle 0s',
      '  … +5 more',
    ]);
    expect(drawn(picking('d'), limit: 4, focused: true), [
      '  b     codex  ◦ idle 0s',
      '  c     codex  ◦ idle 0s',
      '❯ d     codex  ◦ idle 0s',
      '  … +5 more',
    ]);
    for (final picked in ['g', 'd']) {
      final layout = agentsLayout(
        picking(picked),
        limit: 4,
        width: 120,
        focused: true,
        now: now,
      );
      expect(layout.more, names.length - layout.rows.length);
    }
  });

  test("a narrow list drops the model, then puts a row's state under its "
      'detail, and wraps a long name in a third of the width, cutting nothing '
      '(CHD-471)', () {
    final long = row(
      'the-long-parser-name',
      wait: const AgentWait(working: now - 41000),
    );

    expect(drawn([main_, parser], width: 36), [
      '  main    claude  ◦ idle 0s',
      '  parser  codex   ✻ working 41s',
    ]);
    expect(drawn([main_, parser], width: 20, limit: 6), [
      '  main    claude',
      '          ◦ idle 0s',
      '  parser  codex',
      '          ✻ working',
      '          41s',
    ]);
    expect(drawn([long], width: 20, limit: 6), [
      '  the-lo  codex',
      '  ng-par  ✻ working',
      '  ser-na  41s',
      '  me',
    ]);
    // Each wrapped row counts its lines toward the limit.
    expect(drawn([main_, parser], width: 20), [
      '  main    claude',
      '          ◦ idle 0s',
      '  … +1 more',
    ]);
  });

  test("a row's effort follows its model, and a narrow list drops it a step "
      'before the model', () {
    final main = copy(main_, effort: 'high');
    final parser_ = copy(parser, effort: 'xhigh');

    expect(drawn([main, parser_]), [
      '  main    claude · Opus · high           ◦ idle 0s',
      '  parser  codex · gpt-5.3-codex · xhigh  ✻ working 41s',
    ]);
    expect(drawn([main, parser_], width: 50), [
      '  main    claude · Opus          ◦ idle 0s',
      '  parser  codex · gpt-5.3-codex  ✻ working 41s',
    ]);
    expect(drawn([main, parser_], width: 36), [
      '  main    claude  ◦ idle 0s',
      '  parser  codex   ✻ working 41s',
    ]);
  });

  test('the hint says what the keys do, shorter at 80 columns', () {
    expect(
      agentsHint(116, 'x'),
      '↑ ↓ to pick · enter to write to it · x to close · esc to go back',
    );
    expect(agentsHint(76, 'x'), '↑ ↓ pick · enter write · x close · esc back');
    expect(agentsHint(76, null), '↑ ↓ pick · enter write · esc back');
  });

  test(
    "a child's transcript opens with its name, runtime, model and who opened "
    'it when',
    () {
      final line = childLine(
        name: 'parser',
        runtime: 'codex',
        openedAt: now - 240000,
        model: 'gpt-5.3-codex',
        now: now,
      );

      expect(
        line.name + line.rest,
        'parser · codex · gpt-5.3-codex · opened by main 4m ago',
      );
    },
  );

  test("a fork's transcript opens with what it was forked from, not who opened "
      'it (CHD-101)', () {
    final line = childLine(
      name: 'fork',
      runtime: 'claude',
      forkedFrom: 'main',
      openedAt: now - 120000,
      model: 'Opus',
      now: now,
    );

    expect(
      line.name + line.rest,
      'fork · claude · Opus · forked from main 2m ago',
    );
  });

  test('the closing note of a resumed session names each agent left open with '
      'its runtime', () {
    expect(
      leftOpenLine([
        (name: 'parser', runtime: 'codex', team: null, agents: null),
      ]),
      'parser (codex) was open when this session was left and is not '
      'reopened · /resume lists it',
    );
    expect(
      leftOpenLine([
        (name: 'parser', runtime: 'codex', team: null, agents: null),
        (name: 'docs', runtime: 'claude', team: null, agents: null),
      ]),
      'parser (codex) and docs (claude) were open when this session was '
      'left and are not reopened · /resume lists them',
    );
    expect(
      leftOpenLine([
        (name: 'parser', runtime: 'codex', team: null, agents: null),
        (name: 'docs', runtime: 'claude', team: null, agents: null),
        (name: 'printer', runtime: 'gemini', team: null, agents: null),
      ]).split(' were ').first,
      'parser (codex), docs (claude), and printer (gemini)',
    );
  });

  test('the closing note counts each team run as one item, with its agents, '
      "and names each team's /team run once", () {
    const LeftOpen parser = (
      name: 'parser',
      runtime: 'codex',
      team: null,
      agents: null,
    );
    LeftOpen run(String name, String team, int agents) =>
        (name: name, runtime: 'claude', team: team, agents: agents);
    expect(
      leftOpenLine([parser, run('bugfix', 'bugfix', 4)]),
      'parser (codex) and team bugfix (4 agents) were open when this session '
      'was left and are not reopened · /resume lists them · /team run '
      'bugfix starts the team again',
    );
    // /resume lists the lead and each member, so even one run is "them".
    expect(
      leftOpenLine([run('bugfix', 'bugfix', 1)]),
      'team bugfix (1 agent) was open when this session was left and is not '
      'reopened · /resume lists them · /team run bugfix starts the team again',
    );
    expect(
      leftOpenLine([
        run('bugfix', 'bugfix', 4),
        run('bugfix 2', 'bugfix', 3),
        run('docs', 'docs', 2),
      ]),
      'team bugfix (4 agents), team bugfix 2 (3 agents), and team docs '
      '(2 agents) were open when this session was left and are not '
      'reopened · /resume lists them · /team run bugfix and /team run docs '
      'start the teams again',
    );
  });

  test('↑ ↓ move the ❯ through the agents; the last stays the last, and '
      'above the first the keys go back to the box', () {
    final rows = listRows([main_, parser]);

    expect(moveListFocus(rows, 1), 6);
    expect(moveListFocus(rows, 2), 6);
    expect(moveListFocus(rows, -1), isNull);
    expect(moveListFocus([], 1), isNull);
  });

  test("the background's summary line is the list's last stop, and with no "
      'agents drawn its one', () {
    final rows = listRows([main_, parser]);
    expect(moveListTarget(rows, 1, summary: true), const ListAgent(6));
    expect(moveListTarget(rows, 2, summary: true), const ListSummary());
    expect(
      moveListTarget(rows, 1, summary: true, onSummary: true),
      const ListSummary(),
    );
    expect(
      moveListTarget(rows, -1, summary: true, onSummary: true),
      const ListAgent(6),
    );
    // Without one, the last agent stays the last.
    expect(moveListTarget(rows, 2), const ListAgent(6));
    expect(moveListTarget(const [], 1, summary: true), const ListSummary());
    expect(moveListTarget(const [], -1, summary: true), isNull);
    expect(moveListTarget(const [], 1), isNull);
    expect(summaryHint(120), '↑ ↓ to move · enter to open · esc to go back');
    expect(summaryHint(76), '↑ ↓ move · enter open · esc back');
  });

  test('the ❯ marks the picked row only while the list has the keys', () {
    final rows = listRows([main_, parser]);

    expect(drawn(rows, focused: true).first.substring(0, 2), '❯ ');
    expect(
      [for (final line in drawn(rows)) line.substring(0, 2)],
      ['  ', '  '],
    );
  });

  test("the list ticks while any agent on it is open, an idle one's time "
      'counting too, and not once all are gone (CHD-471)', () {
    final rows = [
      for (final each in [main_, parser, docs]) copy(each, wait: idle),
    ];

    expect(listTimed(listRows(rows)), isTrue);
    expect(
      listTimed([
        for (final each in rows)
          copy(each, wait: const AgentWait(exited: true)),
      ]),
      isFalse,
    );
  });

  test('an exit and never starting are states, gravest first; a failed turn is '
      'a mark the agent reads idle beside, gone once seen', () {
    String words(AgentWait wait, {bool failed = false}) =>
        agentState(row('x', wait: wait, failed: failed), now).words;
    const turn = Unseen(
      UnseenKind.failed,
      since: now - 60000,
      failure: Failure.turn,
    );

    expect(
      words(const AgentWait(unseen: turn, stopped: now - 60000)),
      'idle 1m',
    );
    expect(
      agentMark(row('x', wait: const AgentWait(unseen: turn)))?.words,
      'turn failed',
    );
    expect(words(const AgentWait(unseen: turn, exited: true)), 'exited');
    expect(
      words(const AgentWait(unseen: turn), failed: true),
      'failed to start',
    );
    expect(words(const AgentWait(exited: true), failed: true), 'exited');
    // Asking still comes first.
    expect(
      words(AgentWait(unseen: turn, exited: true, asking: permission(now))),
      'permission 0s',
    );
    // Seen, a failed turn leaves no mark.
    expect(agentMark(row('x')), isNull);
    // An exit and never starting stay until the agent is closed, seen or
    // not.
    expect(words(const AgentWait(exited: true)), 'exited');
    expect(words(idle, failed: true), 'failed to start');
  });

  group('CHD-264 tester: failure age and row fallback', () {
    test(
      'an idle failed turn has a timeless mark, and a narrow row retains its '
      'error glyph',
      () {
        const unseen = Unseen(
          UnseenKind.failed,
          failure: Failure.turn,
          since: now - 120000,
          failedAt: now - 12000,
        );
        final failed = row('parser', wait: const AgentWait(unseen: unseen));
        final exited = copy(
          failed,
          wait: const AgentWait(unseen: unseen, exited: true),
        );

        expect(agentState(failed, now).words, 'idle 0s');
        expect(
          agentMark(failed),
          const AgentState(
            glyph: '✗',
            words: 'turn failed',
            tone: AgentTone.error,
          ),
        );
        expect(
          drawn([main_, failed], width: 76).join(' '),
          contains('◦ idle 0s  ✗ turn failed'),
        );
        expect(
          drawn([main_, failed], width: 20, limit: 6).join(' '),
          contains('✗'),
        );
        expect(agentState(exited, now).words, 'exited');
        expect(agentMark(exited), isNull);
      },
    );
  });

  test("a reply not yet seen is a mark with no time: the agent's own time says "
      'when it stopped, in a row (CHD-471)', () {
    final parser = row(
      'parser',
      wait: const AgentWait(
        stopped: now - 1000,
        unseen: Unseen(UnseenKind.replied, since: now - 23000),
      ),
    );

    expect(agentState(parser, now).words, 'idle 1s');
    expect(agentMark(parser)?.words, 'new reply');
  });

  test(
    "a narrow list drops a mark's words before the state's, each leaving its "
    'glyph (CHD-471)',
    () {
      final replied = row(
        'parser',
        wait: const AgentWait(
          stopped: now - 13000,
          unseen: Unseen(UnseenKind.replied, since: now),
        ),
      );
      final rows = [
        copy(main_, wait: const AgentWait(stopped: now - 4000)),
        replied,
      ];

      expect(drawn(rows), [
        '  main    claude · Opus          ◦ idle 4s',
        '  parser  codex · gpt-5.3-codex  ◦ idle 13s  ✓ new reply',
      ]);
      expect(drawn(rows, width: 40), [
        '  main    claude  ◦ idle 4s',
        '  parser  codex   ◦ idle 13s  ✓',
      ]);
      // Narrower still, each state goes whole under its detail, its mark
      // after it.
      expect(drawn(rows, width: 22, limit: 6), [
        '  main    claude',
        '          ◦ idle 4s',
        '  parser  codex',
        '          ◦ idle 13s',
        '          ✓',
      ]);
    },
  );

  group('CHD-471 tester: state and unseen marks are independent', () {
    test(
      'working retains an older reply and a gone agent is no longer timed',
      () {
        final working = row(
          'parser',
          wait: const AgentWait(
            working: now - 9000,
            stopped: now - 30000,
            unseen: Unseen(UnseenKind.replied, since: now - 20000),
          ),
        );

        expect(agentState(working, now).words, 'working 9s');
        expect(agentState(working, now + 2000).words, 'working 11s');
        expect(agentMark(working)?.words, 'new reply');
        expect(
          drawn([working]).join(' '),
          contains('✻ working 9s  ✓ new reply'),
        );
        expect(listTimed([working]), isTrue);
        expect(
          listTimed([copy(working, wait: const AgentWait(exited: true))]),
          isFalse,
        );
      },
    );
  });

  group('CHD-471 a row that does not fit wraps, and counts its lines', () {
    // The original's rows with its team's three as plain rows: teams fold
    // with CTUI-37, and this case draws them unfolded.
    AgentWait asking(int since) => AgentWait(asking: permission(now - since));
    final rows = [
      row(
        'main',
        key: 1,
        runtime: 'fake',
        wait: const AgentWait(stopped: now - 4000),
      ),
      row(
        'parser',
        key: 2,
        runtime: 'fake',
        wait: const AgentWait(
          stopped: now - 13000,
          unseen: Unseen(UnseenKind.replied, since: now),
        ),
      ),
      row(
        'docs',
        key: 3,
        runtime: 'fake',
        wait: AgentWait(
          asking: permission(now - 17000),
          unseen: const Unseen(UnseenKind.message, from: '@main', since: now),
        ),
      ),
      row(
        'bugfix',
        key: 4,
        runtime: 'team · fake',
        wait: const AgentWait(
          stopped: now,
          unseen: Unseen(UnseenKind.replied, since: now),
        ),
      ),
      row('tester', key: 5, runtime: 'fake', wait: asking(8000)),
      row('coder', key: 6, runtime: 'fake'),
    ];

    test('past the limit the list keeps whole rows, the picked one among them, '
        'and counts the rest', () {
      final picked = [
        for (final each in rows) copy(each, picked: each.name == 'coder'),
      ];

      expect(drawn(picked, width: 30, limit: 5, focused: true), [
        '  tester  fake',
        '          ● permission 8s',
        '❯ coder   fake  ◦ idle 0s',
        '  … +4 more',
      ]);
    });
  });

  test(
    'a detail wider than its line on its own wraps under its start, inside a '
    'word only where the word alone is wider, and the state follows under it '
    '(CHD-471)',
    () {
      final rows = [
        row('main', key: 1, runtime: 'fake', model: null),
        row(
          'parser',
          key: 2,
          runtime: 'a-runtime-named-past-the-line and more words',
          model: null,
          wait: const AgentWait(stopped: now - 4000),
        ),
      ];

      expect(drawn(rows, width: 30, limit: 9), [
        '  main    fake  ◦ idle 0s',
        '  parser  a-runtime-named-past',
        '          -the-line and more',
        '          words',
        '          ◦ idle 4s',
      ]);
    },
  );

  group(
    'CHD-471 a row taller than the list is read by line, the list never past '
    'its limit',
    () {
      const title =
          'Summarise the release notes for 0.56.0 from the commits since '
          '0.55.2, grouped by area, with a line for each user-facing change '
          'and a note for each breaking one, then draft the announcement for '
          'the forum and the changelog entry, and list the open questions '
          'for the owner to settle before the tag.';
      final rows = [
        row(
          'main',
          key: 1,
          runtime: 'fake',
          model: null,
          wait: const AgentWait(stopped: now - 4000),
        ),
        row(
          title,
          key: 2,
          runtime: 'fake',
          model: null,
          wait: const AgentWait(working: now - 41000),
        ),
        row('docs', key: 3, runtime: 'fake', model: null),
      ];
      List<AgentRow> pick(int key) => [
        for (final each in rows) copy(each, picked: each.key == key),
      ];
      AgentsView? scrolled(int key, int by, AgentsView? view) => scrolledView(
        pick(key),
        by,
        limit: 4,
        width: 76,
        now: now,
        view: view,
      );
      AgentsView? entered(int key, int top) =>
          enteredView(pick(key), top, limit: 4, width: 76, now: now);
      int topOf(int key, AgentsView? view) => agentsLayout(
        pick(key),
        limit: 4,
        width: 76,
        focused: true,
        now: now,
        view: view,
      ).top;

      test(
        'with the prompt keeping the keys, the tall row shows the lines that '
        'fit, ↓ beside its last, and … +N more counts the rows after it',
        () {
          expect(drawn(rows, width: 76), [
            '  main                       fake  ◦ idle 4s',
            '  Summarise the release      fake  ✻ working 41s',
            '↓ notes for 0.56.0 from the',
            '  … +1 more',
          ]);
        },
      );

      test(
        'picked, it comes into sight the least move from where the list was, '
        'and ↓ moves a line of it a press, ↑ and ↓ marking what is out of '
        'sight',
        () {
          var view = entered(2, topOf(1, null));

          expect(drawn(pick(2), width: 76, focused: true, view: view), [
            '  main                       fake  ◦ idle 4s',
            '❯ Summarise the release      fake  ✻ working 41s',
            '  notes for 0.56.0 from the',
            '↓ commits since 0.55.2,',
          ]);

          for (var press = 0; press < 4; press++) {
            view = scrolled(2, 1, view);
          }

          expect(drawn(pick(2), width: 76, focused: true, view: view), [
            '↑ grouped by area, with a',
            '  line for each user-facing',
            '  change and a note for',
            '↓ each breaking one, then',
          ]);

          // ↑ goes back a line a press until its first line is in sight,
          // then the pick moves on as moveListFocus says.
          view = scrolled(2, -1, view);

          expect(view?.top, 3);

          var back = view;
          while (back != null) {
            view = back;
            back = scrolled(2, -1, view);
          }

          expect(view?.top, 1);
          expect(
            drawn(pick(2), width: 76, focused: true, view: view).first,
            '❯ Summarise the release      fake  ✻ working 41s',
          );
        },
      );

      test('read to its last line, ↓ goes no further in it, and picked from '
          'below it shows from its first line', () {
        var view = entered(2, 0);
        var next = view;
        while (next != null) {
          view = next;
          next = scrolled(2, 1, view);
        }

        expect(drawn(pick(2), width: 76, focused: true, view: view), [
          '↑ changelog entry, and list',
          '  the open questions for',
          '  the owner to settle',
          '↓ before the tag.',
        ]);

        // From docs, below, ↑ picks it: the least move shows its first
        // line.
        expect(entered(2, topOf(3, view))?.top, 1);
      });

      test('another width, or no view, starts it again the least move from the '
          'top; the list is never past its limit', () {
        const view = AgentsView(key: 2, width: 76, limit: 4, top: 6);

        expect(
          drawn(pick(2), width: 60, focused: true, view: view),
          hasLength(4),
        );
        // The same width at another height: a view for another limit is
        // not this one's.
        expect(
          drawn(pick(2), width: 76, limit: 6, focused: true, view: view)[1],
          '❯ Summarise the release      fake  ✻ working 41s',
        );
        expect(
          drawn(pick(2), width: 76, focused: true)[1],
          '❯ Summarise the release      fake  ✻ working 41s',
        );

        for (final width in [30, 50, 76, 116]) {
          for (final focused in [false, true]) {
            expect(
              drawn(pick(2), width: width, focused: focused, limit: 4).length,
              lessThanOrEqualTo(4),
            );
          }
        }
      });
    },
  );

  group('CHD-471 L1b tester: every wrapped line remains reachable', () {
    for (final width in [26, 39, 76, 116]) {
      for (final limit in [4, 6]) {
        test('wide text and long runtime survive the $width-column $limit-line '
            'budget', () {
          final name = '解析🚀 ${'abcdefghijk ' * 30}';
          final runtime =
              'runtime-with-a-very-long-unbroken-identifier '
              '${'追加の説明 ' * 10}';
          final rows = [
            row(
              name,
              key: 10,
              picked: true,
              runtime: runtime,
              wait: AgentWait(
                asking: permission(now - 17000),
                unseen: const Unseen(UnseenKind.replied, since: now),
              ),
            ),
          ];
          final complete = agentsLayout(
            rows,
            width: width,
            limit: 10000,
            focused: true,
            now: now,
          ).rows.first;

          expect(
            compact([complete.name, ...complete.names].join()),
            compact(name),
          );

          final detail = [
            complete.detail,
            for (final line in complete.below)
              for (final run in line) run.text,
          ].join();

          expect(compact(detail), contains(compact(runtime)));
          expect(
            compact([complete.state?.text ?? '', detail].join()),
            contains('●permission17s'),
          );

          var view = enteredView(rows, 0, width: width, limit: limit, now: now);
          final visited = <int>{};

          for (var step = 0; step <= complete.height; step++) {
            final layout = agentsLayout(
              rows,
              width: width,
              limit: limit,
              focused: true,
              now: now,
              view: view,
            );
            final lines = drawn(
              rows,
              width: width,
              limit: limit,
              focused: true,
              view: view,
            );

            expect(lines.length, lessThanOrEqualTo(limit));
            expect(lines.every((line) => cellWidth(line) <= width), isTrue);

            for (final line in layout.rows.first.lines) {
              visited.add(line.at);
            }

            final next = scrolledView(
              rows,
              1,
              width: width,
              limit: limit,
              now: now,
              view: view,
            );
            if (next == null) break;

            expect(next.top, (view?.top ?? 0) + 1);
            view = next;
          }

          expect(visited.toList()..sort(), [
            for (var at = 0; at < complete.height; at++) at,
          ]);

          for (var step = 0; step <= complete.height; step++) {
            final previous = scrolledView(
              rows,
              -1,
              width: width,
              limit: limit,
              now: now,
              view: view,
            );
            if (previous == null) break;
            view = previous;
          }

          expect(view?.top, 0);
        });
      }
    }
  });

  group('CHD-464 tester: list space at its floor', () {
    test(
      'an absent or single agent needs no folded row, while several keep one '
      'agent and more',
      () {
        final rows = [
          for (final (key, name) in ['main', 'tester', 'coder'].indexed)
            row(name, key: key, model: null),
        ];
        int lines(List<AgentRow> rows, {int limit = 1}) => agentsLines(
          rows,
          limit: limit,
          width: 76,
          focused: false,
          now: now,
        );

        expect(lines([]), 0);
        expect(lines(rows.sublist(0, 1)), 1);
        expect(lines(rows), 2);
        expect(drawn(rows, limit: 1, width: 76), [
          '  main    codex  ◦ idle 0s',
          '  … +2 more',
        ]);
        expect(lines(rows, limit: 4), 3);
        expect(lines(rows), 2);
      },
    );
  });

  group('a wrapped agent name in the list (CHD-523)', () {
    test(
      'a picked row as tall as the list, rows after it, is read by line and '
      "shows whole, and the next press moves on (the picker's exact fit)",
      () {
        final tallName = [
          for (var at = 0; at < 6; at++) 'line${at}word',
        ].join(' ');
        final rows = [row(tallName, picked: true), row('parser'), row('docs')];
        final lines = drawn(rows, limit: 6, width: 30, focused: true);

        expect(lines, hasLength(6));
        expect(lines.join('\n'), contains('line5word'));
        expect(lines.join('\n'), isNot(contains('more')));
        expect(
          scrolledView(rows, 1, limit: 6, width: 30, now: now, view: null),
          isNull,
        );
        // Unpicked, it shows the lines that fit beside the notice.
        expect(drawn(rows, limit: 6, width: 30).last, '  … +2 more');
      },
    );
  });

  group('leaving a tall row read by line (CHD-445)', () {
    test('the next row comes whole into sight with the least move, the rows '
        'above kept as far as they fit, and ↑ picks the tall row again from '
        'its first line', () {
      // The agent's name wraps to five lines in a list of four.
      final name = [for (var at = 0; at < 5; at++) 'line${at}word'].join(' ');
      List<AgentRow> pick(int key) => [
        row(name, key: 0, picked: key == 0),
        row('parser', key: 1, picked: key == 1),
        row('docs', key: 2, picked: key == 2),
      ];
      int topOf(int key, AgentsView view) => agentsLayout(
        pick(key),
        limit: 4,
        width: 50,
        focused: true,
        now: now,
        view: view,
      ).top;
      AgentsView? entered(int key, int top, {bool reading = false}) =>
          enteredView(
            pick(key),
            top,
            limit: 4,
            width: 50,
            now: now,
            reading: reading,
          );
      AgentsView? scrolled(AgentsView view) =>
          scrolledView(pick(0), 1, limit: 4, width: 50, now: now, view: view);

      // Read main to its last line.
      var view = entered(0, 0)!;
      view = scrolled(view)!;

      expect(scrolled(view), isNull);

      final onParser = entered(1, topOf(0, view), reading: true)!;
      final lines = drawn(
        pick(1),
        limit: 4,
        width: 50,
        focused: true,
        view: onParser,
      );

      expect(lines, hasLength(4));
      expect(lines[0], startsWith('↑ '));
      expect(lines.sublist(0, 3).join('\n'), contains('line4word'));
      expect(lines[3], startsWith('❯ parser'));
      expect(lines.join('\n'), isNot(contains('more')));

      // Back up: main from its first line.
      final back = entered(0, topOf(1, onParser), reading: true)!;

      expect(
        drawn(pick(0), limit: 4, width: 50, focused: true, view: back).first,
        startsWith('❯ line0word'),
      );
      // Not read by line before: a row that fits gets no window, as today.
      expect(entered(1, 0), isNull);
    });
  });

  group("the original's captures (bun dev chord --fake --qa agents)", () {
    // The list draws inside two columns of padding: at 120 columns its rows
    // are 116 wide, at 80 they are 76.
    const large = 'Fake Large with a 1M context window';
    List<AgentRow> moment({
      required int idleMain,
      required int idleParser,
      required int asking,
      bool seen = false,
      String? picked,
    }) => [
      row(
        'main',
        key: 1,
        runtime: 'fake',
        model: large,
        effort: 'medium',
        picked: picked == 'main',
        wait: AgentWait(stopped: now - idleMain * 1000),
      ),
      row(
        'parser',
        key: 2,
        runtime: 'fake',
        model: 'Fake Small',
        effort: 'medium',
        picked: picked == 'parser',
        wait: AgentWait(
          stopped: now - idleParser * 1000,
          unseen: seen ? null : const Unseen(UnseenKind.replied, since: now),
        ),
      ),
      row(
        'docs',
        key: 3,
        runtime: 'fake',
        model: large,
        effort: 'medium',
        picked: picked == 'docs',
        wait: AgentWait(
          asking: permission(now - asking * 1000),
          unseen: seen
              ? null
              : const Unseen(UnseenKind.message, from: '@main', since: now),
        ),
      ),
    ];
    final asked = moment(idleMain: 5, idleParser: 7, asking: 8);

    test('a child asking, the prompt holding the keys, at 120 columns', () {
      expect(drawn(asked, width: 116), [
        '  main    fake · $large · medium  ◦ idle 5s',
        '  parser  fake · Fake Small · medium                           '
            '◦ idle 7s        ✓ new reply',
        '  docs    fake · $large · medium  ● permission 8s  ← new message',
      ]);
    });

    test('the same moment at 80 columns: model and effort give way', () {
      expect(drawn(asked, width: 76), [
        '  main    fake  ◦ idle 5s',
        '  parser  fake  ◦ idle 7s        ✓ new reply',
        '  docs    fake  ● permission 8s  ← new message',
      ]);
    });

    test('docs picked at 80 columns: its marks seen, the model comes back', () {
      final picked = moment(
        idleMain: 13,
        idleParser: 15,
        asking: 16,
        seen: true,
        picked: 'docs',
      );

      expect(drawn(picked, width: 76, focused: true), [
        '  main    fake · $large  ◦ idle 13s',
        '  parser  fake · Fake Small                           ◦ idle 15s',
        '❯ docs    fake · $large  ● permission 16s',
      ]);
    });
  });

  group('narrow and long', () {
    test('widths 0 and 1 lay out clamped to one column, never throwing', () {
      for (final width in [0, 1]) {
        for (final focused in [false, true]) {
          final rows = [copy(main_, picked: true), parser, docs];
          final layout = agentsLayout(
            rows,
            limit: 4,
            width: width,
            focused: focused,
            now: now,
          );
          final lines = drawn(rows, width: width, focused: focused);

          expect(lines.length, lessThanOrEqualTo(4));
          expect(layout.rows.first.nameWidth, 1);
          expect(lines.first, startsWith(focused ? '❯ m' : '  m'));
          expect(
            agentsLines(
              rows,
              limit: 4,
              width: width,
              focused: focused,
              now: now,
            ),
            lessThanOrEqualTo(4),
          );
          expect(
            enteredView(rows, 0, limit: 4, width: width, now: now),
            isA<AgentsView?>(),
          );
          expect(
            scrolledView(rows, 1, limit: 4, width: width, now: now, view: null),
            isA<AgentsView?>(),
          );
        }
      }
    });

    test('a name wider than the list wraps inside its column, cut nowhere', () {
      const name = 'an-agent-name-that-runs-well-past-the-list-width';
      final rows = [row(name, model: null)];
      final complete = agentsLayout(
        rows,
        limit: 100,
        width: 30,
        focused: false,
        now: now,
      ).rows.first;

      expect(complete.nameWidth, 10);
      expect([complete.name, ...complete.names].join().trimRight(), name);
      final lines = drawn(rows, width: 30, limit: 100);
      expect(lines.first, '  an-agent-n  codex  ◦ idle 0s');
      expect(lines.every((line) => cellWidth(line) <= 30), isTrue);
    });
  });
}

void testerAgentLayoutBoundaryTests() {
  group('tester: pure agent layout boundaries', () {
    test(
      'wide emoji and combining clusters survive every narrow column edge',
      () {
        const name = '界🙂e\u0301界🙂e\u0301';
        const runtime = '\x1b[31mruntime界🙂e\u0301\x1b[0m';
        for (final width in [0, 1, 3, 6, 9, 26, 76, 116]) {
          final layout = agentsLayout(
            [row(name, runtime: runtime, model: null)],
            limit: 100,
            width: width,
            focused: false,
            now: now,
          );
          final laid = layout.rows.single;
          final pieces = [laid.name, ...laid.names];
          expect(
            pieces.map((part) => part.trimRight()).join(),
            name,
            reason: 'width $width',
          );
          expect(
            pieces.every(
              (part) =>
                  cellWidth(part) <= (laid.nameWidth < 2 ? 2 : laid.nameWidth),
            ),
            isTrue,
          );
          final detail = stripAnsi(
            [
              laid.detail,
              for (final line in laid.below)
                for (final run in line) run.text,
            ].join(),
          );
          expect(detail, startsWith(stripAnsi(runtime)));
        }
      },
    );

    test(
      'hidden wider rows set the same columns before and after picking them',
      () {
        final rows = List<AgentRow>.unmodifiable([
          row('main', key: 1),
          row('a', key: 2),
          row('b', key: 3),
          row(
            'a-hidden-wide-name',
            key: 4,
            model: 'a-longer-model-than-the-visible-ones',
          ),
          row('last', key: 5),
        ]);
        final all = agentsLayout(
          rows,
          limit: 100,
          width: 116,
          focused: false,
          now: now,
        );
        final short = agentsLayout(
          rows,
          limit: 2,
          width: 116,
          focused: false,
          now: now,
        );
        expect(short.rows.single.row.key, 1);
        expect(short.rows.single.nameWidth, cellWidth('a-hidden-wide-name'));
        expect(short.rows.single.detail, all.rows.first.detail);
        expect(short.more, 4);
        final picked = [
          for (final item in rows) copy(item, picked: item.key == 4),
        ];
        final after = agentsLayout(
          picked,
          limit: 3,
          width: 116,
          focused: true,
          now: now,
        );
        for (final shown in after.rows) {
          final complete = all.rows.firstWhere(
            (item) => item.row.key == shown.row.key,
          );
          expect(shown.nameWidth, complete.nameWidth);
          expect(shown.detail, complete.detail);
          expect(shown.state, complete.state);
        }
      },
    );

    test('empty budgets and stale views do not borrow another row window', () {
      for (final width in [0, 1, 76, 116]) {
        expect(
          agentsLines([], limit: 0, width: width, focused: true, now: now),
          0,
        );
        expect(enteredView([], 999, limit: 0, width: width, now: now), isNull);
        expect(
          scrolledView([], 1, limit: 0, width: width, now: now, view: null),
          isNull,
        );
      }
      final rows = [
        row('long-${'界🙂e\u0301 ' * 30}', key: 1, picked: true),
        row('next', key: 2),
      ];
      final fresh = agentsLayout(
        rows,
        limit: 4,
        width: 76,
        focused: true,
        now: now,
      );
      for (final view in const [
        AgentsView(key: 99, width: 76, limit: 4, top: 999),
        AgentsView(key: 1, width: 80, limit: 4, top: 999),
        AgentsView(key: 1, width: 76, limit: 6, top: 999),
      ]) {
        final layout = agentsLayout(
          rows,
          limit: 4,
          width: 76,
          focused: true,
          now: now,
          view: view,
        );
        expect(layout.top, fresh.top);
        expect(
          layout.rows.expand((item) => item.lines).map((line) => line.at),
          fresh.rows.expand((item) => item.lines).map((line) => line.at),
        );
      }
      expect(moveListFocus(rows, 999), 2);
      expect(moveListFocus(rows, -999), isNull);
    });
  });
}
