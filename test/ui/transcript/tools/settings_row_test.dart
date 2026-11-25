// The settings tool's rows, its box's choices and hint, and what a saved
// setting changes at once, as the original's settings_row.ts,
// permission.ts saveChoices and setting_picked_up.ts have them.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/setting_picked_up.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/settings.dart';
import 'package:chord/ui/dialogs/permission.dart' show saveChoices;
import 'package:chord/ui/dialogs/permission_prompt.dart' show permissionHint;
import 'package:chord/ui/transcript/tools/settings_row.dart';
import 'package:chord/ui/transcript/tools/tools.dart' show Headline;
import 'package:test/test.dart';

ChordCall _call(
  Map<String, Object?> input,
  Object? answer, {
  bool pending = false,
  String? asked,
  ({String user, String project})? files,
}) => ChordCall(
  tool: ChordTool.settings,
  input: input,
  answer: answer,
  pending: pending,
  asked: asked,
  settingsFiles: files,
);

List<String> _drawn(List<SettingsRow>? rows) => [
  for (final row in rows ?? const <SettingsRow>[]) '${row.label}${row.text}',
];

void main() {
  test("a change: now and after, the project that wins, then what became "
      'of it', () {
    const input = {
      'action': 'set',
      'path': ['agent'],
      'value': 'codex',
    };
    final waiting = settingsRows(
      _call(input, {
        'before': 'claude',
        'after': 'codex',
        'shadowedBy': '.chord/settings.json',
      }),
      expanded: false,
      width: 60,
    )!;
    expect(_drawn(waiting), [
      'Now    "claude"',
      'After  "codex"',
      '.chord/settings.json sets this too, and wins here',
    ]);
    expect(waiting.last.tone, SettingsTone.warning);
    final saved = settingsRows(
      _call(input, {
        'after': 'codex',
        'saved': true,
        'file': '~/s.json',
        'takesEffect': 'next start',
      }),
      expanded: false,
      width: 60,
    )!;
    expect(_drawn(saved), [
      'Now    not set',
      'After  "codex"',
      'Saved to ~/s.json · takes effect at the next start',
    ]);
    expect(saved.last.tone, SettingsTone.success);
    expect(
      _drawn(
        settingsRows(
          _call(input, {'before': 'a', 'saved': false}),
          expanded: false,
          width: 60,
        ),
      ).last,
      'Not saved · the person will say what to change',
    );
    expect(
      _drawn(
        settingsRows(
          _call(input, {'before': 'codex', 'unchanged': true}),
          expanded: false,
          width: 60,
        ),
      ),
      ['Already "codex"; nothing to change'],
    );
    expect(
      settingsRows(_call(input, null), expanded: false, width: 60),
      isNull,
    );
  });

  test('a long value wraps under its own column, never cut', () {
    final rows = settingsRows(
      _call({'action': 'set'}, {'after': 'x' * 20}),
      expanded: false,
      width: 15,
    )!;
    expect(_drawn(rows), [
      'Now    not set',
      'After  "xxxxxxx',
      '       xxxxxxxx',
      '       xxxxx"',
    ]);
  });

  test('a read of one key draws its three layers; of every key, its files '
      'folded, then the answer whole', () {
    expect(
      _drawn(
        settingsRows(
          _call(
            {
              'action': 'read',
              'path': ['agent'],
            },
            {'effective': 'a', 'user': 'a', 'problems': <Object?>[]},
          ),
          expanded: false,
          width: 60,
        ),
      ),
      ['Effective  "a"', 'User       "a"', 'Project    not set'],
    );
    final every = _call(
      {'action': 'read'},
      {
        'user': {'theme': 'dark'},
        'problems': [
          {'file': 'f', 'message': 'm'},
        ],
      },
      files: (
        user: '~/s.json · 1 key',
        project: '.chord/settings.json · not there',
      ),
    );
    expect(_drawn(settingsRows(every, expanded: false, width: 60)), [
      'User     ~/s.json · 1 key',
      'Project  .chord/settings.json · not there',
      '1 problem',
    ]);
    expect(_drawn(settingsRows(every, expanded: true, width: 60)).first, '{');
    const line = Headline('Settings', note: ' · read');
    expect(
      foldedSettingsNote(line, every, expanded: false, key: 'ctrl+o').note,
      ' · read (ctrl+o to expand)',
    );
    expect(
      foldedSettingsNote(line, every, expanded: true, key: 'ctrl+o'),
      same(line),
    );
  });

  test("a change taller than the transcript's room overflows; one that fits, "
      'or another call, does not', () {
    final entries = <Entry>[
      ToolEntry(
        't',
        ToolCall(
          'c1',
          chord: _call(
            {
              'action': 'set',
              'path': ['agent'],
            },
            {'after': 'x' * 300},
            pending: true,
            asked: 'a1',
          ),
        ),
      ),
    ];
    expect(settingsChangeOverflows(entries, 'a1', 40, 5), isTrue);
    expect(settingsChangeOverflows(entries, 'a1', 40, 50), isFalse);
    expect(settingsChangeOverflows(entries, 'other', 40, 5), isFalse);
    expect(settingsChangeOverflows(entries, null, 40, 5), isFalse);
  });

  test("the box's choices are numbered, and its hint says what no does and, "
      'overflowing, the key that reads the change', () {
    final wait = PermissionWait(
      'p',
      options: [
        acp.PermissionOption.fromJson({
          'optionId': 'yes',
          'name': 'Yes, in ~/s.json',
          'kind': 'allow_once',
        }),
        acp.PermissionOption.fromJson({
          'optionId': 'no',
          'name': 'No, tell fake what to change',
          'kind': 'reject_once',
        }),
      ],
      save: const SaveBox(
        question: 'Set theme?',
        escape: 'tell fake what to change',
      ),
    );
    expect(
      [for (final c in saveChoices(wait)) c.label],
      ['1. Yes, in ~/s.json', '2. No, tell fake what to change'],
    );
    expect(
      permissionHint(wait, held: false, reject: 'esc'),
      'Esc to tell fake what to change',
    );
    expect(
      permissionHint(wait, held: false, reject: 'esc', pageUp: 'pageup'),
      'Esc to tell fake what to change · pageup to read the whole change',
    );
  });

  test('a saved theme, editor mode or offered agents is taken up; any other '
      'key waits for the next start', () {
    expect(
      (settingPickedUp(['theme'], const SetSetting('light'))! as ThemePickedUp)
          .theme,
      'light',
    );
    expect(
      (settingPickedUp(['theme'], const RemoveSetting())! as ThemePickedUp)
          .theme,
      'auto',
    );
    expect(
      (settingPickedUp(['editorMode'], const SetSetting('vim'))!
              as EditorModePickedUp)
          .vim,
      isTrue,
    );
    expect(
      (settingPickedUp(['editorMode'], const RemoveSetting())!
              as EditorModePickedUp)
          .vim,
      isFalse,
    );
    expect(
      (settingPickedUp(['offeredAgents'], const SetSetting(['codex']))!
              as OfferedAgentsPickedUp)
          .offered,
      ['codex'],
    );
    for (final path in [
      ['mouse'],
      ['agent'],
      ['agents', 'codex', 'model'],
      ['theme', 'deeper'],
    ]) {
      expect(settingPickedUp(path, const SetSetting('x')), isNull);
    }
  });
}
