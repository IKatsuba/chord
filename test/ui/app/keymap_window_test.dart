// The window's keys follow the keybindings file, from the original's
// tests/ui/shortcuts/bindings_test.ts ("keys follow the file").
import 'dart:async';
import 'dart:convert';

import 'package:chord/acp/connection.dart';
import 'package:chord/cli.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/app/keys.dart' as keys;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/prompt/history.dart' as history;
import 'package:chord/ui/shortcuts/bindings.dart';
import 'package:chord/ui/shortcuts/state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

Launch launchWith(List<Object?> blocks) => Launch(
  name: 'fake',
  agent: null,
  agentCommand: 'fake',
  version: '0.0.1',
  directory: '.',
  keymap: readKeybindings(jsonEncode({'bindings': blocks})).keymap,
);

Future<StartConnection> window(
  WidgetTester t,
  Size size,
  List<Object?> blocks, {
  List<String> files = const [],
}) async {
  final hanging = Completer<Agent>();
  final c = StartConnection(
    command: 'fake',
    cwd: '.',
    agent: 'fake',
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
        }) => hanging.future,
  )..start();
  addTearDown(c.close);
  addTearDown(() {
    hanging.future.ignore();
    hanging.completeError(StateError('over'));
  });
  await t.pumpWidget(
    TranscriptWindow(
      launch: launchWith(blocks),
      connection: c,
      walkFiles: (cwd, {cancellationToken}) async => files,
    ),
    size: size,
  );
  return c;
}

/// The command the list highlights: the one row drawn unlike the others.
String highlighted(WidgetTester t) {
  final rows = [
    for (var y = 0; y < t.screen.lines.length; y++)
      if (t.screen.lines[y].startsWith('  /')) y,
  ];
  final styles = [for (final y in rows) t.screen.styleAt(2, y)];
  final odd = rows.where(
    (y) => styles.where((s) => s == t.screen.styleAt(2, y)).length == 1,
  );
  return t.screen.lines[odd.single].trim().split(' ').first;
}

