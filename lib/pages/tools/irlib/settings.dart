import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import '../../../services/repository/app.dart';

const String kDefaultIrdbUrl = 'https://github.com/Lucaslhm/Flipper-IRDB';

class IrdbRepoRef {
  IrdbRepoRef({required this.owner, required this.repo, required this.branch});
  final String owner;
  final String repo;
  final String branch;

  String toUrl() =>
      'https://github.com/$owner/$repo'
      '${branch.isEmpty || branch == 'main' ? '' : '/tree/$branch'}';

  static IrdbRepoRef? tryParse(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;
    var s = raw;
    if (s.endsWith('.git')) s = s.substring(0, s.length - 4);
    s = s.replaceFirst(
      RegExp(r'^git@github\.com:', caseSensitive: false),
      'https://github.com/',
    );
    Uri? uri;
    try {
      uri = Uri.parse(s);
    } catch (_) {
      return null;
    }
    final segs = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    if (segs.length < 2) return null;
    final owner = segs[0];
    final repo = segs[1];
    var branch = 'main';
    if (segs.length >= 4 && (segs[2] == 'tree' || segs[2] == 'blob')) {
      branch = segs.sublist(3).join('/');
    }
    return IrdbRepoRef(owner: owner, repo: repo, branch: branch);
  }
}

class IrLibSettings {
  IrLibSettings({
    this.localPath = '',
    this.githubToken = '',
    this.owner = 'Lucaslhm',
    this.repo = 'Flipper-IRDB',
    this.branch = 'main',
  });

  final String localPath;
  final String githubToken;
  final String owner;
  final String repo;
  final String branch;

  IrLibSettings copyWith({
    String? localPath,
    String? githubToken,
    String? owner,
    String? repo,
    String? branch,
  }) {
    return IrLibSettings(
      localPath: localPath ?? this.localPath,
      githubToken: githubToken ?? this.githubToken,
      owner: owner ?? this.owner,
      repo: repo ?? this.repo,
      branch: branch ?? this.branch,
    );
  }

  Map<String, dynamic> toJson() => {
    'localPath': localPath,
    'githubToken': githubToken,
    'owner': owner,
    'repo': repo,
    'branch': branch,
  };

  factory IrLibSettings.fromJson(Map<String, dynamic> json) {
    return IrLibSettings(
      localPath: '${json['localPath'] ?? ''}',
      githubToken: '${json['githubToken'] ?? ''}',
      owner: '${json['owner'] ?? 'Lucaslhm'}',
      repo: '${json['repo'] ?? 'Flipper-IRDB'}',
      branch: '${json['branch'] ?? 'main'}',
    );
  }
}

class IrLibSettingsStorage {
  static io.File? _cachedFile;

  Future<io.File> _file() async {
    final cached = _cachedFile;
    if (cached != null) return cached;
    final base = await appDocumentsDirectory();
    final dir = io.Directory(pathJoin([base.path, 'irlib']));
    await dir.create(recursive: true);
    final f = io.File(pathJoin([dir.path, 'settings.json']));
    _cachedFile = f;
    return f;
  }

  Future<IrLibSettings> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return IrLibSettings();
      final text = await f.readAsString();
      if (text.trim().isEmpty) return IrLibSettings();
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return IrLibSettings();
      return IrLibSettings.fromJson(decoded);
    } catch (_) {
      return IrLibSettings();
    }
  }

  Future<void> save(IrLibSettings s) async {
    final f = await _file();
    await f.writeAsString(jsonEncode(s.toJson()), flush: true);
  }
}
