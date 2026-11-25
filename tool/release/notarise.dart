/// Notarising the signed darwin chords, as the original's
/// `scripts/dev/release/notarise.ts`: one zip submitted with the team's
/// App Store Connect key from the login keychain, Apple's log kept beside
/// the build whatever the verdict, a stop unless Accepted, then each binary
/// checked to be one Apple's log lists a ticket for, by its cdhash, so what
/// is packed is what was notarised. A bare Mach-O cannot be stapled;
/// Gatekeeper looks the ticket up online on a quarantined copy.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'runner.dart';

/// The notarytool profile in the login keychain that holds the team's key.
const notaryProfile = 'roost-notary';

/// Notarises [binaries], paths from [root], keeping the zip and Apple's
/// answers in [out], and answers each binary's cdhash, the bytes the
/// release records as notarised. [sleep] waits between log fetches.
Future<Map<String, String>> notarise(
  ReleaseRunner runner,
  String root,
  String out,
  List<String> binaries, {
  required Future<void> Function(Duration) sleep,
  required void Function(String line) report,
}) async {
  final folder = Directory(p.join(root, out))..createSync(recursive: true);
  // An answer left by an earlier run must never stand for this one.
  for (final kept in [
    'notarytool.json',
    'notarytool-submit.stderr',
    'notarytool-log.json',
  ]) {
    final file = File(p.join(folder.path, kept));
    if (file.existsSync()) file.deleteSync();
  }
  final zip = p.join(out, 'chord.zip');
  final staging = Directory.systemTemp.createTempSync('chord-notarise-');
  try {
    final chord = Directory(p.join(staging.path, 'chord'))..createSync();
    for (final binary in binaries) {
      File(
        p.join(root, binary),
      ).copySync(p.join(chord.path, '${p.basename(p.dirname(binary))}-chord'));
    }
    final zipped = await runner.run('ditto', [
      '-c',
      '-k',
      '--norsrc',
      '--noextattr',
      '--keepParent',
      chord.path,
      zip,
    ]);
    // Stopped here, or an older zip left in place would be submitted.
    if (zipped.status != 0) {
      die('ditto could not make $zip: ${said(zipped.stderr)}');
    }
  } finally {
    staging.deleteSync(recursive: true);
  }

  // The result is kept, and Apple's log fetched, before any verdict is
  // judged. The JSON result is stdout alone; notarytool's diagnostics are
  // kept apart.
  final submit = await runner.run('xcrun', [
    'notarytool',
    'submit',
    zip,
    '--keychain-profile',
    notaryProfile,
    '--wait',
    '--output-format',
    'json',
  ]);
  final result = said(submit.stdout);
  File(
    p.join(folder.path, 'notarytool-submit.stderr'),
  ).writeAsStringSync(submit.stderr);
  File(p.join(folder.path, 'notarytool.json')).writeAsStringSync('$result\n');
  final (:id, :status) = _fields(result);
  final log = p.join(out, 'notarytool-log.json');

  if (id.isNotEmpty) {
    for (var attempt = 1; ; attempt++) {
      final fetched = await runner.run('xcrun', [
        'notarytool',
        'log',
        id,
        '--keychain-profile',
        notaryProfile,
        log,
      ]);
      if (fetched.status == 0) break;
      if (attempt == 3) {
        die(
          'the notarisation log of $id could not be fetched: '
          '${said(fetched.stdout + fetched.stderr)}',
        );
      }
      await sleep(const Duration(seconds: 10));
    }
  }

  if (submit.status != 0) {
    die(
      'notarytool submit exited ${submit.status ?? 'without a status'}: '
      '$result ${said(submit.stderr)}',
    );
  }
  if (status != 'Accepted') die('notarisation of $zip ended $status: $result');
  if (id.isEmpty) {
    die('notarytool accepted $zip without a submission id: $result');
  }

  final tickets = _cdhashes(p.join(root, log));
  final notarised = <String, String>{};
  for (final binary in binaries) {
    final shown = await runner.run('codesign', ['-dvvv', binary]);
    if (shown.status != 0) {
      die('codesign -dvvv $binary failed: ${said(shown.stderr)}');
    }
    final cdhash =
        RegExp(
          r'^CDHash=(.*)$',
          multiLine: true,
        ).firstMatch(shown.stdout + shown.stderr)?[1] ??
        '';
    if (cdhash.isEmpty) die('the cdhash of $binary could not be read');
    if (!tickets.contains('"cdhash":"$cdhash"')) {
      die(
        "Apple's log has no ticket for $binary (cdhash $cdhash); it lists: "
        '${tickets.join('\n')}',
      );
    }
    notarised[binary] = cdhash;
    report('notarised $binary: $cdhash');
  }
  return notarised;
}

/// notarytool's submission id and status, empty where it gave none.
({String id, String status}) _fields(String result) {
  try {
    final parsed = jsonDecode(result);
    if (parsed is! Map) return (id: '', status: '');
    return (
      id: switch (parsed['id']) {
        final String id => id,
        _ => '',
      },
      status: switch (parsed['status']) {
        final String status => status,
        _ => '',
      },
    );
  } on FormatException {
    return (id: '', status: '');
  }
}

final _hex = RegExp(r'^[0-9a-f]*$');

/// The cdhashes Apple's log has a ticket for, each as `"cdhash":"…"`.
List<String> _cdhashes(String log) {
  try {
    final parsed = jsonDecode(File(log).readAsStringSync());
    final tickets = parsed is Map ? parsed['ticketContents'] : null;
    if (tickets is! List) return [];
    return [
      for (final ticket in tickets)
        if (ticket case {
          'cdhash': final String cdhash,
        } when _hex.hasMatch(cdhash))
          '"cdhash":"$cdhash"',
    ];
  } on FileSystemException {
    return [];
  } on FormatException {
    return [];
  }
}
