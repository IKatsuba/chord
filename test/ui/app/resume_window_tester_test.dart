import 'dart:async';

import 'package:chord/cli.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'resume_window_test.dart' as original;

void main() {
  group('tester: CTUI-34 resume refusal flag provenance', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      for (final source in [null, '.chord/settings.json']) {
        testWidgets(
          'a ${source == null ? 'table' : 'settings'} refusal does not turn a choice into a typed flag after resize $size',
          (t) async {
            final fixture = await original.fixture(
              t,
              size,
              launch: Launch(
                name: 'memory',
                agent: null,
                agentCommand: 'memory',
                version: 'test',
                directory: 'project',
                noMcpServers: true,
                noMcpServersFrom: source,
              ),
            );
            await fixture.saved(
              'remote',
              cwd: '${fixture.directory.path}/other',
              at: 3,
            );
            await original.open(t, fixture);
            await t.resize(
              size.width == 120 ? const Size(80, 24) : const Size(120, 40),
            );
            original.keys(t, ['ctrl+a', 'enter']);
            await t.pump();
            final report = fixture.connection.app.value.transcript.entries
                .whereType<model.ReportEntry>()
                .single;
            expect(
              report.rows.single.text,
              endsWith('chord memory --agent-command memory --resume saved-0'),
            );
            expect(
              report.rows.single.text,
              isNot(contains('--no-mcp-servers')),
            );
            expect(fixture.agents, hasLength(1));
            expect(fixture.connection.app.value.resumePicker, isNull);
          },
        );
      }
    }
  });

  group('CTUI-26 U7 tester: detached window read ownership', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      for (final failure in [false, true]) {
        testWidgets(
          'unmounted scan ${failure ? 'failure' : 'success'} cannot replace remounted snapshot $size',
          (t) async {
            final fixture = await original.fixture(t, size);
            final old = await fixture.saved('old');
            final current = await fixture.saved('current-choice', at: 2);
            final obsolete = Completer<List<SessionRecord>>();
            fixture.deferred = obsolete;
            await original.open(t, fixture);
            final token = fixture.tokens.single!;
            await t.pumpWidget(const SizedBox());
            expect(token.isCancelled, isTrue);
            final fresh = Completer<List<SessionRecord>>();
            fixture.deferred = fresh;
            await t.pumpWidget(
              TranscriptWindow(
                launch: original.launch,
                connection: fixture.connection,
                readSessionRecords: fixture.read,
              ),
              size: size,
            );
            await original.open(t, fixture);
            fresh.complete([current]);
            await t.pump();
            final snapshot = fixture.connection.app.value.resumePicker;
            expect(
              snapshot?.sessions.single.resume.sessionId,
              'current-choice',
            );
            if (failure) {
              obsolete.completeError(
                const FormatException('retired scan failed'),
              );
            } else {
              obsolete.complete([old]);
            }
            await t.pump();
            expect(fixture.connection.app.value.resumePicker, same(snapshot));
            expect(
              fixture.connection.app.value.transcript.entries
                  .whereType<model.ReportEntry>(),
              isEmpty,
            );
            expect(t.screen, shows('Choice current-choice'));
            expect(t.screen, isNot(shows('Choice old')));
            expect(fixture.agents, hasLength(1));
            await t.press('esc');
            expect(fixture.connection.app.value.resumePicker, isNull);
          },
        );
      }
    }
  });
}
