// The keybindings file, from the original's tests/ui/shortcuts/bindings_test.ts.
// The cases that press keys in the window come with the window's keymap.
import 'dart:convert';
import 'dart:io';

import 'package:chord/settings.dart';
import 'package:chord/ui/shortcuts/bindings.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A keybindings file of [blocks], read.
({Keybindings keymap, List<String> problems}) read(List<Object?> blocks) =>
    readKeybindings(jsonEncode({'bindings': blocks}));

Sequence keys(String text) {
  final parsed = parseSequence(text);
  expect(parsed.value, isNotNull, reason: '$text does not parse');
  return parsed.value!;
}

void main() {
  test("a keystroke reads Claude Code's spellings", () {
    expect(
      parseKeystroke('ctrl+shift+p').value,
      const Keystroke('p', ctrl: true, shift: true),
    );
    // Names are read whatever their case, and every alias means its key.
    expect(parseKeystroke('Control+K').value, parseKeystroke('ctrl+k').value);
    expect(parseKeystroke('meta+p').value, parseKeystroke('alt+p').value);
    expect(parseKeystroke('option+p').value, parseKeystroke('alt+p').value);
    expect(parseKeystroke('command+k').value, parseKeystroke('cmd+k').value);
    expect(parseKeystroke('esc').value, parseKeystroke('escape').value);
    expect(parseKeystroke('return').value, parseKeystroke('enter').value);
    expect(parseKeystroke('ctrl++').value, const Keystroke('+', ctrl: true));
  });

  test('a keystroke that is no key says why', () {
    expect(parseKeystroke('ctl+k').problem, '"ctl" is not a modifier');
    expect(parseKeystroke('ctrl+foo').problem, '"foo" is not a key');
    expect(
      parseKeystroke('wheelup').problem,
      'the wheel always scrolls the transcript and cannot be bound',
    );
    expect(parseSequence('  ').problem, 'no key');
  });

  test('a chord is its keystrokes in order, named back as written', () {
    final chord = keys('ctrl+x  ctrl+e');
    expect(chord.length, 2);
    expect(sequenceHint(chord), 'ctrl+x ctrl+e');
    expect(sequencePanel(chord), 'ctrl + x ctrl + e');
    expect(sequencePanel(keys('shift+up')), 'shift + ↑');
    expect(sequenceHint(keys('escape')), 'esc');
  });

  test('with no file, every action has the keys it had before files', () {
    expect(readKeybindings('{"bindings": []}').keymap, defaultKeymap);
    for (final MapEntry(key: action, value: spec) in actions.entries) {
      expect(
        keysOf(defaultKeymap, action).map(sequenceHint),
        spec.keys.map((key) => sequenceHint(keys(key))),
      );
    }
  });

  test('a binding replaces what its key did in its context, and null takes '
      'it away', () {
    final (:keymap, :problems) = read([
      {
        'context': 'Chat',
        'bindings': {'enter': null, 'ctrl+s': 'chat:submit', 'ctrl+g': null},
      },
    ]);
    expect(problems, isEmpty);
    expect(bound(keymap, 'chat:submit', keys('ctrl+s')), isTrue);
    expect(bound(keymap, 'chat:submit', keys('enter')), isFalse);
    expect(keysOf(keymap, 'chat:externalEditor'), isEmpty);

    // A key taken from one action in its own context goes to the new one.
    final moved = read([
      {
        'context': 'Chat',
        'bindings': {'ctrl+g': 'chat:imagePaste'},
      },
    ]);
    expect(moved.problems, isEmpty);
    expect(bound(moved.keymap, 'chat:imagePaste', keys('ctrl+g')), isTrue);
    expect(bound(moved.keymap, 'chat:imagePaste', keys('ctrl+v')), isTrue);
    expect(keysOf(moved.keymap, 'chat:externalEditor'), isEmpty);
  });

  test('a key a Global action holds is a conflict, and the rest still '
      'applies', () {
    final (:keymap, :problems) = read([
      {
        'context': 'Chat',
        'bindings': {'ctrl+o': 'chat:externalEditor', 'ctrl+s': 'chat:submit'},
      },
    ]);
    expect(problems, [
      'ctrl+o already bound to app:toggleTranscript, not to '
          'chat:externalEditor',
    ]);
    expect(bound(keymap, 'app:toggleTranscript', keys('ctrl+o')), isTrue);
    expect(bound(keymap, 'chat:externalEditor', keys('ctrl+o')), isFalse);
    expect(bound(keymap, 'chat:submit', keys('ctrl+s')), isTrue);
  });

  test('a key the transcript scrolls on is a conflict in any context', () {
    final (:keymap, :problems) = read([
      {
        'context': 'Chat',
        'bindings': {'pageup': 'chat:submit', 'ctrl+s': 'chat:submit'},
      },
    ]);
    expect(problems, [
      'pageup already bound to scroll:pageUp, not to chat:submit',
    ]);
    expect(bound(keymap, 'chat:submit', keys('pageup')), isFalse);
    expect(bound(keymap, 'chat:submit', keys('ctrl+s')), isTrue);
  });

  test('one key bound twice in a context keeps the first', () {
    final (:keymap, :problems) = read([
      {
        'context': 'Chat',
        'bindings': {'ctrl+s': 'chat:submit'},
      },
      {
        'context': 'Chat',
        'bindings': {'Control+S': 'chat:imagePaste'},
      },
    ]);
    expect(problems, ['ctrl+s is bound twice in Chat; chat:submit kept']);
    expect(bound(keymap, 'chat:submit', keys('ctrl+s')), isTrue);
    expect(bound(keymap, 'chat:imagePaste', keys('ctrl+s')), isFalse);
  });

  test('a key that starts a chord another action has is a conflict', () {
    final (:keymap, :problems) = read([
      {
        'context': 'Chat',
        'bindings': {
          'ctrl+k ctrl+e': 'chat:externalEditor',
          'ctrl+k': 'chat:imagePaste',
        },
      },
    ]);
    expect(problems, [
      'ctrl+k overlaps ctrl+k ctrl+e (chat:externalEditor), not bound to '
          'chat:imagePaste',
    ]);
    expect(bound(keymap, 'chat:externalEditor', keys('ctrl+k ctrl+e')), isTrue);
  });

  test('what chord cannot take is named and left out', () {
    final (:keymap, :problems) = read([
      {
        'context': 'Transcript',
        'bindings': {'k': 'scroll:lineUp'},
      },
      {'bindings': <String, Object?>{}},
      {'context': 'Chat', 'bindings': <Object?>[]},
      {
        'context': 'Global',
        'bindings': {
          'ctrl+t': 'app:toggleTodos',
          'ctrl+c': 'app:toggleTranscript',
          'ctl+o': 'app:toggleTranscript',
          'ctrl+e': 'chat:externalEditor',
          'ctrl+y': 7,
          'ctrl+r': 'history:search',
        },
      },
    ]);
    expect(problems, [
      'unknown context "Transcript", ignored',
      'a block with no "context", ignored',
      'Chat: "bindings" is not an object, ignored',
      'unknown action "app:toggleTodos", ignored',
      'ctrl+c cannot be rebound, ignored',
      '"ctl+o": "ctl" is not a modifier, ignored',
      'chat:externalEditor belongs in Chat, not Global; ignored',
      'ctrl+y: the action is not a name or null, ignored',
    ]);
    expect(keymap, defaultKeymap);
  });

  test('a file that is not a keybindings file counts for nothing', () {
    expect(readKeybindings('{').keymap, defaultKeymap);
    expect(readKeybindings('{').problems.single, startsWith('not valid JSON'));
    final listed = readKeybindings('[]');
    expect(listed.keymap, defaultKeymap);
    expect(listed.problems, ['has no "bindings" list; the file is ignored']);
  });

  test('the status line says how many problems, then the first', () {
    expect(keybindingsNotice('keybindings.json', []), isNull);
    expect(
      keybindingsNotice('keybindings.json', ['one']),
      'keybindings.json: one',
    );
    expect(
      keybindingsNotice('keybindings.json', ['one', 'two', 'three']),
      'keybindings.json: 3 problems · one',
    );
  });

  test("the keybindings file is chord's, beside its settings", () async {
    expect(
      keybindingsFile('/config'),
      p.join('/config', 'chord', 'keybindings.json'),
    );
    expect(keybindingsFile(null), isNull);

    final dir = await Directory.systemTemp.createTemp('chord-keys-');
    addTearDown(() => dir.delete(recursive: true));
    final file = p.join(dir.path, 'keybindings.json');

    final missing = await loadKeybindings(file);
    expect(missing.keymap, defaultKeymap);
    expect(missing.problems, isEmpty);

    await File(file).writeAsString(
      jsonEncode({
        'bindings': [
          {'context': 'Nope', 'bindings': <String, Object?>{}},
          {
            'context': 'Chat',
            'bindings': {'ctrl+s': 'chat:submit'},
          },
        ],
      }),
    );
    final (:keymap, :problems) = await loadKeybindings(file);
    expect(problems, [
      SettingsProblem(file, 'unknown context "Nope", ignored'),
    ]);
    expect(bound(keymap, 'chat:submit', keys('ctrl+s')), isTrue);
  });

  test('a file that cannot be read leaves the defaults and says so', () async {
    final dir = await Directory.systemTemp.createTemp('chord-keys-');
    addTearDown(() => dir.delete(recursive: true));
    // A directory where the file should be cannot be read as one.
    final file = p.join(dir.path, 'keybindings.json');
    await Directory(file).create();
    final (:keymap, :problems) = await loadKeybindings(file);
    expect(keymap, defaultKeymap);
    expect(problems.single.message, startsWith('cannot be read ('));
    expect(problems.single.message, endsWith('); the file is ignored'));
  });

  test('session:attention is rebound and unbound through the file', () {
    final (:keymap, :problems) = read([
      {
        'context': 'Global',
        'bindings': {'ctrl+x t': 'session:attention', 'ctrl+x a': null},
      },
    ]);
    expect(problems, isEmpty);
    expect(keysOf(keymap, 'session:attention').map(sequenceHint), ['ctrl+x t']);
  });

  test('a file binding an action that went with tabs is told so, and the '
      'rest of it holds', () {
    final (:keymap, :problems) = read([
      {
        'context': 'Global',
        'bindings': {
          'ctrl+x c': 'session:new',
          'ctrl+x n': 'session:next',
          'ctrl+x 3': 'session:goto3',
          'ctrl+x w': 'session:list',
          'ctrl+x k': 'session:close',
          'ctrl+x t': 'session:attention',
        },
      },
    ]);
    expect(problems, [
      'session:new went with tabs: chord runs one session, ignored',
      'session:next went with tabs: chord runs one session, ignored',
      'session:goto3 went with tabs: chord runs one session, ignored',
      'session:list went with tabs: chord runs one session, ignored',
      'session:close went with tabs: chord runs one session, ignored',
    ]);
    expect(bound(keymap, 'session:attention', keys('ctrl+x t')), isTrue);
  });

  test('hints name the first bound key, and none when nothing is bound', () {
    final (:keymap, problems: _) = read([
      {
        'context': 'Chat',
        'bindings': {'ctrl+e': 'chat:externalEditor', 'ctrl+g': null},
      },
    ]);
    expect(hintKey(keymap, 'chat:externalEditor'), 'ctrl+e');
    expect(hintKey(defaultKeymap, 'chat:cancel'), 'esc');
    expect(isDefault(keymap, 'chat:externalEditor'), isFalse);
    expect(isDefault(keymap, 'chat:submit'), isTrue);
    final unbound = read([
      {
        'context': 'Chat',
        'bindings': {'?': null},
      },
    ]).keymap;
    expect(hintKey(unbound, 'help:toggle'), isNull);
  });

  test("the keymap's data gives each changed action its keys as the "
      'framework spells them', () {
    final (:keymap, problems: _) = read([
      {
        'context': 'Global',
        'bindings': {'cmd+t': 'app:toggleTranscript', 'ctrl+o': null},
      },
      {
        'context': 'Scroll',
        'bindings': {'home': null},
      },
    ]);
    final data = keymap.data;
    expect(data.keysFor('app:toggleTranscript'), [Chord.parse('super+t')]);
    expect(data.keysFor('scroll:top'), [Chord.parse('shift+home')]);
    // An action the file left alone keeps the keys the window gave it.
    expect(data.keysFor('session:attention'), isNull);
    expect(data.keysFor('nobody'), isNull);
    expect(defaultKeymap.data, const KeymapData());
  });
}
