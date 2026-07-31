import 'dart:io';

class SourceGlob {
  const SourceGlob._();

  static const List<String> fileExclusion = ['*~'];

  static bool hasGlobMagic(String pattern) =>
      pattern.contains('*') || pattern.contains('?') || pattern.contains('[');

  static List<File> gather(Directory node, List<String> sources) {
    final include = sources.where((s) => !s.startsWith('!')).toList();
    final exclude = sources
        .where((s) => s.startsWith('!'))
        .map((s) => s.substring(1))
        .toList();

    final results = <String, File>{};
    for (final pattern in include) {
      for (final file in globRecursive(node, pattern, exclude)) {
        results[file.path] = file;
      }
    }
    return results.values.toList();
  }

  static List<File> globRecursive(
    Directory node,
    String pattern,
    List<String> exclude,
  ) {
    final excluded = <String>{...exclude, ...fileExclusion};
    final results = <File>[];

    if (!hasGlobMagic(pattern)) {
      results.add(File('${node.path}${Platform.pathSeparator}$pattern'));
      return results;
    }

    if (!node.existsSync()) return results;

    final entries = node.listSync(followLinks: false)
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final entity in entries) {
      if (entity is! Directory) continue;
      if (_matchesAny(_name(entity.path), excluded)) continue;
      results.addAll(globRecursive(entity, pattern, exclude));
    }

    for (final entity in entries) {
      if (entity is! File) continue;
      final name = _name(entity.path);
      if (_matchesAny(name, excluded)) continue;
      if (_matches(name, pattern)) results.add(entity);
    }
    return results;
  }

  static bool _matchesAny(String name, Set<String> patterns) {
    for (final pattern in patterns) {
      if (_matches(name, pattern)) return true;
    }
    return false;
  }

  static bool _matches(String name, String pattern) {
    final buffer = StringBuffer('^');
    for (var i = 0; i < pattern.length; i++) {
      final c = pattern[i];
      switch (c) {
        case '*':
          buffer.write('[^/\\\\]*');
        case '?':
          buffer.write('.');
        case '[':
          final end = pattern.indexOf(']', i);
          if (end < 0) {
            buffer.write(RegExp.escape(c));
          } else {
            buffer.write(pattern.substring(i, end + 1));
            i = end;
          }
        default:
          buffer.write(RegExp.escape(c));
      }
    }
    buffer.write(r'$');
    return RegExp(buffer.toString()).hasMatch(name);
  }

  static String _name(String path) =>
      path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty).last;
}
