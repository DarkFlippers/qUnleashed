import 'package:flutter/material.dart';

/// Accent colours of the file kinds the browser draws that are not an archive
/// category; those take [ArchiveCategoryColor].
enum FileTypeColor {
  application(Color(0xFF6366F1)),
  text(Color(0xFF64748B)),
  code(Color(0xFF0EA5E9)),
  image(Color(0xFFEC4899)),
  audio(Color(0xFFF97316)),
  archive(Color(0xFFA16207)),
  binary(Color(0xFF78716C));

  const FileTypeColor(this.color);

  final Color color;
}
