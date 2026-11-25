import 'dart:async';

import 'package:chord/session/leaving.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/resume_agent.dart';
import '../../session/reopen_session_test.dart' as memory;
import 'resume_window_test.dart' as resume;
import 'window_fake_test.dart' show until;

class FailedFixture extends resume.Fixture {
  FailedFixture(super.directory);
  int failuresRemaining = 1;
  int openings = 0;
  String reason = 'The scripted session could not start.';
}

Future<FailedFixture> failedFixture(
  WidgetTester t,
  Size size, {
  String? reason,
}) async {
  final f = FailedFixture(await memory.directory());
  if (reason != null) f.reason = reason;
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
          f.openings++;
          if (f.failuresRemaining > 0) {
            f.failuresRemaining--;
            return Future.error(StateError(f.reason));
          }
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
      launch: resume.launch,
      connection: f.connection,
      readSessionRecords: f.read,
    ),
    size: size,
  );
  await until(() => f.connection.app.value.start.phase == StartPhase.failed);
  await t.pump();
  return f;
}

Future<void> command(WidgetTester t, String text) async {
  await t.type(text);
  await t.press('enter');
  await t.pump();
}

RenderListViewport viewport(WidgetTester t) {
  final found = <RenderListViewport>[];
  void visit(Element element) {
    if (element is RenderObjectElement &&
        element.renderObject is RenderListViewport) {
      found.add(element.renderObject as RenderListViewport);
    }
    element.visitChildren(visit);
  }

  visit(t.host.rootElement);
  return found.single;
}

