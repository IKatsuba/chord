// The window's long-lived agents with no agent: main up, `parser` and
// `docs` open on scripted sessions, the list under the status line, each
// flag adding a state the fake reaches only by running.
//
//   dart run tool/children.dart
//   dart run tool/children.dart --many
//
// --asking   docs waits on a permission (`● permission`)
// --unseen   parser's reply, a message to docs and other's failed turn,
//            none of them shown (`✓ new reply`, `← new message`,
//            `✗ turn failed`)
// --exited   docs' agent exits (`✗ exited`)
// --failed   lexer's agent never comes up (`✗ failed to start`)
// --tall     a child whose name is taller than the list at 80x24
// --many     children up to the limit of eight: the list folds to
//            `… +N more`
// --held     parser in front, a turn at work and messages held for it
// --tasks    two task agents of main's still at work after its turn
// --codex    the children on runtime codex, a name only: nothing starts,
//            so what names the shown agent's runtime differs from main's
// --light, --plain  the other themes
//
// Ctrl+Q quits.
import 'dart:async';
import 'dart:io';

import 'package:chord/acp/connection.dart';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/cli.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/tasks.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/session/window_agents.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/agents/agents_view.dart' show AgentsClock;
import 'package:chord/ui/app/window_fold.dart' show mainKey;
import 'package:chord_tui/chord_tui.dart';

import '../test/session/conversation_fake.dart';

/// What `--tall` names its child: the original's `LONG_TITLE` from the
/// fake's `agenttitled`, taller than the list at 80x24.
const tallName =
    'Summarise the release notes for 0.56.0 from the commits since 0.55.2, '
    'grouped by area, with a line for each user-facing change and a note for '
    'each breaking one, then draft the announcement for the forum and the '
    'changelog entry, and list the open questions for the owner to settle '
    'before the tag.';

/// The children `--many` opens after parser and docs, to eight.
const manyNames = ['other', 'lexer', 'printer', 'bugfix', 'bugfix 2', 'review'];

/// The flags the fixture reads, each a state of the list.
const childrenFlags = [
  '--asking',
  '--unseen',
  '--exited',
  '--failed',
  '--tall',
  '--many',
  '--held',
  '--tasks',
];

/// The fixture's agents: the window's connection, main never opening its
/// own agent, and each child by name.
final class ChildrenFixture {
  ChildrenFixture._(this.connection, this._hanging);

  /// The window's connection.
  final StartConnection connection;
  final Completer<Agent> _hanging;

  /// Each child's key by name.
  final keys = <String, int>{};

  /// Each child's scripted session by name; none for one that never came
  /// up.
  final sessions = <String, ScriptedSession>{};

  final _emits = <int, void Function(ConversationEvent)>{};

  /// Child [name] reports [event] as its conversation would.
  void emit(String name, ConversationEvent event) =>
      _emits[keys[name]!]!(event);

  /// Lets main's open go and closes the window's agents.
  Future<void> close() async {
    if (!_hanging.isCompleted) {
      _hanging.future.ignore();
      _hanging.completeError(StateError('fixture over'));
    }
    await connection.close();
  }
}

