// The window asks the fake agent's `form` and `link` (the original's
// tests/fixtures/fake_agent/scenarios/forms.ts) in the prompt's place, as
// the original's Form.tsx and Link.tsx do, and leaves their record.
@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/acp/connection.dart' show windowCapabilities;
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/dev.dart' show shellWord;
import '../../fixtures/fake_harness.dart';
import '../app/window_fake_test.dart' show launch, until;

void main() {
  group('forms and links in the window', skip: fakeAgentSkip, () {
    late StartConnection connection;
    late List<String> opened;

    Future<void> open(WidgetTester t, Size size) async {
      final directory = Directory.systemTemp.createTempSync('chord-form-');
      opened = [];
      connection = StartConnection(
        command: fakeAgentCommand().map(shellWord).join(' '),
        cwd: directory.path,
        agent: 'fake',
        open: fakeOpenerWith(capabilities: windowCapabilities()),
        owner: Owned(),
      )..start();
      addTearDown(() async {
        await connection.close();
        directory.deleteSync(recursive: true);
      });
      await until(
        () => connection.app.value.start.phase == StartPhase.connected,
      );
      await t.pumpWidget(
        TranscriptWindow(
          launch: launch,
          connection: connection,
          openUrl: (url) async {
            opened.add(url);
            return null;
          },
        ),
        size: size,
      );
    }

    Future<void> ask(WidgetTester t, String scenario) async {
      await t.type(scenario);
      await t.press('enter');
      await until(() => connection.app.value.transcript.asking.isNotEmpty);
      await t.pump();
    }

    Future<void> settled(WidgetTester t) async {
      await until(() => connection.app.value.transcript.turn is model.Idle);
      await t.pump();
    }

    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('a form stands in the prompt\'s place, its record after at '
          '$size', (t) async {
        await open(t, size);
        await ask(t, 'form');
        final text = t.screen.text;
        expect(text, contains('fake asks for input'));
        expect(text, contains('Set up the deploy target'));
        expect(text, contains('❯ * Project name'));
        expect(text, contains('  Accept   Decline'));
        expect(text, contains('Waiting for your input…'));
        // The prompt box is not drawn while the form has the keys.
        expect(text, isNot(contains('│ ›')));
        expect(
          text,
          contains(
            size.width >= 100
                ? 'Type to fill in · ↑↓ to move · Enter for the next · Esc to cancel'
                : 'Type to fill in · ↑↓ to move · Esc to cancel',
          ),
        );

        // Typed text and ?, which is the prompt's help elsewhere, go in.
        await t.type('ab?');
        expect(t.screen.text, contains('Project name   ab?'));
        await t.press('backspace');
        await t.type('c');
        await t.press('tab');
        await t.press('tab');
        await t.press('tab');
        await t.press('tab');
        await t.press('tab');
        await t.press('space');
        await t.press('2');
        await t.press('tab');
        await t.press('tab');
        expect(t.screen.text, contains('❯ Accept   Decline'));
        await t.press('enter');
        await settled(t);
        final after = t.screen.text;
        expect(after, contains('⏺ fake asked: Set up the deploy target'));
        expect(after, contains('⎿  Answered · 4 fields'));
        expect(after, contains('│ ›'));
        expect(
          after,
          contains('"name":"abc","replicas":2,"public":false,"region":"us"'),
        );
        // ctrl+o shows the values sent, as the form showed them.
        await t.press('ctrl+o');
        expect(t.screen.text, contains('Region        United States'));
        expect(t.screen.text, contains('Public        No'));
      });

      testWidgets('Decline and Esc answer as such at $size', (t) async {
        await open(t, size);
        await ask(t, 'form');
        for (var i = 0; i < 7; i++) {
          await t.press('tab');
        }
        await t.press('right');
        await t.press('enter');
        await settled(t);
        expect(t.screen.text, contains('⎿  Declined'));
        expect(t.screen.text, contains('Elicitation answer: decline'));
        await ask(t, 'form');
        await t.press('esc');
        await settled(t);
        expect(t.screen.text, contains('⎿  Cancelled'));
        expect(t.screen.text, contains('Elicitation answer: cancel'));
      });

      testWidgets('a link names its host, opens on its choice and says so at '
          '$size', (t) async {
        await open(t, size);
        await ask(t, 'link');
        final text = t.screen.text;
        expect(text, contains('fake asks you to open a link'));
        expect(text, contains('Sign in to Example to continue'));
        expect(
          text,
          contains(
            '  https://example.com/oauth/authorize?client=abc&state=9f2c',
          ),
        );
        expect(text, contains('  Opens example.com'));
        expect(text, contains('❯ 1. Open in the browser'));
        expect(text, contains('  2. Decline'));
        expect(text, contains('Enter to choose · Esc to cancel'));
        await t.press('enter');
        await settled(t);
        expect(opened, [
          'https://example.com/oauth/authorize?client=abc&state=9f2c',
        ]);
        expect(
          t.screen.text,
          contains(
            '⎿  Opened https://example.com/oauth/authorize?client=abc&state=9f2c',
          ),
        );
        expect(t.screen.text, contains('Elicitation answer: accept'));
        await ask(t, 'link');
        await t.press('esc');
        await settled(t);
        expect(opened, hasLength(1));
        expect(t.screen.text, contains('⎿  Cancelled'));
      });
    }
  });
}
