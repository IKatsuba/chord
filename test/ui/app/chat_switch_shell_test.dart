// A `!` command's output that lands while its child is hidden is news for
// that child, as an agent's is: the window folds it straight into the
// hidden session, so it must count its scroll there too.
import 'dart:async';

import 'package:chord/shell.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'editor_window_test.dart' show EditorTerminal, settle;
import 'front_routing_test.dart' show show, window;

final class _Shell extends ShellProcess {
  _Shell(this._done);
  final Completer<ShellEnd> _done;
  @override
  Future<ShellEnd> get ended => _done.future;
  @override
  void stop() {
    if (!_done.isCompleted) _done.complete(const ShellEnd(stopped: true));
  }
}

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets("a hidden child's `!` output is news when it is picked again, "
        "main's screen untouched, at $size", (t) async {
      final runs = <(ShellOptions, Completer<ShellEnd>)>[];
      final w = await window(
        t,
        size,
        EditorTerminal(),
        runShell: (command, options) {
          final done = Completer<ShellEnd>();
          runs.add((options, done));
          return _Shell(done);
        },
      );
      show(w.connection, w.child);
      await t.pump();
      await t.type('!printf parser');
      await t.press('enter');
      await settle(t);
      await t.type('go');
      await t.press('enter');
      await settle(t);
      w.session.chunk([for (var i = 0; i < 80; i++) 'line $i'].join('\n\n'));
      await settle(t);
      await t.press('pageup');
      await t.press('pageup');
      await t.pump();
      expect(t.screen, isNot(shows('new output')));

      show(w.connection, mainKey);
      await t.pump();
      await t.pump();
      final main = List.of(t.screen.lines);
      final (options, done) = runs.single;
      options.onOutput!(ShellStream.stdout, 'from the parser');
      done.complete(const ShellEnd(code: 0));
      await settle(t);
      expect(t.screen.lines, main);

      show(w.connection, w.child);
      await t.pump();
      await t.pump();
      expect(t.screen, shows('↓ new output'));
    });
  }
}
