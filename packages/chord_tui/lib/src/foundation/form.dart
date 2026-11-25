import 'dart:math' as math;

import 'package:characters/characters.dart';

import 'notifier.dart';
import 'picker_state.dart';
import 'text_editing.dart';

/// One field of a form: the key its value is sent under, what it is called
/// and how it takes a value. A form draws its fields in one column of
/// labels, so they are data handed to it, as [PickerItem]s are to a picker.
sealed class FormItem {
  const FormItem({
    required this.name,
    required this.label,
    this.description,
    this.required = false,
  });

  /// The key of its value in what the form submits.
  final String name;

  /// What the label column shows.
  final String label;

  /// Drawn under the field while it has the focus.
  final String? description;

  /// Whether the form is refused while it is unset.
  final bool required;

  // The value as the form holds it at first; none for unset.
  Object? get _initial;

  // The validator's words for [raw], held as the form holds it.
  String? _check(Object raw);

  // [raw] as submitted.
  Object? _submitted(Object raw) => raw;

  // [raw] as the value column shows it.
  String _shown(Object raw);
}

/// A line of text.
final class TextFormItem extends FormItem {
  /// A text field, holding [initialValue] at first when it is not empty.
  const TextFormItem({
    required super.name,
    required super.label,
    super.description,
    super.required,
    this.initialValue,
    this.validator,
  });

  /// The text it holds at first.
  final String? initialValue;

  /// What is wrong with the text, in words; null when nothing is.
  final String? Function(String text)? validator;

  @override
  Object? get _initial =>
      initialValue == null || initialValue!.isEmpty ? null : initialValue;

  @override
  String? _check(Object raw) => validator?.call(raw as String);

  @override
  String _shown(Object raw) => raw as String;
}

/// A number typed in: only characters a number can hold are taken, and the
/// value submitted is a [num], an [int] when [integer].
final class NumberFormItem extends FormItem {
  /// A number field, holding [initialValue] at first.
  const NumberFormItem({
    required super.name,
    required super.label,
    super.description,
    super.required,
    this.integer = false,
    this.initialValue,
    this.validator,
  });

  /// Whether only whole numbers are taken.
  final bool integer;

  /// The number it holds at first.
  final num? initialValue;

  /// What is wrong with the typed text, in words; null when nothing is. It
  /// is also asked about text that is no number, and its words, when it
  /// gives any, say so in place of `Not a number`.
  final String? Function(String text)? validator;

  static final _number = RegExp(r'^[-+]?(\d+\.?\d*|\.\d+)$');
  static final _whole = RegExp(r'^[-+]?\d+$');

  @override
  Object? get _initial => switch (initialValue) {
    // A number JSON cannot carry is left unset.
    null || num(isFinite: false) => null,
    final value when value == value.truncate() => '${value.truncate()}',
    final value => '$value',
  };

  // The typed text as the number it submits; none for text that is no
  // number, or one a Dart int or JSON cannot carry: a whole number past
  // 64 bits, or a number too large to be finite.
  num? _parsed(String text) {
    if (!(integer ? _whole : _number).hasMatch(text)) return null;
    var plain = text.replaceFirst('+', '');
    if (plain.endsWith('.')) plain = '${plain}0';
    if (plain.startsWith('.') || plain.startsWith('-.')) {
      plain = plain.replaceFirst('.', '0.');
    }
    final value = integer ? int.tryParse(plain) : num.tryParse(plain);
    return value == null || !value.isFinite ? null : value;
  }

  bool _takes(String text) =>
      (integer ? RegExp(r'^[\d+-]+$') : RegExp(r'^[\d.+-]+$')).hasMatch(text);

  @override
  String? _check(Object raw) {
    final text = raw as String;
    if (_parsed(text) != null) return validator?.call(text);
    return validator?.call(text) ??
        (integer ? 'Not a whole number' : 'Not a number');
  }

  @override
  Object? _submitted(Object raw) => _parsed(raw as String);

  @override
  String _shown(Object raw) => raw as String;
}

