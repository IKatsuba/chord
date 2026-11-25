// /team in the window: in the slash list, its picker of the saved teams with
// a broken file's problem, Enter putting a run's start in the draft, the
// names it offers after `/team show `, a saved team shown, and its refusals
// under the command. The original's tests/ui/teams/Teams_test.tsx and the
// prompt's command tests, at 120x40 and 80x24.
import 'dart:async';
import 'dart:io';

import 'package:chord/acp/connection.dart';
import 'package:chord/cli.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/team_command.dart' show TeamListing;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/window_fold.dart' show mainKey;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:chord/teams.dart' show parseTeam;
import 'package:chord/ui/transcript/tools/proposal.dart' show instructionLines;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../fixtures/fake.dart' show portPackageDir;
import 'editor_window_test.dart' show EditorTerminal, settle;

/// The window over a main that never starts, its host in a project holding
/// the fake's team `bugfix` and a broken `triage`.
Future<StartConnection> _window(
  WidgetTester t,
  Size size, {
  Map<String, String> more = const {},
  Future<TeamListing?> Function(AgentsHost host)? listTeams,
}) async {
  final project = Directory.systemTemp.createTempSync('chord-team-window-');
  addTearDown(() => project.deleteSync(recursive: true));
  final teams = Directory(p.join(project.path, '.chord', 'teams'))
    ..createSync(recursive: true);
  File(p.join(teams.path, 'bugfix.md')).writeAsStringSync(
    File(
      p.join(
        portPackageDir(),
        'test',
        'fixtures',
        'teams',
        'fake',
        'bugfix.md',
      ),
    ).readAsStringSync(),
  );
  File(p.join(teams.path, 'triage.md')).writeAsStringSync('# no frontmatter');
  for (final MapEntry(:key, :value) in more.entries) {
    File(p.join(teams.path, '$key.md')).writeAsStringSync(value);
  }
  final hanging = Completer<Agent>();
  final connection = StartConnection(
    command: 'fake',
    cwd: '.',
    agent: 'fake',
    owner: Owned(),
    open:
        ({
          required command,
          env,
          required cwd,
          required onTraffic,
          required onPermission,
          relay,
          cancellationToken,
        }) => hanging.future,
  )..start();
  addTearDown(connection.close);
  addTearDown(() {
    hanging.future.ignore();
    hanging.completeError(StateError('over'));
  });
  connection.window = AgentsHost(
    runtimeNames: const ['fake'],
    startupOf: (_) => null,
    openChildSession:
        (
          runtime,
          start, {
          required initial,
          chordServer,
          required onTraffic,
          required cancellationToken,
        }) => Future.error(StateError('no runtime in a test')),
    agents: connection.agents,
    opened: (key) => connection.fold.dispatch(AgentOpened(key)),
    closed: (key, front) => connection.fold.dispatch(SessionClosed(key, front)),
    cwd: project.path,
  );
  connection.fold.heard(mainKey, const Connected('m', AgentState.empty));
  await t.pumpWidget(
    TranscriptWindow(
      launch: const Launch(
        name: 'fake',
        agent: null,
        agentCommand: 'fake',
        version: '0.0.1',
        directory: '.',
      ),
      connection: connection,
      terminal: EditorTerminal(),
      listTeams: listTeams,
    ),
    size: size,
  );
  await settle(t);
  return connection;
}

/// The window's team reads, each held until the test lets it come back.
final class _Held {
  final reads = <Completer<TeamListing?>>[];

  Future<TeamListing?> read(AgentsHost host) {
    final read = Completer<TeamListing?>();
    reads.add(read);
    return read.future;
  }
}

/// The teams as the host reads them now.
Future<TeamListing> _listing(StartConnection connection) async =>
    (await (connection.window as AgentsHost).listTeams())!;

/// Whether the teams picker is open.
bool _pickerShown(WidgetTester t) =>
    _rows(t).any((row) => row.contains('1. bugfix'));

/// The fake's team file, whose instructions every test team shares.
final _bugfixFile = File(
  p.join(portPackageDir(), 'test', 'fixtures', 'teams', 'fake', 'bugfix.md'),
).readAsStringSync();

