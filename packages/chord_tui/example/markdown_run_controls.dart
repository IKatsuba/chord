// Application-supplied run policy, with recording callbacks and no execution.
import 'dart:io';
import 'package:chord_tui/chord_tui.dart';

void main(List<String> args) => runApp(
  const MarkdownRunControlsDemo(),
  theme: args.contains('--light') ? ThemeData.light() : ThemeData.dark(),
  environment: {
    ...Platform.environment,
    if (args.contains('--plain')) 'NO_COLOR': '1',
  },
);

class MarkdownRunControlsDemo extends StatefulWidget {
  const MarkdownRunControlsDemo();
  @override
  State<MarkdownRunControlsDemo> createState() => _RunControlsState();
}

class _RunControlsState extends State<MarkdownRunControlsDemo> {
  final selection = SelectionController();
  final source = SelectionSource.markdown(
    id: 'controls',
    revision: 0,
    text: '```custom\nx\n```',
    copyCodeBlocks: true,
    runCodeBlockLanguages: {'custom'},
  );
  final runOnly = SelectionSource.markdown(
    id: 'run-only',
    revision: 0,
    text: '```custom\nrun only\n```',
    runCodeBlockLanguages: {'custom'},
  );
  var note = 'No action', narrow = false, picked = false;
  void record(String action, MarkdownCodeBlock block) =>
      setState(() => note = '$action: ${block.text}');
  @override
  void dispose() {
    selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      Binding('ctrl+q', 'Quit', () => exitApp(context)),
      Binding(
        'r',
        'Record run action',
        () => record('Run', source.codeBlocks.single),
      ),
      Binding(
        'shift+r',
        'Record run-only action',
        () => record('Run only', runOnly.codeBlocks.single),
      ),
      Binding(
        'c',
        'Record copy action',
        () => record('Copy', source.codeBlocks.single),
      ),
      Binding(
        'p',
        'Toggle picked frame',
        () => setState(() => picked = !picked),
      ),
      Binding(
        'n',
        'Toggle narrow controls',
        () => setState(() => narrow = !narrow),
      ),
    ],
    child: SelectionArea(
      controller: selection,
      selectionStyle: const Style(inverse: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: narrow ? 24 : null,
            child: Markdown.fromSelectionSource(
              source,
              selectedCodeBlock: picked ? source.codeBlocks.single.id : null,
              onCopyCodeBlock: (block) => record('Copy', block),
              onRunCodeBlock: (block) => record('Run', block),
            ),
          ),
          Markdown.fromSelectionSource(
            runOnly,
            onRunCodeBlock: (block) => record('Run only', block),
          ),
          Markdown(
            '> ```custom\n> quoted\n> ```\n\n```custom\nopen fence',
            runCodeBlockLanguages: const {'custom'},
            onRunCodeBlock: (block) => record('Run', block),
          ),
          Text(note),
          KeyHelp.builder(
            builder: (context, bindings, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < bindings.length; i += 3)
                  Text(
                    bindings
                        .skip(i)
                        .take(3)
                        .map(
                          (binding) =>
                              '${binding.chord} ${binding.description}',
                        )
                        .join(' · '),
                    style: Theme.of(context).dim,
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
