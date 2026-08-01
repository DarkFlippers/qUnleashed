import 'dart:io';

import 'package:dartufbt/dartufbt.dart';

/// A repository link split into what git needs plus the folder inside it.
class GitTarget {
  const GitTarget({required this.remote, this.ref, this.subdir = ''});

  final String remote;
  final String? ref;
  final String subdir;

  String get name {
    final tail = remote.replaceAll(RegExp(r'[/\\]+$'), '').split('/').last;
    final clean = tail.endsWith('.git')
        ? tail.substring(0, tail.length - 4)
        : tail;
    return clean.isEmpty ? 'repository' : clean;
  }

  @override
  String toString() =>
      'GitTarget(remote: $remote, ref: $ref, subdir: "$subdir")';
}

class GitSourceException implements Exception {
  const GitSourceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GitSource {
  const GitSource._();

  /// Understands a plain remote as well as the browse links the hosts produce:
  /// `.../tree/<ref>/<dir>` on GitHub, `.../-/tree/<ref>/<dir>` on GitLab and
  /// `.../src/<ref>/<dir>` on Bitbucket.
  static GitTarget parse(String input) {
    final url = input.trim().replaceAll(RegExp(r'/+$'), '');
    if (url.isEmpty) throw const GitSourceException('Repository link is empty');

    final web = RegExp(
      r'^(https?://[^/]+/[^/]+/[^/]+?)(?:\.git)?'
      r'(?:/-)?/(?:tree|blob|src)/([^/]+)(/.*)?$',
    ).firstMatch(url);
    if (web != null) {
      return GitTarget(
        remote: web.group(1)!,
        ref: web.group(2),
        subdir: (web.group(3) ?? '').replaceAll(RegExp(r'^/+'), ''),
      );
    }

    if (!url.contains('://') && !url.contains('@')) {
      throw GitSourceException('Not a repository link: $url');
    }
    return GitTarget(remote: url);
  }

  /// Clones (or refreshes) [target] under the ufbt state dir and returns the
  /// folder the project lives in.
  static Future<Directory> checkout({
    required GitTarget target,
    required Directory parent,
    required UfbtLogger logger,
  }) async {
    if (!await _hasGit()) {
      throw const GitSourceException(
        'git was not found in PATH, install it to build from a repository',
      );
    }

    parent.createSync(recursive: true);
    final repoDir = Directory(UfbtPaths.join(parent.path, target.name));
    final ref = target.ref;

    var refreshed = false;
    if (Directory(UfbtPaths.join(repoDir.path, '.git')).existsSync()) {
      final origin = await _run(
        ['-C', repoDir.path, 'remote', 'get-url', 'origin'],
        logger,
        quiet: true,
      );
      if (origin.trim() == target.remote) {
        try {
          await _run([
            '-C',
            repoDir.path,
            'fetch',
            '--depth',
            '1',
            'origin',
            if (ref != null) ref else 'HEAD',
          ], logger);
          await _run([
            '-C',
            repoDir.path,
            'checkout',
            '--force',
            '--detach',
            'FETCH_HEAD',
          ], logger);
          refreshed = true;
        } on GitSourceException {
          refreshed = false;
        }
      }
    }

    if (!refreshed) {
      if (repoDir.existsSync()) repoDir.deleteSync(recursive: true);
      await _run([
        'clone',
        '--depth',
        '1',
        if (ref != null) ...['--branch', ref],
        target.remote,
        repoDir.path,
      ], logger);
    }

    if (target.subdir.isEmpty) return repoDir;
    final path = UfbtPaths.join(
      repoDir.path,
      target.subdir.replaceAll('/', separator),
    );
    // A link to a file inside the repository points at the project it lives in.
    if (File(path).existsSync()) return File(path).parent;
    final dir = Directory(path);
    if (!dir.existsSync()) {
      throw GitSourceException(
        'No "${target.subdir}" folder in the repository',
      );
    }
    return dir;
  }

  static String get separator => Platform.pathSeparator;

  static Future<bool> _hasGit() async {
    try {
      final result = await Process.run('git', ['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<String> _run(
    List<String> args,
    UfbtLogger logger, {
    bool quiet = false,
  }) async {
    if (!quiet) logger.build('GIT', args.join(' '));
    final result = await Process.run('git', args);
    final out = '${result.stdout}';
    final err = '${result.stderr}';
    if (!quiet) {
      for (final line in '$out$err'.split('\n')) {
        if (line.trim().isNotEmpty) logger.raw(line.trimRight());
      }
    }
    if (result.exitCode != 0) {
      throw GitSourceException(
        'git ${args.first} failed: ${err.trim().isEmpty ? out.trim() : err.trim()}',
      );
    }
    return out;
  }
}
