/// Params parsed as the original's SDK parses them with zod v4: the value
/// zod gives (objects stripped to their schema's keys, a union's matching
/// branch, defaults and fallbacks applied), or a refusal in zod's words:
/// -32602 `Invalid params` with zod's `format()` tree as data. Only what
/// the served methods' schemas need of zod is here.
library;

import 'rpc.dart';

/// A key absent from an object, which zod reads as `undefined`; a parse
/// that gives it leaves the key out.
const absent = _Absent();

final class _Absent {
  const _Absent();
}

/// One of zod's issues, at its full [path].
final class Issue {
  /// An issue saying [message] at [path]; [continues] when zod goes on
  /// after it, as after a refinement; [union] for a union no option took.
  const Issue(this.path, this.message, {this.continues = false, this.union});

  /// Where it is, from the params' root.
  final List<Object> path;

  /// zod's English words for it.
  final String message;

  /// Whether it leaves the parse unaborted, as zod's `continue: true`.
  final bool continues;

  /// Each option's issues, for an `invalid_union`.
  final List<List<Issue>>? union;
}

/// A zod schema, as far as chord's params need one.
sealed class Schema {
  const Schema();

  /// What zod makes of [value], found at [path], adding what is wrong with
  /// it to [issues]; [absent] for nothing.
  Object? parse(Object? value, List<Object> path, List<Issue> issues);
}

/// What zod calls [value]'s type in `received <type>`.
String _received(Object? value) => switch (value) {
  _Absent() => 'undefined',
  null => 'null',
  bool() => 'boolean',
  num() => 'number',
  String() => 'string',
  List() => 'array',
  _ => 'object',
};

Issue _invalidType(List<Object> path, String expected, Object? value) => Issue(
  path,
  'Invalid input: expected $expected, received ${_received(value)}',
);

/// `z.string()`.
final class Str extends Schema {
  /// A string.
  const Str();

  @override
  Object? parse(Object? value, List<Object> path, List<Issue> issues) {
    if (value is! String) issues.add(_invalidType(path, 'string', value));
    return value;
  }
}

/// `z.boolean()`.
final class Bool extends Schema {
  /// A boolean.
  const Bool();

  @override
  Object? parse(Object? value, List<Object> path, List<Issue> issues) {
    if (value is! bool) issues.add(_invalidType(path, 'boolean', value));
    return value;
  }
}

/// `z.number()`.
final class Num extends Schema {
  /// A number.
  const Num();

  @override
  Object? parse(Object? value, List<Object> path, List<Issue> issues) {
    if (value is! num || !value.isFinite) {
      issues.add(_invalidType(path, 'number', value));
    }
    return value;
  }
}

/// `z.int().gte(min).lte(max)`.
final class Int extends Schema {
  /// An integer from [min] to [max].
  const Int(this.min, this.max);

  /// The least it may be.
  final int min;

  /// The most it may be.
  final int max;

  @override
  Object? parse(Object? value, List<Object> path, List<Issue> issues) {
    if (value is! num || !value.isFinite) {
      issues.add(_invalidType(path, 'number', value));
    } else if (value != value.truncateToDouble()) {
      issues.add(Issue(path, 'Invalid input: expected int, received number'));
    } else if (value < min) {
      issues.add(Issue(path, 'Too small: expected number to be >=$min'));
    } else if (value > max) {
      issues.add(Issue(path, 'Too big: expected number to be <=$max'));
    }
    return value;
  }
}

/// `z.literal(value)` for a string.
final class Lit extends Schema {
  /// Exactly [value].
  const Lit(this.value);

  /// The one value taken.
  final String value;

  @override
  Object? parse(Object? value, List<Object> path, List<Issue> issues) {
    if (value != this.value) {
      issues.add(Issue(path, 'Invalid input: expected "${this.value}"'));
    }
    return value;
  }
}

/// `z.unknown()`: anything, as it is.
final class Unknown extends Schema {
  /// Anything.
  const Unknown();

  @override
  Object? parse(Object? value, List<Object> path, List<Issue> issues) => value;
}

