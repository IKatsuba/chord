// Opens a link through a StdioTerminal given no runner, as an app does,
// and says what openUrl returned. The test puts fake openers first on
// PATH, so no real opener or browser is reached.
import 'dart:async';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';

Future<void> main(List<String> args) async {
  final terminal = StdioTerminal(
    input: const Stream.empty(),
    openUrlProbes: (
      read: (_) => null,
      exists: (_) => false,
      executable: (_) => false,
    ),
  );
  final said = await terminal.openUrl(args.single);
  stdout.writeln('said: $said');
  await stdout.flush();
  exit(0);
}
