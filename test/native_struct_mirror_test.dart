// The hand-written Dart `Struct`s against the C structs they mirror, as text.
//
// [`ADR 0015`](../docs/adr/0015-hand-written-ffi-bindings.md) is why the
// bindings are hand-written at all and what the other layers of the guard are.
// This file is the layer that compares the two declarations field for field,
// and the one that notices a *reorder*: swap two 32-bit fields on one side only
// and the sizes still match, every static assertion still holds, the status is
// still OK - and Dart reads the wrong word. Swapping `seed` with `last_plain`
// hands the page a plausible seed that is not the seed, which is written to the
// user's Flipper as a `.sub` that opens nothing.
//
// Pure source text: no native build, no device, runs everywhere. Its sibling
// `native_progress_layout_test.dart` asks Dart for the layout it actually
// built, which is the only thing that can see a field the regexes below cannot
// parse.
//
// Three pairings, because `NativeProgress` is one Dart mirror shared by two
// libraries whose C structs are deliberately separate - hardnested declares
// three words, faaccrack four. So faaccrack's struct must *equal* the mirror and
// hardnested's must be a *prefix* of it, which `extraDartFields` names. The two
// together say something neither says alone: that hardnested's struct is a
// prefix of faaccrack's.
//
// It also checks that the assertions it relies on are present and say what they
// should, rather than trusting that a compiler ran. On a pull request no
// compiler has: CI's only native compile is
// `.github/scripts/check_faaccrack_engine.sh`, which builds faaccrack's three
// sources and never includes `qunleashed_hn_progress.h`. For that library this
// file and its sibling are the whole of the cover until a release build.
//
// What it cannot see:
//
//  * A C member that is not `uint32_t`/`uint64_t` - `int32_t`, `uint16_t`, an
//    array, a nested struct - or two declared on one line (`uint32_t a, b;`).
//    Those are invisible to [_cField] and are caught only by the size check
//    below, whose message points at the assertion rather than at the type
//    nobody meant to change.
//  * A member inside `#if`/`#ifdef`, which is counted unconditionally. The test
//    would then demand a Dart word that the default compile does not have, and
//    the obvious way to go green - appending one - is an ABI change.
//  * A Dart field whose annotation is not `@Uint32()`/`@Uint64()`, or written
//    on one line. That is `native_progress_layout_test.dart`'s job.
//  * Whether the compiler laid a C struct out as its declaration reads. That is
//    what the `_Static_assert`s are for.
//  * Whether a shipped library matches the header it was built from. For
//    faaccrack that is the release-path size check in `faaccrack_recoverer.dart`;
//    hardnested exports no size, so nothing covers that for it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'native_sources.dart';

/// A C struct and the Dart `Struct` that reads it.
typedef _Mirror = ({
  /// The C struct, either `struct <name>` or a `typedef struct { ... } <name>;`.
  String cName,

  /// Where it is declared.
  String header,

  /// The Dart class, and the file holding it.
  String dartName,
  String binding,

  /// The words the Dart mirror carries beyond the ones this C struct declares,
  /// in this file's `width:name` form. Non-empty only where the mirror is
  /// shared with a longer struct in another library.
  ///
  /// Named rather than counted. A count can be raised to turn a failure green -
  /// the budget-editing move CLAUDE.md warns about - and it cannot see the slack
  /// word being renamed or re-widened, which is how hardnested would start
  /// reading a field that is no longer the one it was measured against.
  List<String> extraDartFields,
});

const _mirrors = <_Mirror>[
  (
    cName: 'faaccrack_result',
    header: faaccrackHeaderPath,
    dartName: '_FaaccrackResult',
    binding: faaccrackRecovererPath,
    extraDartFields: [],
  ),
  (
    cName: 'faaccrack_progress',
    header: faaccrackHeaderPath,
    dartName: 'NativeProgress',
    binding: nativeBindingPath,
    extraDartFields: [],
  ),
  (
    cName: 'qunleashed_hn_progress',
    header: hardnestedProgressHeaderPath,
    dartName: 'NativeProgress',
    binding: nativeBindingPath,
    // faaccrack's `threads_started`, which this engine has no equivalent of and
    // cannot reach - it only ever holds a pointer to its own three words.
    extraDartFields: ['32:threadsStarted'],
  ),
];

/// `uint32_t permille;` or `volatile uint64_t lrkey;` inside a struct body.
final _cField = RegExp(
  r'^\s*(?:volatile\s+)?uint(32|64)_t\s+(\w+);',
  multiLine: true,
);

/// `@Uint32()` followed by `external int permille;`.
final _dartField = RegExp(
  r'@Uint(32|64)\(\)\s*\n\s*external\s+int\s+(\w+);',
  multiLine: true,
);

/// A live `_Static_assert(sizeof(...) == N`, at the start of a line.
///
/// Anchored, because this is a text search and a disabled assertion is still
/// text. `// _Static_assert(sizeof(qunleashed_hn_progress) == 12,` matched an
/// unanchored pattern perfectly well, so the suite stayed green with every
/// assertion in that header commented out - and that header has no runtime
/// check behind it.
RegExp _sizeAssert(String cName) => RegExp(
  '^_Static_assert\\(\\s*sizeof\\((?:struct )?$cName\\) == (\\d+)',
  multiLine: true,
);

