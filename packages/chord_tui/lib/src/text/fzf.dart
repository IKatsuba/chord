// A port of fzf-for-js 0.5.2's fuzzy matcher (FuzzyMatchV2, with V1 for
// long inputs), its basic match, its stable score sort, byLengthAsc and its
// limit: https://github.com/ajitid/fzf-for-js
//
// Copyright (c) 2021 Ajit
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. Neither the name of the copyright holder nor the names of its
//    contributors may be used to endorse or promote products derived from
//    this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

import 'dart:typed_data';
import 'dart:collection';

import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// How letter case counts in a [Fzf] query, as fzf's `casing` option.
enum FzfCasing {
  /// Case-sensitive when the query has an upper-case letter.
  smartCase,

  /// Case always counts.
  caseSensitive,

  /// Case never counts.
  caseInsensitive,
}

/// An item a [Fzf] query matched.
class FzfResult<T> {
  /// A match of [item], at [index] in the finder's list.
  const FzfResult({
    required this.item,
    required this.index,
    required this.start,
    required this.end,
    required this.score,
    required this.positions,
  });

  /// The item.
  final T item;

  /// Where the item is in the list the finder was made with.
  final int index;

  /// The first matched UTF-16 code unit of the item's NFC text, or -1 for
  /// an empty query.
  final int start;

  /// One past the last matched code unit, or -1 for an empty query.
  final int end;

  /// fzf's score: higher is better.
  final int score;

  /// The matched code units of the item's NFC text, ascending.
  final List<int> positions;
}

/// Orders two results of one score; negative puts [a] first.
typedef FzfTiebreaker<T> =
    int Function(FzfResult<T> a, FzfResult<T> b, String Function(T) selector);

/// fzf's `byLengthAsc`: the shorter text first.
int byLengthAsc<T>(
  FzfResult<T> a,
  FzfResult<T> b,
  String Function(T) selector,
) => selector(a.item).length - selector(b.item).length;

/// Finds the items a query matches, best first, as fzf-for-js's `Fzf` does
/// with its default fuzzy algorithm and basic (not extended) matching: the
/// query's letters in order anywhere in the text, scored by word
/// boundaries, camel case and gaps.
class Fzf<T> {
  /// A finder over [items], matched by [selector]'s text (the item itself
  /// for strings).
  Fzf(
    this.items, {
    String Function(T item)? selector,
    this.casing = FzfCasing.smartCase,
    this.normalize = true,
    this.limit,
    this.tiebreakers = const [],
  }) : selector = selector ?? ((item) => item as String),
       _runes = [] {
    for (final item in items) {
      _runes.add(Uint16List.fromList(unorm.nfc(this.selector(item)).codeUnits));
    }
  }

  /// What is searched.
  final List<T> items;

  /// The text of an item.
  final String Function(T item) selector;

  /// How case counts.
  final FzfCasing casing;

  /// Whether accented Latin letters match their plain letters.
  final bool normalize;

  /// The most results returned; all when null.
  final int? limit;

  /// Orders results of equal score; equal ones keep the list's order.
  final List<FzfTiebreaker<T>> tiebreakers;

  final List<Uint16List> _runes;

  /// The items [query] matches, best first; the first [limit] items, in
  /// order and without positions, for an empty query.
  List<FzfResult<T>> find(String query) {
    final max = limit ?? items.length;
    if (query.isEmpty || items.isEmpty) {
      return [
        for (var i = 0; i < items.length && i < max; i++)
          FzfResult(
            item: items[i],
            index: i,
            start: -1,
            end: -1,
            score: 0,
            positions: const [],
          ),
      ];
    }
    query = unorm.nfc(query);
    var caseSensitive = false;
    switch (casing) {
      case FzfCasing.smartCase:
        caseSensitive = _jsLowerCase(query) != query;
      case FzfCasing.caseSensitive:
        caseSensitive = true;
      case FzfCasing.caseInsensitive:
        query = _jsLowerCase(query);
    }
    final pattern = [
      for (final r in query.codeUnits) normalize ? _normalizeRune(r) : r,
    ];
    final byScore = <int, List<FzfResult<T>>>{};
    for (var i = 0; i < items.length; i++) {
      final input = _runes[i];
      if (pattern.length > input.length) continue;
      final m = _fuzzyMatchV2(caseSensitive, normalize, input, pattern);
      if (m == null) continue;
      (byScore[m.score] ??= []).add(
        FzfResult(
          item: items[i],
          index: i,
          start: m.start,
          end: m.end,
          score: m.score,
          positions: m.positions,
        ),
      );
    }
    // As upstream: whole score groups, best first, until the limit is
    // reached; then ties are broken inside each group, stably.
    final scores = byScore.keys.toList()..sort((a, b) => b - a);
    final out = <FzfResult<T>>[];
    for (final s in scores) {
      final group = byScore[s]!;
      if (tiebreakers.isNotEmpty) _stableSort(group);
      out.addAll(group);
      if (out.length >= max) break;
    }
    return out.length > max ? out.sublist(0, max) : out;
  }

