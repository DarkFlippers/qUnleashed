import '../../../../components/codec/fap/api_version.dart';
import '../catalog_context.dart' show kAppsRoot;

class AtpEntry {
  const AtpEntry({
    required this.appId,
    required this.version,
    required this.folder,
    required this.pack,
    required this.size,
    required this.md5,
    required this.iconBase64,
    required this.name,
  });

  final String appId;
  final String version;
  final String folder;
  final String pack;
  final int size;
  final String md5;
  final String iconBase64;
  final String name;

  String get displayName => name.isNotEmpty ? name : appId;

  String get category => folder.split('/').first.trim();

  String get installDir => folder.isEmpty ? kAppsRoot : '$kAppsRoot/$folder';

  String get installPath => '$installDir/$appId.fap';

  String get archivePath => folder.isEmpty ? '$appId.fap' : '$folder/$appId.fap';

  static AtpEntry? tryParse(String line) {
    final parts = line.split(':');
    if (parts.length < 4) return null;
    final appId = parts[0].trim();
    if (appId.isEmpty) return null;
    return AtpEntry(
      appId: appId,
      version: parts[1].trim(),
      folder: parts[2].trim(),
      pack: parts[3].trim(),
      size: parts.length > 4 ? int.tryParse(parts[4].trim()) ?? 0 : 0,
      md5: parts.length > 5 ? parts[5].trim().toLowerCase() : '',
      iconBase64: parts.length > 6 ? parts[6].trim() : '',
      name: parts.length > 7 ? parts.sublist(7).join(':').trim() : '',
    );
  }
}

class AtpBlock {
  AtpBlock({
    required this.api,
    required this.target,
    required this.tag,
    required this.packs,
    required this.entries,
  });

  final String api;
  final String target;
  final String tag;
  final Map<String, String> packs;
  final List<AtpEntry> entries;

  String? urlFor(AtpEntry entry) => packs[entry.pack];

  (int, int)? get apiVersion => parseApi(api);
}

class AtpIndex {
  const AtpIndex(this.blocks);

  final List<AtpBlock> blocks;

  bool get isEmpty => blocks.isEmpty;

  /// The pack of the release, picked for the hardware target alone: what it was
  /// built against is the firmware's business at load time, not a reason to
  /// hide the list.
  AtpBlock? blockFor({String? target}) {
    if (blocks.isEmpty) return null;
    final matching = [
      for (final block in blocks)
        if (target == null || target.isEmpty || block.target == target) block,
    ];
    final pool = matching.isEmpty ? blocks : matching;
    return pool.reduce((best, block) {
      final left = best.apiVersion;
      final right = block.apiVersion;
      if (left == null || right == null) return best;
      return compareApi(right, left) > 0 ? block : best;
    });
  }

  static AtpIndex parse(String body) {
    final blocks = <AtpBlock>[];
    AtpBlock? current;
    for (final raw in body.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        final header = line.substring(1, line.length - 1).split(' ');
        if (header.length < 3) continue;
        current = AtpBlock(
          api: header[0].trim(),
          target: header[1].trim(),
          tag: header[2].trim(),
          packs: {},
          entries: [],
        );
        blocks.add(current);
        continue;
      }
      if (current == null) continue;
      final pack = _tryParsePack(line);
      if (pack != null) {
        current.packs[pack.$1] = pack.$2;
        continue;
      }
      final entry = AtpEntry.tryParse(line);
      if (entry != null) current.entries.add(entry);
    }
    return AtpIndex(blocks);
  }

  static (String, String)? _tryParsePack(String line) {
    final idx = line.indexOf(':');
    if (idx <= 0) return null;
    final value = line.substring(idx + 1).trim();
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      return null;
    }
    return (line.substring(0, idx).trim(), value);
  }
}