/// Yes or no, toggled.
final class BoolFormItem extends FormItem {
  /// A yes-or-no field, holding [initialValue] at first.
  const BoolFormItem({
    required super.name,
    required super.label,
    super.description,
    super.required,
    this.initialValue,
    this.validator,
  });

  /// The answer it holds at first.
  final bool? initialValue;

  /// What is wrong with the answer, in words; null when nothing is.
  final String? Function(bool value)? validator;

  @override
  Object? get _initial => initialValue;

  @override
  String? _check(Object raw) => validator?.call(raw as bool);

  @override
  String _shown(Object raw) => raw == true ? '☒ Yes' : '☐ No';
}

/// One of a list of [options], picked from a list that opens under it.
final class ChoiceFormItem<T> extends FormItem {
  /// A choice among [options], holding [initialValue] at first when it is
  /// one of them.
  const ChoiceFormItem({
    required super.name,
    required super.label,
    super.description,
    super.required,
    required this.options,
    this.initialValue,
    this.validator,
  });

  /// The choices, in the order the list shows them.
  final List<PickerItem<T>> options;

  /// The value it holds at first.
  final T? initialValue;

  /// What is wrong with the choice, in words; null when nothing is.
  final String? Function(T value)? validator;

  @override
  Object? get _initial {
    final at = options.indexWhere((o) => o.value == initialValue);
    return initialValue == null || at < 0 ? null : at;
  }

  @override
  String? _check(Object raw) => validator?.call(options[raw as int].value);

  @override
  Object? _submitted(Object raw) => options[raw as int].value as Object;

  @override
  String _shown(Object raw) => options[raw as int].label;
}

/// Any of a list of [options], ticked in a list that opens under it; the
/// values are kept in the options' order, whatever order they were ticked
/// in.
final class MultiChoiceFormItem<T> extends FormItem {
  /// A choice of any of [options], holding [initialValue] at first.
  const MultiChoiceFormItem({
    required super.name,
    required super.label,
    super.description,
    super.required,
    required this.options,
    this.initialValue,
    this.validator,
  });

  /// The choices, in the order the list shows them.
  final List<PickerItem<T>> options;

  /// The values it holds at first.
  final List<T>? initialValue;

  /// What is wrong with the values, in words; null when nothing is.
  final String? Function(List<T> value)? validator;

  @override
  Object? get _initial {
    final given = initialValue ?? const [];
    final ticked = [
      for (var i = 0; i < options.length; i++)
        if (given.contains(options[i].value)) i,
    ];
    return ticked.isEmpty ? null : ticked;
  }

  List<T> _values(Object raw) => [
    for (final i in raw as List<int>) options[i].value,
  ];

  @override
  String? _check(Object raw) => validator?.call(_values(raw));

  @override
  Object? _submitted(Object raw) => _values(raw);

  @override
  String _shown(Object raw) =>
      [for (final i in raw as List<int>) options[i].label].join(', ');
}

/// A field the app cannot ask for: drawn, never set.
final class UnsupportedFormItem extends FormItem {
  /// A field shown as one that cannot be filled in.
  const UnsupportedFormItem({
    required super.name,
    required super.label,
    super.description,
    super.required,
  });

  @override
  Object? get _initial => null;

  @override
  String? _check(Object raw) => null;

  @override
  String _shown(Object raw) => '';
}

/// Where a form's focus is: a field by its index, or one of the buttons.
final class FormFocus {
  const FormFocus._(this.index);

  /// The field at [index].
  const FormFocus.field(int index) : this._(index);

  /// The submit button.
  static const submit = FormFocus._(-1);

  /// The decline button.
  static const decline = FormFocus._(-2);

  /// The field's index; negative on a button.
  final int index;

  /// Whether the focus is on a field.
  bool get onField => index >= 0;

  @override
  bool operator ==(Object other) => other is FormFocus && other.index == index;

  @override
  int get hashCode => index.hashCode;

  @override
  String toString() => switch (index) {
    -1 => 'FormFocus.submit',
    -2 => 'FormFocus.decline',
    _ => 'FormFocus.field($index)',
  };
}

/// The mark in a field's status column.
enum FormFieldStatus {
  /// Required and unset: `*`.
  required,

