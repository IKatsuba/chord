// Prints what a lookup finds for a command, for agents_test.dart, which runs
// it under an environment of its own: `ours` is the port's onPath,
// `package` process_run's which with its defaults.
import 'package:chord/agents.dart';
import 'package:process_run/which.dart';

Future<void> main(List<String> args) async {
  final [how, command] = args;

  print(how == 'ours' ? await onPath(command) : await which(command));
}
