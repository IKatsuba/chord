/// The four distinct startup intents; an empty id never stands for a picker.
enum ResumeKind { absent, pick, continuing, id }

/// The bounded optional-argument adapter approved for args' required values.
final class ResumeIntent {
  const ResumeIntent.absent() : kind = ResumeKind.absent, id = null;
  const ResumeIntent.pick() : kind = ResumeKind.pick, id = null;
  const ResumeIntent.continuing() : kind = ResumeKind.continuing, id = null;
  const ResumeIntent.id(String this.id) : kind = ResumeKind.id;
  final ResumeKind kind;
  final String? id;
}

/// An original parser refusal, rendered by the CLI's existing help policy.
final class ResumeArgumentsError implements Exception {
  const ResumeArgumentsError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Normalized options and positional spellings that args otherwise rejects.
final class ResumeArguments {
  ResumeArguments(
    this.intent,
    Iterable<String> arguments,
    Map<String, String> literals,
  ) : arguments = List.unmodifiable(arguments),
      _literals = Map.unmodifiable(literals);
  final ResumeIntent intent;
  final List<String> arguments;
  final Map<String, String> _literals;
  String positional(String value) => _literals[value] ?? value;
}

// Cliffy's optional string declines every declared flag name, with or without
// leading dashes. These names do not enable their deferred port behavior.
const _flagNames = {
  'h',
  'help',
  'V',
  'version',
  'C',
  'cwd',
  'agent-command',
  'm',
  'model',
  'effort',
  'permission-mode',
  'no-mcp-servers',
  'c',
  'continue',
  'r',
  'resume',
  'p',
  'print',
  'dangerously-skip-permissions',
  'output-format',
};
const _valueOptions = {
  '--agent-command',
  '-C',
  '--cwd',
  '-m',
  '--model',
  '--effort',
  '--permission-mode',
  '-p',
  '--print',
  '--output-format',
};
bool _namedFlag(String value) =>
    _flagNames.contains(value.replaceFirst(RegExp(r'^-+'), ''));

/// Removes only resume tokens, respecting other option values and `--`.
ResumeArguments adaptResumeArguments(List<String> argv) {
  var intent = const ResumeIntent.absent();
  var continuing = false;
  String? standalone, duplicateStandalone;
  final tokens = List<String>.of(argv);
  final out = <String>[], literals = <String, String>{};
  String literal(String value) {
    var token = '__chord_resume_positional_${literals.length}__';
    while (argv.contains(token)) {
      token += '_';
    }
    literals[token] = value;
    return token;
  }

  for (var i = 0; i < tokens.length; i++) {
    var token = tokens[i];
    if (token == '--') {
      out.addAll(tokens.skip(i));
      break;
    }
    if (_valueOptions.contains(token)) {
      out.add(token);
      if (i + 1 < tokens.length) out.add(tokens[++i]);
      continue;
    }
    if (token.length > 2 &&
        token.startsWith('-') &&
        !token.startsWith('--') &&
        const {'r', 'c', 'h', 'V'}.contains(token[1]) &&
        (token.substring(1).contains('r') ||
            token.substring(1).contains('c')) &&
        !token.contains('=')) {
      tokens.replaceRange(
        i,
        i + 1,
        token.substring(1).split('').map((letter) => '-$letter'),
      );
      token = tokens[i];
    }
    if (token == '--continue' || token == '-c') {
      if (continuing) {
        throw ResumeArgumentsError(
          'Option "$token" can only occur once, but was found several times.',
        );
      }
      continuing = true;
      out.add(token);
      continue;
    }
    if (token != '--resume' &&
        token != '-r' &&
        !token.startsWith('--resume=') &&
        !token.startsWith('-r=')) {
      if (const {'--help', '-h', '--version', '-V'}.contains(token)) {
        final canonical = const {'--help', '-h'}.contains(token)
            ? '--help'
            : '--version';
        if (standalone == canonical) duplicateStandalone ??= token;
        standalone ??= canonical;
      }
      out.add(token);
      continue;
    }
    if (intent.kind != ResumeKind.absent) {
      final name = token.startsWith('--') ? '--resume' : '-r';
      throw ResumeArgumentsError(
        'Option "$name" can only occur once, but was found several times.',
      );
    }
    final equal = token.indexOf('=');
    if (equal >= 0) {
      final value = token.substring(equal + 1);
      intent = value.isEmpty
          ? const ResumeIntent.absent()
          : _namedFlag(value)
          ? const ResumeIntent.pick()
          : ResumeIntent.id(value);
    } else {
      intent = const ResumeIntent.pick();
      if (i + 1 < tokens.length) {
        final next = tokens[i + 1];
        if (next != '--' && !_namedFlag(next)) {
          if (!next.startsWith('-')) {
            i++;
            intent = next.isEmpty
                ? const ResumeIntent.absent()
                : ResumeIntent.id(next);
          } else if (!_namedFlag(next.split('=').first) &&
              !(next.length > 2 &&
                  !next.startsWith('--') &&
                  const {'r', 'c', 'h', 'V'}.contains(next[1]))) {
            // Cliffy admits an unknown dash word as its optional positional
            // agent; preserve that word without making args parse it as a flag.
            i++;
            out.add(literal(next));
          }
        }
      }
    }
  }
  if (continuing && intent.kind != ResumeKind.absent) {
    throw const ResumeArgumentsError(
      'Option "--continue" conflicts with option "--resume".',
    );
  }
  if (continuing) intent = const ResumeIntent.continuing();
  if (intent.kind != ResumeKind.absent) {
    if (duplicateStandalone != null) {
      throw ResumeArgumentsError(
        'Option "$duplicateStandalone" can only occur once, but was found several times.',
      );
    }
    if (standalone != null) {
      throw ResumeArgumentsError(
        'Option "$standalone" cannot be combined with other options.',
      );
    }
  }
  return ResumeArguments(intent, out, literals);
}
