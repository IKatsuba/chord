// ctrl+v, pasted and typed image paths, and the images a prompt sends, from
// the original's src/ui/app/terminal.ts useImages and keys.ts; through an
// in-memory agent, never a real clipboard.
import 'dart:async';
import 'dart:typed_data';

import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart' show MemoryAgentProcess;
import 'package:chord/cli.dart';
import 'package:chord/images.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/shortcuts/keys.dart' as catalog;
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'window_fake_test.dart' show until;

const launch = Launch(
  name: 'memory',
  agent: null,
  agentCommand: 'memory',
  version: '0.0.1',
  directory: '/w',
);

final pixel = imageOf(
  Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 13, 10, 26, 10, 0, 0]),
)!;

/// An in-memory agent that takes images when [images], answering each
/// prompt at once and keeping what it was sent.
final class _Agent {
  _Agent({this.images = true}) {
    process = MemoryAgentProcess(
      onSignal: (_) {
        if (process.exited) return;
        process.exit(const Exit(143, 'SIGTERM'));
        process.closeStdout();
        process.closeStderr();
      },
    );
    _timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
      for (final message in [...process.stdin.messages]) {
        final id = message['id'];
        final method = message['method'];
        if (id == null || method == null || !_seen.add(id)) continue;
        if (method == 'session/prompt') {
          prompts.add(
            ((message['params'] as Map)['prompt'] as List)
                .cast<Map<String, Object?>>(),
          );
        }
        process.send({
          'jsonrpc': '2.0',
          'id': id,
          'result': switch (method) {
            'initialize' => {
              'protocolVersion': 1,
              'agentCapabilities': {
                'promptCapabilities': {'image': images},
              },
            },
            'session/prompt' => {'stopReason': 'end_turn'},
            _ => {'sessionId': 's1'},
          },
        });
      }
    });
  }

  final bool images;
  late final MemoryAgentProcess process;
  late final Timer _timer;
  final _seen = <Object?>{};

  /// Each prompt's blocks, as sent.
  final prompts = <List<Map<String, Object?>>>[];

  StartConnection connect() => StartConnection(
    command: 'memory',
    cwd: '/w',
    agent: 'memory',
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
        }) => connectAgent(
          process,
          onTraffic: onTraffic,
          onPermission: onPermission,
          relay: relay,
          cancellationToken: cancellationToken,
        ),
  )..start();

  void stop() => _timer.cancel();
}

Future<(_Agent, StartConnection)> _open(
  WidgetTester t,
  Size size, {
  bool images = true,
  ClipboardReader? clipboard,
  ImageFileReader? readImage,
  bool wait = true,
}) async {
  final agent = _Agent(images: images);
  final connection = agent.connect();
  addTearDown(() async {
    agent.stop();
    await connection.close();
  });
  await t.pumpWidget(
    TranscriptWindow(
      launch: launch,
      connection: connection,
      readClipboard: clipboard ?? () async => ImageReadDone(pixel),
      readImage: readImage ?? (_) async => null,
    ),
    size: size,
  );
  if (wait) {
    await until(() => connection.app.value.start.phase == StartPhase.connected);
    await t.pump();
  }
  return (agent, connection);
}

/// Lets the async read land, then draws.
Future<void> settle(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 20));
}

