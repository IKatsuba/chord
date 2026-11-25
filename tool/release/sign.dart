/// Signing the built darwin chords with the team's Developer ID, as the
/// original's `scripts/dev/release/sign.ts`: hardened runtime, secure
/// timestamp, the one entitlement, then `--verify --strict` and the signed
/// entitlements read back and compared with chord.entitlements, since a
/// binary without its entitlement still passes a quick look. The original's
/// `natives` step has no counterpart: a Dart binary embeds no library.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'runner.dart';

/// The team whose Developer ID Application identity signs chord.
const team = 'YQ8ZD2KZ3T';

/// The code signing identifier of chord.
const signingIdentifier = 'dev.katsuba.chord';

/// chord's entitlements, from the root: `allow-unsigned-executable-memory`,
/// which a hardened-runtime Dart binary needs (docs/decisions.md).
const entitlementsPath = 'tool/macos/chord.entitlements';

final _identityHash = RegExp(r'^ *[0-9]+\) ([0-9A-F]{40}) ');

/// The one Developer ID Application identity of [team] in the login
/// keychain under [home], found by team so a renewed certificate is picked
/// up; none or several stop.
Future<String> identity(ReleaseRunner runner, String home) async {
  final listed = await runner.run('security', [
    'find-identity',
    '-v',
    '-p',
    'codesigning',
    p.join(home, 'Library', 'Keychains', 'login.keychain-db'),
  ]);
  // A failed security names nothing, whatever it printed.
  if (listed.status != 0) {
    die('security find-identity failed: ${said(listed.stderr)}');
  }
  final found = said(listed.stdout);
  final matches = [
    for (final line in found.split('\n'))
      if (line.contains('Developer ID Application: ') &&
          line.contains('($team)'))
        line,
  ];
  if (matches.length != 1) {
    die(
      'expected one Developer ID Application identity of team $team, found '
      '${matches.length}; security find-identity said:\n$found',
    );
  }
  return _identityHash.firstMatch(matches.single)?[1] ?? matches.single;
}

/// Signs each of [binaries], paths from [root], as [id], and checks each.
Future<void> sign(
  ReleaseRunner runner,
  String root,
  String id,
  List<String> binaries, {
  required void Function(String line) out,
}) async {
  for (final binary in binaries) {
    if (!File(p.join(root, binary)).existsSync()) die('no binary at $binary');
    final signed = await runner.run('codesign', [
      '--force',
      '--sign',
      id,
      '--options',
      'runtime',
      '--timestamp',
      '--entitlements',
      entitlementsPath,
      '--identifier',
      signingIdentifier,
      binary,
    ], loud: true);
    if (signed.status != 0) die('codesign failed for $binary');
    final verified = await runner.run('codesign', [
      '--verify',
      '--strict',
      '--verbose=2',
      binary,
    ], loud: true);
    if (verified.status != 0) die('$binary does not verify');
    out('signed $binary: ${await checkEntitlements(runner, root, binary)}');
  }
}

/// The signed entitlements of [binary] as JSON, read back and refused
/// unless they are chord.entitlements'.
Future<String> checkEntitlements(
  ReleaseRunner runner,
  String root,
  String binary,
) async {
  final read = await runner.run('codesign', [
    '-d',
    '--entitlements',
    '-',
    '--xml',
    binary,
  ]);
  if (read.status != 0) {
    die('the entitlements of $binary could not be read back');
  }
  // plutil reads the read-back from a file, as the runner passes no stdin.
  final temp = Directory.systemTemp.createTempSync('chord-entitlements-');
  try {
    final xml = File(p.join(temp.path, 'signed.plist'))
      ..writeAsStringSync(read.stdout);
    final converted = await runner.run('plutil', [
      '-convert',
      'json',
      '-o',
      '-',
      xml.path,
    ]);
    if (converted.status != 0) {
      die(
        'the entitlements read back from $binary could not be converted: '
        '${said(converted.stderr)}',
      );
    }
    final got = said(converted.stdout);
    final reference = await runner.run('plutil', [
      '-convert',
      'json',
      '-o',
      '-',
      entitlementsPath,
    ]);
    final want = said(reference.stdout);
    // What is compared against must be read, or a failed read-back that
    // says nothing would equal it.
    if (reference.status != 0 || want.isEmpty) {
      die('$entitlementsPath could not be read: ${said(reference.stderr)}');
    }
    if (got != want) {
      die(
        'entitlements of $binary differ from $entitlementsPath: got $got, '
        'want $want',
      );
    }
    return got;
  } finally {
    temp.deleteSync(recursive: true);
  }
}
