import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:typed_data';

import '../../../services/assembler/built_file.dart';
import '../../../services/http/app_http.dart';
import '../../../services/logging.dart';
import 'models/author.dart';
import 'models/card.dart';
import 'models/category.dart';
import 'models/detail.dart';
import 'models/plan.dart';
import 'artifact_signature.dart';
import 'catalog_server.dart';

part 'api/catalog_v0_api.dart';
part 'api/catalog_v1_api.dart';

enum AppsSort {
  newUpdates(field: 'updated_at', order: -1),
  oldUpdates(field: 'updated_at', order: 1),
  newReleases(field: 'created_at', order: -1),
  oldReleases(field: 'created_at', order: 1),
  alphabetical(field: 'updated_at', order: -1, v1Field: 'name', v1Order: 1),
  popular(
    field: 'updated_at',
    order: -1,
    v1Field: 'downloads',
    v1Order: -1,
    v1Only: true,
  ),
  popularWeek(
    field: 'updated_at',
    order: -1,
    v1Field: 'downloads_week',
    v1Order: -1,
    v1Only: true,
  );

  final String field;
  final int order;
  final String? v1Field;
  final int v1Order;
  final bool v1Only;
  const AppsSort({
    required this.field,
    required this.order,
    this.v1Field,
    this.v1Order = -1,
    this.v1Only = false,
  });
}

class AppsPage {
  final List<AppCard> items;
  final int offset;
  final int limit;

  const AppsPage({
    required this.items,
    required this.offset,
    required this.limit,
  });

  bool get hasMore => items.length >= limit;
  int get nextOffset => offset + items.length;
}

enum CatalogFamily {
  apps(
    v1Root: 'application',
    serverName: 'application',
    usesDevice: true,
    installsAsApp: true,
    listScreenshots: true,
  ),
  animations(
    v1Root: 'animations',
    serverName: 'animation',
    usesDevice: false,
    previewCards: true,
  ),
  menuStyles(
    v1Root: 'menustyles',
    serverName: 'menustyle',
    usesDevice: true,
    previewCards: true,
  ),

  /// Command-line apps: built and installed like any other app, but what they
  /// draw is a terminal, so no two screenshots would ever line up in a list.
  cli(v1Root: 'cli', serverName: 'cli', usesDevice: true, installsAsApp: true);

  final String v1Root;
  final String serverName;
  final bool usesDevice;

  /// A .fap the install engine writes and the manifests track.
  final bool installsAsApp;

  /// Cards are the item's screen: an animation frame or a menu style preview.
  final bool previewCards;

  /// List cards carry the screenshot strip.
  final bool listScreenshots;

  const CatalogFamily({
    required this.v1Root,
    required this.serverName,
    required this.usesDevice,
    this.installsAsApp = false,
    this.previewCards = false,
    this.listScreenshots = false,
  });

  static CatalogFamily? byServerName(String? name) {
    for (final family in values) {
      if (family.serverName == name) return family;
    }
    return null;
  }
}

class CatalogNeedsV1Exception implements Exception {
  CatalogNeedsV1Exception(
    this.server, {
    this.sort,
    this.family,
    this.search = false,
  });

  final String server;
  final AppsSort? sort;
  final CatalogFamily? family;
  final bool search;

  @override
  String toString() =>
      'CatalogNeedsV1Exception(${search ? 'search' : family?.name ?? sort?.name} '
      'needs /api/v1, $server)';
}

class CatalogSearch {
  final String query;
  final List<AppCard> items;
  final Map<CatalogFamily, int> totals;
  final List<AuthorSummary> authors;

  const CatalogSearch({
    required this.query,
    required this.items,
    required this.totals,
    required this.authors,
  });

  List<AppCard> itemsOf(CatalogFamily family) => [
    for (final item in items)
      if (CatalogFamily.byServerName(item.family) == family) item,
  ];
}

class AppsCatalogException implements Exception {
  final int statusCode;
  final String url;
  final String? body;

  AppsCatalogException(this.statusCode, this.url, [this.body]);

  @override
  String toString() =>
      'AppsCatalogException($statusCode, $url${body == null ? '' : ', $body'})';
}

/// Decodes a catalogue list entry by entry, keeping what reads.
///
/// One bad field in one entry used to cost the whole list: `whereType` filters
/// out what is not an object and does nothing about what is inside one, and
/// `.toList()` forces the lazy `.map` so the throw arrives anyway. A page of
/// apps, up to five hundred of them by uid, or the entire SDK list - which the
/// catalogue context turns into a disabled screen. #138.
///
/// The models cast their fields, and rewriting them to read field by field is
/// a larger change than this. Catching per entry bounds the loss to the entry
/// meanwhile, which is the part a user sees.
///
/// What was dropped is said once for the list. One line per app is a log
/// nobody reads, and a feed whose shape has changed drops every one of them.
List<T> readEach<T>(
  List<dynamic> body,
  T Function(Map<String, dynamic> json) read,
  String what,
) {
  final out = <T>[];
  var dropped = 0;
  for (final raw in body) {
    if (raw is! Map<String, dynamic>) {
      dropped++;
      continue;
    }
    try {
      out.add(read(raw));
    } catch (e) {
      dropped++;
    }
  }
  if (dropped > 0) {
    LogService.warn('[Catalog] dropped $dropped of ${body.length} $what');
  }
  return List<T>.unmodifiable(out);
}

