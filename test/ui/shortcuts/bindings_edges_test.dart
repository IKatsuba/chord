import 'dart:convert';
import 'dart:io';

import 'package:chord/settings.dart';
import 'package:chord/ui/shortcuts/bindings.dart';
import 'package:chord_tui/chord_tui.dart' show Chord;
import 'package:test/test.dart';

void main() {
  group('tester: keybindings reader boundaries', () {
    test('all reserved aliases resist removal as well as rebinding', () {
      for (final key in [
        'Control+C',
        'ctrl+d',
        'ctrl+m',
        'ctrl+[',
        'ctrl+i',
        'ctrl+h',
      ]) {
        for (final action in [null, 'chat:submit']) {
          final result = readKeybindings(
            jsonEncode({
              'bindings': [
                {
                  'context': 'Chat',
                  'bindings': {key: action},
                },
              ],
            }),
          );
          expect(result.keymap, defaultKeymap, reason: '$key: $action');
          expect(
            result.problems.single,
            endsWith('cannot be rebound, ignored'),
          );
        }
      }
    });

    test(
      'disjoint contexts can share keys while Global conflicts with both',
      () {
        final result = readKeybindings(
          jsonEncode({
            'bindings': [
              {
                'context': 'Chat',
                'bindings': {'f': 'chat:submit'},
              },
              {
                'context': 'Help',
                'bindings': {'f': 'help:dismiss'},
              },
              {
                'context': 'Global',
                'bindings': {'f': 'app:toggleTranscript'},
              },
            ],
          }),
        );
        expect(result.problems, [
          'f already bound to chat:submit, not to app:toggleTranscript',
        ]);
        expect(
          result.keymap.data.keysFor('chat:submit'),
          contains(Chord.parse('f')),
        );
        expect(
          result.keymap.data.keysFor('help:dismiss'),
          contains(Chord.parse('f')),
        );
        expect(
          keysOf(result.keymap, 'app:toggleTranscript').map(sequenceHint),
          ['ctrl+o'],
        );
      },
    );

    test('bad top-level shapes never partially change defaults', () {
      for (final input in [
        null,
        true,
        42,
        'text',
        [],
        {},
        {'bindings': {}},
      ]) {
        final result = readKeybindings(jsonEncode(input));
        expect(result.keymap, defaultKeymap);
        expect(result.problems, [
          'has no "bindings" list; the file is ignored',
        ]);
      }
    });

    test('modifier aliases bridge to framework super and alt chords', () {
      final result = readKeybindings(
        jsonEncode({
          'bindings': [
            {
              'context': 'Chat',
              'bindings': {'meta+f': 'chat:submit', 'win+f': 'chat:submit'},
            },
          ],
        }),
      );
      expect(result.problems, isEmpty);
      expect(result.keymap.data.keysFor('chat:submit'), [
        Chord.parse('enter'),
        Chord.parse('alt+f'),
        Chord.parse('super+f'),
      ]);
    });

    test('malformed UTF-8 in a file is decoded like the original', () async {
      final dir = await Directory.systemTemp.createTemp('keybindings-tester-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/keybindings.json');
      await file.writeAsBytes([
        ...utf8.encode('{"bindings":[{"context":"'),
        0xff,
        ...utf8.encode('","bindings":{}}]}'),
      ]);
      final result = await loadKeybindings(file.path);
      expect(result.keymap, defaultKeymap);
      expect(result.problems.single.message, 'unknown context "�", ignored');
      final absent = await loadKeybindings(null);
      expect(absent.keymap, defaultKeymap);
      expect(absent.problems, isEmpty);
    });
  });
}
