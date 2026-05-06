import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

// =============================================================================
// Release data fetched from GitHub API
// =============================================================================

class FirmwareRelease {
  final String version;
  final String tagName;
  final String? changelog;
  final String? downloadUrl;

  const FirmwareRelease({
    required this.version,
    required this.tagName,
    this.changelog,
    this.downloadUrl,
  });
}

// =============================================================================
// Config models
// =============================================================================

class FirmwareColors {
  final Color primary;
  final Color secondary;
  final Color tertiary;

  const FirmwareColors({
    required this.primary,
    required this.secondary,
    required this.tertiary,
  });

  factory FirmwareColors.fromJson(Map<String, dynamic> json) => FirmwareColors(
        primary: _hex(json['primary'] as String),
        secondary: _hex(json['secondary'] as String),
        tertiary: _hex(json['tertiary'] as String),
      );
}

class FirmwareEntry {
  final String name;
  final String shortName;
  final String icon;

  /// Human-readable GitHub releases URL, e.g.
  /// https://github.com/DarkFlippers/unleashed-firmware/releases
  final String releaseUrl;
  final FirmwareColors colors;

  const FirmwareEntry({
    required this.name,
    required this.shortName,
    required this.icon,
    required this.releaseUrl,
    required this.colors,
  });

  String get assetPath => 'assets/firmware/$icon';

  /// Converts GitHub releases page URL → GitHub REST API URL for latest release.
  /// https://github.com/OWNER/REPO/releases → https://api.github.com/repos/OWNER/REPO/releases/latest
  String get githubApiUrl {
    final uri = Uri.tryParse(releaseUrl);
    if (uri != null && uri.host == 'github.com') {
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.length >= 2) {
        return 'https://api.github.com/repos/${segs[0]}/${segs[1]}/releases/latest';
      }
    }
    return releaseUrl;
  }

  /// Fetches the latest release from GitHub and returns a [FirmwareRelease],
  /// or null on any error.
  Future<FirmwareRelease?> fetchRelease() async {
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(githubApiUrl));
      req.headers.set(HttpHeaders.userAgentHeader, 'qunleashed-app');
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github.v3+json');
      final res = await req.close();
      if (res.statusCode != 200) {
        client.close();
        return null;
      }
      final body = await res.transform(utf8.decoder).join();
      client.close();

      final data = jsonDecode(body) as Map<String, dynamic>;

      final tagName = (data['tag_name'] as String?) ?? '';
      final version = _extractVersion(tagName);
      final changelog = data['body'] as String?;

      // Find the best firmware asset:
      //   1. .tgz containing "f7" and "update"
      //   2. any .tgz
      //   3. .zip as fallback
      final assets = (data['assets'] as List<dynamic>?) ?? [];
      String? downloadUrl = _findAsset(assets, (n) => n.endsWith('.tgz') && n.contains('f7') && n.contains('update'))
          ?? _findAsset(assets, (n) => n.endsWith('.tgz'))
          ?? _findAsset(assets, (n) => n.endsWith('.zip'));

      return FirmwareRelease(
        version: version,
        tagName: tagName,
        changelog: changelog,
        downloadUrl: downloadUrl,
      );
    } catch (_) {
      return null;
    }
  }

  static String? _findAsset(List<dynamic> assets, bool Function(String name) test) {
    for (final asset in assets) {
      final name = (asset['name'] as String?) ?? '';
      if (test(name)) return asset['browser_download_url'] as String?;
    }
    return null;
  }

  /// Extracts a semver-like version string from a GitHub tag name.
  /// "unleashed-v0.99.1" → "0.99.1"
  /// "v1.0.2"            → "1.0.2"
  /// "1.0.2"             → "1.0.2"
  static String _extractVersion(String tagName) {
    final match = RegExp(r'\d+\.\d+[\d.]*').firstMatch(tagName);
    return match?.group(0) ?? tagName;
  }

  factory FirmwareEntry.fromJson(Map<String, dynamic> json) => FirmwareEntry(
        name: json['name'] as String,
        shortName: json['shortName'] as String,
        icon: json['icon'] as String,
        releaseUrl: json['releaseUrl'] as String,
        colors: FirmwareColors.fromJson(json['colors'] as Map<String, dynamic>),
      );
}

class FirmwareConfig {
  final List<FirmwareEntry> firmwares;

  const FirmwareConfig({required this.firmwares});

  bool get isSingle => firmwares.length == 1;

  factory FirmwareConfig.fromJson(Map<String, dynamic> json) => FirmwareConfig(
        firmwares: (json['firmwares'] as List<dynamic>)
            .map((e) => FirmwareEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static Future<FirmwareConfig> load() async {
    final raw = await rootBundle.loadString('assets/firmware_config.json');
    return FirmwareConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}

// =============================================================================
// Helpers
// =============================================================================

Color _hex(String hex) {
  final s = hex.replaceFirst('#', '');
  return Color(int.parse('FF$s', radix: 16));
}