  void _stableSort(List<FzfResult<T>> group) {
    final order = [for (var i = 0; i < group.length; i++) i];
    order.sort((x, y) {
      for (final t in tiebreakers) {
        final d = t(group[x], group[y], selector);
        if (d != 0) return d;
      }
      return x - y;
    });
    final sorted = [for (final i in order) group[i]];
    group.setAll(0, sorted);
  }
}

/// Cooperative searches with the same scorer and ordering as [Fzf].
///
/// Candidates and tie breakers are shallow immutable snapshots. Keep item
/// values and callbacks stable; replace and dispose the finder to change them.
class AsyncFzf<T> {
  /// Captures [items] and the ordinary [Fzf] options without blocking on scoring.
  AsyncFzf(
    List<T> items, {
    String Function(T item)? selector,
    this.casing = FzfCasing.smartCase,
    this.normalize = true,
    this.limit,
    List<FzfTiebreaker<T>> tiebreakers = const [],
  }) : items = List.unmodifiable(items),
       selector = selector ?? ((item) => item as String),
       tiebreakers = List.unmodifiable(tiebreakers),
       _runes = List.filled(items.length, null);

  /// The captured candidate order; generic values themselves are not cloned.
  final List<T> items;

  /// The stable, pure text selector used by the scorer and tie breakers.
  final String Function(T item) selector;

  /// How case counts, with the same default as [Fzf].
  final FzfCasing casing;

  /// Whether accented Latin letters match their plain letters.
  final bool normalize;

  /// Maximum results, or all results when null.
  final int? limit;

  /// Captured tie breakers; equal results retain their original item order.
  final List<FzfTiebreaker<T>> tiebreakers;

  final List<Uint16List?> _runes;
  var _generation = 0;
  var _disposed = false;
  bool _owns(int generation) => !_disposed && generation == _generation;
  Future<bool> _yield(int generation) async {
    await Future<void>.delayed(Duration.zero);
    return _owns(generation);
  }

  /// Completes with immutable results, or null when superseded or disposed.
  ///
  /// Every call supersedes pending work, including an equal query. Scanning,
  /// preprocessing and stable ordering yield to the event queue in chunks.
  Future<List<FzfResult<T>>?> find(String query) async {
    final generation = ++_generation;
    if (_disposed || !await _yield(generation)) return null;
    final max = limit ?? items.length;
    final matches = <FzfResult<T>?>[];
    if (query.isEmpty || items.isEmpty) {
      for (var i = 0; i < items.length && i < max; i++) {
        matches.add(
          FzfResult(
            item: items[i],
            index: i,
            start: -1,
            end: -1,
            score: 0,
            positions: const [],
          ),
        );
        if ((i + 1) % 256 == 0 && !await _yield(generation)) return null;
      }
    } else {
      query = unorm.nfc(query);
      var caseSensitive = false;
      switch (casing) {
        case FzfCasing.smartCase:
          caseSensitive = _jsLowerCase(query) != query;
        case FzfCasing.caseSensitive:
          caseSensitive = true;
        case FzfCasing.caseInsensitive:
          query = _jsLowerCase(query);
      }
      final pattern = [
        for (final r in query.codeUnits) normalize ? _normalizeRune(r) : r,
      ];
      for (var i = 0; i < items.length; i++) {
        final input = _runes[i] ??= Uint16List.fromList(
          unorm.nfc(selector(items[i])).codeUnits,
        );
        if (pattern.length <= input.length) {
          final match = _fuzzyMatchV2(caseSensitive, normalize, input, pattern);
          if (match != null) {
            matches.add(
              FzfResult(
                item: items[i],
                index: i,
                start: match.start,
                end: match.end,
                score: match.score,
                positions: List.unmodifiable(match.positions),
              ),
            );
          }
        }
        if ((i + 1) % 256 == 0 && !await _yield(generation)) return null;
      }
      // Bottom-up merge ordering avoids one uninterruptible native tie sort.
      var source = matches;
      var target = List<FzfResult<T>?>.filled(matches.length, null);
      var operations = 0;
      for (var width = 1; width < source.length; width *= 2) {
        for (var left = 0; left < source.length; left += 2 * width) {
          final middle = (left + width).clamp(0, source.length);
          final right = (left + 2 * width).clamp(0, source.length);
          var a = left, b = middle;
          for (var at = left; at < right; at++) {
            target[at] =
                a < middle &&
                    (b >= right || _compare(source[a]!, source[b]!) <= 0)
                ? source[a++]
                : source[b++];
            if (++operations % 256 == 0 && !await _yield(generation)) {
              return null;
            }
          }
        }
        final old = source;
        source = target;
        target = old;
      }
      final result = <FzfResult<T>>[];
      // Match the synchronous limit behavior, including invalid negative limits.
      if (max < 0) {
        throw RangeError.range(max, 0, source.length);
      }
      for (var i = 0; i < source.length && i < max; i++) {
        result.add(source[i]!);
        if ((i + 1) % 256 == 0 && !await _yield(generation)) return null;
      }
      return _owns(generation) ? UnmodifiableListView(result) : null;
    }
    final result = <FzfResult<T>>[];
    for (var i = 0; i < matches.length; i++) {
      result.add(matches[i]!);
      if ((i + 1) % 256 == 0 && !await _yield(generation)) return null;
    }
    return _owns(generation) ? UnmodifiableListView(result) : null;
  }

