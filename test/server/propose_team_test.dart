// propose_team: the proposal checked as a team file is, served while the
// person's box is open, the box's question and choices, and the file chord
// writes on a yes, never the agent; a change to a saved team, the person's
// "no", a withdrawn box, a failed write that leaves the old file whole,
// and a fork refused. The original's tests/server/tools_test.ts
// propose_team cases.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/server/tools.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/teams.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../fixtures/fake.dart';
import 'fake_window.dart';

const _team = {
  'name': 'bugfix',
  'description': 'Fixes a bug end to end',
  'lead': {'agent': 'fake', 'model': 'fake-large'},
  'members': [
    {
      'name': 'tester',
      'role': 'Writes the failing test',
      'agent': 'fake',
      'mode': 'acceptEdits',
      'instructions': 'Write it.\n',
    },
  ],
  'body': '# How bugfix works\n\nThe lead splits the job.',
};

/// A window whose team places are in a temporary project and config home.
({FakeWindow window, Caller caller, String project, String user}) _placed() {
  final root = Directory.systemTemp.createTempSync('chord-propose-');
  addTearDown(() => root.deleteSync(recursive: true));
  final project = p.join(root.path, 'work', '.chord', 'teams', 'bugfix.md');
  final user = p.join(root.path, 'config', 'chord', 'teams', 'bugfix.md');
  final window = FakeWindow()
    ..places = (
      agent: 'fake',
      project: (file: project, shown: '.chord/teams/bugfix.md'),
      user: (file: user, shown: '~/.config/chord/teams/bugfix.md'),
      saved: null,
    );
  return (
    window: window,
    caller: Caller(role: Role.person, key: 0, window: window),
    project: project,
    user: user,
  );
}

Future<ToolResult> _propose(Caller caller, Map<String, Object?> input) =>
    toolsOf(caller).firstWhere((t) => t.name == 'propose_team').call(input);