/// `z.record(z.string(), z.unknown())`: an object, as it is.
final class Rec extends Schema {
  /// An object of anything.
  const Rec();

  @override
  Object? parse(Object? value, List<Object> path, List<Issue> issues) {
    if (value is! Map) {
      issues.add(_invalidType(path, 'record', value));
      return value;
    }
    return <String, Object?>{
      for (final MapEntry(:key, :value) in value.entries) '$key': value,
    };
  }
}

/// `z.array(item)`; [nullIsEmpty] for the SDK's `defaultOnNull`, which
/// reads null as an empty array; [skipInvalid] for its `vecSkipError`,
/// which drops elements [item] refuses.
final class Arr extends Schema {
  /// An array of [item].
  const Arr(this.item, {this.nullIsEmpty = false, this.skipInvalid = false});

  /// Each element's schema.
  final Schema item;

  /// Whether null is taken as an empty array.
  final bool nullIsEmpty;

  /// Whether an element [item] refuses is left out instead.
  final bool skipInvalid;

  @override
  Object? parse(Object? value, List<Object> path, List<Issue> issues) {
    if (value == null && nullIsEmpty) return <Object?>[];
    if (value is! List) {
      issues.add(_invalidType(path, 'array', value));
      return value;
    }
    final parsed = <Object?>[];
    for (final (index, element) in value.indexed) {
      final found = <Issue>[];
      final each = item.parse(element, [...path, index], found);
      if (skipInvalid && found.isNotEmpty) continue;
      issues.addAll(found);
      parsed.add(each);
    }
    return parsed;
  }
}

/// `z.object(shape)`, which strips keys the shape does not name, or with
/// [loose] `z.looseObject(shape)`, which keeps them after the shape's.
/// Keys are parsed in the shape's order.
final class Obj extends Schema {
  /// An object with [shape].
  const Obj(this.shape, {this.loose = false});

  /// Each key's schema.
  final Map<String, Schema> shape;

  /// Whether keys the shape does not name are kept.
  final bool loose;

  @override
  Object? parse(Object? value, List<Object> path, List<Issue> issues) {
    if (value is! Map) {
      issues.add(_invalidType(path, 'object', value));
      return value;
    }
    final parsed = <String, Object?>{};
    for (final MapEntry(:key, value: schema) in shape.entries) {
      final each = schema.parse(value.containsKey(key) ? value[key] : absent, [
        ...path,
        key,
      ], issues);
      if (each is! _Absent) parsed[key] = each;
    }
    if (loose) {
      for (final MapEntry(:key, value: each) in value.entries) {
        if (!shape.containsKey(key)) parsed[key as String] = each;
      }
    }
    return parsed;
  }
}

/// `.optional()`, or `.nullish()` with [nullable].
final class Opt extends Schema {
  /// [inner], or absent; or null too when [nullable].
  const Opt(this.inner, {this.nullable = false});

  /// The schema of a value that is there.
  final Schema inner;

  /// Whether null is taken as it is.
  final bool nullable;

  @override
  Object? parse(Object? value, List<Object> path, List<Issue> issues) {
    if (value is _Absent || (nullable && value == null)) return value;
    return inner.parse(value, path, issues);
  }
}

/// `.optional().default(value)`: [value] when absent.
final class Default extends Schema {
  /// [inner], or [value] when absent.
  const Default(this.inner, this.value);

  /// The schema of a value that is there.
  final Schema inner;

  /// What an absent one is.
  final Object? value;

  @override
  Object? parse(Object? value, List<Object> path, List<Issue> issues) =>
      value is _Absent ? this.value : inner.parse(value, path, issues);
}

/// `.catch(fallback)`, the SDK's `defaultOnError`: [inner]'s value, or
/// [fallback] where it refuses; never an issue.
final class Catch extends Schema {
  /// [inner], else [fallback].
  const Catch(this.inner, [this.fallback = absent]);

  /// The schema tried.
  final Schema inner;

  /// What a refused value is: [absent] for `undefined`.
  final Object? fallback;

  @override
  Object? parse(Object? value, List<Object> path, List<Issue> issues) {
    final found = <Issue>[];
    final parsed = inner.parse(value, path, found);
    return found.isEmpty ? parsed : fallback;
  }
}

