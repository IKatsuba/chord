import 'dart:convert';
import 'dart:io';

import 'package:chord/version.dart';
import 'package:test/test.dart';

import '../../../tool/release/version.dart';

/// bun's `%p`: a string quoted as pretty-format quotes it.
String p(String value) => jsonEncode(value);

Matcher refuses([String? text]) => throwsA(
  text == null
      ? isA<VersionError>()
      : isA<VersionError>().having((e) => e.message, 'message', contains(text)),
);

String release(
  String current,
  String? wanted, [
  String? channel,
  String Function()? stable,
]) => releaseVersion(current, wanted, channel: channel, stable: stable);

void main() {
  group('isVersionArgument', () {
    for (final word in [
      'major',
      'minor',
      'patch',
      'fix',
      '1.2.3',
      '0.56.0',
      '1.0.0-rc.1',
    ]) {
      test('takes $word', () => expect(isVersionArgument(word), isTrue));
    }

    for (final word in [
      'v1.2.3',
      '=1.2.3',
      '1.2',
      '1.2.3+build',
      'next',
      'Patch',
      '',
    ]) {
      test(
        'refuses ${p(word)}',
        () => expect(isVersionArgument(word), isFalse),
      );
    }
  });

  group('releaseVersion', () {
    test("with none given is pubspec.yaml's", () {
      expect(release('0.55.0', null), '0.55.0');
    });

    for (final (bump, next) in [
      ('major', '1.0.0'),
      ('minor', '0.56.0'),
      ('patch', '0.55.1'),
      ('fix', '0.55.1'),
    ]) {
      test('$bump bumps it', () => expect(release('0.55.0', bump), next));
    }

    test("pubspec.yaml's own version is pubspec.yaml's", () {
      expect(release('0.55.0', '0.55.0'), '0.55.0');
    });

    test('an exact version above it is taken', () {
      expect(release('0.55.0', '0.55.1'), '0.55.1');
      expect(release('0.55.0', '2.0.0'), '2.0.0');
    });

    for (final (name, current, wanted) in [
      ("a pre-release pubspec.yaml's own", '0.56.0-rc.1', '0.56.0-rc.1'),
      ('a version below', '0.55.0', '0.54.9'),
      ('a pre-release', '0.55.0', '0.56.0-rc.1'),
      ('a bump of a pre-release', '0.56.0-rc.1', 'patch'),
      ('a version below a pre-release', '0.56.0-rc.1', '0.55.9'),
      ('a word that is neither', '0.55.0', 'next'),
      ('a version not written as semver writes it', '0.55.0', 'v0.56.0'),
      ("pubspec.yaml's version that is none", 'latest', 'patch'),
    ]) {
      test('refuses $name', () {
        expect(() => release(current, wanted), refuses());
      });
    }

    test('says why', () {
      expect(
        () => release('0.55.0', '0.54.0'),
        refuses("0.54.0 is not above pubspec.yaml's version 0.55.0"),
      );
    });

    test("with none given is pubspec.yaml's, whatever it holds", () {
      expect(release('1.0.0-next.3', null), '1.0.0-next.3');
      expect(release('latest', null), 'latest');
    });

    test('an exact version over a pre-release is taken', () {
      expect(release('1.0.0-next.5', '1.0.0'), '1.0.0');
      expect(release('1.0.0-next.5', '1.0.1'), '1.0.1');
    });

    for (final bump in ['major', 'minor', 'patch', 'fix']) {
      test('$bump over a pre-release says to name the version', () {
        expect(
          () => release('1.0.0-next.5', bump),
          refuses('name the version'),
        );
      });
    }

    for (final (wanted, channel) in [
      ('1.0.0-next.0', null),
      ('1.0.0-next.0', 'next'),
      ('1.0.0-beta.0', 'next'),
      ('0.68.0-rc.1', 'beta'),
    ]) {
      test('labelled $wanted on channel ${channel ?? 'undefined'} is '
          'refused', () {
        expect(
          () => release('0.67.0', wanted, channel),
          refuses(
            '$wanted has a pre-release label; --channel is the only way to '
            'name one',
          ),
        );
      });
    }

    test('names every bump when the word is neither', () {
      expect(
        () => release('0.55.0', 'next'),
        refuses(
          'next is neither a version nor one of major, minor, patch, fix',
        ),
      );
    });
  });

  group('releaseVersion on a channel', () {
    String stable() => '0.67.0';

    for (final (bump, version) in [
      ('major', '1.0.0-next.0'),
      ('minor', '0.68.0-next.0'),
      ('patch', '0.67.1-next.0'),
      ('fix', '0.67.1-next.0'),
    ]) {
      test('$bump from stable starts at 0', () {
        expect(release('0.67.0', bump, 'next', stable), version);
      });
    }

    test(
      'the same bump again goes up by one, from npm and not pubspec.yaml',
      () {
        expect(
          release('1.0.0-next.0', 'major', 'next', stable),
          '1.0.0-next.1',
        );
        expect(
          release('1.0.0-next.9', 'major', 'next', stable),
          '1.0.0-next.10',
        );
      },
    );

    test('an exact version gives the same two numbers', () {
      expect(release('0.67.0', '1.0.0', 'next', stable), '1.0.0-next.0');
      expect(release('1.0.0-next.0', '1.0.0', 'next', stable), '1.0.0-next.1');
    });

    test('any channel works the same way', () {
      expect(release('0.67.0', 'major', 'beta', stable), '1.0.0-beta.0');
      expect(release('1.0.0-beta.0', '1.0.0', 'beta', stable), '1.0.0-beta.1');
    });

    test('a new base starts at 0', () {
      expect(release('1.0.0-next.4', '1.1.0', 'next', stable), '1.1.0-next.0');
    });

    test(
      "another channel's pre-release of the base starts at 0 when above it",
      () {
        expect(
          release('1.0.0-beta.4', '1.0.0', 'next', stable),
          '1.0.0-next.0',
        );
      },
    );

    for (final (current, wanted, channel, why) in [
      ('1.0.0-next.4', '1.0.0', 'beta', 'it sorts below'),
      ('1.0.0', '1.0.0', 'next', 'a release is above its pre-release'),
      ('1.0.0-next.4', '0.9.0', 'next', 'a lower base'),
      ('1.0.0-next.4', 'minor', 'next', 'a bump of npm below it'),
    ]) {
      test('$current to $wanted on $channel is refused: $why', () {
        expect(
          () => release(current, wanted, channel, stable),
          refuses('is not above'),
        );
      });
    }

    test('stable is asked only for a bump', () {
      String never() => throw StateError('npm was asked');

      expect(release('0.67.0', '1.0.0', 'next', never), '1.0.0-next.0');
      expect(release('1.0.0-next.0', null, 'next', never), '1.0.0-next.0');
      expect(release('0.67.0', 'minor', null, never), '0.68.0');
      expect(
        () => release('0.67.0', 'major', 'next', never),
        throwsA(isA<StateError>()),
      );
    });

    for (final latest in ['latest', '1.0.0-next.0', '']) {
      test(
        "refuses npm's latest ${p(latest)}, which is no stable version to bump",
        () {
          expect(
            () => release('0.67.0', 'major', 'next', () => latest),
            refuses(),
          );
        },
      );
    }

    test('with no version finishes that channel only', () {
      expect(release('1.0.0-next.3', null, 'next', stable), '1.0.0-next.3');
      for (final current in ['1.0.0-beta.3', '0.67.0']) {
        expect(
          () => release(current, null, 'next', stable),
          refuses("pubspec.yaml's version $current is not on channel next"),
        );
      }
    });

    for (final channel in ['latest', 'main', 'x', 'v1', 'Next', '']) {
      test('refuses channel ${p(channel)}, with or without a version', () {
        for (final wanted in [null, '1.0.0', 'major']) {
          expect(() => release('0.67.0', wanted, channel, stable), refuses());
        }
      });
    }

    test("refuses pubspec.yaml's version that is none", () {
      expect(
        () => release('latest', '1.0.0', 'next', stable),
        refuses("pubspec.yaml's version latest is no version"),
      );
    });

    test('a bump on a channel with no stable reader says so', () {
      expect(
        () => release('0.67.0', 'major', 'next'),
        refuses("a bump on a channel needs npm's latest stable"),
      );
    });
  });

  group('tester: CHD-412 version boundaries', () {
    test(
      'major and minor reset subordinate components, and fix equals patch',
      () {
        expect(release('2.9.8', 'major'), '3.0.0');
        expect(release('2.9.8', 'minor'), '2.10.0');
        expect(release('2.9.8', 'fix'), release('2.9.8', 'patch'));
        expect(release('0.0.0', 'fix'), '0.0.1');
      },
    );

    test(
      'exact versions compare numerically across multi-digit components',
      () {
        expect(release('1.9.9', '1.10.0'), '1.10.0');
        expect(release('1.10.0', '1.10.0'), '1.10.0');
        expect(() => release('1.10.0', '1.9.99'), refuses());
      },
    );

    test('noncanonical spellings are refused before version resolution', () {
      for (final wanted in [
        ' 1.2.3',
        '1.2.3 ',
        '01.2.3',
        '1.02.3',
        '1.2.03',
        '=1.2.3',
        '1.2.3+build.1',
        '^1.2.3',
        '*',
        'FIX',
      ]) {
        expect(isVersionArgument(wanted), isFalse, reason: wanted);
        expect(() => release('1.0.0', wanted), refuses());
      }
    });

    test(
      'a prerelease accepts unlabelled higher versions and refuses bumps',
      () {
        for (final wanted in [
          'major',
          'minor',
          'patch',
          'fix',
          '1.2.3-rc.1',
          '1.2.2',
        ]) {
          expect(() => release('1.2.3-rc.1', wanted), refuses());
        }
        for (final wanted in ['1.2.3', '2.0.0']) {
          expect(release('1.2.3-rc.1', wanted), wanted);
        }
      },
    );
  });

  group('tester: CHD-577 version boundaries', () {
    for (final channel in ['next', 'beta']) {
      test('$channel increments minor, patch and fix from npm stable across '
          'counter digits', () {
        for (final (bump, base) in [
          ('minor', '2.10.0'),
          ('patch', '2.9.9'),
          ('fix', '2.9.9'),
        ]) {
          expect(
            release('2.9.8', bump, channel, () => '2.9.8'),
            '$base-$channel.0',
          );
          expect(
            release('$base-$channel.9', bump, channel, () => '2.9.8'),
            '$base-$channel.10',
          );
        }
      });
    }

    test('a newer npm stable selects a new base and restarts the counter', () {
      expect(
        release('1.0.0-next.12', 'major', 'next', () => '1.0.0'),
        '2.0.0-next.0',
      );
    });

    test(
      'explicit bases and resume do not depend on registry availability',
      () {
        String unavailable() => throw StateError('registry unavailable');

        expect(
          release('1.0.0-beta.9', '1.0.0', 'beta', unavailable),
          '1.0.0-beta.10',
        );
        expect(
          release('1.0.0-beta.9', null, 'beta', unavailable),
          '1.0.0-beta.9',
        );
        expect(
          () => release('1.0.0-beta.9', 'major', 'beta', unavailable),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('a malformed current label cannot become a channel release', () {
      for (final current in [
        '1.0.0-next',
        '1.0.0-next.one',
        '1.0.0-latest.0',
      ]) {
        expect(() => release(current, '2.0.0', 'next'), refuses());
      }
    });
  });

  group('the version written by a bump', () {
    const pubspec =
        'name: chord\n'
        'description: chord, version: 9 is not the line\n'
        'version: 0.0.1\n'
        'publish_to: none\n';

    test("only pubspec.yaml's version value changes", () {
      expect(
        withVersion(pubspec, '1.0.0-next.0'),
        pubspec.replaceFirst('version: 0.0.1', 'version: 1.0.0-next.0'),
      );
    });

    test('a pubspec without a version line is not written', () {
      expect(withVersion('name: chord\n', '1.0.0'), isNull);
    });

    const held =
        '/// The port\'s version.\n'
        "const version = '0.0.1';\n";

    test('only the held constant changes', () {
      expect(
        withHeldVersion(held, '1.0.0'),
        held.replaceFirst("'0.0.1'", "'1.0.0'"),
      );
    });

    test("the port's own files are found and kept as laid out", () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final held = File('lib/version.dart').readAsStringSync();
      expect(withVersion(pubspec, version), pubspec);
      expect(withHeldVersion(held, version), held);
      expect(withVersion(pubspec, '9.9.9'), contains('\nversion: 9.9.9\n'));
      expect(withHeldVersion(held, '9.9.9'), contains("version = '9.9.9';"));
    });

    test('a file without the held constant is not written', () {
      expect(withHeldVersion('const other = 1;\n', '1.0.0'), isNull);
    });

    test("the port's lock moves only chord_tui's version", () {
      final lock = File('pubspec.lock').readAsStringSync();
      expect(withLockedVersion(lock, version), lock);
      final moved = withLockedVersion(lock, '9.9.9')!;
      expect(moved.split('\n').where((line) => !lock.contains(line)).toList(), [
        '    version: "9.9.9"',
      ]);
      expect(moved, contains('  chord_tui:\n'));
    });

    test('a lock without chord_tui is not written', () {
      expect(
        withLockedVersion('packages:\n  path:\n    version: "1.0.0"\n', '2'),
        isNull,
      );
    });
  });

  group('tester: release source and text boundaries', () {
    test('a rejected request never asks the stable source', () {
      var reads = 0;
      String stable() {
        reads++;
        return '1.0.0';
      }

      for (final channel in ['main', 'latest', 'v1', 'next\u001b[31m']) {
        expect(() => release('1.0.0', 'major', channel, stable), refuses());
      }
      expect(() => release('1.0.0', 'v2.0.0', 'next', stable), refuses());
      expect(() => release('1.0.0', '2.0.0-beta.0', 'next', stable), refuses());
      expect(reads, 0);
      expect(release('1.0.0', 'major', 'next', stable), '2.0.0-next.0');
      expect(reads, 1);
    });

    test('manifest changes preserve tabs, comments and CRLF', () {
      const text =
          'name: chord\r\nversion:\t1.0.0 # retained\r\n'
          'environment:\r\n  sdk: ^3.12.0\r\n';
      expect(
        withVersion(text, '2.0.0-next.0'),
        text.replaceFirst('1.0.0', '2.0.0-next.0'),
      );
    });

    test('the held version keeps its comment and surrounding source', () {
      const text =
          "/// Version.\r\nconst version = '1.0.0'; // retained\r\n"
          "const other = '1.0.0';\r\n";
      expect(
        withHeldVersion(text, '2.0.0-next.0'),
        text.replaceFirst("'1.0.0'", "'2.0.0-next.0'"),
      );
    });
  });
}