  /// Set and valid: `✔`.
  valid,

  /// Its problem shows: `⚠`.
  invalid,

  /// Nothing to mark.
  none,
}

/// How a field's value reads: its words, dim for `not set`, and the cursor
/// while it is typed in.
final class FormValueView {
  /// A value of [text].
  const FormValueView(this.text, {this.dim = false, this.cursor});

  /// The words drawn.
  final String text;

  /// Drawn dim: `not set`, and what cannot be filled in.
  final bool dim;

  /// Where the cursor sits in [text], in characters, while it is typed in.
  final int? cursor;
}

/// One row of a form's field area.
sealed class FormRow {
  const FormRow();
}

/// A field's own row.
final class FormFieldRow extends FormRow {
  /// The row of [item].
  const FormFieldRow(this.item, this.focused, this.status, this.value);

  /// The field.
  final FormItem item;

  /// Whether the focus is on it.
  final bool focused;

  /// Its status mark.
  final FormFieldStatus status;

  /// Its value.
  final FormValueView value;
}

/// The focused field's description, or any field's problem, under it.
final class FormNoteRow extends FormRow {
  /// A note of [text], a problem when [error].
  const FormNoteRow(this.text, {required this.error});

  /// The words.
  final String text;

  /// Whether it is a problem, drawn in the error colour.
  final bool error;
}

/// One option of an open list, hanging under its field's value.
final class FormOptionRow extends FormRow {
  /// An option row of [label].
  const FormOptionRow(
    this.label, {
    required this.highlighted,
    this.number,
    this.ticked,
    this.current = false,
  });

  /// The option's label.
  final String label;

  /// Whether the list's highlight is on it.
  final bool highlighted;

  /// Its number in a choice list; none in a multi-choice list.
  final int? number;

  /// Whether it is ticked, in a multi-choice list.
  final bool? ticked;

  /// Whether a choice field holds it now.
  final bool current;
}

/// Fields scrolled out of view above or below.
final class FormMoreRow extends FormRow {
  /// [count] fields out of view, above when [up].
  const FormMoreRow({required this.up, required this.count});

  /// Whether they are above.
  final bool up;

  /// How many fields.
  final int count;
}

/// Options of the open list scrolled out of view above or below.
final class FormMoreOptionsRow extends FormRow {
  /// [count] options out of view, above when [up].
  const FormMoreOptionsRow({required this.up, required this.count});

  /// Whether they are above.
  final bool up;

  /// How many options.
  final int count;
}

/// A form's state as plain data: its fields, their values, the focus and
/// the cursor, the open list's highlight, the fields whose problems show,
/// and whether a submit was refused. Each key's action is a method that
/// gives the next state; nothing here draws.
final class FormData {
  const FormData._({
    required this.fields,
    required Map<String, Object> raw,
    required this.focus,
    required this.cursor,
    required this.highlighted,
    required this.shown,
    required this.refused,
  }) : _raw = raw;

  /// The form as it opens: the fields' initial values, the focus on the
  /// first field, or on submit when there is none.
  factory FormData.initial(List<FormItem> fields) {
    final raw = <String, Object>{
      for (final field in fields) field.name: ?field._initial,
    };
    final focus = fields.isEmpty ? FormFocus.submit : const FormFocus.field(0);
    return FormData._(
      fields: List.unmodifiable(fields),
      raw: raw,
      focus: focus,
      cursor: _endOf(fields, raw, focus),
      highlighted: null,
      shown: const {},
      refused: false,
    );
  }

  /// The fields, in the order they are drawn.
  final List<FormItem> fields;

  // Text and number fields hold what is typed, a choice its option's index,
  // a multi-choice the ticked indices in order; unset fields are absent.
  final Map<String, Object> _raw;

  /// Where the focus is.
  final FormFocus focus;

  /// The cursor in the focused text or number field, in characters.
  final int cursor;

  /// The open list's highlighted option; null while no list is open.
  final int? highlighted;

  /// The fields whose problems show, by name. A field joins when the focus
  /// leaves it with a problem other than being required and empty, or when
  /// a submit is refused.
  final Set<String> shown;