List<String> imageBlocks(List<Map<String, Object?>> prompt) => [
  for (final block in prompt)
    if (block['type'] == 'image') '${block['mimeType']}:${block['data']}',
];

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('ctrl+v puts the image at the cursor, and Enter sends it '
        'with the prompt at $size', (t) async {
      final (agent, connection) = await _open(t, size);
      await t.type('what is');
      await t.press('ctrl+v');
      await settle(t);
      expect(connection.app.value.draft, 'what is [Image #1] ');
      expect(t.screen.text, contains('what is [Image #1]'));
      await t.type('this?');
      await t.press('enter');
      await until(() => agent.prompts.isNotEmpty);
      await t.pump();
      expect(agent.prompts.single.first, {
        'type': 'text',
        'text': 'what is [Image #1] this?',
      });
      expect(imageBlocks(agent.prompts.single), ['image/png:${pixel.data}']);
      // As the original draws it: the prompt's own words, placeholder and
      // all.
      expect(t.screen.text, contains('what is [Image #1] this?'));
      expect(connection.app.value.images, isEmpty);
      // The next image takes the next number.
      await t.press('ctrl+v');
      await settle(t);
      expect(connection.app.value.draft, '[Image #2] ');
    });

    testWidgets('a clipboard with no image says so in the status line '
        'until the draft is touched, at $size', (t) async {
      final (_, connection) = await _open(
        t,
        size,
        clipboard: () async =>
            const ImageReadFailed('No image in the clipboard'),
      );
      await t.press('ctrl+v');
      await settle(t);
      expect(t.screen.text, contains('No image in the clipboard'));
      final row = t.screen.lines.indexWhere(
        (line) => line.contains('No image in the clipboard'),
      );
      // In the warning role, as the original draws a failure note.
      final column = t.screen.lines[row].indexOf('No image');
      expect(t.screen.styleAt(column, row).fg, ThemeData.dark().warning.fg);
      await t.type('x');
      expect(t.screen.text, isNot(contains('No image in the clipboard')));
      expect(connection.app.value.draft, 'x');
    });

    testWidgets('an agent that takes no images says so, at $size', (t) async {
      final (_, connection) = await _open(t, size, images: false);
      await t.press('ctrl+v');
      await settle(t);
      expect(t.screen.text, contains('memory does not take images'));
      expect(connection.app.value.images, isEmpty);
    });

    testWidgets('a pasted path to an image is the image, the cursor after '
        'it, at $size', (t) async {
      final (agent, connection) = await _open(
        t,
        size,
        readImage: (path) async => path == '/tmp/shot.png' ? pixel : null,
      );
      await t.type('see ');
      await t.paste('/tmp/shot.png');
      await settle(t);
      expect(connection.app.value.draft, 'see [Image #1]');
      expect(connection.app.value.cursor, 'see [Image #1]'.length);
      // Backspace into it takes the whole placeholder and its image.
      await t.press('backspace');
      await t.pump();
      expect(connection.app.value.draft, 'see ');
      await t.type('ok');
      await t.press('enter');
      await until(() => agent.prompts.isNotEmpty);
      expect(imageBlocks(agent.prompts.single), isEmpty);
    });

    testWidgets('a typed path is read as the prompt goes, and ↑ brings the '
        'prompt back with its image, at $size', (t) async {
      final (agent, connection) = await _open(
        t,
        size,
        readImage: (path) async => path == '/tmp/a.png' ? pixel : null,
      );
      await t.type('look at /tmp/a.png please');
      await t.press('enter');
      await until(() => agent.prompts.isNotEmpty);
      await t.pump();
      expect(agent.prompts.single.first['text'], 'look at [Image #1] please');
      expect(imageBlocks(agent.prompts.single), hasLength(1));
      expect(connection.app.value.draft, isEmpty);
      await t.press('up');
      await t.pump();
      expect(connection.app.value.draft, 'look at [Image #1] please');
      await t.press('enter');
      await until(() => agent.prompts.length == 2);
      expect(imageBlocks(agent.prompts.last), hasLength(1));
    });

    testWidgets('ctrl+w takes a held placeholder whole with its space, and '
        'is the word cut elsewhere, at $size', (t) async {
      final (_, connection) = await _open(t, size);
      await t.type('cut ');
      await t.press('ctrl+v');
      await settle(t);
      expect(connection.app.value.draft, 'cut [Image #1] ');
      await t.press('ctrl+w');
      await t.pump();
      expect(connection.app.value.draft, 'cut ');
      await t.press('ctrl+w');
      await t.pump();
      expect(connection.app.value.draft, isEmpty);
    });

    testWidgets('while a prompt\'s paths are read, Enter sends nothing more, '
        'and a later draft waits behind it, at $size', (t) async {
      final held = Completer<ImageData?>();
      final (agent, connection) = await _open(
        t,
        size,
        readImage: (_) => held.future,
      );
      await t.type('/tmp/a.png');
      await t.press('enter');
      await t.press('enter');
      // A later draft, typed while the read is out, is not sent ahead.
      await t.press('ctrl+c');
      await t.type('later');
      await t.press('enter');
      await t.pump(const Duration(milliseconds: 50));
      expect(agent.prompts, isEmpty);
      expect(connection.app.value.draft, 'later');
      // chord\'s own commands do not wait.
      held.complete(pixel);
      await until(() => agent.prompts.isNotEmpty);
      await t.pump(const Duration(milliseconds: 50));
      expect(agent.prompts, hasLength(1));
      expect(agent.prompts.single.first['text'], '[Image #1]');
      expect(imageBlocks(agent.prompts.single), hasLength(1));
      // The later draft stays, and goes next.
      expect(connection.app.value.draft, 'later');
      await t.press('enter');
      await until(() => agent.prompts.length == 2);
      expect(agent.prompts.last.first['text'], 'later');
    });

    testWidgets('an empty bracketed paste reads the clipboard quietly, at '
        '$size', (t) async {
      final (_, connection) = await _open(t, size);
      await t.paste('');
      await settle(t);
      expect(connection.app.value.draft, '[Image #1] ');
      final (_, quiet) = await _open(
        t,
        size,
        clipboard: () async =>
            const ImageReadFailed('No image in the clipboard'),
      );
      await t.paste('');
      await settle(t);
      expect(quiet.app.value.pasteFailed, isNull);
    });
  }

  testWidgets('before the agent is up ctrl+v says it has not started, until '
      'it has', (t) async {
    final agent = _Agent();
    final connection = agent.connect();
    addTearDown(() async {
      agent.stop();
      await connection.close();
    });
    await t.pumpWidget(
      TranscriptWindow(
        launch: launch,
        connection: connection,
        readClipboard: () async => ImageReadDone(pixel),
      ),
      size: const Size(80, 24),
    );
    await t.press('ctrl+v');
    await t.pump();
    if (connection.app.value.start.phase == StartPhase.starting) {
      expect(connection.app.value.pasteFailed, 'memory has not started yet');
    }
    await until(() => connection.app.value.start.phase == StartPhase.connected);
    expect(connection.app.value.pasteFailed, isNull);
  });

  test('the shortcuts panel and the binding name ctrl+v', () {
    expect(
      catalog.shortcuts.map(catalog.shortcutLine),
      contains('ctrl + v to paste an image'),
    );
  });

  group('tester: delayed image read ownership', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'a failed submit read releases Enter for the next draft at $size',
        (t) async {
          final held = Completer<ImageData?>();
          final (agent, connection) = await _open(
            t,
            size,
            readImage: (_) => held.future,
          );
          await t.type('/tmp/failed.png');
          await t.press('enter');
          await t.press('enter');
          expect(agent.prompts, isEmpty);
          held.completeError(StateError('file vanished'));
          await settle(t);
          await t.press('ctrl+c');
          await t.type('after failure');
          await t.press('enter');
          await until(() => agent.prompts.isNotEmpty);
          expect(agent.prompts, hasLength(1));
          expect(agent.prompts.single.first['text'], 'after failure');
          expect(imageBlocks(agent.prompts.single), isEmpty);
          expect(connection.app.value.draft, isEmpty);
        },
      );

      testWidgets(
        'editing while a pasted path is read keeps the new text at $size',
        (t) async {
          final held = Completer<ImageData?>();
          final (_, connection) = await _open(
            t,
            size,
            readImage: (_) => held.future,
          );
          await t.paste('/tmp/slow.png');
          await t.type(' later');
          held.complete(pixel);
          await settle(t);
          expect(connection.app.value.draft, '/tmp/slow.png later');
          expect(connection.app.value.images, isEmpty);
        },
      );

      testWidgets('removal ignores a late clipboard result at $size', (
        t,
      ) async {
        final held = Completer<ImageRead>();
        final (_, connection) = await _open(
          t,
          size,
          clipboard: () => held.future,
        );
        await t.press('ctrl+v');
        await t.pumpWidget(const SizedBox(), size: size);
        final before = connection.app.value;
        held.complete(ImageReadDone(pixel));
        await settle(t);
        expect(connection.app.value, same(before));
        expect(connection.app.value.images, isEmpty);
      });
    }
  });
}
