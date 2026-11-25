@Tags(['fake_agent'])
library;

import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord/ui/start.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fixture;

void main() {
  group('failed prompt in the real window', skip: fakeAgentSkip, () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      for (final (name, theme) in [
        ('dark', ThemeData.dark()),
        ('light', ThemeData.light()),
        ('plain', ThemeData.plain()),
      ]) {
        testWidgets(
          'error row survives edits and wraps under its message, $name at $size',
          (t) async {
            final connection = await fixture.connected(t, size);
            await t.pumpWidget(
              Theme(
                data: theme,
                child: StartWindow(
                  launch: fixture.launch,
                  connection: connection,
                ),
              ),
              size: size,
            );
            await fixture.sent(t, connection, 'error');
            final errors = connection.app.value.transcript.entries
                .whereType<model.ErrorEntry>()
                .toList();
            expect(errors, hasLength(1));
            final error = errors.single;
            expect(error.message, 'The fake agent failed on purpose.');
            expect(
              connection.app.value.transcript.entries.first,
              isA<model.UserEntry>(),
            );
            expect(connection.app.value.transcript.entries.last, same(error));
            final row = t.screen.lines.indexWhere(
              (line) => line.contains('⏺ ${error.message}'),
            );
            expect(row, greaterThan(0));
            expect(t.screen.lines[row], ' ⏺ ${error.message}');
            expect(t.screen.lines[row - 1], '');
            expect(t.screen.styleAt(1, row).fg, theme.error.fg);
            expect(t.screen.styleAt(3, row).fg, theme.error.fg);
            expect(t.screen, isNot(shows('Error: ${error.message}')));
            expect(t.screen, isNot(shows('any key to quit')));
            await t.type('next draft');
            await t.press('ctrl+c');
            expect(
              connection.app.value.transcript.entries
                  .whereType<model.ErrorEntry>()
                  .single,
              same(error),
            );
            expect(t.exitRequested, isFalse);
            await t.resize(const Size(20, 24));
            final wrapped =
                TextLayout.compute(TextSpan(error.message), maxWidth: 16).lines
                    .map((line) => line.map((glyph) => glyph.text).join())
                    .toList();
            final at = t.screen.lines.indexWhere(
              (line) => line == ' ⏺ ${wrapped.first}',
            );
            expect(at, greaterThan(0));
            for (var i = 1; i < wrapped.length; i++) {
              expect(t.screen.lines[at + i], '   ${wrapped[i]}');
            }
            await t.resize(size);
            await fixture.sent(t, connection, 'text');
            expect(
              connection.app.value.transcript.entries
                  .whereType<model.ErrorEntry>(),
              hasLength(1),
            );
            expect(t.screen, shows('Hello, world.'));
            expect(t.screen, shows(error.message));
          },
        );
      }
    }
  });

  group('tester: failed prompt rendering edges', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'multiline Unicode failure retains exact history across edits and resize at $size',
        (t) async {
          final connection = StartConnection(command: 'unused', cwd: '.');
          addTearDown(connection.close);
          const message = '界🙂e\u0301 \x1b[31mred\x1b[0m\nsecond exact line';
          final initial = AppState(
            start: const StartState(phase: StartPhase.connected),
            transcript: model.Transcript(
              entries: [const model.UserEntry('turn', 'prompt')],
            ),
          );
          connection.app.value = reduceApp(
            initial,
            const Transcribed(model.FailedAction('turn', message)),
          );
          await t.pumpWidget(
            TranscriptWindow(launch: fixture.launch, connection: connection),
            size: size,
          );
          final entry = connection.app.value.transcript.entries
              .whereType<model.ErrorEntry>()
              .single;
          expect(entry.message, message);
          expect(t.screen, shows(' ⏺ 界🙂e\u0301 red'));
          expect(t.screen, shows('   second exact line'));
          await t.paste('new draft');
          await t.press('ctrl+c');
          await t.resize(const Size(20, 24));
          expect(t.screen, shows('界🙂e\u0301 red'));
          await t.resize(size);
          expect(t.screen, shows('   second exact line'));
          expect(
            connection.app.value.transcript.entries
                .whereType<model.ErrorEntry>()
                .single,
            same(entry),
          );
          expect(t.screen, isNot(shows('any key to quit')));
          expect(t.exitRequested, isFalse);
        },
      );

      testWidgets(
        'a failure appended while reading history retains held scroll at $size',
        (t) async {
          final connection = StartConnection(command: 'unused', cwd: '.');
          addTearDown(connection.close);
          connection.app.value = AppState(
            start: const StartState(phase: StartPhase.connected),
            transcript: model.Transcript(
              entries: [
                for (var i = 0; i < 100; i++)
                  model.UserEntry('t$i', 'history $i'),
              ],
            ),
          );
          await t.pumpWidget(
            TranscriptWindow(launch: fixture.launch, connection: connection),
            size: size,
          );
          await t.press('home');
          expect(t.screen, shows('chord v0.0.1'));
          connection.app.value = reduceApp(
            connection.app.value,
            const Transcribed(
              model.FailedAction('t99', 'late failure after history'),
            ),
          );
          await t.pump();
          expect(connection.app.value.scroll.following, isFalse);
          expect(t.screen, shows('chord v0.0.1'));
          expect(t.screen, isNot(shows('late failure after history')));
          await t.resize(const Size(40, 16));
          expect(connection.app.value.scroll.following, isFalse);
          await t.press('end');
          expect(t.screen, shows('late failure after history'));
          expect(
            connection.app.value.transcript.entries
                .whereType<model.ErrorEntry>(),
            hasLength(1),
          );
          await t.resize(size);
          expect(t.screen, shows('late failure after history'));
          expect(t.exitRequested, isFalse);
        },
      );
    }
  });
}
