import 'package:flutter/material.dart';

import '../../../../components/archive/category.dart';
import '../../../../services/localization/l10n.dart';
import '../../../../theme/colors/file_type.dart';
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
      return FileVisual(
        asset: '$_kFileFormatIcon/plugins.svg',
        color: FileTypeColor.application.color,
      );
    case 'txt':
    case 'log':
    case 'md':
      return FileVisual(
        icon: Icons.description_outlined,
        color: FileTypeColor.text.color,
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
      return FileVisual(icon: Icons.code, color: FileTypeColor.code.color);
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'gif':
    case 'bmp':
    case 'webp':
    case 'bmf':
      return FileVisual(
        icon: Icons.image_outlined,
        color: FileTypeColor.image.color,
      );
    case 'mp3':
    case 'wav':
    case 'ogg':
    case 'flac':
      return FileVisual(
        icon: Icons.audiotrack,
        color: FileTypeColor.audio.color,
      );
    case 'zip':
    case 'tar':
    case 'gz':
    case 'tgz':
    case 'rar':
    case '7z':
      return FileVisual(
        icon: Icons.folder_zip_outlined,
        color: FileTypeColor.archive.color,
      );
    case 'bin':
    case 'elf':
    case 'dfu':
    case 'fuf':
      return FileVisual(icon: Icons.memory, color: FileTypeColor.binary.color);
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