  int _compare(FzfResult<T> a, FzfResult<T> b) {
    final score = b.score.compareTo(a.score);
    if (score != 0) return score;
    for (final tiebreaker in tiebreakers) {
      final difference = tiebreaker(a, b, selector);
      if (difference != 0) return difference;
    }
    return a.index.compareTo(b.index);
  }

  /// Invalidates pending work; subsequent finds also return null.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
  }
}

class _Match {
  const _Match(this.start, this.end, this.score, this.positions);

  final int start;
  final int end;
  final int score;
  final List<int> positions;
}

const _scoreMatch = 16;
const _scoreGapStart = -3;
const _scoreGapExtension = -1;
const _bonusBoundary = _scoreMatch ~/ 2;
const _bonusNonWord = _scoreMatch ~/ 2;
const _bonusCamel123 = _bonusBoundary + _scoreGapExtension;
const _bonusConsecutive = -(_scoreGapStart + _scoreGapExtension);
const _bonusFirstCharMultiplier = 2;

// Upstream's shared scratch buffer: inputs whose size times the pattern's
// is larger go to V1.
const _slab16Size = 100 * 1024;

const _maxAscii = 0x7f;
const _capitalA = 0x41, _capitalZ = 0x5a, _smallA = 0x61, _smallZ = 0x7a;
const _zero = 0x30, _nine = 0x39;

int _classOfAscii(int r) {
  if (r >= _smallA && r <= _smallZ) return 1;
  if (r >= _capitalA && r <= _capitalZ) return 2;
  if (r >= _zero && r <= _nine) return 4;
  return 0;
}

final _number = RegExp(r'\p{N}', unicode: true);
final _letter = RegExp(r'\p{L}', unicode: true);
final _nonAsciiClasses = <int, int>{};

int _classOfNonAscii(int r) => _nonAsciiClasses.putIfAbsent(r, () {
  final c = String.fromCharCode(r);
  if (c != c.toUpperCase()) return 1;
  if (c != c.toLowerCase()) return 2;
  if (_number.hasMatch(c)) return 4;
  if (_letter.hasMatch(c)) return 3;
  return 0;
});

int _classOf(int r) => r <= _maxAscii ? _classOfAscii(r) : _classOfNonAscii(r);

int _lower(int r) => String.fromCharCode(r).toLowerCase().runes.first;

final _cased = RegExp(r'\p{Cased}', unicode: true);
final _caseIgnorable = RegExp(r'\p{Case_Ignorable}', unicode: true);

bool _is(RegExp property, int rune) =>
    property.hasMatch(String.fromCharCode(rune));

