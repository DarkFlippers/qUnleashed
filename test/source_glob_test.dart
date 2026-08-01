import 'dart:io';

import 'package:dartufbt/dartufbt.dart';
import 'package:flutter_test/flutter_test.dart';

late Directory _root;

String _rel(File file) =>
    file.path.substring(_root.path.length + 1).replaceAll('\\', '/');

List<String> _gather(List<String> sources) =>
    SourceGlob.gather(_root, sources).map(_rel).toList()..sort();

void main() {
  setUp(() {
    _root = Directory.systemTemp.createTempSync('dartufbt_glob');
    for (final path in const [
      'main.c',
      'helper.h',
      'src/app.c',
      'src/state.c',
      'src/state.h',
      'src/ui/screen.c',
      'src/ui/screen.h',
      'tests/test_app.c',
    ]) {
      final file = File('${_root.path}/$path');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('');
    }
  });

  tearDown(() => _root.deleteSync(recursive: true));

  test('matches a pattern that carries a directory', () {
    expect(_gather(['src/*.c']), ['src/app.c', 'src/state.c']);
  });

  test('recurses for a bare pattern', () {
    expect(_gather(['*.c']), [
      'main.c',
      'src/app.c',
      'src/state.c',
      'src/ui/screen.c',
      'tests/test_app.c',
    ]);
  });

  test('honours exclusions by path and by name', () {
    expect(_gather(['*.c', '!tests/*.c']), [
      'main.c',
      'src/app.c',
      'src/state.c',
      'src/ui/screen.c',
    ]);
    expect(_gather(['src/*.c', '!state.c']), ['src/app.c']);
  });

  test('keeps a plain file name as is', () {
    expect(_gather(['main.c']), ['main.c']);
  });
}