void main() {
  group('the window names each key by its action', () {
    keys.KeyContext context([AppState state = const AppState()]) =>
        keys.KeyContext(
          state: state,
          history: const history.History(),
          rows: 24,
        );

    test('every action-bound window key carries its action', () {
      final ids = {
        for (final b in keys.windowBindings(() => context(), (_) {}))
          '${b.chord}': b.id,
      };
      expect(ids['ctrl+o'], 'app:toggleTranscript');
      expect(ids['ctrl+r'], 'history:search');
      expect(ids['ctrl+v'], 'chat:imagePaste');
      expect(ids['?'], 'help:toggle');
      expect(ids['escape'], 'chat:cancel');
      expect(ids['shift+tab'], 'chat:cycleMode');
      expect(ids['ctrl+x a'], 'session:attention');
      expect(ids['ctrl+x b'], 'codeBlock:pick');
      expect(ids['ctrl+shift+c'], 'selection:copy');
      expect(ids['shift+pageup'], 'scroll:pageUp');
      expect(ids['end'], 'scroll:bottom');
      // ctrl+c and ctrl+d no file may take, and bash mode's keys are no
      // action of the file's.
      expect(ids['ctrl+c'], isNull);
      expect(ids['ctrl+d'], isNull);
      expect(ids['!'], isNull);
    });

    test('one key is the action of the context on screen', () {
      expect(keys.windowAction('esc', context()), 'chat:cancel');
      expect(
        keys.windowAction(
          'esc',
          context(const AppState(shortcuts: ShortcutsState(help: true))),
        ),
        'help:dismiss',
      );
    });

    test('a moved binding does what its action does', () {
      final moved = Binding(
        'ctrl+t',
        'Toggle',
        () {},
        id: 'app:toggleTranscript',
      );
      expect(keys.actionChord(moved), Chord.parse('ctrl+o'));
      expect(keys.actionChord(Binding('!', 'Bash', () {})), Chord.parse('!'));
    });
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('a printable key the file binds does its action and types '
        'nothing, at $size', (t) async {
      final c = await window(t, size, [
        {
          'context': 'Global',
          'bindings': {'t': 'app:toggleTranscript', 'ctrl+o': null},
        },
      ]);
      await t.type('ab');
      await t.press('t');
      expect(c.app.value.expanded, isTrue);
      expect(t.screen.text, contains('› ab '));
      expect(t.screen.text, isNot(contains('› abt')));
    });

    testWidgets('a shifted character that is no letter presses the key a '
        'binding names, at $size', (t) async {
      final c = await window(t, size, [
        {
          'context': 'Chat',
          'bindings': {'#': 'help:toggle'},
        },
      ]);
      t.host.handleKey(const KeyEvent('#', shift: true));
      await t.pump();
      expect(c.app.value.shortcuts.help, isTrue);
    });

    testWidgets('? on a draft is text, shifted or not, and opens the panel '
        'on an empty prompt, at $size', (t) async {
      final c = await window(t, size, []);
      await t.type('a');
      await t.press('?');
      t.host.handleKey(const KeyEvent('?', shift: true));
      await t.pump();
      expect(t.screen.text, contains('› a??'));
      expect(c.app.value.shortcuts.help, isFalse);
      for (var i = 0; i < 3; i++) {
        await t.press('backspace');
      }
      t.host.handleKey(const KeyEvent('?', shift: true));
      await t.pump();
      expect(c.app.value.shortcuts.help, isTrue);
    });

    testWidgets('with ? unbound the header and the status line name no '
        'shortcuts key, at $size', (t) async {
      await window(t, size, [
        {
          'context': 'Chat',
          'bindings': {'?': null},
        },
      ]);
      expect(t.screen.text, contains('/help'));
      expect(t.screen.text, isNot(contains('for shortcuts')));
    });

    testWidgets('the panel and the header name the keys the file binds, at '
        '$size', (t) async {
      await window(t, size, [
        {
          'context': 'Chat',
          'bindings': {
            '!': 'help:toggle',
            'enter': null,
            'ctrl+s': 'chat:submit',
          },
        },
      ]);
      expect(t.screen.text, contains('? for shortcuts · /help'));
      await t.press('!');
      expect(
        t.screen.text,
        contains(r'shift + enter or \ + ctrl + s for a newline'),
      );
      // The panel's last row, where the window is short.
      await t.press('end');
      expect(t.screen.text, contains('? ! for shortcuts'));
    });

    testWidgets('a moved key does the action, and the old one nothing, at '
        '$size', (t) async {
      final c = await window(t, size, [
        {
          'context': 'Global',
          'bindings': {'ctrl+t': 'app:toggleTranscript', 'ctrl+o': null},
        },
      ]);
      await t.press('ctrl+o');
      expect(c.app.value.expanded, isFalse);
      await t.press('ctrl+t');
      expect(c.app.value.expanded, isTrue);
    });

    testWidgets('help moved off ? types ? into the prompt, and its new key '
        'opens the panel, at $size', (t) async {
      final c = await window(t, size, [
        {
          'context': 'Chat',
          'bindings': {'?': null, 'ctrl+t': 'help:toggle'},
        },
      ]);
      await t.press('?');
      expect(c.app.value.shortcuts.help, isFalse);
      expect(t.screen.text, contains('› ?'));
      await t.press('backspace');
      await t.press('ctrl+t');
      expect(c.app.value.shortcuts.help, isTrue);
    });

    for (final key in ['j', 'ctrl+k']) {
      testWidgets('the command list moves on the file\'s $key and the draft '
          'keeps it, at $size', (t) async {
        final c = await window(t, size, [
          {
            'context': 'Autocomplete',
            'bindings': {key: 'autocomplete:next'},
          },
        ]);
        await t.type('/');
        await t.press(key);
        expect(t.screen.text, contains('› / '));
        await t.press('tab');
        expect(c.app.value.draft, startsWith('/config'));
      });
    }

    // A list open over the prompt takes every key it binds, whatever the
    // prompt or the text area would do with it.
    for (final key in ['enter', 'tab', 'x', 'ctrl+j']) {
      for (final action in [
        'autocomplete:previous',
        'autocomplete:next',
        'autocomplete:accept',
        'autocomplete:dismiss',
      ]) {
        testWidgets('the command list does $action on $key, at $size', (
          t,
        ) async {
          final c = await window(t, size, [
            {
              'context': 'Autocomplete',
              'bindings': {key: action},
            },
          ]);
          await t.type('/');
          if (action == 'autocomplete:previous') await t.press('down');
          await t.press(key);
          final draft = c.app.value.draft;
          expect(draft, isNot(contains('\n')));
          expect(draft, isNot(contains('x')));
          switch (action) {
            case 'autocomplete:accept':
              expect(draft, startsWith('/clear'));
            case 'autocomplete:dismiss':
              expect(draft, '/');
              expect(t.screen.text, isNot(contains('/config')));
            default:
              expect(draft, '/');
              expect(highlighted(t), switch (action) {
                'autocomplete:next' => '/config',
                _ => '/clear',
              });
          }
        });
      }
    }

    testWidgets('a list chord overlapping a prompt key mounts and moves, at '
        '$size', (t) async {
      final c = await window(t, size, [
        {
          'context': 'Chat',
          'bindings': {'ctrl+s': 'chat:submit'},
        },
        {
          'context': 'Autocomplete',
          'bindings': {'ctrl+s x': 'autocomplete:next'},
        },
      ]);
      await t.type('/');
      await t.press('ctrl+s');
      await t.press('x');
      expect(c.app.value.draft, '/');
      expect(highlighted(t), '/config');
    });

    testWidgets('the shortcuts panel open takes the keys it binds, at $size', (
      t,
    ) async {
      final c = await window(t, size, [
        {
          'context': 'Help',
          'bindings': {'q': 'help:dismiss'},
        },
      ]);
      await t.press('?');
      expect(c.app.value.shortcuts.help, isTrue);
      await t.press('q');
      expect(c.app.value.shortcuts.help, isFalse);
      expect(c.app.value.draft, '');
    });

    testWidgets('the file finder moves on a text area key the file gives it, '
        'at $size', (t) async {
      final c = await window(
        t,
        size,
        [
          {
            'context': 'Autocomplete',
            'bindings': {'ctrl+j': 'autocomplete:next'},
          },
        ],
        files: ['alpha', 'beta'],
      );
      await t.type('@');
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
      await t.press('ctrl+j');
      expect(c.app.value.draft, isNot(contains('\n')));
      await t.press('tab');
      expect(c.app.value.draft, '@beta ');
    });

    testWidgets('the command list closes on the file\'s dismiss key, at '
        '$size', (t) async {
      await window(t, size, [
        {
          'context': 'Autocomplete',
          'bindings': {'escape': null, 'ctrl+g': 'autocomplete:dismiss'},
        },
      ]);
      await t.type('/');
      expect(t.screen.text, contains('/clear'));
      await t.press('esc');
      expect(t.screen.text, contains('/clear'));
      await t.press('ctrl+g');
      expect(t.screen.text, isNot(contains('/clear')));
    });

    testWidgets("a text area key the file gives the window is the window's, "
        'at $size', (t) async {
      final c = await window(t, size, [
        {
          'context': 'Chat',
          'bindings': {'ctrl+k': 'help:toggle'},
        },
      ]);
      await t.press('ctrl+k');
      expect(c.app.value.shortcuts.help, isTrue);
    });

    testWidgets('a key the file binds is its action ahead of bash mode, at '
        '$size', (t) async {
      final c = await window(t, size, [
        {
          'context': 'Chat',
          'bindings': {'!': 'help:toggle'},
        },
      ]);
      await t.press('!');
      expect(c.app.value.shortcuts.help, isTrue);
      expect(c.app.value.bash, isFalse);
    });

    testWidgets('a moved chord waits on its first key, at $size', (t) async {
      await window(t, size, [
        {
          'context': 'Global',
          'bindings': {'ctrl+x t': 'codeBlock:pick', 'ctrl+x b': null},
        },
      ]);
      await t.press('ctrl+x');
      await t.press('b');
      expect(t.screen.text, isNot(contains('No code block')));
      await t.press('ctrl+x');
      await t.press('t');
      expect(t.screen.text, contains('No code block'));
    });
  }
}
