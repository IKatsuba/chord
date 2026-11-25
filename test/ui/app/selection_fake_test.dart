@Tags(['fake_agent'])
library;

import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'code_pick_window_test.dart' show pressBounded, pickHint;
import 'selection_window_test.dart' show select, cellOf, primary;
import 'window_fake_test.dart' show connected, launch, sent, until;

void main() {
  group(
    'selection and code copying through the original fake',
    skip: fakeAgentSkip,
    () {
      for (final size in [const Size(120, 40), const Size(80, 24)]) {
        testWidgets(
          'markdowncode nested, wrapped, blank and range payloads stay exact $size',
          (t) async {
            final connection = await connected(
              t,
              size,
              flags: ['--step-ms', '0'],
            );
            final writes = <String>[];
            await t.pumpWidget(
              TranscriptWindow(
                launch: launch,
                connection: connection,
                copyOnSelect: false,
                copy: (text, _) {
                  writes.add(text);
                  return const copy.CopyResult.sent();
                },
              ),
              size: size,
            );
            await sent(t, connection, 'markdowncode');
            final focus = t.focusManager.primaryFocus;
            await pressBounded(t, 'ctrl+x b c');
            expect(writes, ['bun dev check']);
            await pressBounded(t, 'ctrl+x b up c');
            expect(writes.last, startsWith('bun dev chord'));
            expect(writes.last, endsWith('\n\necho done'));
            await pressBounded(t, 'ctrl+x b up up c');
            expect(writes.last, 'x');
            await pressBounded(t, 'home');
            const prose = 'A paragraph before the code.';
            await select(t, prose);
            expect(writes, hasLength(3));
            await pressBounded(t, 'ctrl+c');
            expect(writes.last, prose);
            final from = cellOf(t, prose, end: true), to = cellOf(t, prose);
            await t.mouse(primary(MouseEventKind.press, from));
            await t.mouse(primary(MouseEventKind.move, to));
            await t.mouse(primary(MouseEventKind.release, to));
            await pressBounded(t, 'ctrl+shift+c');
            expect(writes.last, prose);
            expect(writes, hasLength(5));
            expect(t.focusManager.primaryFocus, same(focus));
            await pressBounded(t, 'ctrl+x b esc');
            expect(t.screen, isNot(shows(pickHint)));
            await t.type('draft');
            expect(connection.app.value.draft, 'draft');
            await t.press('ctrl+c');
            await t.press('ctrl+d');
            expect(t.exitRequested, isTrue);
          },
        );
        testWidgets(
          'streaming open fence never enters current pick until closed $size',
          (t) async {
            final connection = await connected(
              t,
              size,
              flags: ['--step-ms', '2'],
            );
            final writes = <String>[];
            await t.pumpWidget(
              TranscriptWindow(
                launch: launch,
                connection: connection,
                copyOnSelect: false,
                copy: (text, _) {
                  writes.add(text);
                  return const copy.CopyResult.sent();
                },
              ),
              size: size,
            );
            await t.type('markdown');
            await t.press('enter');
            String reply() => connection.app.value.transcript.entries
                .whereType<model.AssistantEntry>()
                .map((e) => e.text.text)
                .join();
            await until(
              () => reply().contains("const session = await openSession"),
            );
            expect(
              connection.app.value.transcript.turn,
              isNot(isA<model.Idle>()),
            );
            await t.pump();
            await pressBounded(t, 'ctrl+x b c');
            expect(writes, [
              'await session.close(); // resolves once the exit is seen',
            ]);
            await until(
              () => connection.app.value.transcript.turn is model.Idle,
            );
            await t.pump();
            await pressBounded(t, 'end');
            await pressBounded(t, 'ctrl+x b c');
            expect(
              writes.last,
              'bun dev compile --all\nfor bin in dist/*/chord; do echo "built \$bin"; done',
            );
            await t.press('ctrl+d');
            expect(t.exitRequested, isTrue);
          },
        );
      }
    },
  );
}
