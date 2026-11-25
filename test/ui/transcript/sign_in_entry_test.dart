// A prompt refused for want of a login, drawn as the original's
// Transcript.tsx 153-161: the failure naming the agent, then the sign-in
// block, opened by what the agent says of its account (SignIn.tsx 25-33,
// sign_in.ts 40-60).
import 'package:chord/session/auth_status.dart';
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/session/sign_in.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../app/code_pick_window_test.dart' show pressBounded;
import '../app/selection_window_test.dart';

void main() {
  group('tester CTUI-160: wrapped sign-in selection geometry', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('following nested text and code remain selectable at $size', (
        t,
      ) async {
        final c = selectionConnection([
          model.SubagentEntry(
            't',
            model.Subagent(
              'child',
              title: 'worker',
              state: model.SubagentState.completed,
              entries: [
                const model.ErrorEntry(
                  't',
                  'Authentication required',
                  code: authRequired,
                  signIn: SignIn(
                    'Authentication required',
                    [
                      (
                        name: 'Browser',
                        description:
                            'Open the account login page and complete the sign-in outside chord',
                      ),
                    ],
                    account: AccountHeard({
                      'state': 'authenticated',
                      'accounts': [
                        {
                          'label': 'A long account label',
                          'email': 'long.address.for.wrapping@example.test',
                          'organization': 'Example Organisation',
                        },
                      ],
                    }),
                  ),
                ),
                model.AssistantEntry(
                  't',
                  TextRun.empty.plus('After 界🙂é\n\n```sh\necho after\n```'),
                ),
              ],
            ),
          ),
        ]);
        addTearDown(c.close);
        final writes = <String>[];
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: c,
            copyOnSelect: false,
            copy: (text, _) {
              writes.add(text);
              return const copy.CopyResult.sent();
            },
          ),
          size: size,
        );
        await t.press('ctrl+o');
        await pressBounded(t, 'ctrl+x b c');
        expect(writes, ['echo after']);
        await select(t, 'After 界🙂é');
        await t.press('ctrl+shift+c');
        expect(writes.last, 'After 界🙂é');
        await t.resize(
          size == const Size(120, 40)
              ? const Size(80, 24)
              : const Size(120, 40),
        );
        await pressBounded(t, 'ctrl+x b c');
        expect(writes.last, 'echo after');
      });
    }
  });
  group('CTUI-160: accountReported', () {
    for (final (account, said) in <(AccountState?, String?)>[
      (null, null),
      (noAccount, null),
      (const AccountPending(), null),
      (const AccountFailed(), null),
      (const AccountHeard({'state': 'unknown'}), null),
      (const AccountHeard({'state': 'not_required'}), null),
      (
        const AccountHeard({'state': 'unauthenticated'}),
        'claude reports that no account is signed in.',
      ),
      (
        const AccountHeard({'state': 'authenticated'}),
        'claude reports signed in.',
      ),
      (
        const AccountHeard({
          'state': 'authenticated',
          'accounts': [
            {'label': 'Claude Max', 'email': 'a@example.com'},
            {'label': 'Anthropic API key'},
          ],
        }),
        'claude reports Claude Max · a@example.com, Anthropic API key.',
      ),
      (
        const AccountHeard({
          'state': 'authenticated',
          'accounts': [
            {'label': 'Old'},
            {'label': 'Claude Max', 'active': true},
          ],
        }),
        'claude reports Claude Max.',
      ),
    ]) {
      test('$account says $said', () {
        expect(accountReported('claude', account), said);
      });
    }
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('the error names the agent and opens its block at $size', (
      t,
    ) async {
      await t.pumpWidget(
        const TranscriptEntry(
          model.ErrorEntry(
            't',
            'Authentication required',
            code: authRequired,
            signIn: SignIn('Authentication required', [
              (name: 'Log in', description: 'with a browser'),
              (name: null, description: 'Set ANTHROPIC_API_KEY'),
            ], account: AccountHeard({'state': 'unauthenticated'})),
          ),
          agent: 'claude',
        ),
        size: size,
      );
      final lines = [for (final line in t.screen.lines) line.trimRight()];
      final failure = lines.indexWhere(
        (line) => line.contains('claude needs a sign-in: Authentication'),
      );
      expect(failure, isNot(-1));
      expect(lines.sublist(failure + 1, failure + 5), [
        '  ⎿  claude reports that no account is signed in.',
        '     claude offers these sign-ins:',
        '       Log in · with a browser',
        '       Set ANTHROPIC_API_KEY',
      ]);
      expect(
        lines[failure + 5],
        startsWith('     chord does not sign agents in.'),
      );
      final bold = t.screen.lines[failure + 3].indexOf('Log in');
      expect(t.screen.styleAt(bold, failure + 3).isBold, isTrue);
    });

    testWidgets('without an account heard the block opens with the ways at '
        '$size', (t) async {
      await t.pumpWidget(
        const TranscriptEntry(
          model.ErrorEntry(
            't',
            'Authentication required',
            signIn: SignIn('Authentication required', [
              (name: 'Log in', description: null),
            ], account: AccountPending()),
          ),
          agent: 'claude',
        ),
        size: size,
      );
      expect(t.screen, shows('⎿  claude offers this sign-in:'));
      expect(t.screen, isNot(shows('reports')));
    });
  }

  testWidgets('an error without a sign-in is the failure alone', (t) async {
    await t.pumpWidget(
      const TranscriptEntry(
        model.ErrorEntry('t', 'Authentication required', code: authRequired),
        agent: 'claude',
      ),
      size: const Size(80, 24),
    );
    expect(t.screen, shows('Authentication required'));
    expect(t.screen, isNot(shows('needs a sign-in')));
    expect(t.screen, isNot(shows('chord does not sign agents in')));
  });
}
