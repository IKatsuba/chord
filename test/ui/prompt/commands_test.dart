import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/agents.dart';
import 'package:chord/ui/prompt/commands.dart';
import 'package:test/test.dart' hide completion;

acp.AvailableCommand command(String name, [String description = '']) =>
    acp.AvailableCommand.fromJson({'name': name, 'description': description});

void main() {
  test("a team's name is completed after /team show, run and stop, a run's "
      'after stop', () {
    expect(teamQuery('/team show bu'), (form: 'show', name: 'bu'));
    expect(teamQuery('/team edit bu'), isNull);
    expect(teamQuery('/team run '), (form: 'run', name: ''));
    expect(teamQuery('/team stop bugfix 2'), (form: 'stop', name: 'bugfix 2'));
    // Once the job starts, or for a form that takes no name, it is put away.
    expect(teamQuery('/team run bugfix fix it'), isNull);
    expect(teamQuery('/team new a'), isNull);
    expect(teamQuery('/team show'), isNull);
    const TeamNames teams = (
      teams: [(name: 'bugfix', broken: false), (name: 'triage', broken: true)],
      runs: ['bugfix', 'bugfix 2'],
    );
    List<String> names(List<CommandItem> items) => [
      for (final item in items) item.name,
    ];
    expect(names(teamItems('run', teams)), ['bugfix']);
    expect(names(teamItems('show', teams)), ['bugfix']);
    expect(names(teamItems('stop', teams)), ['bugfix', 'bugfix 2']);
    final show = teamItems('show', teams).first;
    final run = teamItems('run', teams).first;
    expect(itemLabel(show), 'bugfix');
    expect(completion(show), '/team show bugfix ');
    final shown = submitted('/team show bu', show) as LocalSubmitted;
    expect([shown.name, shown.args], ['team', 'show bugfix']);
    // A run's job is still to be typed, so Enter puts the name in the box.
    expect(
      (submitted('/team run bu', run) as CompleteSubmitted).text,
      '/team run bugfix ',
    );
  });

  test(
    'supported local catalog is original wording and omitted names stay reserved',
    () {
      final items = commandItems([
        command('model', 'collision'),
        command('new', 'reserved'),
        command('echo', '  first line\nmore text  '),
      ]);
      expect(items.map((i) => i.name), [
        'clear',
        'config',
        'context',
        'cost',
        'echo',
        'effort',
        'exit',
        'fast',
        'fork',
        'help',
        'mcp',
        'model',
        'new',
        'rename',
        'resume',
        'status',
        'team',
        'theme',
        'vim',
      ]);
      expect(
        items.singleWhere((i) => i.name == 'team').description,
        'Describe, keep and run teams of agents',
      );
      expect(
        items.singleWhere((i) => i.name == 'echo').description,
        'first line',
      );
      expect(
        items.singleWhere((i) => i.name == 'model').description,
        "Switch the agent's model",
      );
      expect(
        items.singleWhere((i) => i.name == 'resume').description,
        'Resume an earlier session, here or from another directory',
      );
      expect(
        items.singleWhere((i) => i.name == 'mcp').description,
        'Show the MCP servers chord passed to the agent',
      );
      expect(submitted('/mcp'), isA<LocalSubmitted>());
      expect(submitted('/rename x'), isA<LocalSubmitted>());
      expect(
        items.singleWhere((i) => i.name == 'new').description,
        'Open a new agent beside main and go to it; --name names it',
      );
      final typedNew = submitted('/new codex --name x') as LocalSubmitted;
      expect([typedNew.name, typedNew.args], ['new', 'codex --name x']);
      final picked =
          submitted('/new co', agentItems(['codex'], const []).single)
              as LocalSubmitted;
      expect([picked.name, picked.args], ['new', 'codex']);
      expect(completion(agentItems(['codex'], const []).single), '/new codex ');
      expect(itemLabel(agentItems(['codex'], const []).single), 'codex');
      expect(agentQuery('/new co'), 'co');
      expect(agentQuery('/new co --name'), isNull);
      // An agent's /fork is shadowed by chord's own, never offered twice.
      expect(
        commandItems([command('fork')]).where((i) => i.name == 'fork'),
        hasLength(1),
      );
      expect(submitted('/fork x'), isA<LocalSubmitted>());
      // An agent's /team is shadowed by chord's own, as /fork is.
      expect(
        commandItems([command('team')]).where((i) => i.name == 'team'),
        hasLength(1),
      );
      expect(submitted('/team list'), isA<LocalSubmitted>());
    },
  );
  test(
    'typed and highlighted submission share one parser and agent commands stay normal',
    () {
      expect(typedCommand(' /effort high  ')?.args, 'high');
      final local = submitted('/effort high') as LocalSubmitted;
      expect([local.name, local.args], ['effort', 'high']);
      final highlighted =
          submitted('/mo', const CommandItem('model', '')) as LocalSubmitted;
      expect([highlighted.name, highlighted.args], ['model', '']);
      expect(
        (submitted('/ec', const CommandItem('echo', '', local: false))
                as SendSubmitted)
            .text,
        '/echo',
      );
      expect(
        (submitted(' /echo two words ') as SendSubmitted).text,
        '/echo two words',
      );
      expect((submitted(' ordinary ') as SendSubmitted).text, 'ordinary');
      expect(completion(const CommandItem('model', '')), '/model ');
    },
  );
  test('queries stop at spaces, lines or text before slash', () {
    expect(commandQuery('/'), '');
    expect(commandQuery('/Mo'), 'Mo');
    for (final text in [' /model', '/model ', '/a\nb', 'x/model']) {
      expect(commandQuery(text), isNull);
    }
  });
  test(
    'fzf matches names and source order, with owner-approved casefold tie order',
    () {
      final items = commandItems([
        command('Z'),
        command('a'),
        command('A'),
        command('z'),
      ]);
      expect(
        items.map((i) => i.name).where((n) => ['A', 'a', 'Z', 'z'].contains(n)),
        ['A', 'a', 'Z', 'z'],
      );
      expect(compareCommandNames('É', 'é'), lessThan(0));
      expect(matchCommands(items, 'mo').first.name, 'model');
      expect(matchCommands(items, 'zzzz'), isEmpty);
      expect(
        matchCommands(items, '').map((i) => i.name),
        items.map((i) => i.name),
      );
    },
  );
  test('menu window moves only when highlight leaves it and wraps', () {
    expect(visibleRange(20, 4, 6, 0), (start: 0, end: 6));
    expect(visibleRange(20, 6, 6, 0), (start: 1, end: 7));
    expect(visibleRange(20, 0, 6, 10), (start: 0, end: 6));
    expect(moveHighlight(0, 8, -1), 7);
    expect(moveHighlight(7, 8, 1), 0);
    expect(menuRowLimit(40), 10);
    expect(menuRowLimit(24), 6);
  });

  group("/new's agents, as the original's agentItems gives them", () {
    ListedAgent listed(String name, AgentRunner from, {bool? found}) =>
        ListedAgent(
          name: name,
          title: name.toUpperCase(),
          start: name,
          from: from,
          found: found,
        );
    final catalog = [
      listed('reg', AgentRunner.npx),
      listed('gone', AgentRunner.cli, found: false),
      listed('here', AgentRunner.cli, found: true),
      listed('uv', AgentRunner.uvx),
      // Only the settings files define it: no title.
      const ListedAgent(
        name: 'mine',
        title: null,
        start: 'mine',
        from: AgentRunner.settings,
      ),
    ];
    List<(String, String?)> shown(List<CommandItem> items) => [
      for (final item in items) (item.name, item.description),
    ];

    test(
      'settings first, then found CLIs, the registry, and missing CLIs last, '
      'each kept in the given order and noted as chord agents notes it',
      () {
        final items = agentItems([
          'gone',
          'reg',
          'here',
          'uv',
          'mine',
          'typed',
        ], catalog);
        expect(shown(items), [
          ('mine', 'from settings'),
          // A name chord does not list, as `--agent-command` gives main's.
          ('typed', null),
          ('here', 'HERE'),
          ('reg', 'REG'),
          ('uv', 'UV'),
          ('gone', 'GONE · not on PATH'),
        ]);
        expect(items.every((item) => item.of == 'new'), isTrue);
      },
    );

    test(
      "main's unlisted runtime, given first, stays ahead of the settings'",
      () {
        expect(shown(agentItems(['typed', 'here', 'mine'], catalog)), [
          ('typed', null),
          ('mine', 'from settings'),
          ('here', 'HERE'),
        ]);
      },
    );

    test('offeredAgents lists its known names alone, once each, in its order, '
        'a missing CLI kept', () {
      expect(
        shown(
          agentItems(
            ['reg', 'here'],
            catalog,
            offered: ['gone', 'nobody', 'uv', 'gone'],
          ),
        ),
        [('gone', 'GONE · not on PATH'), ('uv', 'UV')],
      );
    });
  });
}