/// The fixture's agents in the states [args] ask for.
ChildrenFixture childrenFixture(List<String> args, {Owned? owner}) {
  final hanging = Completer<Agent>();
  final connection = StartConnection(
    command: 'fake',
    cwd: '.',
    agent: 'fake',
    owner: owner ?? Owned(),
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
  final fixture = ChildrenFixture._(connection, hanging);
  // Main up, so the status line says what the keys do.
  connection.fold.heard(mainKey, const Connected('m', AgentState.empty));

  // Opened over the last minutes, two apart: parser 18m ago, docs 16m,
  // the last of the limit 4m, so each header says a plausible age.
  final started = _now();
  // Whether child [name] opened: past the window's limit it is refused, as
  // the original's open_agent refuses one more.
  bool open(String name, {String? model, bool fails = false}) {
    final session = fails ? null : ScriptedSession();
    final key = connection.agents.openChild(
      ChildInfo(
        id: 'id-${fixture.keys.length + 1}',
        name: name,
        runtime: args.contains('--codex') ? 'codex' : 'fake',
        model: model,
        openedAt:
            started -
            Duration(minutes: 18 - 2 * fixture.keys.length).inMilliseconds,
      ),
      (emit, key) {
        fixture._emits[key] = emit;
        connection.fold.dispatch(AgentOpened(key));
        return Conversation(
          ({required onTraffic, required cancellationToken}) => session == null
              ? Future.error(StateError('fake exited before it answered'))
              : Future.value(session),
        )..listen(emit);
      },
    );
    if (key == null) return false;
    fixture.keys[name] = key;
    if (session != null) fixture.sessions[name] = session;
    return true;
  }

  open('parser', model: 'fake-small');
  open('docs');
  // The children a flag asks for by name first, then --many's up to the
  // limit, the rest refused.
  if (args.contains('--failed')) open('lexer', fails: true);
  if (args.contains('--tall')) open(tallName);
  if (args.contains('--many')) {
    for (final name in manyNames) {
      if (fixture.keys.containsKey(name)) continue;
      if (!open(name)) break;
    }
  }
  if (args.contains('--unseen') && !args.contains('--many')) open('other');
  return fixture;
}

/// Now, as the list's clock counts.
int _now() => AgentsClock.now();

/// Child [name] runs a turn, [turn] by id.
void _working(ChildrenFixture f, String name, [String turn = 'turn']) =>
    f.emit(name, Transcribed(model.PromptAction(turn, 'go on', _now())));

/// Child [name]'s turn [turn] ends with [result].
void _ended(
  ChildrenFixture f,
  String name, [
  model.TurnResult result = const model.TurnAnswered('end_turn'),
  String turn = 'turn',
]) => f.emit(name, Transcribed(model.ResultAction(turn, result)));

/// The states [args] ask for, once every child has had its session open.
void childrenStates(ChildrenFixture f, List<String> args) {
  if (args.contains('--asking')) {
    _working(f, 'docs');
    f.emit(
      'docs',
      Transcribed(
        model.PermissionRequestedAction(
          'turn',
          model.PermissionWait(
            'fixture',
            title: 'Edit README.md',
            kind: 'edit',
            options: [
              acpOption('allow', 'Allow once', 'allow_once'),
              acpOption('deny', 'Deny', 'reject_once'),
            ],
          ),
        ),
      ),
    );
  }
  if (args.contains('--unseen')) {
    _working(f, 'parser');
    _ended(f, 'parser');
    f.emit(
      'docs',
      Transcribed(
        model.PromptAction(
          'from-main',
          'Then the docs, once the tests pass.',
          _now(),
          from: model.MessageFrom('main', reachable: true),
        ),
      ),
    );
    _working(f, 'other');
    _ended(f, 'other', const model.TurnFailed('The model is overloaded.'));
  }
  if (args.contains('--exited')) {
    f.sessions['docs']!.exit('fake: lost its connection');
  }
  if (args.contains('--held')) {
    _working(f, 'parser');
    f.emit(
      'parser',
      const Queued(
        'held-1',
        'Then the docs, once the tests pass.',
        afterCalls: true,
        from: model.MessageFrom('main', reachable: true),
      ),
    );
    f.emit(
      'parser',
      const Queued(
        'held-2',
        'The README names the old flag.\nIt is --fake now.',
        from: model.MessageFrom('docs', runtime: 'fake', reachable: true),
      ),
    );
    final key = f.keys['parser']!;
    f.connection.agents.pick(key);
    f.connection.fold.dispatch(SessionShown(key));
  }
  if (args.contains('--tasks')) {
    final fold = f.connection.fold;
    void heard(model.TranscriptAction action) =>
        fold.heard(mainKey, Transcribed(action));
    heard(model.PromptAction('t1', 'tasktwo', _now()));
    for (final (id, name) in const [
      ('task-1', 'Watch the build'),
      ('task-2', 'Watch the deploy'),
    ]) {
      heard(
        model.UpdateAction(
          't1',
          taskUpdate(
            id,
            model.SubagentState.running,
            task: TaskStart(
              id: id,
              name: name,
              runtime: 'fake',
              prompt: 'taskwait',
            ),
          ),
        ),
      );
    }
    heard(const model.ResultAction('t1', model.TurnAnswered('end_turn')));
  }
}

/// A permission option as an agent sends it.
acp.PermissionOption acpOption(String id, String name, String kind) =>
    acp.PermissionOption.fromJson({'optionId': id, 'name': name, 'kind': kind});

/// The fixture's window over [fixture], Ctrl+Q quitting.
Widget childrenPreview(ChildrenFixture fixture) => Builder(
  builder: (context) => Actions(
    bindings: [Binding('ctrl+q', 'Quit fixture', () => exitApp(context))],
    child: TranscriptWindow(
      launch: const Launch(
        name: 'fake',
        agent: null,
        agentCommand: 'fake',
        version: '0.0.1',
        directory: 'project',
      ),
      connection: fixture.connection,
    ),
  ),
);

Future<void> main(List<String> args) async {
  final owner = Owned();
  final fixture = childrenFixture(args, owner: owner);
  // Each child's session opens on a microtask; its states come after.
  await Future<void>.delayed(Duration.zero);
  childrenStates(fixture, args);
  await runApp(
    childrenPreview(fixture),
    theme: args.contains('--light') ? ThemeData.light() : ThemeData.dark(),
    environment: {
      ...Platform.environment,
      if (args.contains('--plain')) 'NO_COLOR': '1',
    },
    beforeExit: () async {
      await fixture.close();
      await leave(from: owner);
    },
  );
}
