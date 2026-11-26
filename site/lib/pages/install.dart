import 'package:chord_tui/chord_tui.dart';

/// How to install chord, as the README says it.
class InstallPage extends StatelessWidget {
  /// The install page.
  const InstallPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Text command(String line) => Text('    $line', style: theme.accent);
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'npm, or bun, pnpm and yarn',
            style: theme.text.merge(Style.bold),
          ),
          command('npm install -g @chorded/chord'),
          Text(
            'A small shim around a prebuilt binary for macOS and Linux, arm64 '
            'and x64. chord upgrade updates it the way it was installed.',
            style: theme.dim,
          ),
          Text(''),
          Text(
            'Homebrew, for stable releases',
            style: theme.text.merge(Style.bold),
          ),
          command('brew install ikatsuba/tap/chord'),
          Text(''),
          Text(
            'From source, with Dart 3.12 or newer',
            style: theme.text.merge(Style.bold),
          ),
          command('git clone https://github.com/IKatsuba/chord && cd chord'),
          command('dart pub get'),
          command('dart compile exe bin/chord.dart -o build/chord'),
          command('./build/chord'),
        ],
      ),
    );
  }
}