void main() {
  _testerFailedStartLifecycle();
  // ../chord breaks these after a punctuation mark inside the token, as
  // OpenTUI does (docs/design/evidence/CTUI-52/u52c-original-*.txt); the
  // agent here is memory, its words StateError's, so the rows are shifted.
  for (final (size, reason, rows) in const [
    (
      Size(120, 40),
      'it refused session/new: session/new requires `agentAlias` '
          '(alias of a configured [agents.<alias>] entry)',
      [
        ' ⏺ memory did not start: Bad state: it refused session/new: '
            'session/new requires `agentAlias` (alias of a configured [',
        '   agents.<alias>] entry)',
      ],
    ),
    (
      Size(80, 24),
      'refused: Resource not found: 00000000-0000-0000-0000-000000000002',
      [
        ' ⏺ memory did not start: Bad state: refused: Resource not found: '
            '00000000-0000-',
        '   0000-0000-000000000002',
      ],
    ),
  ]) {
    testWidgets('a long token in the failure breaks as the original at $size', (
      t,
    ) async {
      await failedFixture(t, size, reason: reason);
      final lines = t.screen.lines.map((l) => l.trimRight()).toList();
      final at = lines.indexWhere((l) => l.contains('did not start'));
      expect(lines.sublist(at, at + 2), rows);
    });
  }
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets(
      'failed start keeps prompt, command owner and send guard $size',
      (t) async {
        final f = await failedFixture(t, size), c = f.connection;
        expect(t.screen, shows('memory did not start:'));
        expect(
          t.screen.lines.indexWhere((l) => l.contains('did not start')),
          greaterThan(3),
        );
        expect(t.screen, shows('╭'));
        final header = viewport(t).selectionDelegate!.idAt(0);
        await command(t, 'unsent ordinary text');
        expect(c.app.value.draft, 'unsent ordinary text');
        expect(c.app.value.transcript.entries, isEmpty);
        expect(c.app.value.queue, isEmpty);
        expect(f.agents, isEmpty);
        await t.press('ctrl+c');
        await t.press('up');
        expect(c.app.value.draft, isEmpty);
        for (final name in ['/model', '/config', '/fast', '/effort high']) {
          await command(t, name);
          expect(c.app.value.transcript.entries, isEmpty, reason: name);
          expect(f.openings, 1);
        }
        await command(t, '/effort');
        expect(t.screen, shows('memory offers no effort.'));
        expect(t.screen, isNot(shows('for .')));
        expect(c.app.value.transcript.entries.single, isA<model.NotedEntry>());
        await command(t, '/status');
        expect(
          c.app.value.transcript.entries.whereType<model.ReportEntry>(),
          hasLength(1),
        );
        await command(t, '/help');
        expect(c.app.value.shortcuts.help, isTrue);
        await t.press('esc');
        expect(c.app.value.shortcuts.help, isFalse);
        expect(viewport(t).selectionDelegate!.idAt(0), header);
        expect(
          c.app.value.transcript.entries.whereType<model.ErrorEntry>(),
          isEmpty,
        );
        await command(t, '/clear');
        await until(() => c.app.value.start.phase == StartPhase.connected);
        await t.pump();
        expect(f.openings, 2);
        expect(t.screen, isNot(shows('did not start')));
        expect(c.app.value.transcript.entries, isEmpty);
        await command(t, 'accepted after retry');
        await until(
          () => c.app.value.transcript.entries
              .whereType<model.UserEntry>()
              .isNotEmpty,
        );
        expect(
          c.app.value.transcript.entries
              .whereType<model.UserEntry>()
              .single
              .text,
          'accepted after retry',
        );
      },
    );

    testWidgets(
      'failed start resume completion, empty, scope, cancel and replacement $size',
      (t) async {
        final f = await failedFixture(t, size), c = f.connection;
        await command(t, '/res');
        expect(f.reads, 1);
        expect(t.screen, shows('No earlier memory session to resume'));
        await f.saved('local');
        await f.saved('remote', cwd: '${f.directory.path}/remote', at: 2);
        await command(t, '/resume');
        expect(t.screen, shows('Choice local'));
        await t.press('ctrl+a');
        expect(t.screen, shows('Choice remote'));
        await t.press('esc');
        expect(c.app.value.resumePicker, isNull);
        expect(f.openings, 1);
        await command(t, '/resume');
        await t.press('enter');
        await until(() => c.app.value.start.phase == StartPhase.connected);
        await t.pump();
        expect(c.app.value.resumed?.sessionId, 'local');
        expect(t.screen, isNot(shows('did not start')));
        expect(
          c.app.value.transcript.entries
              .whereType<model.UserEntry>()
              .single
              .text,
          'Saved past local',
        );
        expect(
          f.agents.single.requests.where(
            (r) => r['method'] == 'session/prompt',
          ),
          isEmpty,
        );
      },
    );

    testWidgets(
      'failed replacement stays command capable without partial past $size',
      (t) async {
        final f = await failedFixture(t, size), c = f.connection;
        await f.saved('local');
        f.failuresRemaining = 1;
        await command(t, '/resume');
        await t.press('enter');
        await until(
          () => f.openings == 2 && c.app.value.start.phase == StartPhase.failed,
        );
        await t.pump();
        expect(c.app.value.resumed, isNull);
        expect(
          c.app.value.transcript.entries.whereType<model.UserEntry>(),
          isEmpty,
        );
        expect(t.screen, shows('did not start'));
        await command(t, 'still unsent');
        expect(c.app.value.draft, 'still unsent');
        await t.press('ctrl+c');
        await command(t, '/resume');
        await t.press('enter');
        await until(() => c.app.value.start.phase == StartPhase.connected);
        await t.pump();
        expect(c.app.value.resumed?.sessionId, 'local');
        expect(
          c.app.value.transcript.entries.whereType<model.UserEntry>(),
          hasLength(1),
        );
      },
    );
    testWidgets(
      'failure is excluded scroll furniture with full wrapped geometry $size',
      (t) async {
        final f = await failedFixture(
          t,
          size,
          reason:
              '${[for (var i = 1; i <= 60; i++) 'Failure detail $i 界😀 ${'wrapped words ' * 8}'].join('\n')} end-of-failure',
        );
        final view = viewport(t);
        expect(view.extents.length, 2);
        expect(
          view.extents.heightOf(1),
          1 +
              TextLayout.compute(
                TextSpan(
                  printable(
                    statusLine(f.connection.app.value.start, 'memory')!,
                  ),
                ),
                maxWidth: size.width - 4,
              ).height,
        );
        expect(view.extents.heightOf(1), greaterThan(size.height));
        expect(view.selectionDelegate!.sourceAt(1).children, isEmpty);
        expect(t.screen, shows('end-of-failure'));
        await t.press('home');
        expect(t.screen, shows('memory did not start:'));
        expect(t.screen, isNot(shows('end-of-failure')));
        await t.resize(const Size(32, 10));
        await t.press('end');
        expect(t.screen, shows('end-of-failure'));
        await t.resize(size);
        await command(t, '/resume');
        expect(
          f.connection.app.value.transcript.entries
              .whereType<model.ErrorEntry>(),
          isEmpty,
        );
        expect(
          f.connection.app.value.transcript.entries
              .whereType<model.ReportEntry>(),
          hasLength(1),
        );
      },
    );
    for (final oldFailure in [false, true]) {
      testWidgets(
        'failed-start latest scan owns repeated resume $oldFailure $size',
        (t) async {
          final f = await failedFixture(t, size), c = f.connection;
          final old = await f.saved('old');
          final current = await f.saved('current-choice', at: 2);
          final obsolete = Completer<List<SessionRecord>>();
          f.deferred = obsolete;
          await command(t, '/resume');
          final oldToken = f.tokens.single!;
          final fresh = Completer<List<SessionRecord>>();
          f.deferred = fresh;
          await command(t, '/resume');
          expect(oldToken.isCancelled, isTrue);
          fresh.complete([current]);
          await t.pump();
          final picker = c.app.value.resumePicker;
          if (oldFailure) {
            obsolete.completeError(const FormatException('retired scan'));
          } else {
            obsolete.complete([old]);
          }
          await t.pump();
          expect(c.app.value.resumePicker, same(picker));
          expect(t.screen, shows('Choice current-choice'));
          expect(c.app.value.transcript.entries, isEmpty);
          await t.resize(const Size(8, 3));
          t.host.handleKey(const KeyEvent('enter'));
          await t.pump();
          expect(f.openings, 1);
          await t.resize(size);
          await t.press('esc');
          expect(c.app.value.resumePicker, isNull);
        },
      );
    }
  }
}

