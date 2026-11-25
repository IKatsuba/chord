// A team in the list under the prompt: its members nested under its lead
// with the tree's branches, folded into the lead's row when the list does
// not fit, the team the pick is in unfolded, a folded lead's size, its most
// urgent state naming the member and its first unseen mark, and the lead's
// and member's first lines. The original's tests/ui/agents/agents_test.ts
// team cases.
import 'package:chord/notify.dart';
import 'package:chord/session/waits.dart';
import 'package:chord/ui/agents/agents.dart';
import 'package:test/test.dart';

const now = 100000;

AgentRow row(
  String name, {
  required int key,
  String runtime = 'codex',
  String? model = 'gpt-5.3-codex',
  int? team,
  bool picked = false,
  bool failed = false,
  AgentWait wait = idle,
}) => AgentRow(
  key: key,
  name: name,
  runtime: runtime,
  model: model,
  team: team,
  picked: picked,
  failed: failed,
  wait: wait,
);

/// [from] with what is given changed, as the original spreads a row.
AgentRow copy(
  AgentRow from, {
  int? key,
  String? name,
  int? team,
  bool? picked,
  bool? failed,
  AgentWait? wait,
}) => AgentRow(
  key: key ?? from.key,
  name: name ?? from.name,
  runtime: from.runtime,
  model: from.model,
  effort: from.effort,
  colour: from.colour,
  team: team ?? from.team,
  picked: picked ?? from.picked,
  failed: failed ?? from.failed,
  wait: wait ?? from.wait,
);

Asking permission(num since) => (on: const PermissionAsk(), since: since);

/// The rows as the list draws them, without the colours: a member's branch
/// ahead of its name, and the tree under it on its name's further lines.
List<String> drawn(
  List<AgentRow> rows, {
  int limit = 4,
  int width = 116,
  bool focused = false,
}) {
  final layout = agentsLayout(
    rows,
    limit: limit,
    width: width,
    focused: focused,
    now: now,
  );
  return [
    for (final laid in layout.rows)
      for (final (:at, :gutter) in laid.lines)
        if (at == 0)
          '$gutter${laid.branch ?? ''}${laid.name}  ${laid.detail}'
                  '${laid.state == null ? '' : '  ${laid.state!.text}'}'
                  '${laid.unseen == null ? '' : '  ${laid.unseen!.text}'}'
              .trimRight()
        else
          () {
            final name = at - 1 < laid.names.length
                ? '${laid.tree}${laid.names[at - 1]}'
                : ' ' * laid.nameWidth;
            final below = at - 1 < laid.below.length
                ? laid.below[at - 1].map((run) => run.text).join()
                : '';
            return '$gutter$name${below.isEmpty ? '' : '  $below'}'.trimRight();
          }(),
    if (layout.more > 0) '  … +${layout.more} more',
  ];
}

/// The team at work: `bugfix` with three members, `tester` asking, and
/// `parser`, a plain child, after it; [picked] has the prompt.
List<AgentRow> team([String picked = 'main']) => [
  row('main', key: 1, runtime: 'claude', model: 'Opus'),
  row(
    'bugfix',
    key: 2,
    runtime: 'team · claude',
    model: 'Opus',
    team: 2,
    wait: const AgentWait(
      unseen: Unseen(UnseenKind.replied, since: now - 40000),
    ),
  ),
  row(
    'tester',
    key: 3,
    runtime: 'claude',
    model: 'Sonnet',
    team: 2,
    wait: AgentWait(asking: permission(now - 12000)),
  ),
  row('coder', key: 4, team: 2),
  row(
    'reviewer',
    key: 5,
    runtime: 'claude',
    model: 'Opus',
    team: 2,
    wait: const AgentWait(
      unseen: Unseen(UnseenKind.replied, since: now - 60000),
    ),
  ),
  row('parser', key: 6, wait: const AgentWait(working: now - 9000)),
].map((each) => copy(each, picked: each.name == picked)).toList();

int Function(List<AgentRow>) height(int width) =>
    (rows) => agentsHeight(rows, width: width, now: now);

