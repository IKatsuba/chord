/// An elicitation form as the framework's [Form] asks it, from the
/// original's `ui/dialogs/form.ts`: the fields a requested schema asks for,
/// their defaults, what is wrong with a value and in what words, and how an
/// answered form and a link read back.
library;

import 'package:chord_tui/chord_tui.dart';
import 'package:json_schema/json_schema.dart';
import 'package:punycoder/punycoder.dart';

/// The `oneOf`/`anyOf` titled options, or the plain `enum` ones, of a
/// property: a string's, or an array's items'.
List<PickerItem<String>> _optionsOf(Map<String, Object?> schema) {
  List<PickerItem<String>> titled(Object? list) => [
    if (list is List)
      for (final entry in list)
        if (entry case {'const': final String value})
          PickerItem(
            value: value,
            label: switch (entry['title']) {
              final String title => title,
              _ => value,
            },
          ),
  ];
  List<PickerItem<String>> plain(Object? list) => [
    if (list is List)
      for (final value in list.whereType<String>())
        PickerItem(value: value, label: value),
  ];
  if (schema['type'] == 'array') {
    final items = switch (schema['items']) {
      final Map<String, Object?> items => items,
      _ => const <String, Object?>{},
    };
    return items.containsKey('anyOf')
        ? titled(items['anyOf'])
        : plain(items['enum']);
  }
  return schema.containsKey('oneOf')
      ? titled(schema['oneOf'])
      : plain(schema['enum']);
}

/// The words of a number property's bounds: `A whole number from 1 to 9`.
String numberWords(Map<String, Object?> schema) {
  final what = schema['type'] == 'integer' ? 'A whole number' : 'A number';
  final min = schema['minimum'], max = schema['maximum'];
  String shown(Object bound) =>
      bound is double && bound == bound.truncate() && bound.isFinite
      ? '${bound.truncate()}'
      : '$bound';
  return switch ((min, max)) {
    (final num min, final num max) =>
      '$what from ${shown(min)} to ${shown(max)}',
    (final num min, _) => '$what of ${shown(min)} or more',
    (_, final num max) => '$what of ${shown(max)} or less',
    _ => what,
  };
}

/// The words for a format the agent asked for, as the original words zod's
/// findings; another format reads as the package says it.
const formatWords = {
  'email': 'Not an email address, such as name@example.com',
  'uri': 'Not a URL, such as https://example.com',
  'date': 'Not a date, such as 2026-10-06',
  'date-time': 'Not a date and time, such as 2026-10-06T14:30:00Z',
};

/// The keywords a property's value is checked by, one at a time, in the
/// order zod's `fromJSONSchema` builds its checks, so the first that fails
/// is the one the original reports: a string's format before its lengths
/// and pattern.
const _keywords = [
  'type',
  'enum',
  'const',
  'oneOf',
  'anyOf',
  'items',
  'format',
  'minLength',
  'maxLength',
  'pattern',
  'minimum',
  'maximum',
  'exclusiveMinimum',
  'exclusiveMaximum',
  'multipleOf',
  'minItems',
  'maxItems',
  'uniqueItems',
];

// Each property's schema as json_schema builds it, once; null for one it
// cannot build, whose values are then left unchecked, as the original
// leaves them where zod cannot read the schema.
final _built = Expando<Object>();

JsonSchema? _schemaOf(Map<String, Object?> schema) {
  final built = _built[schema] ??= _build(schema) ?? false;
  return built is JsonSchema ? built : null;
}

JsonSchema? _build(Map<String, Object?> schema) {
  try {
    return JsonSchema.create(schema, schemaVersion: SchemaVersion.draft2020_12);
  } on Object {
    return null;
  }
}

bool _valid(JsonSchema schema, Object? value) =>
    schema.validate(value, validateFormats: true).isValid;

/// What is wrong with [value] against [property], the property's schema, in
/// chord's words; null when nothing is. json_schema decides; which keyword
/// failed is found by checking the value against each keyword alone, as
/// its errors do not name one.
String? checkValue(Map<String, Object?> property, Object? value) {
  final whole = _schemaOf(property);
  if (whole == null || _valid(whole, value)) return null;
  final type = property['type'];
  if (type == 'number' || type == 'integer') return numberWords(property);
  final multi = type == 'array';
  for (final keyword in _keywords) {
    if (!property.containsKey(keyword)) continue;
    final alone = _schemaOf(_alone(property, keyword));
    if (alone == null || _valid(alone, value)) continue;
    final bound = property[keyword];
    return switch (keyword) {
      'enum' ||
      'const' ||
      'oneOf' ||
      'anyOf' ||
      'items' => 'Not one of the choices',
      'minLength' => 'At least ${_characters(bound)}',
      'maxLength' => 'At most ${_characters(bound)}',
      'minItems' => 'Pick at least $bound',
      'maxItems' => 'Pick at most $bound',
      'pattern' => 'Must match $bound',
      'format' when formatWords[bound] != null => formatWords[bound]!,
      _ => _said(whole, value),
    };
  }
  return multi ? 'Not one of the choices' : _said(whole, value);
}

// One keyword of [property] alone, as a schema of its own.
final _alones = Expando<Map<String, Map<String, Object?>>>();

Map<String, Object?> _alone(Map<String, Object?> property, String keyword) =>
    (_alones[property] ??= {})[keyword] ??= {keyword: property[keyword]};

String _characters(Object? count) =>
    count == 1 ? '1 character' : '$count characters';

