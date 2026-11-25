// `/resume` and the window's children (design CTUI-35 section 7, interface
// I11, ../chord docs/design/CHD-493.md): a child's session has its name
// before its title, one open now says `open now`, and Enter on that row
// picks the child, as the agents list does, instead of loading it a second
// time.
import 'package:chord/session/conversation.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/window_agents.dart';
import 'package:chord/ui/app/state.dart' show AgentOpened;
import 'package:chord/ui/pickers/picker.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../session/conversation_fake.dart';
import '../app/resume_window_test.dart' show fixture, open;

/// A child's record as the scan reads it: its name, a parent and a title.
SessionRecord _child(
  String id,
  String name,
  String title, {
  required String cwd,
  required num at,
}) => SessionRecord(
  path: '$id.jsonl',
  sessionId: id,
  agent: 'memory',
  cwd: cwd,
  lastUsedAt: at,
  prompt: 'first prompt of $name',
  parent: 'main-session',
  name: name,
  title: title,
);

void main() {
  _testerResumeChildren();
  test("a child's session has its name before its title or prompt", () {
    final sessions = earlierSessions([
      _child('a', 'parser', 'agentchild', cwd: 'w', at: 3),
      SessionRecord(
        path: 'b.jsonl',
        sessionId: 'b',
        agent: 'memory',
        cwd: 'w',
        lastUsedAt: 2,
        prompt: 'permission',
        parent: 'main-session',
        name: 'docs',
      ),
      const SessionRecord(
        path: 'c.jsonl',
        sessionId: 'c',
        agent: 'memory',
        cwd: 'w',
        lastUsedAt: 1,
        prompt: 'fix the tokenizer',
      ),
    ], agent: 'memory');
    expect(
      [for (final s in sessions) s.prompt],
      ['parser · agentchild', 'docs · permission', 'fix the tokenizer'],
    );
  });

  test("/resume's rows say which session is open now, as a child of this "
      'one, in a column only a row that says it opens', () {
    // ../chord tests/ui/pickers/picker_test.ts, the same two rows.
    final now = DateTime.utc(2026, 10, 5, 12).millisecondsSinceEpoch;
    EarlierSession session(String id, String at, String prompt) =>
        EarlierSession(
          resume: Resume(sessionId: id, cwd: '/work'),
          lastUsedAt: at,
          prompt: prompt,
        );
    final sessions = [
      session('s1', '2026-10-05T11:58:00.000Z', 'fix the build'),
      session('s2', '2026-10-02T12:00:00.000Z', 'add a test'),
    ];
    final choices = sessionChoices(sessions, now, open: {'s2'});
    expect(
      [for (final c in choices) c.label],
      [
        '2 minutes ago            fix the build',
        '3 days ago     open now  add a test',
      ],
    );
    // The title hangs after the column, for every row alike.
    expect(
      [for (final c in choices) c.label.substring(c.hang)],
      ['fix the build', 'add a test'],
    );
    expect(
      [for (final c in sessionChoices(sessions, now)) c.label],
      ['2 minutes ago  fix the build', '3 days ago     add a test'],
    );
    // A session open now in another directory keeps its directory column.
    final all = sessionChoices(sessions, now, directories: true, open: {'s1'});
    expect(all.first.label, '2 minutes ago  open now  /work  fix the build');
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('Enter on an open now row picks the child instead of resuming '
        'it at $size', (t) async {
      final f = await fixture(t, size), c = f.connection;
      final at = DateTime.now().millisecondsSinceEpoch - 60000;
      // parser, open behind main on a scripted session, whose id is s1.
      final parser = c.agents.openChild(
        const ChildInfo(
          id: 'id-parser',
          name: 'parser',
          runtime: 'memory',
          openedAt: 0,
        ),
        (emit, key) {
          c.fold.dispatch(AgentOpened(key));
          final session = ScriptedSession();
          return Conversation(
            ({required onTraffic, required cancellationToken}) async => session,
          )..listen(emit);
        },
      )!;
      for (
        var i = 0;
        i < 10 && c.fold.stateOf(parser)?.start.sessionId == null;
        i++
      ) {
        await t.pump(const Duration(milliseconds: 10));
      }
      expect(c.fold.stateOf(parser)?.start.sessionId, 's1');
      f.records.addAll([
        _child('s1', 'parser', 'agentchild', cwd: f.directory.path, at: at),
        _child('s2', 'docs', 'permission', cwd: f.directory.path, at: at),
      ]);
      await f.saved('fix the tokenizer', at: at - 2 * 60 * 60 * 1000);
      int loads() => f.agents.single.requests
          .where((request) => request['method'] == 'session/load')
          .length;
      final before = loads();

      await open(t, f);
      await t.pump();
      final rows = t.screen.lines;
      final first = rows.indexWhere((row) => row.contains('1. 1 minute ago'));
      expect(first, isNot(-1), reason: rows.join('\n'));
      // CHD-493's screen, the same inside the frame at either width, with
      // the two spaces between columns the original's sessionChoices puts
      // there (its own test reads `just now  open now  parser · agentchild`;
      // the design's mock has three after `1 minute ago`).
      expect(
        rows[first],
        contains('❯ 1. 1 minute ago  open now  parser · agentchild'),
      );
      expect(
        rows[first + 1],
        contains('  2. 1 minute ago            docs · permission'),
      );
      expect(
        rows[first + 2],
        contains('  3. 2 hours ago             Choice fix the tokenizer'),
      );
      expect(rows[first], startsWith('│ ❯ 1.'));
      expect(rows[first], endsWith('│'));

      await t.press('enter');
      await t.pump();
      expect(c.app.value.resumePicker, isNull);
      // parser in front, as the agents list picks it; main not resumed.
      expect(c.fold.front, parser);
      expect(c.agents.agents.picked, parser);
      expect(f.agents, hasLength(1));
      expect(loads(), before);
      expect(t.screen.lines.join('\n'), isNot(contains('Resume a session')));
    });
  }
}

void _testerResumeChildren() {
  group('CTUI-35 tester: resume child routing', () {
    test(
      'wide directory columns align by cells and unrelated open ids add no column',
      () {
        final sessions = [
          EarlierSession(
            resume: Resume(sessionId: 'a', cwd: '界🙂'),
            lastUsedAt: '1970-01-01T00:00:00Z',
            prompt: 'parser · title',
          ),
          EarlierSession(
            resume: Resume(sessionId: 'b', cwd: 'abc'),
            lastUsedAt: '1970-01-01T00:00:00Z',
            prompt: 'docs · title',
          ),
        ];
        final choices = sessionChoices(
          sessions,
          60000,
          directories: true,
          open: {'a'},
        );
        expect(
          choices
              .map(
                (choice) => cellWidth(choice.label.substring(0, choice.hang)),
              )
              .toSet(),
          hasLength(1),
        );
        expect(choices.first.label, contains('open now'));
        expect(choices.last.label, isNot(contains('open now')));
        expect(
          sessionChoices(
            sessions,
            60000,
            open: {'missing'},
          ).map((c) => c.label),
          sessionChoices(sessions, 60000).map((c) => c.label),
        );
      },
    );

    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'open child selection beats a late working-main refusal at $size',
        (t) async {
          final f = await fixture(t, size), c = f.connection;
          final child = c.agents.openChild(
            const ChildInfo(
              id: 'parser-id',
              name: '界🙂e\u0301',
              runtime: 'memory',
              openedAt: 0,
            ),
            (emit, key) {
              c.fold.dispatch(AgentOpened(key));
              return Conversation(
                ({required onTraffic, required cancellationToken}) async =>
                    ScriptedSession(),
              )..listen(emit);
            },
          )!;
          for (
            var i = 0;
            i < 20 && c.fold.stateOf(child)?.start.sessionId == null;
            i++
          ) {
            await t.pump(const Duration(milliseconds: 10));
          }
          expect(c.fold.stateOf(child)?.start.sessionId, 's1');
          f.records.add(
            _child(
              's1',
              '界🙂e\u0301',
              'saved title',
              cwd: f.directory.path,
              at: DateTime.now().millisecondsSinceEpoch,
            ),
          );
          await open(t, f);
          f.agents.single.holdPrompt = true;
          expect(c.conversation.send('late working turn'), isTrue);
          await t.pump();
          final requests = f.agents.single.requests.length;
          await t.press('enter');
          await t.pump();
          expect(c.fold.front, child);
          expect(c.app.value.resumePicker, isNull);
          expect(f.agents, hasLength(1));
          expect(
            f.agents.single.requests
                .skip(requests)
                .where(
                  (r) =>
                      r['method'] == 'session/load' ||
                      r['method'] == 'session/new',
                ),
            isEmpty,
          );
          expect(
            t.screen.lines.join('\n'),
            isNot(contains('Finish or cancel')),
          );
          f.agents.single.finishPrompt();
          await t.pump();
        },
      );
    }
  });
}