/// A live `_Static_assert(offsetof(<struct>, <field>) == N`, at the start of a
/// line. The offset may be on the following line, as the longer ones are
/// wrapped.
RegExp _offsetAssert(String cName) => RegExp(
  '^_Static_assert\\(\\s*offsetof\\((?:struct )?$cName,\\s*(\\w+)\\)\\s*==\\s*'
  r'(\d+)',
  multiLine: true,
);

/// C comments removed, so a commented-out declaration or assertion is not read
/// as a live one.
///
/// Blank lines rather than nothing for `/* */`, so the line anchors above still
/// mean what they say.
String _stripComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// The body of `struct <name> { ... };`, or of the anonymous struct a
/// `typedef struct { ... } <name>;` names - hardnested writes it the second way.
///
/// Throws rather than expects, and that has a consequence worth knowing: this
/// runs while the file is being loaded to build the groups below, so a struct
/// this cannot find is a load error that takes every other pairing's results
/// with it, not one red test. `expect` is not available out here either - it
/// fails the whole suite with an unhelpful OutsideTestException.
String _cStructBody(String header, String name) {
  final named = header.indexOf('struct $name {');
  if (named >= 0) {
    final close = header.indexOf('};', named);
    if (close < 0) throw StateError('struct $name is never closed');
    return header.substring(named, close);
  }
  final end = header.indexOf('} $name;');
  if (end < 0) throw StateError('struct $name not found in the header');
  final start = header.lastIndexOf('typedef struct {', end);
  if (start < 0) throw StateError('no typedef struct body for $name');
  return header.substring(start, end);
}

/// The body of `final class <name> extends Struct { ... }`.
String _dartStructBody(String source, String name) {
  final start = source.indexOf('final class $name extends Struct {');
  if (start < 0) throw StateError('$name not found in the binding');
  final end = source.indexOf('\n}', start);
  if (end < 0) throw StateError('$name is never closed');
  return source.substring(start, end);
}

/// snake_case to the lowerCamelCase a Dart field would use.
String _camel(String snake) {
  final parts = snake.split('_').where((p) => p.isNotEmpty);
  return parts.first +
      parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
}

List<String> _fields(RegExp pattern, String body, {required bool camel}) =>
    pattern
        .allMatches(body)
        .map(
          (m) => '${m.group(1)}:${camel ? _camel(m.group(2)!) : m.group(2)!}',
        )
        .toList(growable: false);

/// Bytes a field of this file's `width:name` form occupies.
int _widthOf(String field) => field.startsWith('64') ? 8 : 4;

void main() {
  final sources = <String, String>{};
  String read(String path) =>
      sources[path] ??= _stripComments(File(path).readAsStringSync());

  for (final mirror in _mirrors) {
    group('${mirror.cName} / ${mirror.dartName}', () {
      final header = read(mirror.header);
      final body = _cStructBody(header, mirror.cName);
      final native = _fields(_cField, body, camel: true);
      // The same fields under their C spelling, which is how the offset
      // assertions name them.
      final nativeRaw = _fields(_cField, body, camel: false);
      final dart = _fields(
        _dartField,
        _dartStructBody(read(mirror.binding), mirror.dartName),
        camel: false,
      );

      test('has fields to compare at all', () {
        // Two regexes that matched nothing would make the comparison below pass
        // against two empty lists, which is the failure this whole file exists
        // to prevent.
        expect(native, isNotEmpty);
        expect(dart, isNotEmpty);
      });

      test('the Dart mirror is this struct followed by its allowed extras', () {
        // One assertion rather than a prefix comparison plus a length check:
        // those two together accept the trailing word being renamed or widened,
        // since neither looks at it. Naming the tail closes that.
        expect(
          dart,
          [...native, ...mirror.extraDartFields],
          reason:
              'the Dart mirror of ${mirror.cName} no longer matches the header '
              'field for field. A reorder passes every size check and every '
              'static assertion while Dart reads the wrong word - see this '
              'file.',
        );
      });

      test('the header asserts a size that matches the fields it declares', () {
        // What this really pins is that [_cField] parsed the declaration, and
        // parsed all of it: the compiler already checks the declaration against
        // the asserted number, in every variant compile of faaccrack. Nothing
        // compiles the hardnested header on a pull request, so here it also
        // pins that the assertion exists and is not commented out.
        final asserted = _sizeAssert(mirror.cName).firstMatch(header);
        expect(
          asserted,
          isNotNull,
          reason: 'no live sizeof assertion for ${mirror.cName}',
        );
        expect(
          int.parse(asserted!.group(1)!),
          native.fold<int>(0, (total, field) => total + _widthOf(field)),
          reason: 'the asserted size does not match the declared fields',
        );
      });

      test('every declared field has an offset assertion of its own', () {
        // "Every offset, not only the size" is what both headers claim, and
        // until this test nothing held them to it: a field could be added with
        // the sizeof assertion bumped and no offsetof line, leaving the headers'
        // own prose false and nothing red. A size alone cannot see a
        // permutation of same-width fields, which is the whole hazard here.
        var offset = 0;
        final expected = <String, int>{};
        for (final field in nativeRaw) {
          expected[field.split(':')[1]] = offset;
          offset += _widthOf(field);
        }
        final asserted = {
          for (final m in _offsetAssert(mirror.cName).allMatches(header))
            m.group(1)!: int.parse(m.group(2)!),
        };
        expect(
          asserted,
          expected,
          reason:
              '${mirror.cName} must assert one offset per declared field, with '
              'the offsets its declaration implies. Field names here are the C '
              'spelling, and the expectation is derived from the declaration '
              'rather than read from the assertions.',
        );
      });
    });
  }
}