/// [s] lower-cased as JavaScript's String.toLowerCase does: Dart's, plus
/// the two SpecialCasing rules Dart leaves out, which upstream's query
/// lower-casing goes through: İ becomes i and a combining dot above, and a
/// Σ that ends a word (Final_Sigma) becomes ς.
String _jsLowerCase(String s) {
  if (!s.contains('\u0130') && !s.contains('\u03a3')) return s.toLowerCase();
  final runes = s.runes.toList();
  final out = StringBuffer();
  for (var i = 0; i < runes.length; i++) {
    final r = runes[i];
    if (r == 0x130) {
      out.write('i\u0307');
    } else if (r == 0x3a3) {
      out.write(_finalSigma(runes, i) ? 'ς' : 'σ');
    } else {
      out.write(String.fromCharCode(r).toLowerCase());
    }
  }
  return out.toString();
}

// Unicode's Final_Sigma: a cased letter before, skipping case-ignorable
// ones, and none after.
bool _finalSigma(List<int> runes, int at) {
  var j = at - 1;
  while (j >= 0 && _is(_caseIgnorable, runes[j])) {
    j--;
  }
  if (j < 0 || !_is(_cased, runes[j])) return false;
  var k = at + 1;
  while (k < runes.length && _is(_caseIgnorable, runes[k])) {
    k++;
  }
  return k >= runes.length || !_is(_cased, runes[k]);
}

int _bonusFor(int prev, int curr) {
  if (prev == 0 && curr != 0) return _bonusBoundary;
  if (prev == 1 && curr == 2 || prev != 4 && curr == 4) return _bonusCamel123;
  if (curr == 0) return _bonusNonWord;
  return 0;
}

int _max(int a, int b) => a > b ? a : b;

int _trySkip(List<int> input, bool caseSensitive, int char, int from) {
  var idx = input.indexOf(char, from);
  if (idx == from) return from;
  var end = input.length;
  if (!caseSensitive && char >= _smallA && char <= _smallZ) {
    if (idx > from) end = idx;
    final upper = input.sublist(from, end).indexOf(char - 32);
    if (upper >= 0) idx = from + upper;
  }
  return idx < 0 ? -1 : idx;
}

bool _isAscii(List<int> runes) => runes.every((r) => r < 128);

int _asciiFuzzyIndex(List<int> input, List<int> pattern, bool caseSensitive) {
  if (!_isAscii(input)) return 0;
  if (!_isAscii(pattern)) return -1;
  var firstIdx = 0, idx = 0;
  for (var pidx = 0; pidx < pattern.length; pidx++) {
    idx = _trySkip(input, caseSensitive, pattern[pidx], idx);
    if (idx < 0) return -1;
    if (pidx == 0 && idx > 0) firstIdx = idx - 1;
    idx++;
  }
  return firstIdx;
}