void main() {
  group('CTUI-37 tester: proposal save boundaries', () {
    test(
      'replacing a user team writes that target and leaves project absent',
      () async {
        final placed = _placed();
        final before = checkProposal(
          {..._team, 'description': 'before'},
          const ['fake'],
        ).team!;
        File(placed.user)
          ..createSync(recursive: true)
          ..writeAsStringSync(teamText(before));
        placed.window.places = (
          agent: 'fake',
          project: placed.window.places.project,
          user: placed.window.places.user,
          saved: (
            file: placed.user,
            shown: '~/.config/chord/teams/bugfix.md',
            team: before,
          ),
        );
        placed.window.picks = (_, _, _) async => 'replace';
        final result = await _propose(placed.caller, _team);
        expect(result.isError, isFalse);
        expect(result.text, 'Saved to ~/.config/chord/teams/bugfix.md.');
        expect(File(placed.project).existsSync(), isFalse);
        expect(
          File(placed.user).readAsStringSync(),
          teamText(checkProposal(_team, const ['fake']).team!),
        );
      },
    );

    test(
      'a failed replacement keeps the actual old file and removes temporaries',
      () async {
        final placed = _placed();
        final before = checkProposal(
          {..._team, 'description': 'before'},
          const ['fake'],
        ).team!;
        final file = File(placed.project)
          ..createSync(recursive: true)
          ..writeAsStringSync(teamText(before));
        placed.window.places = (
          agent: 'fake',
          project: placed.window.places.project,
          user: placed.window.places.user,
          saved: (
            file: placed.project,
            shown: '.chord/teams/bugfix.md',
            team: before,
          ),
        );
        placed.window.picks = (_, _, _) async => 'replace';
        final dir = p.dirname(placed.project);
        expect(Process.runSync('chmod', ['500', dir]).exitCode, 0);
        try {
          final result = await _propose(placed.caller, _team);
          expect(result.isError, isTrue);
          expect(
            result.text,
            startsWith('.chord/teams/bugfix.md was not saved: '),
          );
          expect(file.readAsStringSync(), teamText(before));
          expect(
            Directory(dir).listSync().map((entry) => p.basename(entry.path)),
            ['bugfix.md'],
          );
        } finally {
          Process.runSync('chmod', ['700', dir]);
        }
      },
      testOn: 'posix',
    );

    test(
      'two answers for one name save in answer order with distinct receipts',
      () async {
        final placed = _placed();
        final held = <Completer<String?>>[];
        placed.window.picks = (_, _, _) {
          final answer = Completer<String?>();
          held.add(answer);
          return answer.future;
        };
        final first = _propose(placed.caller, {
          ..._team,
          'description': 'first',
        });
        final second = _propose(placed.caller, {
          ..._team,
          'description': 'second',
        });
        addTearDown(() async {
          for (final answer in held) {
            if (!answer.isCompleted) answer.complete(null);
          }
          await Future.wait([first, second]);
        });
        for (var i = 0; i < 100 && held.length < 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(held, hasLength(2));
        held[1].complete('project');
        expect((await second).isError, isFalse);
        held[0].complete('project');
        expect((await first).isError, isFalse);
        expect(
          parseTeam('bugfix', File(placed.project).readAsStringSync(), const [
            'fake',
          ]).team!.description,
          'first',
        );
        expect(
          placed.window.calls
              .where((call) => call.pending)
              .map((call) => call.asked)
              .toSet(),
          hasLength(2),
        );
      },
    );
  });

  test("its schema is the original's, as its SDK lists it", () {
    final window = FakeWindow();
    final spec = toolsOf(
      Caller(role: Role.person, key: 0, window: window),
    ).firstWhere((t) => t.name == 'propose_team');
    expect(
      spec.inputSchema,
      jsonDecode(
        File(
          p.join(
            portPackageDir(),
            'test',
            'fixtures',
            'propose_team_schema.json',
          ),
        ).readAsStringSync(),
      ),
    );
    expect(
      spec.description,
      startsWith('Proposes a team for the person to save'),
    );
  });

  test('a new team is served while the box asks, then saved for this '
      'project on a yes, the agent told where', () async {
    final placed = _placed();
    placed.window.picks = (_, _, _) async => 'project';
    final result = await _propose(placed.caller, _team);
    expect(
      (result.text, result.isError),
      ('Saved to .chord/teams/bugfix.md.', false),
    );
    expect(result.structured, {
      'proposal': 'new',
      'files': {
        'project': '.chord/teams/bugfix.md',
        'user': '~/.config/chord/teams/bugfix.md',
      },
      'saved': '.chord/teams/bugfix.md',
    });
    final (title, detail, options, save) = placed.window.questions.single;
    expect(title, 'Team(bugfix)');
    final checked = checkProposal(_team, const ['fake']).team!;
    expect(detail, teamText(checked));
    expect(
      [for (final o in options) (o.optionId, o.name, o.kind)],
      [
        ('project', 'Yes, for this project', 'allow_once'),
        ('user', 'Yes, for every project', 'allow_always'),
        ('change', 'No, tell fake what to change', 'reject_once'),
      ],
    );
    expect(save.question, 'Save team bugfix?');
    expect(save.escape, 'tell fake what to change');
    expect(save.files, {
      'project': '.chord/teams/bugfix.md',
      'user': '~/.config/chord/teams/bugfix.md',
    });
    expect(File(placed.project).readAsStringSync(), teamText(checked));
    // Served while it waited, then with the answer, under one asked.
    final [shown, answered] = placed.window.calls;
    expect(shown.pending, isTrue);
    expect(shown.answer, {
      'proposal': 'new',
      'files': {
        'project': '.chord/teams/bugfix.md',
        'user': '~/.config/chord/teams/bugfix.md',
      },
    });
    expect(save.asked, shown.asked);
    expect(answered.asked, shown.asked);
    expect(answered.tool, ChordTool.proposeTeam);
  });

  test('for every project, the file goes beside the user settings', () async {
    final placed = _placed();
    placed.window.picks = (_, _, _) async => 'user';
    final result = await _propose(placed.caller, _team);
    expect(result.text, 'Saved to ~/.config/chord/teams/bugfix.md.');
    expect(File(placed.user).existsSync(), isTrue);
    expect(File(placed.project).existsSync(), isFalse);
  });

  test('a change to a saved team asks to replace it, and on a no says the '
      'person will say what to change, nothing written', () async {
    final placed = _placed();
    final before = checkProposal(
      {..._team, 'description': 'The old one'},
      const ['fake'],
    ).team!;
    placed.window
      ..places = (
        agent: 'fake',
        project: placed.window.places.project,
        user: placed.window.places.user,
        saved: (
          file: placed.window.places.project.file,
          shown: '.chord/teams/bugfix.md',
          team: before,
        ),
      )
      ..picks = (_, _, _) async => 'change';
    final result = await _propose(placed.caller, _team);
    expect(
      result.text,
      'The person did not save it; they will say what to change.',
    );
    expect(result.structured, {
      'proposal': 'change',
      'files': {'project': '.chord/teams/bugfix.md'},
      'before': before.toJson(),
      'saved': false,
    });
    final (_, _, options, save) = placed.window.questions.single;
    expect(
      [for (final o in options) (o.optionId, o.name)],
      [
        ('replace', 'Yes, in .chord/teams/bugfix.md'),
        ('change', 'No, tell fake what to change'),
      ],
    );
    expect(save.question, 'Replace team bugfix?');
    expect(save.files, isEmpty);
    expect(File(placed.project).existsSync(), isFalse);
  });

  test('a failed write leaves the old file whole and nothing beside it, '
      'and says which file', () async {
    final placed = _placed();
    final dir = Directory(p.dirname(placed.project))
      ..createSync(recursive: true);
    // A directory where the file goes: the rename over it fails.
    Directory(placed.project).createSync();
    File(p.join(dir.path, 'review.md')).writeAsStringSync('old');
    placed.window.picks = (_, _, _) async => 'project';
    final result = await _propose(placed.caller, _team);
    expect(result.isError, isTrue);
    expect(result.text, startsWith('.chord/teams/bugfix.md was not saved: '));
    expect(dir.listSync().map((e) => p.basename(e.path)).toList()..sort(), [
      'bugfix.md',
      'review.md',
    ]);
    expect(File(p.join(dir.path, 'review.md')).readAsStringSync(), 'old');
  });

  test("a team that fails the check is refused with its first problem, and "
      'a withdrawn box saves nothing', () async {
    final placed = _placed();
    final refused = await _propose(placed.caller, {..._team, 'name': 'Bugfix'});
    expect(
      (refused.text, refused.isError),
      (
        'the name Bugfix must be a lowercase letter, then up to 23 of a-z, '
            '0-9 and -',
        true,
      ),
    );
    expect(placed.window.questions, isEmpty);
    final withdrawn = await _propose(placed.caller, _team);
    expect(
      withdrawn.text,
      'The person was not asked to the end; nothing was saved',
    );
    expect(File(placed.project).existsSync(), isFalse);
  });

  test('a fork is refused, and asked nothing', () async {
    final placed = _placed();
    final fork = Caller(
      role: Role.person,
      key: 3,
      window: placed.window,
      fork: true,
    );
    final result = await _propose(fork, _team);
    expect(
      (result.text, result.isError),
      ('This tool works only from main and its agents, not from a fork.', true),
    );
    expect(placed.window.questions, isEmpty);
  });
}
