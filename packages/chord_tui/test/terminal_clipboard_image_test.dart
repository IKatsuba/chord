import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

typedef Answer = ({int exitCode, List<int> stdout, String stderr});

/// A runner that answers each tool from [answers], by its executable and
/// first argument, and records what was run; a tool with no answer is not
/// there.
class Runner {
  Runner(this.answers);
  final Map<String, Answer> answers;
  final calls = <List<String>>[];

  Future<Answer> call(String executable, List<String> arguments) async {
    calls.add([executable, ...arguments]);
    final answer =
        answers['$executable ${arguments.join(' ')}'] ?? answers[executable];
    if (answer == null) {
      throw ProcessException(executable, arguments, 'No such file', 2);
    }
    return answer;
  }
}

Answer ok(List<int> stdout) => (exitCode: 0, stdout: stdout, stderr: '');
Answer text(String stdout, [int exitCode = 0]) =>
    (exitCode: exitCode, stdout: utf8.encode(stdout), stderr: '');
Answer failed(int exitCode, String stderr) =>
    (exitCode: exitCode, stdout: const [], stderr: stderr);

const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

Future<ClipboardImage> read(
  Runner runner,
  String system, [
  Map<String, String> environment = const {},
]) => readSystemClipboardImage(
  run: runner.call,
  operatingSystem: system,
  environment: environment,
);

Matcher readBytes(List<int> bytes) =>
    isA<ClipboardImageRead>().having((image) => image.bytes, 'bytes', bytes);