  /// Whether a submit was refused; the buttons count the problems since.
  final bool refused;

  /// The focused field, if the focus is on one.
  FormItem? get focused => focus.onField ? fields[focus.index] : null;

  /// Whether the focused field's list is open.
  bool get listOpen => highlighted != null;

  /// What a submit sends: every set field by name, in its type; a number
  /// field whose text is no number it can send is left out.
  Map<String, Object> get values => {
    for (final field in fields)
      if (_raw[field.name] case final raw?) field.name: ?field._submitted(raw),
  };

  /// Every field's problem by name: `Required` for a required field left
  /// unset, and the field's own words for the rest.
  Map<String, String> get problems => {
    for (final field in fields) field.name: ?_problemOf(field),
  };

  /// How many problems the buttons count, once a submit was refused.
  int get toFix => refused ? problems.length : 0;

  String? _problemOf(FormItem field) {
    final raw = _raw[field.name];
    if (raw == null) return field.required ? 'Required' : null;
    return field._check(raw);
  }

  FormData _with({
    Map<String, Object>? raw,
    FormFocus? focus,
    int? cursor,
    Object? highlighted = _same,
    Set<String>? shown,
    bool? refused,
  }) => FormData._(
    fields: fields,
    raw: raw ?? _raw,
    focus: focus ?? this.focus,
    cursor: cursor ?? this.cursor,
    highlighted: identical(highlighted, _same)
        ? this.highlighted
        : highlighted as int?,
    shown: shown ?? this.shown,
    refused: refused ?? this.refused,
  );

  static const _same = Object();

  static int _endOf(
    List<FormItem> fields,
    Map<String, Object> raw,
    FormFocus focus,
  ) => switch (focus.onField ? raw[fields[focus.index].name] : null) {
    final String text => TextEditingController(text: text).length,
    _ => 0,
  };

  // Moving through the form never turns an empty required field red; a
  // field the focus leaves with any other problem shows it from then on.
  FormData _moveTo(FormFocus to) {
    var shown = this.shown;
    final left = focused;
    if (left != null && !shown.contains(left.name)) {
      final problem = _problemOf(left);
      if (problem != null && _raw[left.name] != null) {
        shown = {...shown, left.name};
      }
    }
    return _with(
      focus: to,
      shown: shown,
      cursor: _endOf(fields, _raw, to),
      highlighted: null,
    );
  }

  FormData _step(int by) {
    final count = fields.length;
    final at = focus.onField ? focus.index : count;
    final next = math.min(math.max(at + by, 0), count);
    if (next == at) return this;
    return _moveTo(next < count ? FormFocus.field(next) : FormFocus.submit);
  }

  /// The focus on the field before, from the buttons on the last field.
  FormData previous() => _step(-1);

  /// The focus on the next field, from the last field on the buttons.
  FormData next() => _step(1);

  /// The focus on the submit button, from the decline button.
  FormData toSubmit() => focus.onField ? this : _with(focus: FormFocus.submit);

  /// The focus on the decline button, from the submit button.
  FormData toDecline() =>
      focus.onField ? this : _with(focus: FormFocus.decline);

  FormData _set(FormItem field, Object? raw, [int? cursor]) {
    final values = {..._raw}..remove(field.name);
    if (raw != null) values[field.name] = raw;
    return _with(raw: values, cursor: cursor);
  }

  bool get _typing =>
      !listOpen && (focused is TextFormItem || focused is NumberFormItem);

  // An edit of the focused text field through the editing controller.
  FormData _edit(void Function(TextEditingController text) edit) {
    final field = focused;
    if (!_typing || field == null) return this;
    final text = TextEditingController(
      text: (_raw[field.name] as String?) ?? '',
    )..cursor = cursor;
    edit(text);
    // Typed a piece at a time, a grapheme the pieces join into is one: the
    // cursor counts the text's own graphemes before it.
    final value = text.text;
    final at = math.min(
      text.beforeCursor.characters.length,
      value.characters.length,
    );
    return _set(field, value.isEmpty ? null : value, at);
  }

