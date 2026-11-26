// An entry that builds the site's four live chord fixtures, for
// live_compile_test.dart: it must compile to Wasm. It is compiled, never run.
import 'package:chord_site/live/permission.dart';
import 'package:chord_site/live/plan.dart';
import 'package:chord_site/live/prompt.dart';
import 'package:chord_site/live/start.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/web.dart';

Future<void> main() => runApp(
  Column(
    children: [
      Expanded(child: LivePrompt()),
      Expanded(child: LivePermission()),
      Expanded(child: LivePlan()),
      Expanded(child: LiveStart()),
    ],
  ),
  terminal: WebTerminal(),
  exitProcess: false,
  handleSignals: false,
);
