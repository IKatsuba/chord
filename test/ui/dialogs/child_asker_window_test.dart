// A box a child asks while it is in front names it, as the original's
// App.tsx passes `child: childShown` to the permission box and `picked:
// childShown` to askerParts for the form, question and link boxes
// (src/ui/dialogs/asker.ts, Asker.tsx): `docs asks`, the name bold in its
// colour, against the original's `agents` capture after ctrl+x a
// (docs/design/evidence/CTUI-35/children/orig-120x40-agents-attend.*).
import 'dart:async';
import 'dart:io';

import 'package:chord/acp/connection.dart';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/cli.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/questions.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/session/window_agents.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/window_fold.dart' show mainKey;
import 'package:chord/ui/dialogs/asker.dart';
import 'package:chord/ui/dialogs/permission_prompt.dart';
import 'package:chord/ui/dialogs/permission_scroll.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../session/conversation_fake.dart';
import '../app/editor_window_test.dart' show EditorTerminal, settle;

/// The window over a main that never starts, with `parser` and `docs`
/// open behind it on scripted sessions, `docs` in the agents' second
/// colour as the fake's run gave it; [emit] reports an event as child
/// [key]'s conversation would.
typedef _Agents = ({
  StartConnection connection,
  int parser,
  int docs,
  void Function(int key, ConversationEvent event) emit,
});

Future<_Agents> _window(WidgetTester t, Size size) async {
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
  );
  final emits = <int, void Function(ConversationEvent)>{};
  int open(String name, int colour) => connection.agents.openChild(
    ChildInfo(
      id: 'id-$name',
      name: name,
      runtime: 'fake',
      openedAt: 0,
      colour: colour,
    ),
    (emit, key) {
      emits[key] = emit;
      connection.fold.dispatch(AgentOpened(key));
      final session = ScriptedSession();
      return Conversation(
        ({required onTraffic, required cancellationToken}) async => session,
      )..listen(emit);
    },
  )!;
  connection.fold.heard(mainKey, const Connected('m', AgentState.empty));
  final parser = open('parser', 0);
  final docs = open('docs', 1);
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
    ),
    size: size,
  );
  await settle(t);
  return (
    connection: connection,
    parser: parser,
    docs: docs,
    emit: (key, event) => emits[key]!(event),
  );
}

/// The fake's write request, as its `askPermission` sends it
/// (../chord/tests/fixtures/fake_agent/scenarios/permissions.ts), with the
/// three options the original's capture shows.
model.PermissionWait _writeNotes() => model.PermissionWait(
  'ask',
  toolCallId: 'write-1',
  title: 'Write notes.txt',
  kind: 'edit',
  locations: [
    acp.ToolCallLocation.fromJson({'path': 'notes.txt'}),
  ],
  content: [
    acp.ToolCallContent.fromJson({
      'type': 'diff',
      'path': 'notes.txt',
      'newText': 'notes\n',
    }),
  ],
  options: [
    for (final (id, name, kind) in const [
      ('allow', 'Allow', 'allow_once'),
      ('always', 'Always allow', 'allow_always'),
      ('deny', 'Deny', 'reject_once'),
    ])
      acp.PermissionOption.fromJson({
        'optionId': id,
        'name': name,
        'kind': kind,
      }),
  ],
);

/// Child [key] asks [wait], in a running turn or [between] turns.
void _ask(
  _Agents w,
  int key,
  model.TranscriptAction Function(String turn) asked, {
  bool between = false,
}) {
  if (!between) {
    w.emit(key, const Transcribed(model.PromptAction('turn', 'go on', 0)));
  }
  w.emit(key, Transcribed(asked('turn')));
}

/// A cell as a capture or the screen draws it.
typedef _Cell = ({String char, Color? fg, Color? bg, bool bold, bool dim});

/// [lines]' cells, row by row, their SGR codes read as the terminal
/// would: what one row sets holds into the next.
List<List<_Cell>> _parse(List<String> lines) {
  final rows = <List<_Cell>>[];
  Color? fg;
  Color? bg;
  var bold = false;
  var dim = false;
  for (final line in lines) {
    final cells = <_Cell>[];
    rows.add(cells);
    void add(String text) {
      for (final rune in text.runes) {
        cells.add((
          char: String.fromCharCode(rune),
          fg: fg,
          bg: bg,
          bold: bold,
          dim: dim,
        ));
      }
    }

    var at = 0;
    for (final match in RegExp(r'\x1b\[([0-9;]*)m').allMatches(line)) {
      add(line.substring(at, match.start));
      at = match.end;
      final codes = [
        for (final code in match[1]!.split(';')) int.tryParse(code) ?? 0,
      ];
      for (var i = 0; i < codes.length; i++) {
        switch (codes[i]) {
          case 0:
            (fg, bg, bold, dim) = (null, null, false, false);
          case 1:
            bold = true;
          case 2:
            dim = true;
          case 22:
            (bold, dim) = (false, false);
          case 39:
            fg = null;
          case 49:
            bg = null;
          case 38 || 48 when codes[i + 1] == 2:
            final colour = RgbColor(codes[i + 2], codes[i + 3], codes[i + 4]);
            if (codes[i] == 38) {
              fg = colour;
            } else {
              bg = colour;
            }
            i += 4;
        }
      }
    }
    add(line.substring(at));
  }
  return rows;
}