  /// [text] typed at the cursor of the focused text or number field; a line
  /// break in it is a space, and a number field takes only what a number
  /// can hold.
  FormData type(String text) {
    final field = focused;
    final typed = text.replaceAll(RegExp(r'\r\n|\r|\n'), ' ');
    if (typed.isEmpty) return this;
    if (field is NumberFormItem && !field._takes(typed)) return this;
    return _edit((c) => c.insert(typed));
  }

  /// The cursor a character to the left.
  FormData cursorLeft() => _edit((c) => c.cursor--);

  /// The cursor a character to the right.
  FormData cursorRight() => _edit((c) => c.cursor++);

  /// The cursor at the start.
  FormData cursorHome() => _edit((c) => c.cursor = 0);

  /// The cursor at the end.
  FormData cursorEnd() => _edit((c) => c.cursor = c.length);

  /// The character before the cursor deleted; a yes-or-no or choice field
  /// cleared.
  FormData backspace() => _typing ? _edit((c) => c.backspace()) : clear();

  /// The character at the cursor deleted; a yes-or-no or choice field
  /// cleared.
  FormData delete() => _typing ? _edit((c) => c.delete()) : clear();

  /// The text before the cursor deleted.
  FormData deleteToStart() => _edit((c) => c.deleteToStart());

  /// The text from the cursor deleted.
  FormData deleteToEnd() => _edit((c) => c.deleteToEnd());

  /// The word before the cursor deleted.
  FormData deleteWordBefore() => _edit((c) => c.deleteWordBefore());

  /// The focused yes-or-no, choice or multi-choice field unset.
  FormData clear() {
    final field = focused;
    if (listOpen ||
        !(field is BoolFormItem ||
            field is ChoiceFormItem ||
            field is MultiChoiceFormItem)) {
      return this;
    }
    return _set(field!, null);
  }

  /// The focused yes-or-no field turned over.
  FormData toggle() {
    final field = focused;
    if (field is! BoolFormItem) return this;
    return _set(field, _raw[field.name] != true);
  }

  int _optionCount(FormItem? field) => switch (field) {
    ChoiceFormItem(:final options) => options.length,
    MultiChoiceFormItem(:final options) => options.length,
    _ => 0,
  };

  /// The focused choice or multi-choice field's list opened, highlighting
  /// what it holds, or the first option.
  FormData openList() {
    final field = focused;
    if (listOpen || _optionCount(field) == 0) return this;
    final at = switch (_raw[field!.name]) {
      final int index => index,
      final List<int> ticked => ticked.first,
      _ => 0,
    };
    return _with(highlighted: at);
  }

  /// The open list closed.
  FormData closeList() => listOpen ? _with(highlighted: null) : this;

  /// The open list's highlight on the option above.
  FormData previousOption() =>
      listOpen ? _with(highlighted: math.max(highlighted! - 1, 0)) : this;

  /// The open list's highlight on the option below.
  FormData nextOption() => listOpen
      ? _with(
          highlighted: math.min(highlighted! + 1, _optionCount(focused) - 1),
        )
      : this;

  /// The choice list's option numbered [number], from 1, or the highlighted
  /// one, picked, and the list closed.
  FormData pick([int? number]) {
    final field = focused;
    if (!listOpen || field is! ChoiceFormItem) return this;
    final at = number == null ? highlighted! : number - 1;
    if (at < 0 || at >= field.options.length) return this;
    return _set(field, at)._with(highlighted: null);
  }

  /// The multi-choice list's highlighted option ticked, or unticked.
  FormData tick() {
    final field = focused;
    if (!listOpen || field is! MultiChoiceFormItem) return this;
    final ticked = {...?(_raw[field.name] as List<int>?)};
    if (!ticked.remove(highlighted!)) ticked.add(highlighted!);
    final ordered = ticked.toList()..sort();
    return _set(
      field,
      ordered.isEmpty ? null : List<int>.unmodifiable(ordered),
    );
  }

