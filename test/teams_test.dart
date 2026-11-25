import 'dart:io';

import 'package:chord/teams.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures/fake.dart';

const _runtimes = ['claude', 'codex'];

/// The original's example team, `bugfix`, as its tests read it.
final _example = File(
  p.join(portPackageDir(), 'test', 'fixtures', 'teams', 'bugfix.md'),
).readAsStringSync();

/// A config home and a project, both temporary; nothing reads the home
/// directory of whoever runs the tests.
({String configHome, String cwd, String project, String user}) _place() {
  final root = Directory.systemTemp.createTempSync('chord-teams-');
  addTearDown(() => root.deleteSync(recursive: true));
  final configHome = p.join(root.path, 'config');
  final cwd = p.join(root.path, 'work');
  final dirs = teamDirs(configHome: configHome, cwd: cwd);
  return (
    configHome: configHome,
    cwd: cwd,
    project: dirs.project,
    user: dirs.user!,
  );
}

void _write(String dir, String name, String text) {
  Directory(dir).createSync(recursive: true);
  File(p.join(dir, name)).writeAsStringSync(text);
}

Team _teamOf(String text, [String name = 'bugfix']) {
  final read = parseTeam(name, text, _runtimes);
  expect(read.problem, isNull);
  return read.team!;
}

String? _problemOf(String text, [String name = 'bugfix']) =>
    parseTeam(name, text, _runtimes).problem;

/// [text] with the first match of [pattern] replaced, as JavaScript's
/// `replace` with a regular expression.
String _replace(String text, Pattern pattern, String replacement) =>
    text.replaceFirst(pattern, replacement);

final _descriptionLine = RegExp(r'^description: .*$', multiLine: true);

