// CTUI-104: a word -C or --cwd takes as its directory is no option, as
// Cliffy reads it: `chord agents -C --model --json` lists the agents of
// a directory named --model as JSON; a real `agents --model` is refused.
import 'dart:convert';
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('chord-agents-cwd-');
    Directory(p.join(root.path, '--model')).createSync();
    Directory(p.join(root.path, '-C')).createSync();
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<(CliOutcome, String, String)> run(List<String> args) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final outcome = await runCli(
      args,
      stdout: out,
      stderr: err,
      cwd: root.path,
      home: p.join(root.path, 'home'),
      environment: {'XDG_CONFIG_HOME': p.join(root.path, 'config')},
      lookup: (command) async => null,
      readSessionRecords: () async => const [],
    );
    return (outcome, '$out', '$err');
  }

  for (final args in [
    ['agents', '-C', '--model', '--json'],
    ['agents', '--cwd', '--model', '--json'],
    ['agents', '--json', '-C', '--model'],
  ]) {
    test('${args.join(' ')} takes --model as the directory', () async {
      final (outcome, out, err) = await run(args);
      expect(err, isEmpty);
      expect(outcome.code, 0);
      expect(jsonDecode(out), containsPair('version', 1));
    });
  }

  test('an option after a consumed -C is still refused', () async {
    final (outcome, _, err) = await run(['agents', '-C', '-C', '--model', 'x']);
    expect(outcome.code, 2);
    expect(err, contains('Unknown option "--model".'));
  });

  test('agents --model is still refused', () async {
    final (outcome, _, err) = await run(['agents', '--model', 'x']);
    expect(outcome.code, 2);
    expect(err, contains('Unknown option "--model".'));
  });

  // CTUI-119: an attached value as the original's Cliffy reads it, its
  // splitFlags cutting a short cluster into one-letter words; each case is
  // what `bun src/main.tsx` in ../chord printed.
  group('attached short values', () {
    void preferring(String directory) =>
        File(p.join(root.path, directory, '.chord', 'settings.json'))
          ..createSync(recursive: true)
          ..writeAsStringSync(jsonEncode({'agent': 'codex'}));

    for (final args in [
      ['agents', '-C--model', '--json'],
      ['agents', '-C--', '--json'],
    ]) {
      test('${args.join(' ')}: -C takes --, the next -- ends the options, '
          'so the table', () async {
        final (outcome, out, err) = await run(args);
        expect(err, isEmpty);
        expect(outcome.code, 0);
        expect(out, isNot(startsWith('{')));
        expect(out, contains('claude'));
      });
    }

    for (final (word, directory) in [
      ('-C-', '--'),
      ('-C12', '12'),
      ('-C=x', 'x'),
    ]) {
      test('agents $word --json reads the directory $directory', () async {
        preferring(directory);
        final (outcome, out, err) = await run(['agents', word, '--json']);
        expect(err, isEmpty);
        expect(outcome.code, 0);
        expect(jsonDecode(out)['preferred'], 'codex');
      });
    }

    // CTUI-123: splitFlags asks `isNaN(Number(flag[flag.length - 1]))`
    // (@jsr/cliffy__flags 1.3.1, flags.ts:727), and Number reads a lone
    // JavaScript whitespace as 0, so the cluster keeps its value whole.
    // U+0085 is no JavaScript whitespace: the cluster splits to -C and
    // -\u0085, which -C takes as its directory. Each case is what
    // `bun src/main.tsx` in ../chord printed.
    String shown(String text) => [
      for (final unit in text.codeUnits)
        unit > 0x20 && unit < 0x7f
            ? String.fromCharCode(unit)
            : 'U+${unit.toRadixString(16).toUpperCase().padLeft(4, '0')}',
    ].join();
    for (final (word, directory) in [
      ('-C ', ' '),
      ('-C\t', '\t'),
      ('-C ', ' '),
      ('-C﻿', '﻿'),
      ('-C ', ' '),
      ('-Cx ', 'x '),
      ('-C\u0085', '-\u0085'),
    ]) {
      test('agents ${shown(word)} --json reads the directory '
          '${shown(directory)}', () async {
        preferring(directory);
        final (outcome, out, err) = await run(['agents', word, '--json']);
        expect(err, isEmpty);
        expect(outcome.code, 0);
        expect(jsonDecode(out)['preferred'], 'codex');
      });
    }

    test('agents -C -- --json takes -- as the directory', () async {
      preferring('--');
      final (outcome, out, err) = await run(['agents', '-C', '--', '--json']);
      expect(err, isEmpty);
      expect(outcome.code, 0);
      expect(jsonDecode(out)['preferred'], 'codex');
    });

    for (final (word, line) in [
      ('-Cfoo', 'Unknown option "-o". Did you mean option "-h"?'),
      ('-C.', 'Unknown option "-C.". Did you mean option "-C"?'),
      ('-C..', 'Unknown option "-C..". Did you mean option "-C"?'),
    ]) {
      test('agents $word --json is refused as the original', () async {
        final (outcome, _, err) = await run(['agents', word, '--json']);
        expect(outcome.code, 2);
        expect(err, '\n  error: $line\n\n');
      });
    }
  });

  group('tester CTUI-104: option-looking directories', () {
    for (final value in [
      '--version',
      '--effort',
      '--print',
      '--agent-command',
      '--no-mcp-servers',
      '-V',
      '-m',
      '-p',
    ]) {
      test('$value remains a literal cwd for both option spellings', () async {
        File(p.join(root.path, value, '.chord', 'settings.json'))
          ..createSync(recursive: true)
          ..writeAsStringSync(jsonEncode({'agent': 'codex'}));
        for (final option in ['-C', '--cwd']) {
          final (outcome, out, err) = await run([
            'agents',
            option,
            value,
            '--json',
          ]);
          expect(outcome.code, 0, reason: '$option $value: $err');
          expect(outcome.launch, isNull);
          expect(err, isEmpty);
          expect(jsonDecode(out)['preferred'], 'codex');
        }
      });
    }

    test('a repeated cwd is refused before a later unknown option', () async {
      for (final option in ['-C', '--cwd']) {
        final (outcome, _, err) = await run([
          'agents',
          option,
          '--model',
          option,
          '-C',
          '--model',
          'bad',
        ]);
        expect(outcome.code, 2);
        expect(outcome.launch, isNull);
        expect(
          err,
          contains(
            'Option "$option" can only occur once, but was found several times.',
          ),
        );
      }
    });
  });
  group('tester CTUI-119: attached cwd boundaries', () {
    for (final (word, directory) in [
      ('-C=x=y', 'x=y'),
      ('-C==x', '=x'),
      ('-C=--json', '--json'),
      ('-C0', '0'),
    ]) {
      test('$word reads settings from the full attached value', () async {
        File(p.join(root.path, directory, '.chord', 'settings.json'))
          ..createSync(recursive: true)
          ..writeAsStringSync(jsonEncode({'agent': 'codex'}));
        final (outcome, out, err) = await run(['agents', word, '--json']);
        expect(outcome.code, 0);
        expect(outcome.launch, isNull);
        expect(err, isEmpty);
        expect(jsonDecode(out)['preferred'], 'codex');
      });
    }

    test('a separated cwd value is never split as a cluster', () async {
      const directory = '-C--model';
      File(p.join(root.path, directory, '.chord', 'settings.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'agent': 'codex'}));
      for (final option in ['-C', '--cwd']) {
        final (outcome, out, err) = await run([
          'agents',
          option,
          directory,
          '--json',
        ]);
        expect(outcome.code, 0);
        expect(err, isEmpty);
        expect(jsonDecode(out)['preferred'], 'codex');
      }
    });

    for (final words in [
      ['--', '-C--model', '--json'],
      ['-C', '--', '--', '--json'],
      ['-C--json', '--json'],
    ]) {
      test('${words.join(' ')} keeps the terminator boundary', () async {
        final (outcome, out, err) = await run(['agents', ...words]);
        expect(outcome.code, 0);
        expect(outcome.launch, isNull);
        expect(err, isEmpty);
        expect(out, isNot(startsWith('{')));
        expect(out, contains('claude'));
      });
    }

    test('a dotted option cannot collide with a literal placeholder', () async {
      final (outcome, _, err) = await run([
        'agents',
        '-C.',
        '__chord_agents_word_0__',
      ]);
      expect(outcome.code, 2);
      expect(
        err,
        '\n  error: Unknown option "-C.". '
        'Did you mean option "-C"?\n\n',
      );
    });
  });

  group('tester CTUI-123: Number character boundaries', () {
    for (final unit in [
      0x0009,
      0x000a,
      0x000b,
      0x000c,
      0x000d,
      0x0020,
      0x00a0,
      0x1680,
      0x2000,
      0x2001,
      0x2002,
      0x2003,
      0x2004,
      0x2005,
      0x2006,
      0x2007,
      0x2008,
      0x2009,
      0x200a,
      0x2028,
      0x2029,
      0x202f,
      0x205f,
      0x3000,
      0xfeff,
    ]) {
      test('U+${unit.toRadixString(16)} keeps the entire cwd value', () async {
        final directory = '界😀e\u0301${String.fromCharCode(unit)}';
        File(p.join(root.path, directory, '.chord', 'settings.json'))
          ..createSync(recursive: true)
          ..writeAsStringSync(jsonEncode({'agent': 'codex'}));
        final (outcome, out, err) = await run([
          'agents',
          '-C$directory',
          '--json',
        ]);
        expect(outcome.code, 0, reason: err);
        expect(outcome.launch, isNull);
        expect(err, isEmpty);
        expect(jsonDecode(out)['preferred'], 'codex');
      });
    }

    for (final unit in [0x0085, 0x180e, 0x200b, 0x2060, 0x0660, 0xff10]) {
      test('U+${unit.toRadixString(16)} still splits the cluster', () async {
        final character = String.fromCharCode(unit);
        File(p.join(root.path, '-$character', '.chord', 'settings.json'))
          ..createSync(recursive: true)
          ..writeAsStringSync(jsonEncode({'agent': 'codex'}));
        final (outcome, out, err) = await run([
          'agents',
          '-C$character',
          '--json',
        ]);
        expect(outcome.code, 0, reason: err);
        expect(outcome.launch, isNull);
        expect(err, isEmpty);
        expect(jsonDecode(out)['preferred'], 'codex');
      });
    }
  });
}