/// The original paints default text white where the port leaves it to the
/// terminal, and a blank's colour and weight never show: neither is a
/// difference.
_Cell _seen(_Cell cell) => cell.char == ' '
    ? (char: ' ', fg: null, bg: cell.bg, bold: false, dim: false)
    : cell.fg == const RgbColor(255, 255, 255)
    ? (char: cell.char, fg: null, bg: cell.bg, bold: cell.bold, dim: cell.dim)
    : cell;

/// Row [y] of the screen as cells.
List<_Cell> _row(WidgetTester t, int y) => [
  for (final (x, rune) in t.screen.lines[y].runes.indexed)
    () {
      final style = t.screen.styleAt(x, y);
      return (
        char: String.fromCharCode(rune),
        fg: style.fg,
        bg: style.bg,
        bold: style.isBold,
        dim: style.isDim,
      );
    }(),
];

const _capture =
    'docs/design/evidence/CTUI-35/children/orig-120x40-agents-attend';

/// The original's permission box after ctrl+x a, its 13 rows from `╭`.
List<String> _originalBox(String extension) {
  final lines = File('$_capture.$extension').readAsLinesSync();
  final top = lines.indexWhere(
    (line) => line.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '').startsWith('╭─'),
  );
  return lines.sublist(top, top + 13);
}

/// [row], one of the original's 120-column box rows, [width] wide.
String _narrowed(String row, int width) => switch (row[0]) {
  '╭' => '╭${'─' * (width - 2)}╮',
  '╰' => '╰${'─' * (width - 2)}╯',
  _ => '│${row.substring(1, row.length - 1).trimRight().padRight(width - 2)}│',
};

const _docs = RgbColor(0xc4, 0x9c, 0xff);
const _permission = RgbColor(177, 185, 249);