void main() {
  group('tester team file boundaries', () {
    test(
      'discovery rereads edits and deletions without cached fallback',
      () async {
        final place = _place();
        Future<List<FoundTeam>> read() => findTeams(
          configHome: place.configHome,
          cwd: place.cwd,
          runtimes: _runtimes,
        );
        _write(place.user, 'bugfix.md', _example);
        _write(place.project, 'bugfix.md', '# broken');
        final [broken] = await read();
        expect(broken.place, TeamPlace.project);
        expect(broken.hides, isTrue);
        expect(broken.team, isNull);
        expect(broken.problem, 'no frontmatter between --- lines');
        final revised = _replace(
          _example,
          _descriptionLine,
          'description: Changed since the last read',
        );
        _write(place.project, 'bugfix.md', revised);
        final [changed] = await read();
        expect(changed.team!.description, 'Changed since the last read');
        await File(teamFile(place.project, 'bugfix')).delete();
        final [fallback] = await read();
        expect(fallback.place, TeamPlace.user);
        expect(fallback.hides, isFalse);
        expect(fallback.team, _teamOf(_example));
        await File(teamFile(place.user, 'bugfix')).delete();
        expect(await read(), isEmpty);
      },
    );

    test('discovery preserves member name problems from saved files', () async {
      final place = _place();
      for (final (name, escaped, problem) in [
        ('quote', r'a\"b', 'must not contain the character "'),
        (
          'control',
          r'a\u001bb',
          'must not contain the control character U+001B',
        ),
      ]) {
        _write(
          place.project,
          '$name.md',
          _example.replaceFirst('name: tester', 'name: "$escaped"'),
        );
        final found = await findTeams(
          configHome: place.configHome,
          cwd: place.cwd,
          runtimes: _runtimes,
        );
        final file = found.singleWhere((f) => f.name == name);
        expect(file.team, isNull);
        expect(file.problem, 'members.0.name: $problem');
      }
    });

    test('proposal efforts survive writing and a member-only change', () {
      final original = _teamOf(_example);
      final proposal = {
        ...original.frontmatter(),
        'name': 'bugfix',
        'body': original.body,
        'lead': {...original.lead.toMap(), 'effort': 'high'},
        'members': [
          for (final member in original.members)
            {...member.toMap(), if (member.name == 'coder') 'effort': 'xhigh'},
        ],
      };
      final checked = checkProposal(proposal, _runtimes);
      expect(checked.problem, isNull);
      expect(checked.team!.lead.effort, 'high');
      expect(checked.team!.members[1].effort, 'xhigh');
      expect(_teamOf(teamText(checked.team!)), checked.team);
      final changes = teamChanges(original, checked.team!);
      expect(changes.lead, RowChange.changed);
      expect(changes.members, {'coder': RowChange.changed});
    });

    test('a failed overwrite preserves the existing target bytes', () async {
      final place = _place();
      final file = teamFile(place.project, 'bugfix');
      _write(place.project, 'bugfix.md', _example);
      final chmod = Process.runSync('chmod', ['500', place.project]);
      expect(chmod.exitCode, 0);
      try {
        await expectLater(
          saveTeam(file, _teamOf(_example)),
          throwsA(isA<FileSystemException>()),
        );
        expect(File(file).readAsStringSync(), _example);
        expect(
          Directory(place.project).listSync().map((e) => p.basename(e.path)),
          ['bugfix.md'],
        );
      } finally {
        Process.runSync('chmod', ['700', place.project]);
      }
    }, testOn: 'posix');
  });

  test("teams are in the project's .chord/teams and in teams/ beside the "
      "user's settings", () {
    final dirs = teamDirs(configHome: '/c', cwd: '/w');
    expect(dirs.project, p.join('/w', '.chord', 'teams'));
    expect(dirs.user, p.join('/c', 'chord', 'teams'));
    expect(teamDirs(configHome: null, cwd: '/w').user, isNull);
  });

  test('the example team reads as its frontmatter and body', () {
    final team = _teamOf(_example);
    expect(team.description, startsWith('Fixes a bug end to end'));
    expect(
      team.lead,
      TeamLead(
        agent: 'claude',
        model: 'opus',
        mode: 'default',
        instructions: team.lead.instructions,
      ),
    );
    expect(team.members.map((member) => member.name), [
      'tester',
      'coder',
      'reviewer',
    ]);
    expect(team.members[1].mode, 'auto');
    expect(
      team.members[2].instructions,
      'Read `git diff` and the test. Say what is wrong, or that nothing is.\n'
      'Never edit a file.\n',
    );
    expect(team.body, startsWith('# How bugfix works\n\n1. The lead'));
    expect(team.body, endsWith('does not need every step.'));
  });

  test('the example team is read back equal after a write', () async {
    final place = _place();
    final team = _teamOf(_example);
    final file = teamFile(place.project, 'bugfix');
    await saveTeam(file, team);
    final text = File(file).readAsStringSync();
    expect(text, startsWith('---\ndescription:'));
    expect(_teamOf(text), team);
    expect(teamText(_teamOf(text)), text);
    expect(Directory(place.project).listSync().map((e) => p.basename(e.path)), [
      'bugfix.md',
    ]);
  });

  test('a write that fails leaves the old file whole and nothing beside '
      'it', () async {
    final place = _place();
    final file = teamFile(place.project, 'bugfix');
    _write(place.project, 'bugfix.md', _example);
    Directory(p.join(place.project, 'review.md')).createSync();
    await expectLater(
      saveTeam(p.join(place.project, 'review.md'), _teamOf(_example)),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(file).readAsStringSync(), _example);
    expect(
      Directory(
        place.project,
      ).listSync().map((e) => p.basename(e.path)).toList()..sort(),
      ['bugfix.md', 'review.md'],
    );
  });

  test("the project's team wins a name clash, and says it hides the "
      "user's", () async {
    final place = _place();
    final other = _replace(
      _example,
      _descriptionLine,
      'description: The user one',
    );
    _write(place.project, 'bugfix.md', _example);
    _write(place.user, 'bugfix.md', other);
    _write(place.user, 'review.md', other);
    _write(place.user, 'notes.txt', 'not a team');
    final found = await findTeams(
      configHome: place.configHome,
      cwd: place.cwd,
      runtimes: _runtimes,
    );
    expect(
      [for (final f in found) (f.name, f.file, f.place, f.hides)],
      [
        ('bugfix', p.join(place.project, 'bugfix.md'), TeamPlace.project, true),
        ('review', p.join(place.user, 'review.md'), TeamPlace.user, false),
      ],
    );
    expect(found.map((f) => f.team?.description), [
      _teamOf(_example).description,
      'The user one',
    ]);
  });

  test('teams sort by code unit, and a directory named .md is not '
      'one', () async {
    final place = _place();
    for (final name in ['b.md', 'Z.md', 'a-b.md', 'ab.md']) {
      _write(place.project, name, _example);
    }
    Directory(p.join(place.project, 'dir.md')).createSync();
    final found = await findTeams(
      configHome: place.configHome,
      cwd: place.cwd,
      runtimes: _runtimes,
    );
    expect(found.map((f) => f.name), ['Z', 'a-b', 'ab', 'b']);
  });

  test('a team file that starts with a BOM reads as the same team', () async {
    expect(_teamOf('\uFEFF$_example'), _teamOf(_example));
    final place = _place();
    _write(place.project, 'bugfix.md', '\uFEFF$_example');
    final [found] = await findTeams(
      configHome: place.configHome,
      cwd: place.cwd,
      runtimes: _runtimes,
    );
    expect(found.problem, isNull);
    expect(found.team, _teamOf(_example));
  });

  test('a team file with CRLF line ends reads as the same team but its '
      'line ends', () {
    final team = _teamOf(_example.replaceAll('\n', '\r\n'));
    expect(team.members.map((m) => m.name), ['tester', 'coder', 'reviewer']);
    expect(team.description, _teamOf(_example).description);
  });

  test('an empty frontmatter block is not a file without one', () {
    expect(_problemOf('# no frontmatter'), 'no frontmatter between --- lines');
    expect(
      _problemOf('\uFEFF# no frontmatter'),
      'no frontmatter between --- lines',
    );
    // As the original: an empty frontmatter, or one JavaScript reads as
    // false, is an empty mapping.
    expect(_problemOf('---\n---\n# How it works'), 'description is missing');
    expect(_problemOf('---\n0\n---\nx'), 'description is missing');
    expect(
      _problemOf('---\nhello\n---\nx'),
      'the frontmatter is not a YAML mapping',
    );
  });

  test("a frontmatter that does not parse names Dart yaml's message", () {
    expect(
      _problemOf('---\na: 1\na: 2\n---\nx'),
      'the frontmatter is not valid YAML (Duplicate mapping key.)',
    );
  });

  test('no team directory at all finds no teams', () async {
    final place = _place();
    expect(
      await findTeams(
        configHome: place.configHome,
        cwd: place.cwd,
        runtimes: _runtimes,
      ),
      isEmpty,
    );
  });

  test('a broken file is listed with its first problem in zod path '
      'words', () async {
    final place = _place();
    _write(
      place.user,
      'triage.md',
      _example.replaceFirst('    agent: codex\n', ''),
    );
    final [found] = await findTeams(
      configHome: place.configHome,
      cwd: place.cwd,
      runtimes: _runtimes,
    );
    expect(
      (found.name, found.file, found.place, found.hides, found.problem),
      (
        'triage',
        p.join(place.user, 'triage.md'),
        TeamPlace.user,
        false,
        'members.1.agent is missing',
      ),
    );
  });

  test('a file that cannot be read says so in the OS words', () async {
    final place = _place();
    _write(place.project, 'locked.md', _example);
    Process.runSync('chmod', ['000', p.join(place.project, 'locked.md')]);
    final [found] = await findTeams(
      configHome: place.configHome,
      cwd: place.cwd,
      runtimes: _runtimes,
    );
    expect(found.problem, 'cannot be read (Permission denied)');
  }, testOn: 'posix');

  test('the check refuses what part 1 refuses, naming the first problem', () {
    final cases = <(String, String)>[
      ('# no frontmatter', 'no frontmatter between --- lines'),
      ('---\nlead: [1\n---\nx', 'the frontmatter is not valid YAML'),
      ('---\n- 1\n---\nx', 'the frontmatter is not a YAML mapping'),
      (_replace(_example, _descriptionLine, ''), 'description is missing'),
      (
        _replace(_example, _descriptionLine, 'description: ""'),
        'description: too small',
      ),
      (
        _replace(_example, _descriptionLine, r'description: "two\nlines"'),
        'description: must be one line',
      ),
      (
        _example.replaceFirst(
          '  agent: claude\n  model: opus\n',
          '  model: opus\n',
        ),
        'lead.agent is missing',
      ),
      (
        _example.replaceFirst('agent: codex', 'agent: codx'),
        'members.1.agent: chord knows no runtime named codx',
      ),
      (
        _example.replaceFirst(
          '  mode: default\n',
          '  mode: default\n  colour: red\n',
        ),
        'lead.colour is not a key a team has',
      ),
      (
        _example.replaceFirst('name: coder', 'name: tester'),
        'members.1.name: tester is named twice',
      ),
      (
        _example.replaceFirst('name: coder', 'name: main'),
        'members.1.name: main is taken',
      ),
      (
        _example.replaceFirst('name: coder', 'name: bugfix'),
        'members.1.name: bugfix is taken',
      ),
      (
        _example.replaceFirst('name: coder', 'name: Coder'),
        'members.1.name: must be a lowercase letter',
      ),
      (
        _example
            .replaceFirst(
              RegExp(r'^ {6}Make the failing[\s\S]*?why\.\n', multiLine: true),
              '',
            )
            .replaceFirst(
              '    instructions: |\n  - name: reviewer',
              '  - name: reviewer',
            ),
        'members.1.instructions is missing',
      ),
      (
        _example.replaceFirst(
          RegExp(r'^ {4}role: Writes the fix.*$', multiLine: true),
          '    role: ${'x' * 81}',
        ),
        'members.1.role: too big',
      ),
      (
        _example.replaceFirst(
          RegExp(r'members:[\s\S]*?^---$', multiLine: true),
          'members: []\n---',
        ),
        'members: too small',
      ),
      (
        _example.replaceFirst(
          RegExp(r'^# How bugfix works[\s\S]*', multiLine: true),
          '\n',
        ),
        'the body is empty',
      ),
    ];
    for (final (text, problem) in cases) {
      expect(_problemOf(text), startsWith(problem));
    }
  });

  // Each recorded from the original's checkTeam under bun: zod's first
  // issue, in its words and order.
  test("the check's order and words are zod's", () {
    final team = _teamOf(_example);
    final fm = team.frontmatter();
    final m = team.members[0].toMap();
    String? check(Object? frontmatter) =>
        checkTeam('bugfix', frontmatter, team.body, _runtimes).problem;
    Map<String, Object?> with_(Map<String, Object?> extra) => {...fm, ...extra};
    final nine = [
      for (var i = 0; i < 9; i++) {...m, 'name': 'm$i'},
    ]..[1] = ({...m, 'name': 'm1'}..remove('agent'));
    final cases = <(Object?, String)>[
      (
        with_({'members': nine}),
        'members: too big: expected array to have <=8 items',
      ),
      (
        with_({
          'members': [
            m,
            {...m, 'agent': 'x'},
            m,
          ],
        }),
        'members.1.agent: chord knows no runtime named x',
      ),
      (
        with_({
          'members': [
            m,
            m,
            {...m, 'agent': 'x'},
          ],
        }),
        'members.2.agent: chord knows no runtime named x',
      ),
      (
        with_({
          'members': [
            m,
            {...m, 'name': 'b'},
            {...m, 'name': 'b'},
            m,
          ],
        }),
        'members.2.name: b is named twice',
      ),
      (
        {'Zeta': 1, ...fm, 'description': 5},
        'description: invalid input: expected string, received number',
      ),
      (with_({'Zeta': 1, 'Alpha': 2}), 'unrecognized keys: "zeta", "alpha"'),
      (with_({'Zeta': 1}), 'unrecognized key: "zeta"'),
      (
        with_({
          'lead': {'colour': 1, 'agent': 'nope'},
        }),
        'lead.agent: chord knows no runtime named nope',
      ),
      (
        with_({
          'members': {'a': 1},
        }),
        'members: invalid input: expected array, received object',
      ),
      (
        with_({'lead': 'x'}),
        'lead: invalid input: expected object, received string',
      ),
      (
        with_({
          'lead': {'agent': 'claude', 'model': null},
        }),
        'lead.model: invalid input: expected string, received null',
      ),
      (
        with_({'description': true}),
        'description: invalid input: expected string, received boolean',
      ),
      (
        with_({'description': []}),
        'description: invalid input: expected string, received array',
      ),
      (
        with_({'description': null}),
        'description: invalid input: expected string, received null',
      ),
      (
        with_({'description': 'x' * 201}),
        'description: too big: expected string to have <=200 characters',
      ),
      (
        with_({'description': 'x\n' * 201}),
        'description: too big: expected string to have <=200 characters',
      ),
      (with_({'description': 'a\rb'}), 'description: must be one line'),
      (
        {'description': 'a\nb', 'members': fm['members']},
        'description: must be one line',
      ),
      (
        with_({
          'lead': {'agent': ''},
        }),
        'lead.agent: too small: expected string to have >=1 characters',
      ),
      (
        with_({
          'members': [
            {...m, 'name': ''},
          ],
        }),
        'members.0.name: must be a lowercase letter, then up to 15 of a-z, '
            '0-9 and -',
      ),
      (
        with_({
          'members': [
            {...m, 'name': 'a' * 17},
          ],
        }),
        'members.0.name: must be a lowercase letter, then up to 15 of a-z, '
            '0-9 and -',
      ),
      (
        with_({
          'members': [
            {...m, 'role': ''},
          ],
        }),
        'members.0.role: too small: expected string to have >=1 characters',
      ),
      (
        with_({
          'members': [
            {...m, 'name': 'chord'},
          ],
        }),
        'members.0.name: chord is taken',
      ),
      (
        with_({
          'members': ['x'],
        }),
        'members.0: invalid input: expected object, received string',
      ),
      (
        with_({
          'members': [<String, Object?>{}],
        }),
        'members.0.name is missing',
      ),
      (
        with_({
          'members': [
            {...m, 'Foo': 1, 'bar': 2},
          ],
        }),
        'members.0.Foo is not a key a team has',
      ),
      ([1], 'the frontmatter is not a YAML mapping'),
      (null, 'the frontmatter is not a YAML mapping'),
    ];
    for (final (frontmatter, problem) in cases) {
      expect(check(frontmatter), problem, reason: '$frontmatter');
    }
  });

  test('a team holds at most eight members', () {
    final team = _teamOf(_example);
    final fm = team.frontmatter();
    final members = [
      for (var i = 0; i < 9; i++) {...team.members[0].toMap(), 'name': 'm$i'},
    ];
    expect(
      checkTeam(
        'bugfix',
        {...fm, 'members': members},
        team.body,
        _runtimes,
      ).problem,
      'members: too big: expected array to have <=8 items',
    );
    expect(
      checkTeam(
        'bugfix',
        {...fm, 'members': members.sublist(0, 8)},
        team.body,
        _runtimes,
      ).team,
      isNotNull,
    );
  });

  test("a team's name is the file's, and some names are not a team's", () {
    expect(_problemOf(_example, 'main'), 'the name main is taken');
    expect(_problemOf(_example, 'chord'), 'the name chord is taken');
    expect(
      _problemOf(_example, 'Bug_fix'),
      'the name Bug_fix must be a lowercase letter, then up to 23 of a-z, '
      '0-9 and -',
    );
    expect(_problemOf(_example, 'a' * 25), startsWith('the name'));
    expect(_problemOf(_example, 'fix-2'), isNull);
  });

  test("a lead's team part names its tools, the other runs, its "
      'instructions, the members and the body', () {
    final team = _teamOf(_example);
    final part = teamPart(
      'bugfix',
      team,
      const LeadRole(lead: 'bugfix 2', others: ['bugfix', 'review']),
      '/src/app',
    );
    expect(part.team, 'bugfix');
    expect(part.member, isNull);
    expect(
      part.text,
      startsWith(
        'You are the lead of team bugfix, running as bugfix 2: a long-lived '
        'agent chord opened for main',
      ),
    );
    expect(part.text, contains('You work in /src/app'));
    expect(part.text, contains('open_agent {member, prompt}'));
    expect(part.text, contains('by these names: bugfix and review.'));
    expect(part.text, contains('Your instructions:\nRead the job'));
    expect(
      part.text,
      contains(
        '- coder: Writes the fix, in the files the lead names (codex · '
        'gpt-5.3-codex · auto)',
      ),
    );
    expect(part.text, endsWith('How the team works:\n${team.body}'));
    expect(
      teamPart(
        'bugfix',
        team,
        const LeadRole(lead: 'bugfix', others: []),
        '/a',
      ).text,
      contains('No other run of a team is open in this session.'),
    );
  });

  test("a member's team part names its lead, the other members it reaches, "
      'its role and its instructions', () {
    final team = _teamOf(_example);
    final part = teamPart(
      'bugfix',
      team,
      MemberRole(member: team.members[0], lead: 'bugfix 2'),
      '/src/app',
    );
    expect(part.member, 'tester');
    expect(
      part.text,
      startsWith(
        'You are tester, a member of team bugfix, opened by its lead, '
        'bugfix 2.',
      ),
    );
    expect(
      part.text,
      contains('reaches your lead, bugfix 2, and coder and reviewer, the team'),
    );
    expect(part.text, contains('You open no long-lived agents.'));
    expect(
      part.text,
      contains('Your role: Writes the failing test, then proves the fix'),
    );
    expect(part.text, contains('Your instructions:\nWrite the smallest test'));
  });

  const proposal = {
    'name': 'bugfix',
    'description': 'Fixes a bug end to end',
    'lead': {'agent': 'claude', 'model': 'opus'},
    'members': [
      {
        'name': 'tester',
        'role': 'Writes the failing test',
        'agent': 'claude',
        'mode': 'acceptEdits',
        'instructions': 'Write it.',
      },
    ],
    'body': '\n# How bugfix works\n',
  };

  test('a proposal is checked as its file would be, its name with it', () {
    final checked = checkProposal(proposal, _runtimes);
    expect(checked.name, 'bugfix');
    expect(
      checked.team,
      const Team(
        description: 'Fixes a bug end to end',
        lead: TeamLead(agent: 'claude', model: 'opus'),
        members: [
          TeamMember(
            name: 'tester',
            role: 'Writes the failing test',
            agent: 'claude',
            mode: 'acceptEdits',
            instructions: 'Write it.',
          ),
        ],
        body: '# How bugfix works',
      ),
    );
    expect(
      checkProposal({...proposal}..remove('name'), _runtimes).problem,
      'name is missing',
    );
    expect(
      checkProposal({...proposal, 'body': ' '}, _runtimes).problem,
      'the body is empty',
    );
    expect(
      checkProposal({...proposal, 'members': []}, _runtimes).problem,
      'members: too small: expected array to have >=1 items',
    );
    expect(
      checkProposal({
        ...proposal,
        'members': [
          {...(proposal['members']! as List)[0] as Map, 'name': 'bugfix'},
        ],
      }, _runtimes).problem,
      'members.0.name: bugfix is taken',
    );
  });

  test("a team's changes are the lead's, and each member's by its name", () {
    final before = checkProposal(proposal, _runtimes).team!;
    final after = Team(
      description: before.description,
      lead: const TeamLead(agent: 'claude', model: 'sonnet'),
      members: const [
        TeamMember(
          name: 'coder',
          role: 'Writes the fix',
          agent: 'codex',
          instructions: 'Fix it.',
        ),
      ],
      body: before.body,
    );
    final changes = teamChanges(before, after);
    expect(changes.lead, RowChange.changed);
    expect(changes.members, {
      'coder': RowChange.added,
      'tester': RowChange.removed,
    });
    final same = teamChanges(before, before);
    expect(same.lead, isNull);
    expect(same.members, isEmpty);
  });

  test("a team's lead and members take an effort, which the team part "
      'lists and a change counts', () {
    final text = _example
        .replaceFirst(
          '  model: opus\n  mode: default\n',
          '  model: opus\n  effort: high\n  mode: default\n',
        )
        .replaceFirst(
          'model: gpt-5.3-codex\n',
          'model: gpt-5.3-codex\n    effort: xhigh\n',
        );
    final team = _teamOf(text);
    expect(team.lead.effort, 'high');
    expect(team.members[1].effort, 'xhigh');
    expect(team.members[0].effort, isNull);
    expect(_teamOf(teamText(team)), team);
    expect(
      teamPart(
        'bugfix',
        team,
        const LeadRole(lead: 'bugfix', others: []),
        '/a',
      ).text,
      contains(
        '- coder: Writes the fix, in the files the lead names (codex · '
        'gpt-5.3-codex · xhigh · auto)',
      ),
    );
    expect(
      _problemOf(text.replaceFirst('effort: high', 'effort: ""')),
      startsWith('lead.effort: too small'),
    );
    final changed = teamChanges(
      team,
      Team(
        description: team.description,
        lead: TeamLead(
          agent: team.lead.agent,
          model: team.lead.model,
          effort: 'medium',
          mode: team.lead.mode,
          instructions: team.lead.instructions,
        ),
        members: team.members,
        body: team.body,
      ),
    );
    expect(changed.lead, RowChange.changed);
    expect(changed.members, isEmpty);
  });

  test('quoted team and member names are refused (CHD-519)', () {
    final bad = _example.replaceFirst(
      'name: tester',
      '''name: 'a "b @notes.md suffix\'''',
    );
    const problem = 'members.0.name: must not contain the character "';
    expect(_problemOf(bad), problem);
    expect(_problemOf(_example, 'a"b'), 'must not contain the character "');
    final team = _teamOf(_example);
    expect(
      checkProposal({
        ...team.frontmatter(),
        'name': 'bugfix',
        'members': [
          {...team.members[0].toMap(), 'name': 'a"b'},
        ],
        'body': team.body,
      }, _runtimes).problem,
      problem,
    );
  });

  test('control characters in team and member names are refused '
      '(CHD-519)', () {
    for (final (name, code) in [
      ('a\n@notes.md suffix', '000A'),
      ('a\rline', '000D'),
      ('a\ttab', '0009'),
      ('a\u0000nul', '0000'),
      ('a\u007Fdel', '007F'),
    ]) {
      final escaped = name
          .replaceAll('\n', r'\n')
          .replaceAll('\r', r'\r')
          .replaceAll('\t', r'\t')
          .replaceAll('\u0000', r'\u0000')
          .replaceAll('\u007F', r'\u007f');
      final member = _example.replaceFirst('name: tester', 'name: "$escaped"');
      final problem = 'must not contain the control character U+$code';
      expect(_problemOf(_example, name), problem);
      expect(_problemOf(member), 'members.0.name: $problem');
    }
  });

  test("the repository's own team files load", () {
    final dir = p.join(portPackageDir(), '.chord', 'teams');
    for (final name in ['architects', 'ship']) {
      final read = parseTeam(
        name,
        File(p.join(dir, '$name.md')).readAsStringSync(),
        _runtimes,
      );
      expect(read.problem, isNull, reason: name);
      expect(read.team!.members, isNotEmpty);
      expect(_teamOf(teamText(read.team!), name), read.team, reason: name);
    }
  });

  test("YAML 1.1 scalars read as the original's npm yaml 2.9.1 reads them, "
      'and zod words what is no string', () {
    // YAML 1.2's core schema on both sides: yes/no/on/off, 1_000,
    // sexagesimal and unquoted dates stay strings.
    final team = _teamOf(
      '---\n'
      'description: 2024-01-02\n'
      'lead:\n'
      '  agent: claude\n'
      '  model: yes\n'
      '  effort: on\n'
      '  mode: 1:20\n'
      'members:\n'
      '  - name: tester\n'
      '    role: 1_000\n'
      '    agent: codex\n'
      '    model: 2001-12-14t21:59:43.10-05:00\n'
      '    effort: off\n'
      '    mode: 190:20:30\n'
      '    instructions: no\n'
      '---\n'
      '# How it works\n',
    );
    expect(team.description, '2024-01-02');
    expect(
      team.lead,
      const TeamLead(agent: 'claude', model: 'yes', effort: 'on', mode: '1:20'),
    );
    final member = team.members.single;
    expect(member.role, '1_000');
    expect(member.model, '2001-12-14t21:59:43.10-05:00');
    expect(member.effort, 'off');
    expect(member.mode, '190:20:30');
    expect(member.instructions, 'no');

    // What npm yaml reads as no string, and zod's word for its type.
    for (final (scalar, received) in [
      ('0755', 'number'),
      ('0o755', 'number'),
      ('0x1F', 'number'),
      ('010', 'number'),
      ('1e3', 'number'),
      ('True', 'boolean'),
      ('~', 'null'),
      ('.nan', 'NaN'),
      ('.inf', 'Infinity'),
      ('-.Inf', '-Infinity'),
    ]) {
      expect(
        _problemOf(
          '---\ndescription: d\nlead:\n  agent: claude\n  model: $scalar\n'
          'members:\n  - name: tester\n    role: r\n    agent: codex\n'
          '    instructions: i\n---\nx\n',
        ),
        'lead.model: invalid input: expected string, received $received',
        reason: scalar,
      );
    }
  });

  group('tester: YAML scalar persistence boundaries', () {
    test('quoted scalar-looking descriptions survive save and reload', () {
      for (final scalar in [
        'yes',
        'no',
        'on',
        'off',
        '0755',
        '1_000',
        '1:20',
        '~',
        '2024-01-02',
        '.nan',
        '.inf',
        '-.Inf',
      ]) {
        final team = _teamOf(
          _replace(_example, _descriptionLine, 'description: "$scalar"'),
        );
        expect(team.description, scalar, reason: scalar);
        final reread = _teamOf(teamText(team));
        expect(reread.description, scalar, reason: scalar);
        expect(reread, team, reason: scalar);
      }
    });

    test('nonfinite member modes name the value at the nested field', () {
      for (final (scalar, received) in [
        ('.NaN', 'NaN'),
        ('+.INF', 'Infinity'),
        ('-.inf', '-Infinity'),
      ]) {
        final text = _example.replaceFirst(
          'mode: acceptEdits',
          'mode: $scalar',
        );
        expect(
          _problemOf(text),
          'members.0.mode: invalid input: expected string, received $received',
          reason: scalar,
        );
      }
    });
  });

  test('andList says one, two and more names as Intl.ListFormat does', () {
    expect(andList(['a']), 'a');
    expect(andList(['a', 'b']), 'a and b');
    expect(andList(['a', 'b', 'c']), 'a, b, and c');
  });
}