void main() {
  group('macOS, through osascript', () {
    test('the clipboard as PNG, from the hex AppleScript prints', () async {
      final runner = Runner({
        'osascript': text('«data PNGf89504E470D0A1A0A»\n'),
      });
      expect(await read(runner, 'macos'), readBytes(png));
      expect(runner.calls.single, [
        'osascript',
        '-e',
        'the clipboard as «class PNGf»',
      ]);
    });

    test('a clipboard that cannot be made an image holds none', () async {
      final none = Runner({
        'osascript': failed(
          1,
          "execution error: Can't make some data into the expected type. "
          '(-1700)',
        ),
      });
      expect(await read(none, 'macos'), isA<ClipboardImageNone>());
    });

    test('another failure says what osascript said', () async {
      final runner = Runner({'osascript': failed(1, 'boom\n')});
      expect(
        await read(runner, 'macos'),
        isA<ClipboardImageFailed>().having((f) => f.reason, 'reason', 'boom'),
      );
    });

    test('no osascript is a clipboard that cannot be read here', () async {
      expect(
        await read(Runner({}), 'macos'),
        isA<ClipboardImageUnavailable>().having(
          (u) => u.reason,
          'reason',
          'osascript was not found',
        ),
      );
    });
  });

  group('Linux, through wl-paste then xclip', () {
    const wayland = {'WAYLAND_DISPLAY': 'wayland-0', 'DISPLAY': ':0'};

    test('PNG first among the types offered', () async {
      final runner = Runner({
        'wl-paste --list-types': text('text/plain\nimage/jpeg\nimage/png\n'),
        'wl-paste --type image/png': ok(png),
      });
      expect(await read(runner, 'linux', wayland), readBytes(png));
      expect(runner.calls.last, ['wl-paste', '--type', 'image/png']);
    });

    test('else the first image type there is', () async {
      final runner = Runner({
        'wl-paste --list-types': text('text/plain\nimage/jpeg\n'),
        'wl-paste --type image/jpeg': ok([0xFF, 0xD8, 0xFF]),
      });
      expect(
        await read(runner, 'linux', wayland),
        readBytes([0xFF, 0xD8, 0xFF]),
      );
    });

    test('text alone, or an empty clipboard, holds no image', () async {
      for (final listed in [
        text('text/plain\n'),
        text('Nothing is copied\n', 1),
      ]) {
        final runner = Runner({'wl-paste --list-types': listed});
        expect(await read(runner, 'linux', wayland), isA<ClipboardImageNone>());
      }
    });

    test('with no wl-paste, xclip reads it', () async {
      final runner = Runner({
        'xclip -selection clipboard -t TARGETS -o': text(
          'TARGETS\nimage/png\n',
        ),
        'xclip -selection clipboard -t image/png -o': ok(png),
      });
      expect(await read(runner, 'linux', wayland), readBytes(png));
      expect(runner.calls.first.first, 'wl-paste');
    });

    test('X alone asks xclip only', () async {
      final runner = Runner({
        'xclip -selection clipboard -t TARGETS -o': text('image/png\n'),
        'xclip -selection clipboard -t image/png -o': ok(png),
      });
      expect(await read(runner, 'linux', {'DISPLAY': ':0'}), readBytes(png));
      expect(runner.calls.map((call) => call.first).toSet(), {'xclip'});
    });

    test('a read that fails says what the tool said', () async {
      final runner = Runner({
        'wl-paste --list-types': text('image/png\n'),
        'wl-paste --type image/png': failed(1, 'compositor went away'),
      });
      expect(
        await read(runner, 'linux', wayland),
        isA<ClipboardImageFailed>().having(
          (f) => f.reason,
          'reason',
          'compositor went away',
        ),
      );
    });

    test('no tool, or no display, cannot be read here', () async {
      expect(
        await read(Runner({}), 'linux', wayland),
        isA<ClipboardImageUnavailable>().having(
          (u) => u.reason,
          'reason',
          'found neither wl-paste nor xclip',
        ),
      );
      final none = Runner({});
      expect(
        await read(none, 'linux'),
        isA<ClipboardImageUnavailable>().having(
          (u) => u.reason,
          'reason',
          'no Wayland or X display',
        ),
      );
      expect(none.calls, isEmpty);
    });
  });

  group('Windows, through PowerShell', () {
    test('the image as PNG on stdout', () async {
      final runner = Runner({'powershell': ok(png)});
      expect(await read(runner, 'windows'), readBytes(png));
      expect(runner.calls.single.take(4), [
        'powershell',
        '-NoProfile',
        '-NonInteractive',
        '-Command',
      ]);
      expect(runner.calls.single.last, contains('Get-Clipboard -Format Image'));
    });

    test('exit 2 is no image; another failure says why; none is '
        'unavailable', () async {
      expect(
        await read(Runner({'powershell': failed(2, '')}), 'windows'),
        isA<ClipboardImageNone>(),
      );
      expect(
        await read(Runner({'powershell': failed(1, 'denied')}), 'windows'),
        isA<ClipboardImageFailed>(),
      );
      expect(
        await read(Runner({}), 'windows'),
        isA<ClipboardImageUnavailable>(),
      );
    });
  });

  test('a tool that cannot start for another reason is a failure', () async {
    Future<Answer> broken(String executable, List<String> arguments) =>
        throw ProcessException(executable, arguments, 'Permission denied', 13);
    expect(
      await readSystemClipboardImage(run: broken, operatingSystem: 'macos'),
      isA<ClipboardImageFailed>(),
    );
  });

  test(
    'the process terminal reads through its runner and environment',
    () async {
      final runner = Runner({
        'osascript': text('«data PNGf89504E470D0A1A0A»'),
        'wl-paste --list-types': text('image/png\n'),
        'wl-paste --type image/png': ok(png),
        'powershell': ok(png),
      });
      final terminal = StdioTerminal(
        input: const Stream.empty(),
        environment: const {'WAYLAND_DISPLAY': 'wayland-0'},
        clipboardRunner: runner.call,
      );
      expect(await terminal.readClipboardImage(), readBytes(png));
      expect(
        runner.calls.first.first,
        Platform.isMacOS
            ? 'osascript'
            : Platform.isWindows
            ? 'powershell'
            : 'wl-paste',
      );
      await terminal.close();
    },
  );

  test('a terminal of its own reads no clipboard', () async {
    expect(
      await _Plain().readClipboardImage(),
      isA<ClipboardImageUnavailable>(),
    );
  });
  group('tester: clipboard runner boundaries', () {
    test('empty successful output is no image on every platform', () async {
      expect(
        await read(Runner({'osascript': text('«data PNGf»')}), 'macos'),
        isA<ClipboardImageNone>(),
      );
      expect(
        await read(Runner({'powershell': ok([])}), 'windows'),
        isA<ClipboardImageNone>(),
      );
      expect(
        await read(
          Runner({
            'wl-paste --list-types': text('image/png'),
            'wl-paste --type image/png': ok([]),
          }),
          'linux',
          {'WAYLAND_DISPLAY': 'test'},
        ),
        isA<ClipboardImageNone>(),
      );
    });

    test(
      'a permission error is a failure and never tries another display',
      () async {
        final calls = <String>[];
        Future<Answer> denied(String executable, List<String> arguments) async {
          calls.add(executable);
          throw ProcessException(executable, arguments, 'denied', 13);
        }

        final result = await readSystemClipboardImage(
          run: denied,
          operatingSystem: 'linux',
          environment: {'WAYLAND_DISPLAY': 'test', 'DISPLAY': ':0'},
        );
        expect(
          result,
          isA<ClipboardImageFailed>().having(
            (f) => f.reason,
            'reason',
            'denied',
          ),
        );
        expect(calls, ['wl-paste']);
      },
    );

    test(
      'concurrent reads retain their own runner and delayed result',
      () async {
        final first = Completer<Answer>();
        final pending = readSystemClipboardImage(
          operatingSystem: 'windows',
          run: (_, _) => first.future,
        );
        final second = await read(
          Runner({
            'powershell': ok([2, 0, 255]),
          }),
          'windows',
        );
        first.complete(ok([1, 0, 254]));
        expect(second, readBytes([2, 0, 255]));
        expect(await pending, readBytes([1, 0, 254]));
      },
    );
  });
}

class _Plain extends Terminal {
  @override
  Size get size => const Size(80, 24);
  @override
  Stream<String> get input => const Stream.empty();
  @override
  Stream<Size> get resizes => const Stream.empty();
  @override
  void enter() {}
  @override
  Future<void> leave() async {}
  @override
  void write(String data) {}
}
