// The native process seam on its own, for process_io_test.dart: says each
// argument as a failure line, then exits with 3.
import 'package:chord_tui/src/terminal/process_io.dart';

void main(List<String> args) {
  settleFailureReports();
  args.forEach(reportFailure);
  exitWith(3);
}
