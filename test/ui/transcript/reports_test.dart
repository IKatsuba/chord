import 'package:chord/session/agent_state.dart';
import 'package:chord/session/auth_status.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/transcript/reports.dart';
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester CTUI-160: account projection boundaries', () {
    test('all active accounts retain order and suppress inactive accounts', () {
      final accounts = <Map<String, Object?>>[
        {'label': 'old', 'active': false},
        {'label': '界👩‍💻é', 'active': true},
        {'label': 'second', 'active': true},
        {'label': 'unmarked'},
      ];
      expect(shownAccounts(accounts), [accounts[1], accounts[2]]);
      expect(
        accountRows(
          AccountHeard({'state': 'authenticated', 'accounts': accounts}),
          'fake',
        ),
        ['界👩‍💻é', 'second'],
      );
      expect(accounts, hasLength(4));
    });

    test('an account with no printable parts remains an empty account row', () {
      expect(
        accountRows(
          const AccountHeard({
            'state': 'authenticated',
            'accounts': [
              {
                'label': '\x1b[31m\x1b[0m',
                'description': ' \n ',
                'name': null,
                'email': 1,
                'organization': '',
              },
            ],
          }),
          'fake',
        ),
        [''],
      );
      expect(
        accountLine({
          'label': ' A ',
          'description': ' B ',
          'name': ' C ',
          'email': ' D ',
          'organization': ' E ',
        }),
        'A · B · C · D · E',
      );
    });

    test('non-authenticated states ignore stale account details', () {
      for (final (state, expected) in [
        ('unauthenticated', 'not signed in'),
        ('not_required', 'none needed'),
        ('unknown', 'not reported by fake'),
      ]) {
        expect(
          accountRows(
            AccountHeard({
              'state': state,
              'accounts': [
                {'label': 'stale', 'active': true},
              ],
            }),
            'fake',
          ),
          [expected],
        );
      }
    });
  });
  group('tester: status title cleaning boundaries', () {
    for (final (title, expected) in <(String?, String)>[
      (null, 'not given'),
      ('', ''),
      (' \t\r\n ', ''),
      ('Fix\x1b[31m  the\nparser', 'Fix the parser'),
      ('\u00a0日本語\u2003e\u0301🙂\u2028done\ufeff', '日本語 e\u0301🙂 done'),
      ('\x1b]8;;https://example.test\x07title\x1b]8;;\x07', 'title'),
    ]) {
      test('cleans ${title?.codeUnits} as the original status row', () {
        final rows = statusReport(
          AgentState.empty,
          agent: 'fake',
          cwd: '/workspace',
          title: title,
        );
        expect(rows[1], (label: 'Title:', text: expected));
        expect(
          rows.map((row) => row.label).where((label) => label == 'Title:'),
          hasLength(1),
        );
      });
    }
  });

  test('status preserves unknown mode, says a missing title is not given and '
      'omits the unavailable account', () {
    final rows = statusReport(
      AgentState.empty,
      agent: 'fake',
      cwd: '/workspace',
      fallbackMode: 'unknown',
    );
    expect(rows, [
      (label: 'Agent:', text: 'fake'),
      (label: 'Title:', text: 'not given'),
      (label: 'Model:', text: 'not reported by fake'),
      (label: 'Mode:', text: 'unknown'),
      (label: 'Session:', text: 'starting…'),
      (label: 'Directory:', text: '/workspace'),
    ]);
  });
  // CTUI-113: the original's Title row, after Agent, the agent's string
  // without its escapes and on one line.
  test('status gives a title as one clean line after the agent', () {
    final rows = statusReport(
      AgentState.empty,
      agent: 'fake',
      cwd: '/workspace',
      title: '  \x1b[1mFix the\n  parser\x1b[0m\t tests  ',
    );
    expect(rows.take(2), [
      (label: 'Agent:', text: 'fake'),
      (label: 'Title:', text: 'Fix the parser tests'),
    ]);
  });

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'status rows retain original command gutter and aligned dim labels at $size',
      (t) async {
        await t.pumpWidget(
          TranscriptEntry(
            model.ReportEntry(
              'report',
              'status',
              statusReport(
                AgentState.empty,
                agent: 'fake',
                cwd: '/workspace',
                sessionId: 'one',
              ),
            ),
          ),
          size: size,
        );
        expect(t.screen, shows('› /status'));
        expect(t.screen, shows('⎿  Agent:     fake'));
        expect(t.screen, shows('Title:     not given'));
        expect(t.screen, shows('Directory: /workspace'));
        expect(t.screen.styleAt(5, 2).isDim, isTrue);
      },
    );
  }

  group('CTUI-160: the Account row', () {
    List<model.ReportRow> status(AccountState account) => statusReport(
      AgentState.empty,
      agent: 'fake',
      cwd: '/workspace',
      sessionId: 'one',
      account: account,
    );

    test('no row where the agent does not advertise auth.status', () {
      expect(
        status(noAccount).map((row) => row.label),
        isNot(contains('Account:')),
      );
      expect(accountRows(noAccount, 'fake'), isEmpty);
    });

    for (final (name, account, said) in <(String, AccountState, String)>[
      ('pending', const AccountPending(), 'checking…'),
      ('failed', const AccountFailed(), 'not reported by fake'),
      (
        'signed in without accounts',
        const AccountHeard({'state': 'authenticated'}),
        'signed in',
      ),
      (
        'signed in with an empty list',
        const AccountHeard({'state': 'authenticated', 'accounts': []}),
        'signed in',
      ),
      (
        'not signed in',
        const AccountHeard({'state': 'unauthenticated'}),
        'not signed in',
      ),
      (
        'none needed',
        const AccountHeard({'state': 'not_required'}),
        'none needed',
      ),
      (
        'unknown',
        const AccountHeard({'state': 'unknown'}),
        'not reported by fake',
      ),
      (
        'the active account, its parts cleaned and joined',
        const AccountHeard({
          'state': 'authenticated',
          'accounts': [
            {'label': 'Old', 'active': false},
            {
              'label': '\x1b[1mClaude Max\x1b[0m',
              'description': '',
              'name': 'A  Name',
              'email': 'name@example.com',
              'organization': 'Example\nOrg',
              'active': true,
            },
          ],
        }),
        'Claude Max · A Name · name@example.com · Example Org',
      ),
    ]) {
      test('$name: Account says "$said", right after Agent', () {
        final rows = status(account);
        expect(rows[0], (label: 'Agent:', text: 'fake'));
        expect(rows[1], (label: 'Account:', text: said));
        expect(rows[2].label, 'Title:');
        expect(rows, hasLength(7));
      });
    }

    test('several accounts, none active: each after an empty row, its label '
        'left blank, before Title', () {
      final rows = status(
        const AccountHeard({
          'state': 'authenticated',
          'accounts': [
            {'label': 'Claude Max', 'email': 'a@example.com'},
            {'label': 'Anthropic API key', 'description': 'ANTHROPIC_API_KEY'},
            {'name': 'Third'},
          ],
        }),
      );
      expect(rows.take(7), [
        (label: 'Agent:', text: 'fake'),
        (label: 'Account:', text: 'Claude Max · a@example.com'),
        (label: '', text: ''),
        (label: ' ', text: 'Anthropic API key · ANTHROPIC_API_KEY'),
        (label: '', text: ''),
        (label: ' ', text: 'Third'),
        (label: 'Title:', text: 'not given'),
      ]);
    });

    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('several accounts line up under the first at $size', (
        t,
      ) async {
        await t.pumpWidget(
          TranscriptEntry(
            model.ReportEntry(
              'report',
              'status',
              status(
                const AccountHeard({
                  'state': 'authenticated',
                  'accounts': [
                    {'label': 'Claude Max'},
                    {'label': 'Anthropic API key'},
                  ],
                }),
              ),
            ),
          ),
          size: size,
        );
        expect(t.screen, shows('⎿  Agent:     fake'));
        expect(t.screen.lines[3], startsWith('     Account:   Claude Max'));
        expect(t.screen.lines[4].trimRight(), '');
        expect(
          t.screen.lines[5],
          startsWith('                Anthropic API key'),
        );
        expect(t.screen.lines[6], startsWith('     Title:     not given'));
      });
    }
  });
}
