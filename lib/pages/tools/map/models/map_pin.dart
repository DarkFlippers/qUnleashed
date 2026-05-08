import '../../../archive/models/archive_category.dart';

class MapPin {
  MapPin({
    required this.id,
    required this.name,
    required this.path,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.content,
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
  final ArchiveCategory category;
  final double latitude;
  final double longitude;
  final String content;
  final String? frequency;
  final String? protocol;
  final String? bit;
  final String? uid;
  final String? key;
  final String? keyType;
}