  /// A submit: the values when nothing is wrong; otherwise null, every
  /// problem shown and the focus on the first field with one.
  ({FormData form, Map<String, Object>? values}) submit() {
    final problems = this.problems;
    if (problems.isEmpty) return (form: this, values: values);
    final first = fields.indexWhere((f) => problems.containsKey(f.name));
    final to = FormFocus.field(first);
    return (
      form: _with(
        focus: to,
        cursor: _endOf(fields, _raw, to),
        highlighted: null,
        shown: {...shown, ...problems.keys},
        refused: true,
      ),
      values: null,
    );
  }

  FormValueView _valueOf(FormItem field, bool isFocused) {
    final raw = _raw[field.name];
    if (isFocused && listOpen) return const FormValueView('▾');
    if (isFocused && (field is TextFormItem || field is NumberFormItem)) {
      return FormValueView((raw as String?) ?? '', cursor: cursor);
    }
    if (field is UnsupportedFormItem) {
      return const FormValueView("can't be filled in here", dim: true);
    }
    if (raw == null) return const FormValueView('not set', dim: true);
    return FormValueView(field._shown(raw));
  }

  FormFieldStatus _statusOf(FormItem field, String? problem) {
    if (problem != null && shown.contains(field.name)) {
      return FormFieldStatus.invalid;
    }
    if (_raw[field.name] == null) {
      return field.required ? FormFieldStatus.required : FormFieldStatus.none;
    }
    return problem == null ? FormFieldStatus.valid : FormFieldStatus.none;
  }

  List<List<FormRow>> _blocks() {
    final problems = this.problems;
    return [
      for (final (index, field) in fields.indexed)
        _block(field, index == focus.index, problems[field.name]),
    ];
  }

  List<FormRow> _block(FormItem field, bool isFocused, String? problem) {
    final rows = <FormRow>[
      FormFieldRow(
        field,
        isFocused,
        _statusOf(field, problem),
        _valueOf(field, isFocused),
      ),
    ];
    if (isFocused && listOpen) {
      final raw = _raw[field.name];
      switch (field) {
        case ChoiceFormItem(:final options):
          for (final (i, option) in options.indexed) {
            rows.add(
              FormOptionRow(
                option.label,
                highlighted: i == highlighted,
                number: i + 1,
                current: raw == i,
              ),
            );
          }
        case MultiChoiceFormItem(:final options):
          for (final (i, option) in options.indexed) {
            rows.add(
              FormOptionRow(
                option.label,
                highlighted: i == highlighted,
                ticked: raw is List<int> && raw.contains(i),
              ),
            );
          }
        default:
      }
    }
    if (problem != null && shown.contains(field.name)) {
      rows.add(FormNoteRow(problem, error: true));
    } else if (isFocused && field.description != null) {
      rows.add(FormNoteRow(field.description!, error: false));
    }
    return rows;
  }

  /// The field area's rows, never more than [limit] of them, none at 0.
  /// Fields that do not fit scroll by whole fields, from the first view
  /// from the top that holds the focused field's block whole, its open list
  /// and note with it (the first field's with the focus on a button), a row
  /// above or below counting the fields out of view. A block taller than
  /// that is drawn alone and cut, its field row and highlighted option kept
  /// (docs/design/CTUI-70.md).
  List<FormRow> rows([int? limit]) {
    final blocks = _blocks();
    final all = [for (final block in blocks) ...block];
    if (limit == null || all.length <= limit) return all;
    if (limit <= 0 || blocks.isEmpty) return const [];
    final at = focus.onField ? focus.index : 0;
    for (var top = 0; top <= at; top++) {
      final rows = <FormRow>[if (top > 0) FormMoreRow(up: true, count: top)];
      var end = top;
      while (end < blocks.length) {
        final below = end + 1 < blocks.length ? 1 : 0;
        if (rows.length + blocks[end].length + below > limit) break;
        rows.addAll(blocks[end]);
        end++;
      }
      // A view that misses the anchor is passed over, whatever stopped it.
      if (at < end) {
        if (end < blocks.length) {
          rows.add(FormMoreRow(up: false, count: blocks.length - end));
        }
        return rows;
      }
    }
    return _cut(blocks, at, limit);
  }