_Match? _fuzzyMatchV2(
  bool caseSensitive,
  bool normalize,
  List<int> input,
  List<int> pattern,
) {
  final m = pattern.length;
  if (m == 0) return const _Match(0, 0, 0, []);
  final n = input.length;
  if (n * m > _slab16Size) {
    return _fuzzyMatchV1(caseSensitive, normalize, input, pattern);
  }
  final idx = _asciiFuzzyIndex(input, pattern, caseSensitive);
  if (idx < 0) return null;
  // Upstream reuses a scratch slab without clearing it; fresh zeroed arrays
  // give the same scores, and positions as on a fresh slab.
  final h0 = Int16List(n), c0 = Int16List(n), b = Int16List(n);
  final f = Int32List(m);
  final t = Int32List.fromList(input);
  var maxScore = 0, maxScorePos = 0;
  var pidx = 0, lastIdx = 0;
  final pchar0 = pattern[0];
  var pchar = pattern[0], prevH0 = 0, prevClass = 0, inGap = false;
  for (var col = idx; col < n; col++) {
    var char = t[col];
    int cls;
    if (char <= _maxAscii) {
      cls = _classOfAscii(char);
      if (!caseSensitive && cls == 2) char += 32;
    } else {
      cls = _classOfNonAscii(char);
      if (!caseSensitive && cls == 2) char = _lower(char);
      if (normalize) char = _normalizeRune(char);
    }
    t[col] = char;
    final bonus = _bonusFor(prevClass, cls);
    b[col] = bonus;
    prevClass = cls;
    if (char == pchar) {
      if (pidx < m) {
        f[pidx] = col;
        pidx++;
        pchar = pattern[pidx < m - 1 ? pidx : m - 1];
      }
      lastIdx = col;
    }
    if (char == pchar0) {
      final score = _scoreMatch + bonus * _bonusFirstCharMultiplier;
      h0[col] = score;
      c0[col] = 1;
      if (m == 1 && score > maxScore) {
        maxScore = score;
        maxScorePos = col;
        if (bonus == _bonusBoundary) break;
      }
      inGap = false;
    } else {
      h0[col] = _max(prevH0 + (inGap ? _scoreGapExtension : _scoreGapStart), 0);
      c0[col] = 0;
      inGap = true;
    }
    prevH0 = h0[col];
  }
  if (pidx != m) return null;
  if (m == 1) {
    return _Match(maxScorePos, maxScorePos + 1, maxScore, [maxScorePos]);
  }

  final f0 = f[0];
  final width = lastIdx - f0 + 1;
  final h = Int16List(width * m), c = Int16List(width * m);
  for (var i = 0; i < width; i++) {
    h[i] = h0[f0 + i];
    c[i] = c0[f0 + i];
  }
  for (var p = 1; p < m; p++) {
    var inGap2 = false;
    final pchar2 = pattern[p], start = f[p], row = p * width;
    h[row + start - f0 - 1] = 0;
    for (var col = start; col <= lastIdx; col++) {
      final at = row + col - f0;
      var s1 = 0, consecutive = 0;
      final s2 = h[at - 1] + (inGap2 ? _scoreGapExtension : _scoreGapStart);
      if (pchar2 == t[col]) {
        s1 = h[at - 1 - width] + _scoreMatch;
        var bonus = b[col];
        consecutive = c[at - 1 - width] + 1;
        if (bonus == _bonusBoundary) {
          consecutive = 1;
        } else if (consecutive > 1) {
          bonus = _max(
            bonus,
            _max(_bonusConsecutive, b[col - consecutive + 1]),
          );
        }
        if (s1 + bonus < s2) {
          s1 += b[col];
          consecutive = 0;
        } else {
          s1 += bonus;
        }
      }
      c[at] = consecutive;
      inGap2 = s1 < s2;
      final score = _max(_max(s1, s2), 0);
      if (p == m - 1 && score > maxScore) {
        maxScore = score;
        maxScorePos = col;
      }
      h[at] = score;
    }
  }
  final positions = <int>[];
  var i = m - 1, j = maxScorePos;
  var preferMatch = true;
  while (true) {
    final row = i * width, j0 = j - f0, s = h[row + j0];
    var s1 = 0, s2 = 0;
    if (i > 0 && j >= f[i]) s1 = h[row - width + j0 - 1];
    if (j > f[i]) s2 = h[row + j0 - 1];
    if (s > s1 && (s > s2 || s == s2 && preferMatch)) {
      positions.add(j);
      if (i == 0) break;
      i--;
    }
    preferMatch =
        c[row + j0] > 1 ||
        row + width + j0 + 1 < c.length && c[row + width + j0 + 1] > 0;
    j--;
  }
  return _Match(j, maxScorePos + 1, maxScore, positions.reversed.toList());
}

int _fold(int rune, bool caseSensitive, bool normalize) {
  if (!caseSensitive) {
    if (rune >= _capitalA && rune <= _capitalZ) {
      rune += 32;
    } else if (rune > _maxAscii) {
      rune = _lower(rune);
    }
  }
  return normalize ? _normalizeRune(rune) : rune;
}

(int, List<int>) _calculateScore(
  bool caseSensitive,
  bool normalize,
  List<int> text,
  List<int> pattern,
  int sidx,
  int eidx,
) {
  var pidx = 0, score = 0, consecutive = 0, firstBonus = 0;
  var inGap = false;
  final positions = <int>[];
  var prevClass = sidx > 0 ? _classOf(text[sidx - 1]) : 0;
  for (var idx = sidx; idx < eidx; idx++) {
    final rune = _fold(text[idx], caseSensitive, normalize);
    final cls = _classOf(text[idx]);
    if (rune == pattern[pidx]) {
      positions.add(idx);
      score += _scoreMatch;
      var bonus = _bonusFor(prevClass, cls);
      if (consecutive == 0) {
        firstBonus = bonus;
      } else {
        if (bonus == _bonusBoundary) firstBonus = bonus;
        bonus = _max(_max(bonus, firstBonus), _bonusConsecutive);
      }
      score += pidx == 0 ? bonus * _bonusFirstCharMultiplier : bonus;
      inGap = false;
      consecutive++;
      pidx++;
    } else {
      score += inGap ? _scoreGapExtension : _scoreGapStart;
      inGap = true;
      consecutive = 0;
      firstBonus = 0;
    }
    prevClass = cls;
  }
  return (score, positions);
}

