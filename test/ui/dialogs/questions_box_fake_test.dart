// The window asks the fake agent's question forms (the original's
// tests/fixtures/fake_agent/scenarios/forms.ts) in the question box, as
// the original's Questions.tsx asks them, in the prompt's place.
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
  group('questions in the window', skip: fakeAgentSkip, () {
    late StartConnection connection;
    late List<String> opened;

    Future<void> open(WidgetTester t, Size size) async {
      final directory = Directory.systemTemp.createTempSync('chord-questions-');
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
      testWidgets("claude's questions stand in the prompt's place, and the "
          'answers go back under its fields at $size', (t) async {
        await open(t, size);
        await ask(t, 'askclaude');
        final text = t.screen.text;
        expect(text, contains('fake asks you 2 questions'));
        expect(text, contains('← ◉ Language   ○ Checks   ○ Submit →'));
        expect(text, contains('❯ 1. Deno (TypeScript) (Recommended)'));
        // The prompt box is not drawn while the box has the keys.
        expect(text, isNot(contains('│ ›')));
        await t.press('enter');
        await t.press('space');
        await t.press('down');
        await t.press('down');
        await t.press('space');
        expect(t.screen.text, contains('❯ [✔] 3. Tests'));
        await t.press('enter');
        expect(t.screen.text, contains('Checks    Types, Tests'));
        await t.press('enter');
        await settled(t);
        // What the agent said back; at 80x24 it is scrolled past.
        expect(
          [
            for (final entry in connection.app.value.transcript.entries)
              if (entry is model.AssistantEntry) entry.text.text,
          ].join(),
          contains(
            '{"question_0":"Deno (TypeScript) (Recommended)",'
            '"question_1":["Types","Tests"]}',
          ),
        );
        expect(t.screen.text, contains('│ ›'));
      });

      testWidgets("codex's questions: a secret typed as dots, Esc cancels at "
          '$size', (t) async {
        await open(t, size);
        await ask(t, 'askcodex');
        expect(t.screen.text, matches(RegExp(r'answers itself in [45]:\d\d')));
        await t.press('tab');
        await t.type('sk-1');
        expect(t.screen.text, contains('❯ ••••'));
        await t.press('tab');
        expect(
          t.screen.text,
          contains('Next step  no answer yet, and fake needs one'),
        );
        expect(t.screen.text, isNot(contains('sk-1')));
        await t.press('esc');
        await settled(t);
        expect(t.screen.text, contains('Elicitation answer: cancel'));
      });

      testWidgets('an answered box leaves a row per question under the '
          'turn, saying who asked at $size', (t) async {
        await open(t, size);
        await ask(t, 'askcodex');
        await t.press('2');
        await t.type('sk-1');
        await t.press('enter');
        await t.press('enter');
        await settled(t);
        // Right under the prompt it answers, as a command's outcome is.
        final lines = t.screen.lines;
        final prompt = lines.indexWhere((line) => line.contains('› askcodex'));
        expect(
          lines[prompt + 1],
          contains('⎿  fake asked · Next step  Review existing work'),
        );
        expect(
          t.screen.text,
          matches(RegExp(r'^ +Token {6}\(hidden\)', multiLine: true)),
        );

        await ask(t, 'askclaude');
        await t.press('tab');
        await t.press('tab');
        await t.press('down');
        await t.press('enter');
        await settled(t);
        expect(t.screen.text, contains('⎿  Language, Checks · Skipped'));

        await ask(t, 'askdroid');
        expect(t.screen.text, contains('fake asks you 3 questions'));
        await t.press('esc');
        await settled(t);
        expect(
          t.screen.text,
          contains('⎿  fake asked · Storage, Formats, Bucket · Cancelled'),
        );
      });

      testWidgets("claude's AskUserQuestion call draws the box's record in "
          'place of its own lines at $size', (t) async {
        await open(t, size);
        await ask(t, 'askclaude');
        await t.press('1');
        await t.press('enter');
        await t.press('enter');
        await settled(t);
        final lines = t.screen.lines;
        final call = lines.indexWhere(
          (line) => line.contains('Asking(for your input)'),
        );
        expect(call, isNonNegative);
        expect(
          lines[call + 1],
          contains('⎿  Language  Deno (TypeScript) (Recommended)'),
        );
        expect(lines[call + 2], contains('Checks    skipped'));
        expect(
          t.screen.text,
          isNot(contains('User has answered your questions')),
        );
        expect(t.screen.text, isNot(contains('fake asked ·')));
      });

      testWidgets("claude's lone question reads Asking(<the question>) while "
          'its box is open and once answered at $size', (t) async {
        await open(t, size);
        await ask(t, 'askclaudeone');
        expect(t.screen.text, contains('fake asks you a question'));
        // Above the open box too, as the person reads it while answering.
        expect(
          t.screen.text,
          contains('⏺ Asking(Which language should helper scripts use?)'),
        );
        await t.press('1');
        await t.press('enter');
        await settled(t);
        expect(
          t.screen.text,
          contains('⏺ Asking(Which language should helper scripts use?)'),
        );
        expect(t.screen.text, isNot(contains('Which(language')));
      });

      // CTUI-174: a Note growing to a third row, and deleted back to two,
      // moves the editor within the box; it keeps the keys either way.
      testWidgets('the Note keeps its keys as it grows and shrinks at $size', (
        t,
      ) async {
        const note =
            'alpha bravo charlie delta echo foxtrot golf hotel india juliet '
            'kilo lima mike november oscar papa quebec romeo sierra tango '
            'uniform victor whiskey';
        await open(t, size);
        await ask(t, 'askclaude');
        await t.press('down down');
        await t.type(note);
        await t.pump();
        expect(t.screen, shows('or whiskey'));
        for (var i = 0; i < 24; i++) {
          await t.press('backspace');
        }
        await t.type('Q');
        await t.pump();
        expect(t.screen, shows('sierra tangQ'));
      });
    }
  });
}