// The package's own words, for a rule chord has none for, as the original
// shows zod's.
String _said(JsonSchema schema, Object? value) =>
    schema.validate(value, validateFormats: true).errors.first.message;

/// The requested schema's properties as the form's fields, in the order it
/// lists them; [check] gives a field its validator, the words for what is
/// wrong with a value, from the property's schema. A form whose schema the
/// package cannot build as a whole leaves every value unchecked, as the
/// original does where zod cannot read it.
List<FormItem> fieldsOf(
  Map<String, Object?> schema, {
  String? Function(Map<String, Object?> property, Object? value)? check =
      checkValue,
}) {
  final required = {...?(schema['required'] as List?)?.whereType<String>()};
  final properties = switch (schema['properties']) {
    final Map<String, Object?> properties => properties,
    _ => const <String, Object?>{},
  };
  if (check != null &&
      _build({
            'type': 'object',
            'properties': properties,
            'required': [...required],
          }) ==
          null) {
    check = null;
  }
  return [
    for (final MapEntry(:key, value: raw) in properties.entries)
      _fieldOf(
        key,
        raw is Map<String, Object?> ? raw : const {},
        required.contains(key),
        check,
      ),
  ];
}

FormItem _fieldOf(
  String key,
  Map<String, Object?> property,
  bool required,
  String? Function(Map<String, Object?> property, Object? value)? check,
) {
  final label = switch (property['title']) {
    final String title when title.isNotEmpty => title,
    _ => key,
  };
  final description = switch (property['description']) {
    final String text when text.isNotEmpty => text,
    _ => null,
  };
  final options = _optionsOf(property);
  final initial = property['default'];
  String? checked(Object? value) => check?.call(property, value);
  switch (property['type']) {
    case 'string' when options.isEmpty:
      return TextFormItem(
        name: key,
        label: label,
        description: description,
        required: required,
        initialValue: initial is String ? initial : null,
        validator: checked,
      );
    case 'string':
      return ChoiceFormItem<String>(
        name: key,
        label: label,
        description: description,
        required: required,
        options: options,
        initialValue: initial is String ? initial : null,
        validator: checked,
      );
    case 'number' || 'integer':
      final integer = property['type'] == 'integer';
      return NumberFormItem(
        name: key,
        label: label,
        description: description,
        required: required,
        integer: integer,
        initialValue: initial is num ? initial : null,
        // Text that is no number reads as the bounds do.
        validator: (text) {
          final value = integer ? int.tryParse(text) : num.tryParse(text);
          return value == null ? numberWords(property) : checked(value);
        },
      );
    case 'boolean':
      return BoolFormItem(
        name: key,
        label: label,
        description: description,
        required: required,
        initialValue: initial is bool ? initial : null,
        validator: checked,
      );
    case 'array' when options.isNotEmpty:
      return MultiChoiceFormItem<String>(
        name: key,
        label: label,
        description: description,
        required: required,
        options: options,
        initialValue: initial is List
            ? initial.whereType<String>().toList()
            : null,
        validator: checked,
      );
    default:
      return UnsupportedFormItem(
        name: key,
        label: label,
        description: description,
        required: required,
      );
  }
}

/// One row of an answered form's record, as ctrl+o shows it.
typedef AnsweredRow = ({String label, String value});

/// What an accepted form sent, field by field in the form's order, each
/// value as the form showed it: an option's title, `Yes` or `No`.
List<AnsweredRow> answeredRows(
  Map<String, Object?> schema,
  Map<String, Object?> content,
) => [
  for (final field in fieldsOf(schema, check: null))
    if (content[field.name] case final value?)
      (label: field.label, value: _shown(field, value)),
];

String _shown(FormItem field, Object value) {
  String title(Object? chosen) => switch (field) {
    ChoiceFormItem<String>(:final options) ||
    MultiChoiceFormItem<String>(:final options) =>
      options.where((o) => o.value == chosen).firstOrNull?.label ?? '$chosen',
    _ => '$chosen',
  };
  return switch (value) {
    true => 'Yes',
    false => 'No',
    final List<Object?> list => list.map(title).join(', '),
    final String text when field is ChoiceFormItem => title(text),
    // A whole number reads as JavaScript prints it: 3, not 3.0.
    final double number when number.isFinite && number == number.truncate() =>
      '${number.truncate()}',
    _ => '$value',
  };
}

/// `Answered · 7 fields`: how many values an accepted form sent.
String answeredText(Map<String, Object?>? content) {
  final count = content?.length ?? 0;
  return count == 0
      ? 'Answered'
      : 'Answered · $count field${count == 1 ? '' : 's'}';
}

/// The host a link opens, named under it so a long or misleading URL cannot
/// hide where it goes; none for one that does not parse or is not a web
/// link, which chord does not offer to open.
String? linkHost(String url) {
  // As a browser reads it: spaces and controls around the link dropped.
  final parsed = Uri.tryParse(url.replaceAll(_around, ''));
  if (parsed == null ||
      !(parsed.scheme == 'http' || parsed.scheme == 'https') ||
      parsed.host.isEmpty) {
    return null;
  }
  final host = parsed.host;
  // An IPv6 address is named in its brackets, as a browser names it.
  if (host.contains(':')) return '[$host]';
  // A host of other letters than ASCII's is named as a browser sends it,
  // in punycode, so a look-alike cannot pass for the host it mimics.
  try {
    return domainToAscii(Uri.decodeComponent(host), validate: false);
  } on Object {
    return host;
  }
}

final _around = RegExp(r'^[\x00-\x20]+|[\x00-\x20]+$');
