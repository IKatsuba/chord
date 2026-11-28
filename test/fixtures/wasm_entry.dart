// An entry that reaches chord's window, screens and platform libraries, for
// wasm_compile_test.dart: it must build with dart2wasm, which has no
// dart:ffi, so the site can run chord's own screens. It is compiled, never
// run.
import 'package:chord/platform/group_exec.dart';
import 'package:chord/platform/process.dart';
import 'package:chord/platform/resource_executable.dart';
import 'package:chord/ui/app/start.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/dialogs/permission_prompt.dart';
import 'package:chord/ui/plan/plan.dart';
import 'package:chord/ui/prompt/prompt_input.dart';

void main() {
  print([
    groupExecFlag,
    groupExec,
    spawnGroup,
    strerror,
    machineInspection,
    resolveResourceExecutable,
    StartPage,
    TranscriptWindow,
    PermissionPrompt,
    Plan,
    PromptInput,
  ]);
}