_Match? _fuzzyMatchV1(
  bool caseSensitive,
  bool normalize,
  List<int> text,
  List<int> pattern,
) {
  if (_asciiFuzzyIndex(text, pattern, caseSensitive) < 0) return null;
  var pidx = 0, sidx = -1, eidx = -1;
  for (var index = 0; index < text.length; index++) {
    if (_fold(text[index], caseSensitive, normalize) == pattern[pidx]) {
      if (sidx < 0) sidx = index;
      pidx++;
      if (pidx == pattern.length) {
        eidx = index + 1;
        break;
      }
    }
  }
  if (sidx < 0 || eidx < 0) return null;
  pidx--;
  for (var index = eidx - 1; index >= sidx; index--) {
    // As upstream, the backward pass folds case but not accents.
    if (_fold(text[index], caseSensitive, false) == pattern[pidx]) {
      pidx--;
      if (pidx < 0) {
        sidx = index;
        break;
      }
    }
  }
  final (score, positions) = _calculateScore(
    caseSensitive,
    normalize,
    text,
    pattern,
    sidx,
    eidx,
  );
  return _Match(sidx, eidx, score, positions);
}

int _normalizeRune(int rune) {
  if (rune < 192 || rune > 8580) return rune;
  return _normalized[rune] ?? rune;
}

