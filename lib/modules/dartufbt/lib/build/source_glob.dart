import 'dart:io';

class SourceGlob {
  const SourceGlob._();

  static const List<String> fileExclusion = ['*~'];

  static final RegExp _separator = RegExp(r'[/\\]');

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
    List<String> exclude, {
    Directory? root,
  }) {
    final base = root ?? node;
    final excluded = <String>{...exclude, ...fileExclusion};
    final results = <File>[];

    if (!hasGlobMagic(pattern)) {
      results.add(File(_join(node.path, pattern)));
      return results;
    }

    if (!node.existsSync()) return results;

    for (final dir in _entries(node).whereType<Directory>()) {
      if (_isExcluded(dir.path, base, excluded)) continue;
      results.addAll(globRecursive(dir, pattern, exclude, root: base));
    }

    results.addAll(_glob(node, pattern, base, excluded));
    return results;
  }

  /// SCons `Dir.glob`: the pattern may carry a directory part, which is
  /// resolved before the file name is matched inside it.
  static List<File> _glob(
    Directory node,
    String pattern,
    Directory base,
    Set<String> excluded,
  ) {
    final split = pattern.lastIndexOf(_separator);
    if (split < 0) return _globFiles(node, pattern, base, excluded);

    final dirPattern = pattern.substring(0, split);
    final namePattern = pattern.substring(split + 1);
    final dirs = hasGlobMagic(dirPattern)
        ? _globDirs(node, dirPattern)
        : [Directory(_join(node.path, dirPattern))];

    final results = <File>[];
    for (final dir in dirs) {
      results.addAll(_globFiles(dir, namePattern, base, excluded));
    }
    return results;
  }

  static List<Directory> _globDirs(Directory node, String pattern) {
    var dirs = <Directory>[node];
    for (final part in pattern.split(_separator)) {
      if (part.isEmpty) continue;
      final next = <Directory>[];
      for (final dir in dirs) {
        if (!hasGlobMagic(part)) {
          final child = Directory(_join(dir.path, part));
          if (child.existsSync()) next.add(child);
          continue;
        }
        if (!dir.existsSync()) continue;
        for (final child in _entries(dir).whereType<Directory>()) {
          if (_matches(_name(child.path), part)) next.add(child);
        }
      }
      dirs = next;
    }
    return dirs;
  }

  static List<File> _globFiles(
    Directory dir,
    String pattern,
    Directory base,
    Set<String> excluded,
  ) {
    if (!dir.existsSync()) return const [];
    final results = <File>[];
    for (final file in _entries(dir).whereType<File>()) {
      if (!_matches(_name(file.path), pattern)) continue;
      if (_isExcluded(file.path, base, excluded)) continue;
      results.add(file);
    }
    return results;
  }

  static List<FileSystemEntity> _entries(Directory dir) =>
      dir.listSync(followLinks: false)
        ..sort((a, b) => a.path.compareTo(b.path));

  static bool _isExcluded(String path, Directory base, Set<String> patterns) {
    final relative = _relative(path, base.path);
    for (final pattern in patterns) {
      if (_matches(_name(path), pattern)) return true;
      if (_matches(relative, pattern, crossSeparators: true)) return true;
    }
    return false;
  }

  static bool _matches(
    String name,
    String pattern, {
    bool crossSeparators = false,
  }) {
    final any = crossSeparators ? '.*' : '[^/\\\\]*';
    final buffer = StringBuffer('^');
    for (var i = 0; i < pattern.length; i++) {
      final c = pattern[i];
      switch (c) {
        case '*':
          buffer.write(any);
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

  static String _join(String dir, String name) =>
      '$dir${Platform.pathSeparator}$name';

  static String _relative(String path, String base) {
    if (!path.startsWith(base)) return path;
    return path
        .substring(base.length)
        .replaceAll('\\', '/')
        .replaceFirst(RegExp('^/'), '');
  }

  static String _name(String path) =>
      path.split(_separator).where((p) => p.isNotEmpty).last;
}
