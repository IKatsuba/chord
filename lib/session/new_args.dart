/// `/new`'s words read, whoever hosts it: `[agent] --name <name>`. The first
/// word is always an agent, never guessed as a name; the name is the rest of
/// the line after `--name`, so it may hold spaces. From the original's
/// `session/new_args.ts`.
library;

import '../js_trim.dart';

/// What `/new` was asked: a runtime, a name, both or neither; or words it
/// cannot read.
sealed class NewArgs {
  const NewArgs();
}

/// `/new` read: [agent] and [name], each null when not given.
final class NewAsked extends NewArgs {
  const NewAsked({this.agent, this.name});

  final String? agent;
  final String? name;

  @override
  bool operator ==(Object other) =>
      other is NewAsked && other.agent == agent && other.name == name;

  @override
  int get hashCode => Object.hash(agent, name);

  @override
  String toString() => 'NewAsked(agent: $agent, name: $name)';
}

/// Words `/new` cannot read, and what it says of them.
final class NewProblem extends NewArgs {
  const NewProblem(this.problem);

  final String problem;

  @override
  bool operator ==(Object other) =>
      other is NewProblem && other.problem == problem;

  @override
  int get hashCode => problem.hashCode;

  @override
  String toString() => 'NewProblem($problem)';
}

const _usage = '/new [agent] --name <name>';

/// Said of `--name` with nothing after it.
const noName = '--name needs a name · $_usage';

/// Said of any other word after the agent, `--name=x` among them.
const notName = '/new takes an agent, then --name <name> · $_usage';

final _firstWord = RegExp(r'^\S*');
final _flag = RegExp(r'^--name(?:\s+|$)');

/// Reads `/new`'s [args].
NewArgs newArgs(String args) {
  final text = jsTrim(args);
  final first = _firstWord.firstMatch(text)?.group(0) ?? '';
  final agent = first == '--name' ? '' : first;
  final rest = jsTrim(text.substring(agent.length));
  final named = agent.isEmpty ? null : agent;
  if (rest.isEmpty) return NewAsked(agent: named);
  final flag = _flag.firstMatch(rest);
  if (flag == null) return const NewProblem(notName);
  final name = jsTrim(rest.substring(flag.end));
  return name.isEmpty
      ? const NewProblem(noName)
      : NewAsked(agent: named, name: name);
}