// Generated from upstream's table: an accented Latin letter's code unit
// to its plain letter's.
const _normalized = <int, int>{
  192: 65,
  193: 65,
  194: 65,
  195: 65,
  196: 65,
  197: 65,
  199: 67,
  200: 69,
  201: 69,
  202: 69,
  203: 69,
  204: 73,
  205: 73,
  206: 73,
  207: 73,
  209: 78,
  210: 79,
  211: 79,
  212: 79,
  213: 79,
  214: 79,
  216: 79,
  217: 85,
  218: 85,
  219: 85,
  220: 85,
  221: 89,
  223: 115,
  224: 97,
  225: 97,
  226: 97,
  227: 97,
  228: 97,
  229: 97,
  231: 99,
  232: 101,
  233: 101,
  234: 101,
  235: 101,
  236: 105,
  237: 105,
  238: 105,
  239: 105,
  241: 110,
  242: 111,
  243: 111,
  244: 111,
  245: 111,
  246: 111,
  248: 111,
  249: 117,
  250: 117,
  251: 117,
  252: 117,
  253: 121,
  255: 121,
  256: 65,
  257: 97,
  258: 65,
  259: 97,
  260: 65,
  261: 97,
  262: 67,
  263: 99,
  264: 67,
  265: 99,
  266: 67,
  267: 99,
  268: 67,
  269: 99,
  270: 68,
  271: 100,
  273: 100,
  274: 69,
  275: 101,
  276: 69,
  277: 101,
  278: 69,
  279: 101,
  280: 69,
  281: 101,
  282: 69,
  283: 101,
  284: 71,
  285: 103,
  286: 71,
  287: 103,
  288: 71,
  289: 103,
  290: 71,
  291: 103,
  292: 72,
  293: 104,
  295: 104,
  296: 73,
  297: 105,
  298: 73,
  299: 105,
  300: 73,
  301: 105,
  302: 73,
  303: 105,
  304: 73,
  305: 105,
  308: 74,
  309: 106,
  310: 75,
  311: 107,
  313: 76,
  314: 108,
  315: 76,
  316: 108,
  317: 76,
  318: 108,
  320: 108,
  322: 108,
  323: 78,
  324: 110,
  325: 78,
  326: 110,
  327: 78,
  328: 110,
  332: 79,
  333: 111,
  334: 79,
  335: 111,
  336: 79,
  337: 111,
  340: 82,
  341: 114,
  342: 82,
  343: 114,
  344: 82,
  345: 114,
  346: 83,
  347: 115,
  348: 83,
  349: 115,
  350: 83,
  351: 115,
  352: 83,
  353: 115,
  354: 84,
  355: 116,
  356: 84,
  357: 116,
  359: 116,
  360: 85,
  361: 117,
  362: 85,
  363: 117,
  364: 85,
  365: 117,
  366: 85,
  367: 117,
  368: 85,
  369: 117,
  370: 85,
  371: 117,
  372: 87,
  373: 119,
  374: 89,
  375: 121,
  376: 89,
  377: 90,
  378: 122,
  379: 90,
  380: 122,
  381: 90,
  382: 122,
  383: 115,
  384: 98,
  385: 66,
  387: 98,
  390: 79,
  392: 99,
  393: 68,
  394: 68,
  396: 100,
  398: 69,
  400: 69,
  402: 102,
  403: 71,
  407: 73,
  409: 107,
  410: 108,
  412: 77,
  413: 78,
  414: 110,
  415: 79,
  416: 79,
  417: 111,
  421: 112,
  427: 116,
  429: 116,
  430: 84,
  431: 85,
  432: 117,
  434: 86,
  436: 121,
  438: 122,
  461: 65,
  462: 97,
  463: 73,
  464: 105,
  465: 79,
  466: 111,
  467: 85,
  468: 117,
  471: 85,
  472: 117,
  477: 101,
  485: 103,
  486: 71,
  487: 103,
  488: 75,
  489: 107,
  490: 79,
  491: 111,
  496: 106,
  500: 71,
  501: 103,
  504: 78,
  505: 110,
  512: 65,
  513: 97,
  514: 65,
  515: 97,
  516: 69,
  517: 101,
  518: 69,
  519: 101,
  520: 73,
  521: 105,
  522: 73,
  523: 105,
  524: 79,
  525: 111,
  526: 79,
  527: 111,
  528: 82,
  529: 114,
  530: 82,
  531: 114,
  532: 85,
  533: 117,
  534: 85,
  535: 117,
  536: 83,
  537: 115,
  538: 84,
  539: 116,
  542: 72,
  543: 104,
  544: 78,
  545: 100,
  549: 122,
  550: 65,
  551: 97,
  552: 69,
  553: 101,
  558: 79,
  559: 111,
  562: 89,
  563: 121,
  564: 108,
  565: 110,
  566: 116,
  567: 106,
  570: 65,
  571: 67,
  572: 99,
  573: 76,
  574: 84,
  575: 115,
  576: 122,
  579: 66,
  580: 85,
  581: 86,
  582: 69,
  583: 101,
  584: 74,
  585: 106,
  586: 81,
  587: 113,
  588: 82,
  589: 114,
  590: 89,
  591: 121,
  592: 97,
  593: 97,
  595: 98,
  596: 111,
  597: 99,
  598: 100,
  599: 100,
  600: 101,
  603: 101,
  604: 101,
  605: 101,
  606: 101,
  607: 106,
  608: 103,
  609: 103,
  610: 71,
  613: 104,
  614: 104,
  616: 105,
  618: 73,
  619: 108,
  620: 108,
  621: 108,
  623: 109,
  624: 109,
  625: 109,
  626: 110,
  627: 110,
  628: 78,
  629: 111,
  633: 114,
  634: 114,
  635: 114,
  636: 114,
  637: 114,
  638: 114,
  639: 114,
  640: 82,
  641: 82,
  642: 115,
  647: 116,
  648: 116,
  649: 117,
  651: 118,
  652: 118,
  653: 119,
  654: 121,
  655: 89,
  656: 122,
  657: 122,
  663: 99,
  665: 66,
  666: 101,
  667: 71,
  668: 72,
  669: 106,
  670: 107,
  671: 76,
  672: 113,
  686: 104,
  867: 97,
  868: 101,
  869: 105,
  870: 111,
  871: 117,
  872: 99,
  873: 100,
  874: 104,
  875: 109,
  876: 114,
  877: 116,
  878: 118,
  879: 120,
  7424: 65,
  7427: 66,
  7428: 67,
  7429: 68,
  7431: 69,
  7432: 101,
  7433: 105,
  7434: 74,
  7435: 75,
  7436: 76,
  7437: 77,
  7438: 78,
  7439: 79,
  7440: 79,
  7441: 111,
  7442: 111,
  7443: 111,
  7446: 111,
  7447: 111,
  7448: 80,
  7449: 82,
  7450: 82,
  7451: 84,
  7452: 85,
  7453: 117,
  7454: 117,
  7455: 109,
  7456: 86,
  7457: 87,
  7458: 90,
  7522: 105,
  7523: 114,
  7524: 117,
  7525: 118,
  7680: 65,
  7681: 97,
  7682: 66,
  7683: 98,
  7684: 66,
  7685: 98,
  7686: 66,
  7687: 98,
  7690: 68,
  7691: 100,
  7692: 68,
  7693: 100,
  7694: 68,
  7695: 100,
  7696: 68,
  7697: 100,
  7698: 68,
  7699: 100,
  7704: 69,
  7705: 101,
  7706: 69,
  7707: 101,
  7710: 70,
  7711: 102,
  7712: 71,
  7713: 103,
  7714: 72,
  7715: 104,
  7716: 72,
  7717: 104,
  7718: 72,
  7719: 104,
  7720: 72,
  7721: 104,
  7722: 72,
  7723: 104,
  7724: 73,
  7725: 105,
  7726: 73,
  7727: 105,
  7728: 75,
  7729: 107,
  7730: 75,
  7731: 107,
  7732: 75,
  7733: 107,
  7734: 76,
  7735: 108,
  7738: 76,
  7739: 108,
  7740: 76,
  7741: 108,
  7742: 77,
  7743: 109,
  7744: 77,
  7745: 109,
  7746: 77,
  7747: 109,
  7748: 78,
  7749: 110,
  7750: 78,
  7751: 110,
  7752: 78,
  7753: 110,
  7754: 78,
  7755: 110,
  7764: 80,
  7765: 112,
  7766: 80,
  7767: 112,
  7768: 82,
  7769: 114,
  7770: 82,
  7771: 114,
  7774: 82,
  7775: 114,
  7776: 83,
  7777: 115,
  7778: 83,
  7779: 115,
  7786: 84,
  7787: 116,
  7788: 84,
  7789: 116,
  7790: 84,
  7791: 116,
  7792: 84,
  7793: 116,
  7794: 85,
  7795: 117,
  7796: 85,
  7797: 117,
  7798: 85,
  7799: 117,
  7804: 86,
  7805: 118,
  7806: 86,
  7807: 118,
  7808: 87,
  7809: 119,
  7810: 87,
  7811: 119,
  7812: 87,
  7813: 119,
  7814: 87,
  7815: 119,
  7816: 87,
  7817: 119,
  7818: 88,
  7819: 120,
  7820: 88,
  7821: 120,
  7822: 89,
  7823: 121,
  7824: 90,
  7825: 122,
  7826: 90,
  7827: 122,
  7828: 90,
  7829: 122,
  7830: 104,
  7831: 116,
  7832: 119,
  7833: 121,
  7834: 97,
  7835: 115,
  7840: 65,
  7841: 97,
  7842: 65,
  7843: 97,
  7844: 65,
  7845: 97,
  7846: 65,
  7847: 97,
  7848: 65,
  7849: 97,
  7850: 65,
  7851: 97,
  7852: 65,
  7853: 97,
  7854: 65,
  7855: 97,
  7856: 65,
  7857: 97,
  7858: 65,
  7859: 97,
  7860: 65,
  7861: 97,
  7862: 65,
  7863: 97,
  7864: 69,
  7865: 101,
  7866: 69,
  7867: 101,
  7868: 69,
  7869: 101,
  7870: 69,
  7871: 101,
  7872: 69,
  7873: 101,
  7874: 69,
  7875: 101,
  7876: 69,
  7877: 101,
  7878: 69,
  7879: 101,
  7880: 73,
  7881: 105,
  7882: 73,
  7883: 105,
  7884: 79,
  7885: 111,
  7886: 79,
  7887: 111,
  7888: 79,
  7889: 111,
  7890: 79,
  7891: 111,
  7892: 79,
  7893: 111,
  7894: 79,
  7895: 111,
  7896: 79,
  7897: 111,
  7898: 79,
  7899: 111,
  7900: 79,
  7901: 111,
  7902: 79,
  7903: 111,
  7904: 79,
  7905: 111,
  7906: 79,
  7907: 111,
  7908: 85,
  7909: 117,
  7910: 85,
  7911: 117,
  7912: 85,
  7913: 117,
  7914: 85,
  7915: 117,
  7916: 85,
  7917: 117,
  7918: 85,
  7919: 117,
  7920: 85,
  7921: 117,
  7922: 89,
  7923: 121,
  7924: 89,
  7925: 121,
  7926: 89,
  7927: 121,
  7928: 89,
  7929: 121,
  8305: 105,
  8341: 104,
  8342: 107,
  8343: 108,
  8344: 109,
  8345: 110,
  8346: 112,
  8347: 115,
  8348: 116,
  8580: 99,
};
