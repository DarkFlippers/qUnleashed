import '../../../archive/models/category.dart';

class MapPin {
  MapPin({
    required this.id,
    required this.name,
    required this.path,
    required this.fileName,
    required this.extension,
    required this.subFolder,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.content,
    this.remotePath,
    this.frequency,
    this.protocol,
    this.bit,
    this.uid,
    this.key,
    this.keyType,
  });

  final String id;
  final String name;
  final String path;
  final String fileName;
  final String extension;
  final String subFolder;
  final ArchiveCategory category;
  final double latitude;
  final double longitude;
  final String content;
  final String? remotePath;
  final String? frequency;
  final String? protocol;
  final String? bit;
  final String? uid;
  final String? key;
  final String? keyType;
}

class MapPickTarget {
  const MapPickTarget({
    required this.localPath,
    required this.displayName,
    this.remotePath,
    this.initialLatitude,
    this.initialLongitude,
  });

  final String localPath;
  final String displayName;
  final String? remotePath;
  final double? initialLatitude;
  final double? initialLongitude;
}
