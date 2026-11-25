import 'dart:convert';

import 'package:chord_tui/chord_tui.dart';

void require(bool value, String reason) {
  if (!value) throw StateError(reason);
}

void main(List<String> args) {
  var assertionsEnabled = false;
  assert(() {
    assertionsEnabled = true;
    return true;
  }());
  var checked = 0;
  for (final size in const [Size(120, 40), Size(80, 24), Size(0, 0)]) {
    for (final callbackThrows in [false, true]) {
      final controller = TextAreaController(text: 'unchanged');
      Object? caught;
      final host = AppHost(
        ErrorBoundary(
          onError: (error, _) => caught = error,
          errorBuilder: (_, error, stack) => Text('Rejected'),
          child: TextArea(
            controller: controller,
            autofocus: true,
            textSpanBuilder: (_, text) {
              if (callbackThrows) throw StateError('callback failure');
              return TextSpan('$text changed');
            },
          ),
        ),
      );
      host.drawFrame(size);
      require(
        callbackThrows ? caught is StateError : caught is ArgumentError,
        'AOT build rejection was not active',
      );
      require(
        host.focusManager.activeBindings.every(
          (binding) => binding.description != 'Undo',
        ),
        'A rejected editor retained handlers',
      );
      host.handlePaste('hidden');
      require(controller.text == 'unchanged', 'Rejected input changed text');
      host.dispose();
      controller.dispose();
      checked++;
    }
  }
  print(
    jsonEncode({
      'checks': checked,
      'runtimeRejection': true,
      'assertionsEnabled': assertionsEnabled,
      if (args.isNotEmpty) 'source': args.single,
    }),
  );
}