/// Captures the server and device filters for a request, so a settings change
/// cannot redirect a retry or the next chunk of an in-flight lookup.
abstract class _CatalogProtocol {
  _CatalogProtocol({
    required this.server,
    required this.userAgent,
    this.api,
    this.target,
    this.unfiltered = false,
  });
  final String server;
  final String userAgent;
  final String? api;
  final String? target;
  bool unfiltered;
  String get version;

  Map<String, String> _apiParams() =>
      !unfiltered && api != null && target != null
      ? {'api': api!, 'target': target!}
      : const {};

  Uri _uri(String path, Map<String, String> query) =>
      Uri.parse('$server/api/$version$path')
          .replace(queryParameters: query.isEmpty ? null : query);

  Future<dynamic> _getJson(Uri uri, {Duration? ttl}) {
    final headers = {io.HttpHeaders.userAgentHeader: userAgent};
    return ttl == null
        ? AppHttp.getJson(uri, headers: headers)
        : AppHttp.getJsonCached(uri, ttl: ttl, headers: headers);
  }

  /// The file at [uri] once its signature holds, and the headers it came
  /// with.
  Future<({Uint8List bytes, Map<String, String> headers})> _signed(
    Uri uri, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final response = await AppHttp.getBytesWithHeaders(
      uri,
      headers: {io.HttpHeaders.userAgentHeader: userAgent},
      onProgress: onProgress,
    );
    return (
      bytes: await verifySignedArtifact(uri, response),
      headers: response.headers,
    );
  }

  Future<Uint8List> _signedBytes(
    Uri uri, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async => (await _signed(uri, onProgress: onProgress)).bytes;
}

/// One stable API reference for the backend's registries and install queue.
/// Official speaks v0; every community/custom origin speaks v1.
class AppsCatalogApi {
  static const officialServer = CatalogServer.official;
  static const defaultServer = CatalogServer.defaultServer;
  static const defaultBaseUrl = '$defaultServer/api/v0';

  AppsCatalogApi({
    String server = defaultServer,
    String? baseUrl,
    this.userAgent = AppHttp.userAgent,
    this.api,
    this.target,
  }) : _server = CatalogServer.normalize(
         baseUrl == null
             ? server
             : baseUrl.replaceFirst(RegExp(r'/api/v0/?$'), ''),
       );

  String _server;
  String get server => _server;
  set server(String value) {
    final next = CatalogServer.normalize(value);
    if (next == _server) return;
    _server = next;
    unfiltered = false;
  }

  final String userAgent;
  String? api;
  String? target;
  bool unfiltered = false;
  String get baseUrl => '$server/api/v0';
  bool get hasV1 => server != officialServer;
  bool ranksOnServer(AppsSort sort, CatalogFamily family) => hasV1;

  CatalogV0Api get _v0 => CatalogV0Api(
    server: server,
    userAgent: userAgent,
    api: api,
    target: target,
    unfiltered: unfiltered,
  );
  CatalogV1Api get _v1 {
    if (!hasV1) throw CatalogNeedsV1Exception(server);
    return CatalogV1Api(
      server: server,
      userAgent: userAgent,
      api: api,
      target: target,
      unfiltered: unfiltered,
    );
  }

  Future<T> _official<T>(Future<T> Function(CatalogV0Api api) request) async {
    final client = _v0;
    final result = await request(client);
    if (client.server == server) unfiltered = client.unfiltered;
    return result;
  }

  Future<List<AppSdk>> fetchSdks() =>
      hasV1 ? _v1.fetchSdks() : _official((api) => api.fetchSdks());

  Future<List<AppCategory>> fetchCategories({
    int limit = 500,
    CatalogFamily family = CatalogFamily.apps,
  }) async {
    if (hasV1) return _v1.fetchCategories(family: family);
    if (family != CatalogFamily.apps) {
      throw CatalogNeedsV1Exception(server, family: family);
    }
    return _official((api) => api.fetchCategories(limit: limit));
  }

  Future<AppsPage> fetchApps({
    int offset = 0,
    int limit = 48,
    AppsSort sortBy = AppsSort.newUpdates,
    String? categoryId,
    String? query,
    bool? isLatestReleaseVersion,
    bool? hasVersion,
    CatalogFamily family = CatalogFamily.apps,
    String? authorId,
  }) async {
    if (hasV1) {
      return _v1.fetchApps(
        offset: offset,
        limit: limit,
        sortBy: sortBy,
        categoryId: categoryId,
        query: query,
        family: family,
        authorId: authorId,
      );
    }
    if (family != CatalogFamily.apps || sortBy.v1Only || authorId != null) {
      throw CatalogNeedsV1Exception(server, family: family, sort: sortBy);
    }
    return _official(
      (api) => api.fetchApps(
        offset: offset,
        limit: limit,
        sortBy: sortBy,
        categoryId: categoryId,
        query: query,
        isLatestReleaseVersion: isLatestReleaseVersion,
        hasVersion: hasVersion,
      ),
    );
  }

