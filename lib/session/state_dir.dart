import 'package:path/path.dart' as p;
import 'package:xdg_directories/xdg_directories.dart' as xdg;

/// Where chord keeps state shared with the original client.
String chordStateDir() {
  try {
    return p.join(xdg.stateHome.path, 'chord');
  } on StateError {
    throw StateError(
      "HOME or XDG_STATE_HOME must be set to keep chord's state.",
    );
  }
}
