// The hand-written Dart `Struct`s against the C structs they mirror.
//
// This is the one hole nothing else can see. `keep.txt` and the compiler keep
// the C sides honest; the `_Static_assert`s in each header pin every offset for
// every compiled variant; faaccrack's bridge exports both sizes and the binding
// checks them at runtime, in release. None of that notices a *reorder*: swap two
// 32-bit fields on one side only and the sizes still match, every assert still
// holds, the status is still OK - and Dart reads the wrong word. Swapping
// `seed` with `last_plain` hands the page a plausible seed that is not the
// seed, which is written to the user's Flipper as a `.sub` that opens nothing.
// Swapping `permille` with `abort` sends Stop into the progress field, so the
// button does nothing and the bar never moves.
//
// So this compares the field *sequences*, in order, by name and width. Pure
// source text: no native build, no device, runs everywhere.
//
// Parameterised over three pairings rather than one, because `NativeProgress`
// is now a single Dart mirror shared by two libraries whose C structs are
// deliberately not shared - hardnested declares the first three words and
// faaccrack all four. That makes the shared mirror's *length* load-bearing in
// two directions at once, which is exactly what [_Mirror.extraDartWords]
// records: hardnested tolerates a trailing word it never touches, and faaccrack
// does not tolerate one at all.
//
// What it cannot see:
//
//  * Whether the compiler laid a C struct out as its declaration reads. That is
//    what the `_Static_assert`s are for, and they run in every variant compile
//    including the one in CI.
//  * Whether a shipped library matches the header it was built from. For
//    faaccrack that is the runtime size check in `faaccrack_recoverer.dart`;
//    hardnested exports no size, which is why its header gained assertions of
//    its own rather than relying on one.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'faaccrack_sources.dart';

/// Where the other two sources live. faaccrack's are in `faaccrack_sources.dart`
/// with the rest of that library's guard paths.
const _hardnestedProgressHeaderPath =
    'lib/modules/cpp/hardnested/qunleashed_hn_progress.h';
const _nativePath = 'lib/services/native.dart';

/// A C struct and the Dart `Struct` that reads it.
typedef _Mirror = ({
  /// The C struct, either `struct <name>` or a `typedef struct { ... } <name>;`.
  String cName,

  /// Where it is declared.
  String header,

  /// The Dart class, and the file holding it.
  String dartName,
  String binding,

  /// How many words the Dart mirror has beyond the ones this C struct
  /// declares - non-zero only where the mirror is shared with a longer struct
  /// in another library. The C side never reads them; see `NativeProgress`.
  int extraDartWords,
});

const _mirrors = <_Mirror>[
  (
    cName: 'faaccrack_result',
    header: faaccrackHeaderPath,
    dartName: '_FaaccrackResult',
    binding: faaccrackRecovererPath,
    extraDartWords: 0,
  ),
  (
    cName: 'faaccrack_progress',
    header: faaccrackHeaderPath,
    dartName: 'NativeProgress',
    binding: _nativePath,
    extraDartWords: 0,
  ),
  (
    cName: 'qunleashed_hn_progress',
    header: _hardnestedProgressHeaderPath,
    dartName: 'NativeProgress',
    binding: _nativePath,
    // faaccrack's `threads_started`, which this engine has no equivalent of and
    // never writes.
    extraDartWords: 1,
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

/// The body of `struct <name> { ... };`, or of the anonymous struct a
/// `typedef struct { ... } <name>;` names - hardnested writes it the second way.
String _cStructBody(String header, String name) {
  // Thrown rather than expected: this runs while the file is being loaded to
  // build the groups below, and `expect` outside a test body fails the whole
  // suite with an unhelpful OutsideTestException.
  final named = header.indexOf('struct $name {');
  if (named >= 0) return header.substring(named, header.indexOf('};', named));
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
  return source.substring(start, end);
}

/// snake_case to the lowerCamelCase a Dart field would use.
String _camel(String snake) {
  final parts = snake.split('_');
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

void main() {
  final sources = <String, String>{};
  String read(String path) => sources[path] ??= File(path).readAsStringSync();

  for (final mirror in _mirrors) {
    group('${mirror.cName} / ${mirror.dartName}', () {
      final header = read(mirror.header);
      final native = _fields(
        _cField,
        _cStructBody(header, mirror.cName),
        camel: true,
      );
      final dart = _fields(
        _dartField,
        _dartStructBody(read(mirror.binding), mirror.dartName),
        camel: false,
      );

      test('has fields to compare at all', () {
        // A regex that matched nothing would make the comparisons below pass
        // against two empty lists, which is the failure this whole file exists
        // to prevent.
        expect(native, isNotEmpty);
        expect(dart, isNotEmpty);
      });

      test('the Dart mirror lists the same fields in the same order', () {
        expect(
          dart.take(native.length).toList(growable: false),
          native,
          reason:
              'the Dart mirror of ${mirror.cName} no longer matches the header '
              'field for field. A reorder passes every size check and every '
              'static assertion while Dart reads the wrong word - see this '
              'file.',
        );
      });

      test('the Dart mirror is exactly as long as it is allowed to be', () {
        // The prefix comparison above cannot see a field appended to the Dart
        // side, and appending one is an ABI change for faaccrack: its runtime
        // size check would start refusing every search as an engine fault,
        // which reads to the user as a broken build.
        expect(
          dart.length,
          native.length + mirror.extraDartWords,
          reason:
              '${mirror.dartName} has ${dart.length} words and '
              '${mirror.cName} declares ${native.length}, with '
              '${mirror.extraDartWords} allowed beyond it. A trailing word is '
              'free for a C struct that never reads it and fatal for one whose '
              'size is checked - see NativeProgress.',
        );
      });

      test('the sizes the header asserts match the fields it declares', () {
        // Keeps this test honest about the one thing it is not checking: that
        // the declaration and the asserted size agree.
        final asserted = RegExp(
          'sizeof\\((?:struct )?${mirror.cName}\\) == (\\d+)',
        ).firstMatch(header);
        expect(
          asserted,
          isNotNull,
          reason: 'no sizeof assertion for ${mirror.cName}',
        );
        final declared = native.fold<int>(
          0,
          (total, field) => total + (field.startsWith('64') ? 8 : 4),
        );
        expect(
          int.parse(asserted!.group(1)!),
          declared,
          reason: 'the asserted size does not match the declared fields',
        );
      });
    });
  }
}
