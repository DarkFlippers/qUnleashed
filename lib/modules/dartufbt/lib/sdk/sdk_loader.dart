import 'dart:convert';
import 'dart:io';

import '../log/logger.dart';
import '../net/file_fetcher.dart';
import 'directory_index.dart';
import 'file_type.dart';

class UfbtValueError implements Exception {
  const UfbtValueError(this.message);

  final String message;

  @override
  String toString() => message;
}

class UfbtRuntimeError implements Exception {
  const UfbtRuntimeError(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class UfbtSdkLoader {
  UfbtSdkLoader({
    required this.logger,
    required this.fetcher,
    required this.downloadDir,
  });

  static const String versionUnknown = 'unknown';
  static const List<String> alwaysUpdateVersions = [versionUnknown, 'local'];

  final UfbtLogger logger;
  final UfbtFileFetcher fetcher;
  final Directory downloadDir;

  String get modeKey;

  Future<void> load();

  Future<File> getSdkComponent(String target);

  Map<String, String> get metadata;
}

class BranchSdkLoader extends UfbtSdkLoader {
  BranchSdkLoader({
    required super.logger,
    required super.fetcher,
    required super.downloadDir,
    required this.branch,
    String? branchRootUrl,
  }) : branchRoot = branchRootUrl ?? updateServerBranchRoot;

  static const String loaderModeKey = 'branch';
  static const String updateServerBranchRoot =
      'https://update.flipperzero.one/builds/firmware';

  static final RegExp _fileNameRe = RegExp(
    r'flipper-z-(\w+)-(\w+)-(.+)\.(\w+)',
  );
  static final RegExp _hrefRe = RegExp(
    '''<a[^>]+href=["']([^"']+)["']''',
    caseSensitive: false,
  );

  final String branch;
  final String branchRoot;

  final Map<String, String> _branchFiles = {};
  String? _version;

  String get branchUrl => '$branchRoot/$branch/';

  @override
  String get modeKey => loaderModeKey;

  @override
  Future<void> load() async {
    logger.info('Fetching branch index $branchUrl');
    final html = await fetcher.readAsString(branchUrl);

    for (final match in _hrefRe.allMatches(html)) {
      final href = match.group(1)!;
      if (href.contains('.map')) continue;

      final fileMatch = _fileNameRe.matchAsPrefix(href);
      if (fileMatch == null) continue;

      final target = fileMatch.group(1)!;
      final fileType = fileMatch.group(2)!;
      final version = fileMatch.group(3)!;
      final ext = fileMatch.group(4)!;

      final typeId = '${fileType}_$ext'.toLowerCase();
      final known = UfbtFileType.values.where((type) => type.id == typeId);
      if (known.isNotEmpty) {
        _branchFiles['${known.first.id}|$target'] = href;
      }
      if (_version == null) {
        _version = version;
      } else if (!version.startsWith(_version!)) {
        throw UfbtRuntimeError(
          'Found multiple versions: $_version and $version',
        );
      }
    }

    logger.info('Found version $_version');
  }

  @override
  Future<File> getSdkComponent(String target) async {
    final fileName = _branchFiles['${UfbtFileType.sdkZip.id}|$target'];
    if (fileName == null) {
      throw UfbtValueError('SDK bundle not found for $target');
    }
    return fetcher.fetchFile(branchUrl + fileName, downloadDir);
  }

  @override
  Map<String, String> get metadata => {
    'mode': loaderModeKey,
    'branch': branch,
    'version': _version ?? UfbtSdkLoader.versionUnknown,
    'branch_root': branchRoot,
  };
}

class UpdateChannelSdkLoader extends UfbtSdkLoader {
  UpdateChannelSdkLoader({
    required super.logger,
    required super.fetcher,
    required super.downloadDir,
    required this.channel,
    String? jsonIndexUrl,
  }) : jsonIndexUrl = jsonIndexUrl ?? officialIndexUrl;

  static const String loaderModeKey = 'channel';
  static const String officialIndexUrl =
      'https://update.flipperzero.one/firmware/directory.json';

  final UfbtUpdateChannel channel;
  final String jsonIndexUrl;

  UfbtIndexVersion? _versionInfo;

  UfbtIndexVersion get versionInfo {
    final info = _versionInfo;
    if (info == null) throw StateError('Loader is not initialized');
    return info;
  }

  String get _channelRepr => 'UpdateChannel.${channel.pythonName}';

  @override
  String get modeKey => loaderModeKey;

  @override
  Future<void> load() async {
    logger.info('Fetching version info for $_channelRepr from $jsonIndexUrl');

    final Map<String, dynamic> raw;
    try {
      final body = await fetcher.readAsString(jsonIndexUrl);
      raw = Map<String, dynamic>.from(jsonDecode(body) as Map);
    } on FormatException catch (e) {
      throw UfbtValueError('Invalid JSON: ${e.message}');
    }

    final index = UfbtDirectoryIndex.fromJson(raw);
    if (index.channels.isEmpty) {
      throw UfbtValueError('Invalid channel: $_channelRepr');
    }

    final channelData = index.findChannel(channel.id);
    if (channelData == null) {
      throw UfbtValueError('Invalid channel: $_channelRepr');
    }
    if (channelData.versions.isEmpty) {
      throw UfbtValueError('Empty channel: $_channelRepr');
    }

    final version = channelData.versions.first;
    logger.info('Using version: ${version.version}');
    logger.debug('Changelog: ${version.changelog ?? 'None'}');
    _versionInfo = version;
  }

  @override
  Future<File> getSdkComponent(String target) async {
    final version = versionInfo;
    if (version.files.isEmpty) {
      throw const UfbtValueError('Empty files list');
    }

    final file = version.findFile(UfbtFileType.sdkZip, target);
    if (file == null) {
      throw UfbtValueError(
        'Invalid file type: FileType.${UfbtFileType.sdkZip.id.toUpperCase()}',
      );
    }
    if (file.url.isEmpty) {
      throw const UfbtValueError('Invalid file url');
    }

    return fetcher.fetchFile(file.url, downloadDir);
  }

  @override
  Map<String, String> get metadata => {
    'mode': loaderModeKey,
    'channel': channel.key,
    'json_index': jsonIndexUrl,
    'version': _versionInfo?.version ?? UfbtSdkLoader.versionUnknown,
  };
}

class UrlSdkLoader extends UfbtSdkLoader {
  UrlSdkLoader({
    required super.logger,
    required super.fetcher,
    required super.downloadDir,
    required this.url,
  });

  static const String loaderModeKey = 'url';

  final String url;

  @override
  String get modeKey => loaderModeKey;

  @override
  Future<void> load() async {}

  @override
  Future<File> getSdkComponent(String target) async {
    logger.info('Fetching SDK from $url');
    return fetcher.fetchFile(url, downloadDir);
  }

  @override
  Map<String, String> get metadata => {
    'mode': loaderModeKey,
    'url': url,
    'version': UfbtSdkLoader.versionUnknown,
  };
}

class LocalSdkLoader extends UfbtSdkLoader {
  LocalSdkLoader({
    required super.logger,
    required super.fetcher,
    required super.downloadDir,
    required this.filePath,
  });

  static const String loaderModeKey = 'local';

  final String filePath;

  @override
  String get modeKey => loaderModeKey;

  @override
  Future<void> load() async {}

  @override
  Future<File> getSdkComponent(String target) async {
    logger.info('Loading SDK from $filePath');
    return File(filePath);
  }

  @override
  Map<String, String> get metadata => {
    'mode': loaderModeKey,
    'file_path': filePath,
    'version': UfbtSdkLoader.versionUnknown,
  };
}