/// `z.union(options)`: the first option that takes the value, with its
/// value; else, when exactly one option failed without aborting, its
/// issues; else one `invalid_union` carrying every option's.
final class Union extends Schema {
  /// One of [options].
  const Union(this.options);

  /// The options, in order.
  final List<Schema> options;

  @override
  Object? parse(Object? value, List<Object> path, List<Issue> issues) {
    final results = <List<Issue>>[];
    for (final option in options) {
      final found = <Issue>[];
      final parsed = option.parse(value, path, found);
      if (found.isEmpty) return parsed;
      results.add(found);
    }
    final unaborted = [
      for (final found in results)
        if (found.every((issue) => issue.continues)) found,
    ];
    if (unaborted.length == 1) {
      issues.addAll(unaborted.single);
    } else {
      issues.add(Issue(path, 'Invalid input', union: results));
    }
    return value;
  }
}

/// `left.and(right)`: both, the left's issues first, their objects merged.
final class And extends Schema {
  /// [left] and [right].
  const And(this.left, this.right);

  /// The first schema.
  final Schema left;

  /// The second.
  final Schema right;

  @override
  Object? parse(Object? value, List<Object> path, List<Issue> issues) {
    final a = left.parse(value, path, issues);
    final b = right.parse(value, path, issues);
    return a is Map<String, Object?> && b is Map<String, Object?>
        ? <String, Object?>{...a, ...b}
        : a;
  }
}

/// `.refine(test)`: [inner], then `Invalid input` where [test] refuses,
/// which zod does not abort on.
final class Refine extends Schema {
  /// [inner] that [test] also takes.
  const Refine(this.inner, this.test);

  /// The schema first checked.
  final Schema inner;

  /// What the value must pass besides.
  final bool Function(Object? value) test;

  @override
  Object? parse(Object? value, List<Object> path, List<Issue> issues) {
    final found = <Issue>[];
    final parsed = inner.parse(value, path, found);
    issues.addAll(found);
    if (found.isEmpty && !test(value)) {
      issues.add(Issue(path, 'Invalid input', continues: true));
    }
    return parsed;
  }
}

/// [issues] as zod's `error.format()`: a tree of `_errors` lists by path,
/// a union's options merged in at its place, integer keys first as a
/// JavaScript object orders them.
Map<String, Object?> formatIssues(List<Issue> issues) {
  final root = <String, Object?>{'_errors': <String>[]};
  void process(List<Issue> issues) {
    for (final issue in issues) {
      if (issue.union case final union? when union.isNotEmpty) {
        union.forEach(process);
        continue;
      }
      var node = root;
      for (final element in issue.path) {
        final key = '$element';
        // zod merges a segment named `_errors` into its node.
        if (key == '_errors') continue;
        node =
            (node[key] ??= <String, Object?>{'_errors': <String>[]})
                as Map<String, Object?>;
      }
      (node['_errors'] as List<String>).add(issue.message);
    }
  }

  process(issues);
  return _jsOrder(root);
}

Map<String, Object?> _jsOrder(Map<String, Object?> node) {
  final index = RegExp(r'^(0|[1-9]\d*)$');
  final integers = node.keys.where((key) => index.hasMatch(key)).toList()
    ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
  return {
    for (final key in [
      ...integers,
      ...node.keys.where((key) => !index.hasMatch(key)),
    ])
      key: switch (node[key]) {
        final Map<String, Object?> child => _jsOrder(child),
        final other => other,
      },
  };
}

/// Params parsed by [schema]: zod's value, an absent one read as `{}`, or
/// -32602 `Invalid params` with zod's tree as data.
Map<String, Object?> Function(Object? params) checkedBy(Schema schema) =>
    (params) {
      final issues = <Issue>[];
      final parsed = schema.parse(
        params ?? const <String, Object?>{},
        const [],
        issues,
      );
      if (issues.isNotEmpty) {
        throw RpcException(
          -32602,
          'Invalid params',
          data: formatIssues(issues),
        );
      }
      return (parsed as Map).cast<String, Object?>();
    };
