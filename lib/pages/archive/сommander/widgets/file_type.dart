import 'package:flutter/material.dart';

import '../../../../theme.dart';
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

/// Resolves the right icon + accent color for a directory entry, recognizing
/// Flipper file formats (.sub/.nfc/.ir/.rfid/.ibtn/.bad) as well as common
/// generic file types.
FileVisual fileVisualFor(RemoteEntry e, QAppColors colors) {
  if (e.isDir) {
    return FileVisual(asset: '$_kFileIcon/folder.svg', color: colors.accent);
  }

  switch (_ext(e.name)) {
    case 'sub':
      return const FileVisual(
        asset: '$_kFileFormatIcon/sub.svg',
        color: Color(0xFF9C6ADE),
      );
    case 'nfc':
      return const FileVisual(
        asset: '$_kFileFormatIcon/nfc.svg',
        color: Color(0xFF3B82F6),
      );
    case 'ir':
      return const FileVisual(
        asset: '$_kFileFormatIcon/ir.svg',
        color: Color(0xFF14B8A6),
      );
    case 'rfid':
      return const FileVisual(
        asset: '$_kFileFormatIcon/rfid.svg',
        color: Color(0xFF22C55E),
      );
    case 'ibtn':
      return const FileVisual(
        asset: '$_kFileFormatIcon/ibutton.svg',
        color: Color(0xFFF59E0B),
      );
    case 'bad':
    case 'badusb':
    case 'u2f':
      return const FileVisual(
        asset: '$_kFileFormatIcon/badusb.svg',
        color: Color(0xFFEF4444),
      );
    case 'fap':
      return const FileVisual(icon: Icons.extension, color: Color(0xFF6366F1));
    case 'txt':
    case 'log':
    case 'md':
      return const FileVisual(
        icon: Icons.description_outlined,
        color: Color(0xFF64748B),
      );
    case 'json':
    case 'js':
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
  if (e.isDir) return 'Folder';
  switch (_ext(e.name)) {
    case 'sub':
      return 'Sub-GHz';
    case 'nfc':
      return 'NFC';
    case 'ir':
      return 'Infrared';
    case 'rfid':
      return 'RFID 125kHz';
    case 'ibtn':
      return 'iButton';
    case 'bad':
    case 'badusb':
      return 'BadUSB';
    case 'u2f':
      return 'U2F';
    case 'fap':
      return 'Application';
    case '':
      return 'File';
    default:
      return '${_ext(e.name).toUpperCase()} file';
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
