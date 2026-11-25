import 'package:chord_tui/chord_tui.dart';

void main(List<String> args) => runApp(
  _Activation(
    presentation: args.contains('--presentation'),
    viewport: args.contains('--viewport'),
  ),
);

class _Activation extends StatefulWidget {
  const _Activation({this.presentation = false, this.viewport = false});
  final bool viewport;
  final bool presentation;

  @override
  State<_Activation> createState() => _ActivationState();
}

class _ActivationState extends State<_Activation> {
  final node = FocusNode(debugLabel: 'choices');
  late final items = [
    for (var i = 1; i <= (widget.presentation ? 3 : 12); i++)
      PickerItem(
        value: i,
        label: widget.presentation
            ? '$i. Allow this command in the current folder and do not ask again'
            : 'Choice $i',
      ),
  ];
  var enabled = true;
  var answer = 'None';

  @override
  void dispose() {
    node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      Binding('ctrl+t', 'Toggle choices', () {
        setState(() => enabled = !enabled);
      }),
      Binding('ctrl+g', 'Focus choices', node.requestFocus),
      Binding('ctrl+c', 'Quit', () => exitApp(context)),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(enabled ? 'Choices enabled' : 'Choices disabled'),
        Picker<int>(
          items: items,
          initialValue: widget.viewport ? 4 : null,
          showInitialSelectionAtTop: !widget.viewport,
          countHiddenItemsAbove: widget.viewport,
          unhandledKeys: widget.viewport
              ? const {'home', 'end', 'pageup', 'pagedown'}
              : const {},
          enabled: enabled,
          focusNode: node,
          searchable: true,
          wrapNavigation: widget.presentation,
          showNumbers: !widget.presentation,
          itemBuilder: widget.presentation
              ? (context, item, _) => Text(item.label)
              : null,
          maxVisibleRows: 6,
          onSelected: (value) => setState(() => answer = '$value'),
          onCanceled: () => setState(() => answer = 'Canceled'),
        ),
        Text('Answer: $answer'),
        const KeyHelp(),
      ],
    ),
  );
}