void _testerFailedStartLifecycle() {
  group('tester: U52b failed-start scan ownership', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'unmounted closed failure ignores a late scan error at $size',
        (t) async {
          final f = await failedFixture(t, size);
          final late = Completer<List<SessionRecord>>();
          f.deferred = late;
          await command(t, '/resume');
          final token = f.tokens.single!;
          await t.pumpWidget(const SizedBox());
          expect(token.isCancelled, isTrue);
          await f.connection.close();
          final closed = f.connection.app.value;
          late.completeError(
            const FormatException('retired failed-start scan'),
          );
          await t.pump();
          expect(f.connection.app.value, same(closed));
          expect(f.openings, 1);
          expect(f.agents, isEmpty);
        },
      );

      testWidgets(
        'retired failure cannot replace another connection resume at $size',
        (t) async {
          final first = await failedFixture(t, size);
          final old = await first.saved('obsolete-first');
          final late = Completer<List<SessionRecord>>();
          first.deferred = late;
          await command(t, '/resume');
          final token = first.tokens.single!;
          await t.pumpWidget(const SizedBox());
          expect(token.isCancelled, isTrue);
          final second = await failedFixture(t, size);
          await second.saved('current-second');
          await command(t, '/resume');
          expect(t.screen, shows('Choice current-second'));
          await t.press('enter');
          await until(
            () =>
                second.connection.app.value.start.phase == StartPhase.connected,
          );
          await t.pump();
          late.complete([old]);
          await t.pump();
          expect(
            second.connection.app.value.resumed?.sessionId,
            'current-second',
          );
          expect(
            second.connection.app.value.transcript.entries
                .whereType<model.UserEntry>()
                .single
                .text,
            'Saved past current-second',
          );
          expect(t.screen.text, isNot(contains('obsolete-first')));
          expect(first.agents, isEmpty);
          expect(second.agents, hasLength(1));
        },
      );
    }
  });
}
