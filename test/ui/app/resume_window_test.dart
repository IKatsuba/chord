import 'dart:async';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/cli.dart';
import 'package:chord/session/conversation.dart' show quietMs;
import 'package:chord/session/leaving.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../fixtures/resume_agent.dart';
import '../../session/recording_start_test.dart' show connected, until, idle;
import '../../session/reopen_session_test.dart' as memory;

const launch = Launch(
  name: 'memory',
  agent: null,
  agentCommand: 'memory',
  version: 'test',
  directory: 'project',
);

class Fixture {
  Fixture(this.directory);
  final Directory directory;
  late StartConnection connection;
  final agents = <ResumeAgent>[];
  final records = <SessionRecord>[];
  final tokens = <CancellationToken?>[];
  Completer<List<SessionRecord>>? deferred;
  Object? failure;
  int reads = 0;
  Future<List<SessionRecord>> read({
    CancellationToken? cancellationToken,
  }) async {
    reads++;
    tokens.add(cancellationToken);
    if (failure case final error?) throw error;
    return deferred == null ? records : await deferred!.future;
  }

  Future<SessionRecord> saved(
    String id, {
    String? cwd,
    num at = 1,
    String agent = 'memory',
  }) async {
    final where = cwd ?? directory.path;
    final file = File(p.join(directory.path, 'saved-${records.length}.jsonl'));
    await file.writeAsString(
      [
        {
          'type': 'session',
          'version': 1,
          'sessionId': id,
          'agent': agent,
          'cwd': where,
          'at': at,
        },
        {
          'type': 'prompt',
          'turnId': 'past',
          'prompt': 'Saved past $id',
          'images': 0,
          'at': at,
        },
        {
          'type': 'result',
          'turnId': 'past',
          'result': {'status': 'completed', 'stopReason': 'end_turn'},
        },
      ].map(encodeRecord).join(),
    );
    final record = SessionRecord(
      path: file.path,
      sessionId: id,
      agent: agent,
      cwd: where,
      lastUsedAt: at,
      prompt: 'Choice $id',
    );
    records.add(record);
    return record;
  }
}

Future<Fixture> fixture(
  WidgetTester t,
  Size size, {
  Launch launch = launch,
}) async {
  final f = Fixture(await memory.directory());
  f.connection = StartConnection(
    command: 'memory',
    cwd: f.directory.path,
    agent: 'memory',
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
        }) {
          final agent = ResumeAgent();
          f.agents.add(agent);
          return agent.open(
            command: command,
            env: env,
            cwd: cwd,
            onTraffic: onTraffic,
            onPermission: onPermission,
            relay: relay,
            cancellationToken: cancellationToken,
          );
        },
  )..start();
  addTearDown(() async {
    await f.connection.close();
    expect(f.agents.every((a) => a.process.exited), isTrue);
  });
  await t.pumpWidget(
    TranscriptWindow(
      launch: launch,
      connection: f.connection,
      readSessionRecords: f.read,
    ),
    size: size,
  );
  await connected(f.connection);
  await t.pump();
  return f;
}

Future<void> open(WidgetTester t, Fixture f) async {
  await t.type('/resume');
  await t.press('enter');
  await t.pump();
}

