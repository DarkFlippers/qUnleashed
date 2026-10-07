import 'package:flutter/material.dart';

import '../../../../components/archive/category.dart';
import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../controller.dart';

/// Visual descriptor for a file/folder row: either a Flipper SVG asset or a
/// Material icon, plus a distinct accent color used for the icon badge.
@immutable
class FileVisual {
  const FileVisual({this.asset, this.icon, required this.color})
    : assert(asset != null || icon != null);

  final String? asset;
  final IconData? icon;
  final Color color;
}

const _kFileIcon = 'assets/ic/file';
const _kFileFormatIcon = 'assets/ic/fileformat';

/// The archive category a file in the browser is drawn as, or null for a
/// file that is not one. A `.txt` is a text file here, not a Bad USB script:
/// the category claims the extension only inside its own folder.
ArchiveCategory? _categoryOf(String ext) => switch (ext) {
  'bad' || 'badusb' || 'u2f' => ArchiveCategory.badusb,
  'txt' => null,
  _ => ArchiveCategory.fromExtension(ext),
};

/// Resolves the icon and accent color for a directory entry: a Flipper file
/// format takes its category's, everything else a generic type's.
FileVisual fileVisualFor(RemoteEntry e, QAppColors colors) {
  if (e.isDir) {
    return FileVisual(asset: '$_kFileIcon/folder.svg', color: colors.accent);
  }

  final ext = _ext(e.name);
  final cat = _categoryOf(ext);
  if (cat != null) return FileVisual(asset: cat.asset, color: cat.color);

  switch (ext) {
    case 'fap':
      return const FileVisual(
        asset: '$_kFileFormatIcon/plugins.svg',
        color: Color(0xFF6366F1),
      );
    case 'txt':
    case 'log':
    case 'md':
      return const FileVisual(
        icon: Icons.description_outlined,
        color: Color(0xFF64748B),
      );
    case 'json':
    case 'c':
    case 'h':
    case 'cpp':
    case 'py':
    case 'sh':
    case 'xml':
    case 'yaml':
    case 'yml':
      return const FileVisual(icon: Icons.code, color: Color(0xFF0EA5E9));
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'gif':
    case 'bmp':
    case 'webp':
    case 'bmf':
      return const FileVisual(
        icon: Icons.image_outlined,
        color: Color(0xFFEC4899),
      );
    case 'mp3':
    case 'wav':
    case 'ogg':
    case 'flac':
      return const FileVisual(icon: Icons.audiotrack, color: Color(0xFFF97316));
    case 'zip':
    case 'tar':
    case 'gz':
    case 'tgz':
    case 'rar':
    case '7z':
      return const FileVisual(
        icon: Icons.folder_zip_outlined,
        color: Color(0xFFA16207),
      );
    case 'bin':
    case 'elf':
    case 'dfu':
    case 'fuf':
      return const FileVisual(icon: Icons.memory, color: Color(0xFF78716C));
    default:
      return FileVisual(
        asset: '$_kFileIcon/default.svg',
        color: colors.textSecondary,
      );
  }
}

String _ext(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// Short human-readable type label (e.g. "Sub-GHz", "NFC", "Folder").
String fileTypeLabel(RemoteEntry e) {
  if (e.isDir) return l10n.typeFolder;
  switch (_ext(e.name)) {
    case 'sub':
      return l10n.typeSubghz;
    case 'nfc':
      return 'NFC';
    case 'ir':
      return l10n.typeInfrared;
    case 'rfid':
      return l10n.typeRfid;
    case 'ibtn':
      return 'iButton';
    case 'bad':
    case 'badusb':
      return l10n.typeBadusb;
    case 'u2f':
      return l10n.typeU2f;
    case 'fap':
      return l10n.typeApplication;
    case '':
      return l10n.typeFile;
    default:
      return l10n.typeExtFile(_ext(e.name).toUpperCase());
  }
}
