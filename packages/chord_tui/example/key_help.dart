import 'package:chord_tui/chord_tui.dart';

/// Custom and plain key help; `--rebound` moves Quit to ctrl+q through a
/// [Keymap].
void main(List<String> args) {
  final scroll = ScrollController();
  final app = Builder(
    builder: (context) => Actions(
      bindings: [
        Binding('ctrl+x a', 'Complete chord', () {}),
        Binding('q', 'Quit', () => exitApp(context), id: 'app:quit'),
        ...scrollBindings(
          scroll,
          keys: const ScrollKeys(
            pageUp: ['pageup', 'shift+pageup'],
            pageDown: ['pagedown', 'shift+pagedown'],
            top: ['home', 'shift+home'],
            bottom: ['end', 'shift+end'],
          ),
        ),
      ],
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            KeyHelp.builder(
              builder: (_, bindings, pending) {
                // The key Quit has now, found by its id wherever it moved.
                final quit = bindings
                    .where((b) => b.id == 'app:quit')
                    .map((b) => '${b.chord}')
                    .firstOrNull;
                return Text(
                  [
                    'Custom shortcuts. Press ctrl+x, then a'
                        '${quit == null ? '' : '; $quit quits'}.',
                    if (pending.isNotEmpty) 'Pending: ${pending.join(' ')}',
                    for (final group in groupBindings(bindings))
                      '${group.chords.join('/')}  ${group.description}',
                  ].join('\n'),
                );
              },
            ),
            KeyHelp(),
          ],
        ),
      ),
    ),
  );
  runApp(
    args.contains('--rebound')
        ? Keymap(
            data: KeymapData({
              'app:quit': [Chord.parse('ctrl+q')],
            }),
            child: app,
          )
        : app,
  );
}
