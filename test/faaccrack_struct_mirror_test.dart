// The hand-written Dart `Struct`s against the C structs they mirror.
//
// This is the one hole nothing else can see. `keep.txt` and the compiler keep
// the C side honest; the `_Static_assert`s in faaccrack.h pin every offset for
// every compiled variant; the bridge exports both sizes and the binding checks
// them at runtime, in release. None of that notices a *reorder*: swap two
// 32-bit fields on one side only and the sizes still match, every assert still
// holds, the status is still OK - and Dart reads the wrong word. Swapping
// `seed` with `last_plain` hands the page a plausible seed that is not the
// seed, which is written to the user's Flipper as a `.sub` that opens nothing.
// Swapping `permille` with `abort` sends Stop into the progress field, so the
// button does nothing and the bar never moves.
//
// So this compares the two field *sequences*, in order, by name and width. Pure
// source text: no native build, no device, runs everywhere.
//
// What it cannot see:
//
//  * Whether the compiler laid the C struct out as the declaration reads. That
//    is what the `_Static_assert`s are for, and they run in every variant
//    compile including the one in CI.
//  * Whether the shipped library matches the header it was built from. That is
//    the runtime size check in `faaccrack_recoverer.dart`.
import 'package:flutter_test/flutter_test.dart';

import 'faaccrack_sources.dart';

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

/// The body of `struct <name> { ... };`.
String _cStructBody(String header, String name) {
  // Thrown rather than expected: this runs while the file is being loaded to
  // build the groups below, and `expect` outside a test body fails the whole
  // suite with an unhelpful OutsideTestException.
  final start = header.indexOf('struct $name {');
  if (start < 0) throw StateError('struct $name not found in the header');
  final end = header.indexOf('};', start);
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
  final header = faaccrackHeader();
  final binding = faaccrackRecovererSource();

  for (final (cName, dartName) in const [
    ('faaccrack_result', '_FaaccrackResult'),
    ('faaccrack_progress', '_FaaccrackProgress'),
  ]) {
    group(cName, () {
      final native = _fields(_cField, _cStructBody(header, cName), camel: true);
      final dart = _fields(
        _dartField,
        _dartStructBody(binding, dartName),
        camel: false,
      );

      test('has fields to compare at all', () {
        // A regex that matched nothing would make the comparison below pass
        // against two empty lists, which is the failure this whole file exists
        // to prevent.
        expect(native, isNotEmpty);
        expect(dart, isNotEmpty);
      });

      test('the Dart mirror lists the same fields in the same order', () {
        expect(
          dart,
          native,
          reason:
              'the Dart mirror of $cName no longer matches the header field '
              'for field. A reorder passes every size check and every static '
              'assertion while Dart reads the wrong word - see this file.',
        );
      });

      test('the sizes the header asserts match the fields it declares', () {
        // Keeps this test honest about the one thing it is not checking: that
        // the declaration and the asserted size agree.
        final asserted = RegExp('sizeof\\(struct $cName\\) == (\\d+)')
            .firstMatch(header);
        expect(asserted, isNotNull, reason: 'no sizeof assertion for $cName');
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