  /// Whether this catalog has [family] at all: Archivarius has the apps
  /// only.
  bool serves(CatalogFamily family) => hasV1 || family == CatalogFamily.apps;

  /// What a device has installed, looked up under [family]'s own root: an
  /// entry is found only in its family.
  Future<List<AppCard>> fetchAppsByUids(
    List<String> uids, {
    AppsSort sortBy = AppsSort.newUpdates,
    CatalogFamily family = CatalogFamily.apps,
  }) async {
    if (!serves(family)) return const [];
    if (hasV1) return _v1.fetchAppsByUids(uids, family: family);
    return _official((api) => api.fetchAppsByUids(uids, sortBy: sortBy));
  }

  Future<AppDetail> fetchApp(
    String idOrAlias, {
    bool? isLatestReleaseVersion,
    CatalogFamily family = CatalogFamily.apps,
    String? app,
  }) async {
    if (hasV1) return _v1.fetchApp(idOrAlias, family: family, app: app);
    if (family != CatalogFamily.apps) {
      throw CatalogNeedsV1Exception(server, family: family);
    }
    return _official(
      (api) => api.fetchApp(
        idOrAlias,
        isLatestReleaseVersion: isLatestReleaseVersion,
      ),
    );
  }

  Future<CatalogSearch> search(String query, {int limit = 36}) async =>
      _v1.search(query, limit: limit);
  Future<CatalogSearch> fetchNewFeed({int limit = 36}) async =>
      _v1.fetchNewFeed(limit: limit);
  Future<List<AuthorSummary>> fetchAuthors({
    String? query,
    int offset = 0,
    int limit = 48,
  }) async => _v1.fetchAuthors(query: query, offset: offset, limit: limit);
  Future<AuthorSummary> fetchAuthor(String id) async => _v1.fetchAuthor(id);

  Uri buildDownloadUri(
    String versionId, {
    required String api,
    String target = 'f7',
    CatalogFamily family = CatalogFamily.apps,
  }) {
    if (hasV1) {
      return _v1.buildDownloadUri(
        versionId,
        api: api,
        target: target,
        family: family,
      );
    }
    return _v0._uri(
      '/application/version/${Uri.encodeComponent(versionId)}/build/compatible',
      {'target': target, 'api': api},
    );
  }

  /// The file and, from our servers, the API it was built for; Archivarius
  /// does not say.
  Future<BuiltFile> fetchFapBuild(
    String versionId, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    String? apiOverride,
    CatalogFamily family = CatalogFamily.apps,
  }) async => hasV1
      ? _v1.fetchBuild(
          versionId,
          family: family,
          onProgress: onProgress,
          apiOverride: apiOverride,
        )
      : BuiltFile(
          await _v0.fetchFapBuild(
            versionId,
            onProgress: onProgress,
            apiOverride: apiOverride,
          ),
          buildApi: null,
        );

  Future<BuiltFile> fetchMenuStyleBuild(
    String versionId, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    String? apiOverride,
  }) async => _v1.fetchBuild(
    versionId,
    family: CatalogFamily.menuStyles,
    onProgress: onProgress,
    apiOverride: apiOverride,
  );

  /// Whether what this catalog serves is built for a development firmware,
  /// which an installed app's `.fim` records as DevCatalog. Our servers say
  /// so in their status, and one that does not is an error; the official
  /// catalog is a release one.
  Future<bool> fetchDevCatalog() async => hasV1 ? _v1.fetchDevCatalog() : false;

  Future<InstallPlan> fetchAnimationPlan(String versionId) async =>
      _v1.fetchAnimationPlan(versionId);
  Future<Uint8List> fetchPlanFile(String uri) async =>
      _v1._signedBytes(Uri.parse(uri));
  Future<Uint8List> fetchAnimationFile(String versionId, String name) async =>
      _v1.fetchAnimationFile(versionId, name);

  Uri sourceBundleUri(
    String versionId, {
    CatalogFamily family = CatalogFamily.apps,
  }) => hasV1
      ? _v1.sourceBundleUri(versionId, family: family)
      : _v0.sourceBundleUri(versionId);
  Future<List<int>> fetchSourceBundle(
    String versionId, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    CatalogFamily family = CatalogFamily.apps,
  }) => hasV1
      ? _v1._signedBytes(
          _v1.sourceBundleUri(versionId, family: family),
          onProgress: onProgress,
        )
      : _v0.fetchSourceBundle(versionId, onProgress: onProgress);
}