  /// Block [at] alone in [limit] rows, as design CTUI-70 claims them: its
  /// field row, the highlighted option, the fields above, the fields below,
  /// its note, then the largest window of options around the highlight.
  List<FormRow> _cut(List<List<FormRow>> blocks, int at, int limit) {
    final block = blocks[at];
    final options = block.whereType<FormOptionRow>().toList();
    final note = block.whereType<FormNoteRow>().firstOrNull;
    final lit = options.indexWhere((option) => option.highlighted);
    var left = limit - 1;
    bool claim(bool wanted) {
      if (!wanted || left <= 0) return false;
      left--;
      return true;
    }

    final highlight = claim(lit >= 0);
    final up = claim(at > 0);
    final down = claim(at + 1 < blocks.length);
    final noted = claim(note != null);
    // The highlight's window: the first from the top holding it, the largest
    // that fits with its count rows in what is left, the highlight's own row
    // already claimed.
    // Where not even one count row fits beside it, the highlight alone.
    var (from, to) = (lit, lit + 1);
    var counted = false;
    if (highlight) {
      final budget = left + 1;
      for (var start = 0; start <= lit; start++) {
        var rows = start > 0 ? 1 : 0;
        var end = start;
        while (end < options.length) {
          final below = end + 1 < options.length ? 1 : 0;
          if (rows + 1 + below > budget) break;
          rows++;
          end++;
        }
        if (lit < end) {
          (from, to) = (start, end);
          counted = true;
          break;
        }
      }
    }
    return [
      if (up) FormMoreRow(up: true, count: at),
      block.first,
      if (highlight) ...[
        if (counted && from > 0) FormMoreOptionsRow(up: true, count: from),
        ...options.sublist(from, to),
        if (counted && to < options.length)
          FormMoreOptionsRow(up: false, count: options.length - to),
      ],
      if (noted) note!,
      if (down) FormMoreRow(up: false, count: blocks.length - at - 1),
    ];
  }

  /// The hint line's keys for where the focus is: the long form when
  /// [width] is at least 100 and it fits, the short one otherwise.
  /// [submitLabel] and [declineLabel] name the buttons; with no
  /// [declineLabel] there is no decline button.
  String hint(
    int width, {
    String submitLabel = 'Submit',
    String? declineLabel = 'Decline',
  }) {
    String pick(String long, [String? short]) =>
        width >= 100 && long.length <= width ? long : (short ?? long);
    final field = focused;
    if (field == null) {
      final on = focus == FormFocus.decline && declineLabel != null
          ? declineLabel
          : submitLabel;
      return declineLabel == null
          ? 'Enter to ${on.toLowerCase()} · Esc to cancel'
          : '←→ to switch · Enter to ${on.toLowerCase()} · Esc to cancel';
    }
    if (listOpen) {
      if (field is MultiChoiceFormItem) {
        return pick(
          '↑↓ to move · Space to tick · Enter or ← to close the list · Esc to cancel',
          '↑↓ · Space to tick · Enter or ← to close · Esc to cancel',
        );
      }
      final digits = '1–${math.min(_optionCount(field), 9)}';
      return pick(
        '↑↓ to move · $digits or Enter to pick · ← to close the list · Esc to cancel',
        '↑↓ · $digits or Enter to pick · ← to close · Esc to cancel',
      );
    }
    return switch (field) {
      BoolFormItem() => 'Space to toggle · ↑↓ to move · Esc to cancel',
      ChoiceFormItem() || MultiChoiceFormItem() =>
        '→ or Space to choose · ↑↓ to move · Esc to cancel',
      UnsupportedFormItem() => '↑↓ to move · Esc to cancel',
      TextFormItem() || NumberFormItem() => pick(
        'Type to fill in · ↑↓ to move · Enter for the next · Esc to cancel',
        'Type to fill in · ↑↓ to move · Esc to cancel',
      ),
    };
  }
}

/// A form's state, held by the app so a form left and come back to keeps
/// its values, focus and cursor.
class FormController extends ValueNotifier<FormData> {
  /// A form of [fields], as it opens.
  FormController({required List<FormItem> fields})
    : super(FormData.initial(fields));
}