void main() {
  _testerAskerBoundaries();
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    final width = size.width.toInt();

    testWidgets('a child in front opens its permission box with `docs asks`, '
        'row for row as the original, at $size', (t) async {
      final w = await _window(t, size);
      _ask(
        w,
        w.docs,
        (turn) => model.PermissionRequestedAction(turn, _writeNotes()),
      );
      await t.pump();
      await t.press('ctrl+x a');
      await t.pump();
      await t.pump();
      expect(w.connection.fold.front, w.docs);
      final lines = t.screen.lines;
      final asks = lines.indexWhere((line) => line.startsWith('│ docs asks'));
      expect(asks, isNot(-1), reason: lines.join('\n'));
      final box = lines.sublist(asks - 1, asks + 12);
      expect(box, [
        for (final row in _originalBox('txt')) _narrowed(row, width),
      ]);
      // Above the gap, the prompt, the status line and three agents, as
      // in the original's capture.
      expect(asks + 11, lines.length - 9);
      // The row's styles: `docs` bold in its colour, ` asks` plain.
      final original = _parse(_originalBox('ansi'))[1].map(_seen).toList();
      final row = _row(t, asks).map(_seen).toList();
      expect(row.take(11).toList(), original.take(11).toList());
      expect(row[2].fg, _docs);
      expect(row[2].bold, isTrue);
      expect(row[7], (char: 'a', fg: null, bg: null, bold: false, dim: false));
      expect(row.last.fg, _permission);
      if (width == 120) {
        // The whole box, cell for cell, styles included.
        final whole = _parse(_originalBox('ansi'));
        for (var y = 0; y < whole.length; y++) {
          // The framework's Picker bolds its highlighted row, `1. Allow`,
          // where the original draws it in the colour alone: a difference
          // of every choice box, not of who asks, left out here.
          _Cell unbolded(_Cell cell) => y == 7
              ? (
                  char: cell.char,
                  fg: cell.fg,
                  bg: cell.bg,
                  bold: false,
                  dim: cell.dim,
                )
              : cell;
          expect(
            _row(t, asks - 1 + y).map(_seen).map(unbolded).toList(),
            whole[y].map(_seen).toList(),
            reason: 'box row $y',
          );
        }
      }
    });

    testWidgets('main in front draws its own request with no asker row, '
        'at $size', (t) async {
      final w = await _window(t, size);
      final old = w.connection.app.value;
      w.connection.app.value = AppState(
        start: old.start,
        transcript: model.Transcript(
          entries: old.transcript.entries,
          turn: model.AwaitingPermission('t', 0, [_writeNotes()]),
        ),
      );
      await t.pump();
      await t.pump();
      expect(t.screen, shows('Write notes.txt'));
      expect(t.screen, isNot(shows('asks')));
    });

    testWidgets('a child in front names itself on its form, link and '
        'question boxes, bold in its colour, at $size', (t) async {
      for (final (asked, heading) in [
        (
          const model.FormWait(
            'form',
            'Name it',
            schema: {
              'type': 'object',
              'properties': {
                'name': {'type': 'string', 'title': 'Name'},
              },
            },
          ),
          'docs asks for input',
        ),
        (
          const model.LinkWait('link', 'Sign in', 'https://example.com/in'),
          'docs asks you to open a link',
        ),
        (
          const model.FormWait(
            'ask',
            'Which?',
            questions: Questions(QuestionsAgent.claude, [
              Question(
                id: 'q',
                text: 'Which language?',
                options: [
                  QuestionOption(value: 'dart', title: 'Dart'),
                  QuestionOption(value: 'go', title: 'Go'),
                ],
                multiSelect: false,
                required: true,
              ),
            ]),
          ),
          'docs asks you a question',
        ),
      ]) {
        final w = await _window(t, size);
        _ask(
          w,
          w.docs,
          (turn) => model.ElicitationRequestedAction(turn, asked),
        );
        await t.pump();
        await t.press('ctrl+x a');
        await t.pump();
        await t.pump();
        final lines = t.screen.lines;
        final y = lines.indexWhere((line) => line.startsWith('│ docs asks'));
        expect(y, isNot(-1), reason: lines.join('\n'));
        expect(lines[y], startsWith('│ $heading'));
        expect(t.screen, isNot(shows('fake asks')));
        final row = _row(t, y);
        // As the original's AskerHeading: the heading bold in the
        // permission colour, the child's name bold in its own.
        for (var x = 2; x < 6; x++) {
          expect((row[x].fg, row[x].bold), (_docs, true), reason: 'cell $x');
        }
        expect((row[7].fg, row[7].bold), (_permission, true));
      }
    });
  }

  group('the box alone', () {
    const picked = (name: 'docs', colour: _docs, team: null);

    testWidgets('a child between turns is named, not main', (t) async {
      await t.pumpWidget(
        PermissionPrompt(
          wait: _writeNotes(),
          windowRows: 40,
          maxRows: 40,
          scroll: PermissionScroll(),
          onChoose: (_) {},
          onReject: () {},
          picked: picked,
          between: true,
        ),
        size: const Size(80, 24),
      );
      expect(t.screen.lines[2], startsWith('│ docs asks · between turns'));
      expect(t.screen, isNot(shows('main asks')));
      expect(t.screen.styleAt(12, 2).isDim, isTrue);
    });

    test('the pinned rows count the child row', () {
      final wait = _writeNotes();
      expect(
        permissionPinned(wait, 80, picked: picked),
        permissionPinned(wait, 80) + 1,
      );
      expect(
        permissionPinned(wait, 80, picked: picked, between: true),
        permissionPinned(wait, 80, between: true),
      );
    });

    test('a member names its team after it, dim', () {
      final spans = pickedSpans((
        name: 'docs',
        colour: _docs,
        team: 'bugfix',
      ), const Style(fg: _permission, bold: true));
      expect([for (final span in spans) span.text], ['docs', ' · bugfix']);
      expect(spans[0].style, const Style(fg: _docs, bold: true));
      expect(spans[1].style, const Style(fg: _permission, dim: true));
      expect(
        pickedText((name: 'docs', colour: null, team: 'bugfix')),
        'docs · bugfix',
      );
    });
  });
}

void _testerAskerBoundaries() {
  group('CTUI-35 tester: picked asker boundaries', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'same request id in two children uses the current name after switches at $size',
        (t) async {
          final w = await _window(t, size);
          for (final key in [w.parser, w.docs]) {
            _ask(
              w,
              key,
              (turn) => model.PermissionRequestedAction(turn, _writeNotes()),
            );
          }
          for (final (key, name, other) in [
            (w.docs, 'docs', 'parser'),
            (w.parser, 'parser', 'docs'),
            (w.docs, 'docs', 'parser'),
          ]) {
            w.connection.agents.pick(key);
            w.connection.fold.dispatch(SessionShown(key));
            await settle(t);
            expect(t.screen, shows('$name asks'));
            expect(t.screen, isNot(shows('$other asks')));
          }
        },
      );

      testWidgets(
        'wide picked name between turns survives tiny room and resize at $size',
        (t) async {
          final picked = (name: '界🙂e\u0301' * 20, colour: _docs, team: null);
          final box = PermissionPrompt(
            wait: _writeNotes(),
            windowRows: size.height,
            maxRows: size.height,
            scroll: PermissionScroll(),
            onChoose: (_) {},
            onReject: () {},
            picked: picked,
            between: true,
          );
          await t.pumpWidget(box, size: const Size(0, 1));
          await t.pumpWidget(box, size: const Size(1, 1));
          await t.pumpWidget(box, size: size);
          await t.pump();
          expect(t.screen.text, contains('界🙂e\u0301'));
          expect(t.screen, isNot(shows('main asks')));
          expect(
            permissionPinned(_writeNotes(), size.width, picked: picked),
            greaterThan(permissionPinned(_writeNotes(), size.width)),
          );
          expect(t.screen.styleAt(2, 2).fg, _docs);
          expect(t.screen.styleAt(2, 2).isBold, isTrue);
        },
      );
    }
  });
}