/// How many rows the fake team's instructions take under /team show at
/// [size]: the window less the transcript's inset, less the gutter.
int _instructionRows(Size size) {
  final team = parseTeam('bugfix', _bugfixFile, const ['fake']).team!;
  return instructionLines(team, size.width - 4 - 5).length;
}

/// Lets a file read under way come back and the window draw it.
Future<void> _read(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await t.pump();
  }
}

String _screen(WidgetTester t) => t.screen.lines.join('\n');

List<String> _rows(WidgetTester t) => [
  for (final line in t.screen.lines) line.trimRight(),
];

/// The picker's first two rows as the original draws them, by the window's
/// width: numbered, a row too wide kept at both ends around `...`.
List<String> _pickerRows(Size size) => size.width == 120
    ? [
        '│ ❯ 1. bugfix  3 agents · fake  this project               '
            '...s a bug end to end — a failing test first, then the fix. │',
        '│   2. triage  ✗ not read: no frontmatter between --- lines  '
            '.chord/teams/triage.md                                    │',
      ]
    : [
        '│ ❯ 1. bugfix  3 agents  this project  ... a failing test first, '
            'then the fix. │',
        '│   2. triage  ✗ not read: no frontmatter between --- lines        '
            '            │',
      ];

void main() {
  group('CTUI-37 tester: async team picker lifetime', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('late picker read after unmount stays inert at $size', (
        t,
      ) async {
        final held = _Held();
        final connection = await _window(t, size, listTeams: held.read);
        await t.type('/team');
        await t.press('enter');
        await settle(t);
        expect(held.reads, hasLength(1));
        final listing = await _listing(connection);
        await t.pumpWidget(const SizedBox(), size: size);
        held.reads.single.complete(listing);
        await _read(t);
        expect(t.screen.text, isEmpty);
      });

      for (final replacement in ['m', 'resumed']) {
        testWidgets(
          'late completion after session $replacement cannot restore old names at $size',
          (t) async {
            final held = _Held();
            final connection = await _window(t, size, listTeams: held.read);
            await t.type('/team show ');
            await settle(t);
            expect(held.reads, hasLength(1));
            final listing = await _listing(connection);
            connection.fold.heard(mainKey, const Cleared());
            connection.fold.heard(
              mainKey,
              Connected(replacement, AgentState.empty),
            );
            await settle(t);
            held.reads.first.complete(listing);
            await _read(t);
            expect(_screen(t), isNot(contains('bugfix')));
            await t.press('ctrl+u');
            await settle(t);
            await t.type('/team show ');
            await settle(t);
            expect(held.reads, hasLength(2));
            held.reads.last.complete(listing);
            await _read(t);
            expect(_screen(t), contains('bugfix'));
          },
        );
      }

      testWidgets('tiny resize records the CTUI-97 selection reset at $size', (
        t,
      ) async {
        await _window(t, size);
        await t.type('/team');
        await t.press('enter');
        await _read(t);
        await t.press('down');
        await settle(t);
        expect(_screen(t), contains('❯ 2. triage'));
        for (final room in [
          const Size(0, 1),
          const Size(1, 1),
          const Size(30, 12),
          size,
        ]) {
          await t.resize(room);
        }
        await settle(t);
        expect(_screen(t), contains('fix triage'));
        // CTUI-97: preserve today's remount reset and stale hint until
        // the follow-up; the lead explicitly deferred this parity slip.
        expect(_screen(t), contains('❯ 1. bugfix'));
        await t.press('enter');
        await settle(t);
        expect(_pickerShown(t), isFalse);
        expect(_screen(t), contains('/team run bugfix'));
        expect(_screen(t), isNot(contains('/team run triage')));
        expect(_rows(t), isNot(contains(' › /team')));
      });
    }
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets("/team show folds a body with a fence holding a blank line "
        "and inline code holding __ as its Markdown draws them at $size", (
      t,
    ) async {
      const body = '# Fenced\n\n```\nfirst\n\nthird\n```\n\nKeep `a__b` whole.';
      final team = _bugfixFile.replaceFirst(
        RegExp(r'\n---\n[\s\S]*$'),
        '\n---\n\n$body\n',
      );
      await _window(t, size, more: {'fenced': team});
      await t.type('/team show fenced');
      await t.press('enter');
      await _read(t);
      final rows = _rows(t);
      expect(rows, contains('      Fenced'));
      // The fence is one block: its blank row does not end the preview's
      // block, and its third line is not in the preview at all.
      expect(rows.any((row) => row.contains('third')), isFalse);
      expect(rows.any((row) => row.contains('a__b')), isFalse);
      // Heading 1, the fence's box 5, the paragraph 1, a blank row between
      // each: 9 rows; the instructions, a blank row and those, against a
      // blank row and the preview.
      final keep = size.height >= 30 ? 3 : 1;
      final whole = _instructionRows(size) + 1 + 9;
      expect(
        rows,
        contains('      … +${whole - 1 - keep} lines (ctrl+o to expand)'),
      );
      await t.press('ctrl+o');
      await settle(t);
      // Opened, the body whole: the fence's blank row kept inside its
      // box, and a__b as written.
      final opened = _rows(t);
      expect(opened.any((row) => row.contains('third')), isTrue);
      expect(opened.any((row) => row.contains('Keep a__b whole.')), isTrue);
    });

    for (final (crossed, replaced) in [
      ('/clear', 'm'),
      ('a resume', 'earlier'),
    ]) {
      testWidgets("/team's listing coming back after $crossed of main opens "
          'no picker in the session after it at $size', (t) async {
        final held = _Held();
        final connection = await _window(t, size, listTeams: held.read);
        await t.type('/team');
        await t.press('enter');
        await settle(t);
        expect(held.reads, hasLength(1));
        // Both replace main's session the same way: it is cleared, and
        // another comes up, new or the one picked.
        connection.fold.heard(mainKey, const Cleared());
        connection.fold.heard(mainKey, Connected(replaced, AgentState.empty));
        await settle(t);
        held.reads.single.complete(await _listing(connection));
        await _read(t);
        expect(_pickerShown(t), isFalse);
        expect(_rows(t), isNot(contains(' › /team')));
        // Asked again in the session now, it opens.
        await t.type('/team');
        await t.press('enter');
        await settle(t);
        held.reads.last.complete(await _listing(connection));
        await _read(t);
        expect(_pickerShown(t), isTrue);
        expect(_rows(t), contains(' › /team'));
      });
    }

    testWidgets('of two /team listings, only the later one opens the '
        'picker, whichever comes back first, at $size', (t) async {
      final held = _Held();
      final connection = await _window(t, size, listTeams: held.read);
      for (var i = 0; i < 2; i++) {
        await t.type('/team');
        await t.press('enter');
        await settle(t);
        if (_pickerShown(t)) await t.press('escape');
      }
      expect(held.reads, hasLength(2));
      final listing = await _listing(connection);
      held.reads.last.complete(listing);
      await _read(t);
      expect(_pickerShown(t), isTrue);
      await t.press('escape');
      await settle(t);
      held.reads.first.complete(listing);
      await _read(t);
      // The earlier one, come back last, is dropped: no picker again.
      expect(_pickerShown(t), isFalse);
    });

    testWidgets("an earlier read of the team names coming back after a later "
        'one leaves the later names at $size', (t) async {
      final held = _Held();
      final connection = await _window(
        t,
        size,
        more: {'gone': _bugfixFile},
        listTeams: held.read,
      );
      await t.type('/team show ');
      await settle(t);
      // Out of a name and back to one: a second read.
      await t.press('backspace');
      await t.type(' ');
      await settle(t);
      expect(held.reads, hasLength(2));
      final now = await _listing(connection);
      // The later read: `gone` deleted since the earlier one.
      held.reads.last.complete((
        teams: [
          for (final listed in now.teams)
            if (listed.found.name != 'gone') listed,
        ],
        runs: now.runs,
        dirs: now.dirs,
      ));
      await _read(t);
      expect(_screen(t), contains('bugfix'));
      expect(_screen(t), isNot(contains('gone')));
      held.reads.first.complete(now);
      await _read(t);
      expect(_screen(t), contains('bugfix'));
      expect(_screen(t), isNot(contains('gone')));
    });

    testWidgets('/team is in the slash list with its words at $size', (
      t,
    ) async {
      await _window(t, size);
      await t.type('/te');
      await settle(t);
      expect(_screen(t), contains('/team'));
      expect(_screen(t), contains('Describe, keep and run teams of agents'));
    });

    testWidgets('/team lists the saved teams, a broken file with its problem, '
        'and Enter puts a run of the highlighted team in the draft at '
        '$size', (t) async {
      await _window(t, size);
      await t.type('/team');
      await t.press('enter');
      await _read(t);
      final screen = _screen(t);
      expect(screen, contains('Teams'));
      expect(screen, contains('Saved for this project in .chord/teams.'));
      expect(
        _rows(
          t,
        ).where((row) => row.contains('. bugfix') || row.contains('. triage')),
        _pickerRows(size),
      );
      expect(screen, contains('Enter to hand it a job'));
      // The command stands while the picker is open.
      expect(_rows(t), contains(' › /team'));
      await t.press('enter');
      await settle(t);
      expect(_screen(t), isNot(contains('Teams ')));
      expect(_screen(t), contains('/team run bugfix'));
      // And goes with it, as the original's.
      expect(_rows(t), isNot(contains(' › /team')));
    });

    testWidgets('Esc closes the teams picker at $size', (t) async {
      await _window(t, size);
      await t.type('/team');
      await t.press('enter');
      await _read(t);
      expect(_screen(t), contains('Enter to hand it a job'));
      await t.press('esc');
      await settle(t);
      expect(_screen(t), isNot(contains('Enter to hand it a job')));
      expect(_rows(t), isNot(contains(' › /team')));
    });

    testWidgets('/team show offers the teams it can run by name at $size', (
      t,
    ) async {
      await _window(t, size);
      await t.type('/team show ');
      await _read(t);
      await t.type('b');
      await settle(t);
      final screen = _screen(t);
      expect(screen, contains('bugfix'));
      expect(screen, isNot(contains('triage')));
    });

    testWidgets("/team show draws a saved team: its file, its description, "
        'its table and its body folded at $size', (t) async {
      await _window(t, size);
      await t.type('/team show bugfix');
      // The highlighted name runs the command on it.
      await t.press('enter');
      await _read(t);
      final rows = _rows(t);
      expect(rows, contains(' › /team show bugfix'));
      expect(rows, contains('   ⎿  bugfix · .chord/teams/bugfix.md'));
      // As the original's: its width is the window's less four, less the
      // gutter's five.
      if (size.width == 80) {
        final coder = rows.indexWhere((row) => row.startsWith('      coder'));
        expect(rows.sublist(coder, coder + 2), [
          '      coder   fake · fake-large  plan         Writes the fix, in the '
              'files',
          '                                              the lead names',
        ]);
        expect(rows, contains('      How bugfix works'));
        expect(rows, contains('      … +27 lines (ctrl+o to expand)'));
      } else {
        expect(rows, contains('      How bugfix works'));
        expect(
          rows,
          contains(
            "      2. tester writes a test that fails for the bug's own "
            'reason, in tests/.',
          ),
        );
        expect(rows, contains('      … +24 lines (ctrl+o to expand)'));
      }
      // Rendered as Markdown: the heading bold and underlined.
      final heading = rows.indexOf('      How bugfix works');
      final style = t.screen.styleAt(6, heading);
      expect((style.isBold, style.isUnderline), (true, true));
    });

    testWidgets('/team refusals are said under the command at $size', (
      t,
    ) async {
      await _window(t, size);
      await t.type('/team stop bugfix');
      await t.press('enter');
      await _read(t);
      expect(
        _screen(t),
        contains('No run named bugfix is open · the list under the prompt'),
      );
      await t.type('/team edit bugfix');
      await t.press('enter');
      await _read(t);
      // Under the typed line, as the original draws what /team says.
      expect(
        _rows(t),
        contains(
          '   ⎿  /team has no edit; it takes list, new, show, run or stop',
        ),
      );
      await t.type('/team show triage');
      await t.press('enter');
      await _read(t);
      expect(
        _screen(t),
        contains('.chord/teams/triage.md is not a team chord can run:'),
      );
    });
  }
}