void main() {
  group('CTUI-37 tester: stable team folding', () {
    test('equal-priority asks keep roster order before and after folding', () {
      final rows = [
        for (final each in team())
          copy(
            each,
            wait: each.team == 2
                ? AgentWait(asking: permission(now - 5000))
                : idle,
          ),
      ];
      final folded = teamRows(rows, fold: true)[1];
      expect(agentState(folded, now).words, 'permission 5s');
      final memberAsks = [
        for (final each in rows) each.key == 2 ? copy(each, wait: idle) : each,
      ];
      for (var i = 0; i < 1000; i++) {
        final state = teamRows(memberAsks, fold: true)[1];
        expect(agentState(state, now).words, 'tester: permission 5s');
      }
      expect(
        memberAsks.every((r) => r.branch == null && r.folded == null),
        isTrue,
      );
      expect(
        teamRows(memberAsks, fold: false).map((r) => r.key),
        memberAsks.map((r) => r.key),
      );
    });

    test(
      'folding uses the measured boundary and preserves the picked team',
      () {
        final rows = team();
        final natural = agentsHeight(
          teamRows(rows, fold: false),
          width: 76,
          now: now,
        );
        expect(
          listRows(rows, limit: natural, height: height(76)),
          hasLength(rows.length),
        );
        expect(
          listRows(rows, limit: natural - 1, height: height(76)),
          hasLength(3),
        );
        expect(
          listRows(team('coder'), limit: 0, height: height(1)),
          hasLength(rows.length),
        );
        expect(rows.every((r) => r.branch == null && r.folded == null), isTrue);
      },
    );
  });
  test("a team's members nest under its lead with the tree's branches", () {
    expect(drawn(listRows(team(), limit: 6), limit: 6), [
      '  main         claude · Opus          ◦ idle 0s',
      '  bugfix       team · claude · Opus   ◦ idle 0s         ✓ new reply',
      '  ├─ tester    claude · Sonnet        ● permission 12s',
      '  ├─ coder     codex · gpt-5.3-codex  ◦ idle 0s',
      '  └─ reviewer  claude · Opus          ◦ idle 0s         ✓ new reply',
      '  parser       codex · gpt-5.3-codex  ✻ working 9s',
    ]);
  });

  test('a list that does not fit folds each team to its lead, its size and '
      'its most urgent state naming the member', () {
    expect(drawn(listRows(team(), limit: 4), limit: 4, width: 76), [
      '  main         claude                    ◦ idle 0s',
      '  bugfix       team · claude · 4 agents  ● tester: permission 12s  ✓',
      '  parser       codex                     ✻ working 9s',
    ]);
    // A model too long for the row drops the models; the size stays, as it
    // says more.
    final long = [
      for (final each in team())
        each.name == 'main'
            ? AgentRow(
                key: each.key,
                name: each.name,
                runtime: each.runtime,
                model: 'Fake Large with a 1M context window',
                wait: each.wait,
              )
            : each,
    ];
    expect(drawn(listRows(long, limit: 4), limit: 4, width: 76).take(2), [
      '  main         claude                    ◦ idle 0s',
      '  bugfix       team · claude · 4 agents  ● tester: permission 12s  ✓',
    ]);
  });

  test('the team the pick is in unfolds, and the list scrolls to it while '
      'it has the keys', () {
    List<AgentRow> rows(String picked) => listRows(team(picked), limit: 4);
    expect(drawn(rows('bugfix'), limit: 4, width: 76, focused: true), [
      '  main         claude · Opus          ◦ idle 0s',
      '❯ bugfix       team · claude · Opus   ◦ idle 0s         ✓ new reply',
      '  ├─ tester    claude · Sonnet        ● permission 12s',
      '  … +3 more',
    ]);
    // ctrl+x a picks tester without the list having the keys: unfolded.
    expect(rows('tester').map((each) => each.name), [
      'main',
      'bugfix',
      'tester',
      'coder',
      'reviewer',
      'parser',
    ]);
    // ↑ ↓ walk the rows as drawn: onto a folded lead, then into its members.
    expect(moveListFocus(rows('parser'), -1), 2);
    expect(moveListFocus(rows('bugfix'), 1), 3);
    expect(moveListFocus(rows('reviewer'), 1), 6);
  });

  test('two runs fold one by one, each with its own state', () {
    final second = [
      for (final each in team().sublist(1, 5))
        copy(
          each,
          key: each.key + 10,
          team: 12,
          name: each.name == 'bugfix' ? 'bugfix 2' : each.name,
          wait: each.name == 'tester'
              ? AgentWait(asking: permission(now - 5000))
              : idle,
        ),
    ];
    final first = [
      for (final each in team().sublist(0, 5))
        copy(
          each,
          wait: each.name == 'coder'
              ? const AgentWait(working: now - 61000)
              : idle,
        ),
    ];
    List<AgentRow> rows([int picked = 1]) => listRows([
      for (final each in [...first, ...second])
        copy(each, picked: each.key == picked),
    ], limit: 6);
    expect(drawn(rows(), limit: 6), [
      '  main         claude · Opus             ◦ idle 0s',
      '  bugfix       team · claude · 4 agents  ✻ coder: working 1m 1s',
      '  bugfix 2     team · claude · 4 agents  ● tester: permission 5s',
    ]);
    // The run picked unfolds; the other stays folded, so all six rows fit.
    expect(drawn(rows(13), limit: 6, focused: true), [
      '  main         claude · Opus             ◦ idle 0s',
      '  bugfix       team · claude · 4 agents  ✻ coder: working 1m 1s',
      '  bugfix 2     team · claude · Opus      ◦ idle 0s',
      '❯ ├─ tester    claude · Sonnet           ● permission 5s',
      '  ├─ coder     codex · gpt-5.3-codex     ◦ idle 0s',
      '  └─ reviewer  claude · Opus             ◦ idle 0s',
    ]);
  });

  test("a folded lead's own state is its own, and a lead with no member "
      'open folds nothing', () {
    final [main, lead, ...members] = team();
    final failed = copy(lead, failed: true);
    expect(
      drawn(teamRows([main, failed, ...members], fold: true), limit: 9)[1],
      ('  bugfix       team · claude · 4 agents  ● tester: permission 12s  ✓ '
          'new reply'),
    );
    expect(
      drawn(
        teamRows([main, failed, ...members.sublist(1, 3)], fold: true),
        limit: 9,
      )[1],
      '  bugfix       team · claude · 3 agents  ✗ failed to start  ✓ new reply',
    );
    expect(teamRows([main, lead], fold: true)[1], same(lead));
  });

  test('the list ticks while any agent on it is open, a folded member too, '
      'and not once all are gone', () {
    final rows = [for (final each in team()) copy(each, wait: idle)];
    expect(listTimed(listRows(rows, limit: 4)), isTrue);
    const gone = AgentWait(exited: true);
    final folded = teamRows([
      for (final each in rows)
        copy(each, wait: each.name == 'coder' ? idle : gone),
    ], fold: true);
    // Only coder is open, folded into its lead's row.
    expect(listTimed(folded.where((r) => r.name != 'parser').toList()), isTrue);
    expect(
      listTimed(
        teamRows([for (final each in rows) copy(each, wait: gone)], fold: true),
      ),
      isFalse,
    );
  });

  test("a folded lead names the member that is gone, gravest first, and its "
      "mark is the first of its agents' unnamed", () {
    final [main, lead, ...members] = team();
    AgentRow quiet(AgentRow each) =>
        copy(each, wait: const AgentWait(stopped: now - 30000));
    final rows = [
      main,
      quiet(lead),
      for (final member in members)
        member.name == 'tester'
            ? copy(
                member,
                wait: const AgentWait(
                  stopped: now - 12000,
                  unseen: Unseen(
                    UnseenKind.failed,
                    since: now - 12000,
                    failure: Failure.turn,
                  ),
                ),
              )
            : member.name == 'coder'
            ? copy(member, wait: const AgentWait(exited: true))
            : quiet(member),
    ];
    expect(
      drawn(teamRows(rows, fold: true), limit: 9)[1],
      ('  bugfix       team · claude · 4 agents  ✗ coder: exited  ✗ turn failed'),
    );
    // All idle: from the one that stopped last.
    expect(
      drawn(
        teamRows([
          for (final each in rows) each.name == 'coder' ? quiet(each) : each,
        ], fold: true),
        limit: 9,
      )[1],
      '  bugfix       team · claude · 4 agents  ◦ idle 12s  ✗ turn failed',
    );
  });

  test('folding ranks state and marks independently, with idle from the '
      'latest stop', () {
    final rows = [
      for (final (index, each) in team().indexed)
        copy(each, wait: AgentWait(stopped: now - (index + 1) * 10000)),
    ];
    final marked = [
      for (final each in rows)
        copy(
          each,
          wait: switch (each.name) {
            'tester' => AgentWait(
              stopped: each.wait.stopped,
              asking: permission(now - 4000),
              unseen: const Unseen(
                UnseenKind.message,
                from: '@main',
                since: now,
              ),
            ),
            'coder' => AgentWait(
              stopped: each.wait.stopped,
              unseen: const Unseen(UnseenKind.replied, since: now),
            ),
            'reviewer' => AgentWait(
              stopped: each.wait.stopped,
              unseen: const Unseen(
                UnseenKind.failed,
                since: now,
                failure: Failure.turn,
              ),
            ),
            _ => each.wait,
          },
        ),
    ];
    final folded = teamRows(marked, fold: true)[1];
    expect(agentState(folded, now).words, 'tester: permission 4s');
    expect(agentMark(folded)?.words, 'turn failed');
    final noFailure = teamRows([
      for (final each in marked)
        if (each.name != 'reviewer') each,
    ], fold: true)[1];
    expect(agentMark(noFailure)?.words, 'new reply');
    final quiet = teamRows(rows, fold: true)[1];
    expect(agentState(quiet, now).words, 'idle 20s');
    expect(agentMark(quiet), isNull);
  });

  group('a row that does not fit wraps, and counts its lines', () {
    AgentWait asking(int since) => AgentWait(asking: permission(now - since));
    final rows = [
      row(
        'main',
        key: 1,
        runtime: 'fake',
        model: null,
        wait: const AgentWait(stopped: now - 4000),
      ),
      row(
        'parser',
        key: 2,
        runtime: 'fake',
        model: null,
        wait: const AgentWait(
          stopped: now - 13000,
          unseen: Unseen(UnseenKind.replied, since: now),
        ),
      ),
      row(
        'docs',
        key: 3,
        runtime: 'fake',
        model: null,
        wait: AgentWait(
          asking: permission(now - 17000),
          unseen: const Unseen(UnseenKind.message, from: '@main', since: now),
        ),
      ),
      row(
        'bugfix',
        key: 4,
        runtime: 'team · fake',
        model: null,
        team: 4,
        wait: const AgentWait(
          stopped: now,
          unseen: Unseen(UnseenKind.replied, since: now),
        ),
      ),
      row(
        'tester',
        key: 5,
        runtime: 'fake',
        model: null,
        team: 4,
        wait: asking(8000),
      ),
      row('coder', key: 6, runtime: 'fake', model: null, team: 4),
    ];

    test('only a row whose detail leaves its state no room puts it under the '
        "detail, the others' column set without it", () {
      final folded = listRows(rows, limit: 5, height: height(39));
      expect(drawn(folded, width: 39, limit: 5), [
        '  main       fake  ◦ idle 4s',
        '  parser     fake  ◦ idle 13s        ✓',
        '  docs       fake  ● permission 17s  ←',
        '  bugfix     team · fake · 3 agents',
        '             ● tester: permission 8s  ✓',
      ]);
    });

    test("a team folds when its rows' lines, not its rows, pass the limit, "
        'so the width can fold it', () {
      expect(listRows(rows, limit: 6, height: height(116)), hasLength(6));
      // At 30 the states go under, two lines a row: the team folds.
      expect(listRows(rows, limit: 6, height: height(30)), hasLength(4));
    });

    test("a member's long name wraps behind the tree's │, and the last "
        "member's behind spaces", () {
      final named = [
        row('main', key: 1, runtime: 'fake', model: null),
        row('bugfix', key: 2, runtime: 'team · fake', model: null, team: 2),
        row(
          'tester-with-a-long-name',
          key: 3,
          runtime: 'fake',
          model: null,
          team: 2,
        ),
        row(
          'coder-with-a-long-name',
          key: 4,
          runtime: 'fake',
          model: null,
          team: 2,
        ),
      ];
      expect(drawn(teamRows(named, fold: false), width: 60, limit: 9), [
        '  main                  fake         ◦ idle 0s',
        '  bugfix                team · fake  ◦ idle 0s',
        '  ├─ tester-with-a-lon  fake         ◦ idle 0s',
        '  │  g-name',
        '  └─ coder-with-a-long  fake         ◦ idle 0s',
        '     -name',
      ]);
    });
  });

  test("a team's lead and member transcripts say so in their first line, and "
      'who opened them', () {
    final lead = childLine(
      name: 'bugfix',
      runtime: 'claude',
      team: 'bugfix',
      openedAt: now - 420000,
      model: 'Opus',
      now: now,
    );
    final member = childLine(
      name: 'tester',
      runtime: 'claude',
      team: 'bugfix',
      leadName: 'bugfix 2',
      openedAt: now - 360000,
      model: 'Sonnet',
      now: now,
    );
    expect(
      lead.name + lead.rest,
      'bugfix · team · claude · Opus · opened by @main 7m ago',
    );
    expect(
      member.name + member.rest,
      "tester · claude · Sonnet · bugfix 2's member · opened by @bugfix 2 6m "
      'ago',
    );
  });
}
