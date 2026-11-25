// `/status`'s Account row in the window, from what the fake says of its
// account, as the original's reports.ts statusReport lays it out.
@Tags(['fake_agent'])
library;

import 'package:chord/session/auth_status.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fixture;

void main() {
  group(
    'tester CTUI-160: live account report boundaries',
    skip: fakeAgentSkip,
    () {
      for (final (mode, expected) in [
        ('hang', 'checking…'),
        ('error', 'not reported by fake'),
        ('unauthenticated', 'not signed in'),
        ('unknown', 'not reported by fake'),
      ]) {
        testWidgets('$mode account is shown after a resize', (t) async {
          final c = await fixture.connected(
            t,
            const Size(120, 40),
            flags: ['--auth-status', mode],
          );
          await fixture.until(
            () => switch (mode) {
              'hang' => c.conversation.session?.account is AccountPending,
              'error' => c.conversation.session?.account is AccountFailed,
              _ => c.conversation.session?.account is AccountHeard,
            },
          );
          await t.type('/status');
          await t.press('enter');
          await t.pump();
          await t.resize(const Size(80, 24));
          expect(t.screen, shows('Account:   $expected'));
          await t.press('ctrl+d');
          expect(t.exitRequested, isTrue);
        });
      }

      testWidgets(
        'a later account push affects only subsequent status reports',
        (t) async {
          final c = await fixture.connected(
            t,
            const Size(80, 24),
            flags: ['--auth-status', 'authenticated'],
          );
          await fixture.until(
            () => c.conversation.session?.account is AccountHeard,
          );
          await t.type('/status');
          await t.press('enter');
          await t.pump();
          final first = c.app.value.transcript.entries
              .whereType<model.ReportEntry>()
              .single;
          expect(first.rows[1].text, contains('Claude Max'));
          await fixture.sent(t, c, 'authchanged');
          await t.type('/status');
          await t.press('enter');
          await t.pump();
          final reports = c.app.value.transcript.entries
              .whereType<model.ReportEntry>()
              .toList();
          expect(reports, hasLength(2));
          expect(reports.first.rows[1].text, contains('Claude Max'));
          expect(
            reports.last.rows[1].text,
            'Anthropic API key · ANTHROPIC_API_KEY',
          );
          expect(t.screen, shows('Anthropic API key'));
        },
      );
    },
  );
  group('CTUI-160: /status says the account', skip: fakeAgentSkip, () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('two accounts, none active, at $size', (t) async {
        final c = await fixture.connected(
          t,
          size,
          flags: ['--auth-status', 'several'],
        );
        await fixture.until(
          () => c.conversation.session?.account is AccountHeard,
        );
        await t.type('/status');
        await t.pump();
        await t.press('enter');
        await t.pump();
        final rows = c.app.value.transcript.entries
            .whereType<model.ReportEntry>()
            .single
            .rows;
        expect(rows[0], (label: 'Agent:', text: 'fake'));
        expect(rows[1], (
          label: 'Account:',
          text:
              'Claude Max · '
              'a.very.long.address.for.the.capture@engineering.example.com · '
              'Example Organisation of Long Names',
        ));
        expect(rows[2], (label: '', text: ''));
        expect(rows[3], (
          label: ' ',
          text: 'Anthropic API key · ANTHROPIC_API_KEY',
        ));
        expect(rows[4].label, 'Title:');
        expect(t.screen, shows('Account:   Claude Max'));
        expect(t.screen, shows('Anthropic API key · ANTHROPIC_API_KEY'));
      });

      testWidgets('no Account row from an agent without auth.status at $size', (
        t,
      ) async {
        final c = await fixture.connected(t, size);
        await fixture.until(() => c.app.value.start.sessionId != null);
        await t.type('/status');
        await t.pump();
        await t.press('enter');
        await t.pump();
        expect(t.screen, shows('Agent:'));
        expect(t.screen, isNot(shows('Account:')));
      });
    }
  });
}