void keys(WidgetTester t, List<String> keys) {
  for (final key in keys) {
    t.host.handleKey(KeyCombo.parse(key).toEvent());
  }
}

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('another directory\'s session gives a command that repeats a '
        'typed --no-mcp-servers $size', (t) async {
      final f = await fixture(
        t,
        size,
        launch: const Launch(
          name: 'memory',
          agent: null,
          agentCommand: 'memory',
          version: 'test',
          directory: 'project',
          noMcpServers: true,
          noMcpServersFrom: '--no-mcp-servers',
        ),
      );
      final remote = await f.saved(
        'remote',
        cwd: p.join(f.directory.path, 'other'),
        at: 3,
      );
      await open(t, f);
      keys(t, ['ctrl+a', 'enter']);
      await t.pump();
      final report = f.connection.app.value.transcript.entries
          .whereType<model.ReportEntry>()
          .single;
      expect(
        report.rows.single.text,
        endsWith(
          // chord's own record id, the owner's departure (CTUI-176).
          'chord memory --agent-command memory --no-mcp-servers '
          '--resume ${recordId(remote.path)}',
        ),
      );
    });
    testWidgets(
      'local command lists fresh/excluded rows and same-batch scope rejects remote cwd $size',
      (t) async {
        final f = await fixture(t, size), c = f.connection;
        await f.saved('current');
        await f.saved('other-agent', agent: 'other');
        await f.saved('local', at: 2);
        final remote = await f.saved(
          'remote id',
          cwd: p.join(f.directory.path, 'other project'),
          at: 3,
        );
        await open(t, f);
        expect(f.reads, 1);
        expect(c.app.value.resumePicker, isNotNull);
        expect(t.screen, shows('Choice local'));
        expect(t.screen, isNot(shows('Choice current')));
        expect(t.screen, isNot(shows('Choice other-agent')));
        expect(t.screen, isNot(shows('Choice remote id')));
        keys(t, ['ctrl+a', 'enter', 'enter']);
        await t.pump();
        expect(c.app.value.resumePicker, isNull);
        expect(f.agents, hasLength(1));
        final report = c.app.value.transcript.entries
            .whereType<model.ReportEntry>()
            .single;
        expect(report.command, 'resume');
        expect(report.rows.single.text, contains('That session is in'));
        expect(
          report.rows.single.text,
          endsWith('--resume ${recordId(remote.path)}'),
        );
        expect(
          f.agents.single.requests.where(
            (r) => r['method'] == 'session/prompt',
          ),
          isEmpty,
        );
        await open(t, f);
        expect(f.reads, 2);
        expect(c.app.value.resumePicker?.everywhere, isFalse);
        await t.press('esc');
        expect(c.app.value.resumePicker, isNull);
      },
    );
    testWidgets('empty local overlay fills the terminal width $size', (
      t,
    ) async {
      final f = await fixture(t, size);
      await f.saved('remote', cwd: p.join(f.directory.path, 'remote'));
      await open(t, f);
      expect(t.screen, shows('No earlier sessions in this directory.'));
      final title = t.screen.lines.indexWhere(
        (line) => line.contains('Resume a session'),
      );
      expect(t.screen.lines[title - 1], '╭${'─' * (size.width - 2)}╮');
      expect(t.screen.lines[title].endsWith('│'), isTrue);
      await t.press('ctrl+a');
      expect(t.screen, shows('Choice remote'));
      await t.press('ctrl+a');
      final empty = t.screen.lines.indexWhere(
        (line) => line.contains('Resume a session'),
      );
      expect(t.screen.lines[empty - 1], '╭${'─' * (size.width - 2)}╮');
      await t.press('esc');
      expect(f.connection.app.value.resumePicker, isNull);
    });
    testWidgets('close observer starting a turn prevents replacement $size', (
      t,
    ) async {
      final f = await fixture(t, size), c = f.connection;
      await f.saved('chosen');
      await open(t, f);
      f.agents.single.holdPrompt = true;
      var started = false;
      c.app.addListener(() {
        if (!started && c.app.value.resumePicker == null) {
          started = true;
          c.conversation.send('observer turn');
        }
      });
      await t.press('enter');
      await t.pump();
      expect(started, isTrue);
      expect(f.agents, hasLength(1));
      expect(c.app.value.resumePicker, isNull);
      expect(c.app.value.transcript.turn, isNot(isA<model.Idle>()));
      expect(
        c.app.value.transcript.entries
            .whereType<model.ReportEntry>()
            .single
            .command,
        'resume',
      );
      expect(
        f.agents.single.requests.where((r) => r['method'] == 'session/load'),
        isEmpty,
      );
    });
    testWidgets(
      'read pending keeps draft and clear cancels stale completion $size',
      (t) async {
        final f = await fixture(t, size), c = f.connection;
        await f.saved('stale');
        f.deferred = Completer();
        await open(t, f);
        expect(c.app.value.resumeAsked, isNotNull);
        expect(t.screen, isNot(shows('Resume a session')));
        await t.type('kept draft');
        await c.conversation.clear();
        await connected(c);
        expect(f.tokens.single!.isCancelled, isTrue);
        f.deferred!.complete(f.records);
        await t.pump();
        expect(c.app.value.resumePicker, isNull);
        expect(c.app.value.draft, 'kept draft');
        expect(c.app.value.transcript.entries, isEmpty);
      },
    );
    testWidgets(
      'newly busy read and active acceptance report instead of replacing $size',
      (t) async {
        final f = await fixture(t, size), c = f.connection;
        await f.saved('chosen');
        f.deferred = Completer();
        await open(t, f);
        f.agents.first.holdPrompt = true;
        c.conversation.send('held turn');
        f.deferred!.complete(f.records);
        await t.pump();
        expect(c.app.value.resumePicker, isNull);
        expect(t.screen, shows('A turn is running.'));
        f.agents.first.finishPrompt();
        await idle(c);
        await t.pump();
        f.deferred = null;
        await open(t, f);
        f.agents.first.holdPrompt = true;
        c.conversation.send('another held turn');
        await t.pump();
        await t.press('enter');
        expect(c.app.value.resumePicker, isNull);
        expect(f.agents, hasLength(1));
        expect(
          c.app.value.transcript.entries.whereType<model.ReportEntry>(),
          hasLength(2),
        );
        final reads = f.reads;
        await t.type('/resume');
        await t.press('enter');
        expect(f.reads, reads);
        expect(
          c.app.value.transcript.entries.whereType<model.ReportEntry>(),
          hasLength(3),
        );
      },
    );
    testWidgets(
      'permission suspends mounted picker and resumes same highlight $size',
      (t) async {
        final f = await fixture(t, size), c = f.connection;
        await f.saved('first', at: 2);
        await f.saved('second');
        await open(t, f);
        await t.press('down');
        final snapshot = c.app.value.resumePicker;
        f.agents.first.holdPrompt = true;
        c.conversation.send('held');
        f.agents.first.askPermission();
        await until(
          c,
          () => c.app.value.transcript.turn is model.AwaitingPermission,
        );
        await t.pump();
        expect(c.app.value.resumePicker, same(snapshot));
        expect(t.screen, isNot(shows('Resume a session')));
        expect(t.screen, shows('Approve notes'));
        await t.press('ctrl+a');
        expect(c.app.value.resumePicker?.everywhere, isFalse);
        await t.press('1');
        await f.agents.first.permissionAnswered.future.timeout(
          const Duration(seconds: 2),
        );
        f.agents.first.finishPrompt();
        await idle(c);
        await t.pump();
        expect(t.screen, shows('Resume a session'));
        keys(t, ['enter', 'enter']);
        await connected(c);
        await t.pump();
        expect(c.app.value.start.sessionId, 'second');
        expect(f.agents, hasLength(2));
        // The session let go closes after its quiet, as the original.
        await Future<void>.delayed(const Duration(milliseconds: quietMs + 200));
        expect(f.agents.first.process.exited, isTrue);
        expect(t.screen, shows('Saved past second'));
        await t.type('live');
        await t.press('enter');
        await idle(c);
        await t.pump();
        expect(t.screen, shows('Live reply from second.'));
      },
    );
    testWidgets(
      'replacement returns queue ahead of retained draft before old advance $size',
      (t) async {
        final f = await fixture(t, size), c = f.connection;
        await f.saved('chosen');
        f.deferred = Completer();
        await open(t, f);
        await t.type('current draft');
        f.deferred!.complete(f.records);
        await t.pump();
        expect(c.app.value.resumePicker, isNotNull);
        expect(t.screen, shows('Resume a session'));
        f.agents.first.askPermission();
        await until(
          c,
          () => c.app.value.transcript.turn is model.AwaitingPermission,
        );
        c.conversation.send('queued one');
        c.conversation.send('queued two');
        expect(c.app.value.queue, hasLength(2));
        await t.press('ctrl+x a');
        keys(t, ['1', 'enter']);
        await until(c, () => c.app.value.start.sessionId == 'chosen');
        await t.pump();
        expect(c.app.value.queue, isEmpty);
        expect(
          c.app.value.draft.indexOf('queued one'),
          lessThan(c.app.value.draft.indexOf('queued two')),
        );
        expect(
          c.app.value.draft.indexOf('queued two'),
          lessThan(c.app.value.draft.indexOf('current draft')),
        );
        expect(
          f.agents.first.requests.where((r) => r['method'] == 'session/prompt'),
          isEmpty,
        );
        expect(f.agents, hasLength(2));
      },
    );
  }
  testWidgets(
    'zero geometry never defers acceptance and close drops late read',
    (t) async {
      final f = await fixture(t, const Size(80, 24)), c = f.connection;
      await f.saved('chosen');
      await open(t, f);
      final snapshot = c.app.value.resumePicker;
      await t.resize(Size.zero);
      keys(t, ['enter', '1']);
      await t.pump();
      expect(f.agents, hasLength(1));
      expect(c.app.value.resumePicker, same(snapshot));
      await t.resize(const Size(80, 24));
      await t.pump();
      expect(f.agents, hasLength(1));
      await t.press('esc');
      await t.press('ctrl+u');
      f.deferred = Completer();
      await open(t, f);
      expect(f.tokens, hasLength(2));
      expect(c.app.value.resumeAsked, isNotNull);
      final read = f.tokens.last!;
      await c.close();
      expect(read.isCancelled, isTrue);
      f.deferred!.complete(f.records);
      await t.pump();
      expect(c.app.value.resumePicker, isNull);
      expect(c.app.value.resumeAsked, isNull);
      expect(f.agents, hasLength(1));
    },
  );
  testWidgets(
    'latest read owns the immutable snapshot and old failures stay silent',
    (t) async {
      final f = await fixture(t, const Size(80, 24)), c = f.connection;
      final first = await f.saved('old'), second = await f.saved('new', at: 2);
      final old = Completer<List<SessionRecord>>();
      f.deferred = old;
      await open(t, f);
      final newer = Completer<List<SessionRecord>>();
      f.deferred = newer;
      await open(t, f);
      expect(f.tokens.first!.isCancelled, isTrue);
      newer.complete([second]);
      await t.pump();
      final snapshot = c.app.value.resumePicker;
      expect(snapshot?.sessions.single.resume.sessionId, 'new');
      old.completeError(const FormatException('old failure'));
      await t.pump();
      expect(c.app.value.resumePicker, same(snapshot));
      expect(
        c.app.value.transcript.entries.whereType<model.ReportEntry>(),
        isEmpty,
      );
      expect(first.sessionId, 'old');
    },
  );
  testWidgets(
    'empty/error reports are local and a closed observer cannot start replacement',
    (t) async {
      final f = await fixture(t, const Size(80, 24)), c = f.connection;
      await open(t, f);
      expect(t.screen, shows('No earlier memory session to resume'));
      f.failure = const FormatException('denied');
      await open(t, f);
      expect(t.screen, shows('Could not read the earlier sessions:'));
      f.failure = null;
      await f.saved('chosen');
      await open(t, f);
      var closing = false;
      c.app.addListener(() {
        if (!closing && c.app.value.resumePicker == null) {
          closing = true;
          c.close().ignore();
        }
      });
      await t.press('enter');
      await c.close();
      expect(f.agents, hasLength(1));
    },
  );
}
