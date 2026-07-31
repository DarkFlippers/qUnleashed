import 'dart:io';

import '../core/ufbt_paths.dart';
import 'icon.dart';

class CompiledIcons {
  const CompiledIcons({required this.source, required this.header});

  final File source;
  final File header;
}

class IconAssetsCompiler {
  const IconAssetsCompiler({this.codec = const IconCodec()});

  static const List<String> supportedFormats = ['png'];
  static const int maxImageWidth = 0xFFFF;
  static const int maxImageHeight = 0xFFFF;
  static const String frameRateFile = 'frame_rate';

  final IconCodec codec;

  CompiledIcons compile({
    required Directory inputDir,
    required Directory outputDir,
    required String bundleName,
  }) {
    outputDir.createSync(recursive: true);
    final buffer = StringBuffer()
      ..write('#include "$bundleName.h"\n\n#include <gui/icon_i.h>\n\n');
    final icons = <_IconEntry>[];

    _walk(inputDir, buffer, icons);

    for (final icon in icons) {
      buffer.write(
        'const Icon ${icon.name} = {.width=${icon.width},'
        '.height=${icon.height},.frame_count=${icon.frameCount},'
        '.frame_rate=${icon.frameRate},.frames=_${icon.name}};\n',
      );
    }
    buffer.write('\n');

    final source = File(UfbtPaths.join(outputDir.path, '$bundleName.c'))
      ..writeAsStringSync(buffer.toString());

    final headerBuffer = StringBuffer(
      '#pragma once\n\n#include <gui/icon.h>\n\n',
    );
    for (final icon in icons) {
      headerBuffer.write('extern const Icon ${icon.name};\n');
    }
    final header = File(UfbtPaths.join(outputDir.path, '$bundleName.h'))
      ..writeAsStringSync(headerBuffer.toString());

    return CompiledIcons(source: source, header: header);
  }

  void _walk(Directory dir, StringBuffer buffer, List<_IconEntry> icons) {
    if (!dir.existsSync()) {
      throw FileSystemException('Icons directory not found', dir.path);
    }

    final entries = dir.listSync(followLinks: false)
      ..sort((a, b) => a.path.compareTo(b.path));
    final files = entries.whereType<File>().toList();
    final dirs = entries.whereType<Directory>().toList();

    if (files.isNotEmpty) {
      final frameRate = files.where((f) => _name(f) == frameRateFile).toList();
      if (frameRate.isNotEmpty) {
        _writeAnimation(dir, files, frameRate.first, buffer, icons);
      } else {
        _writeIcons(files, buffer, icons);
      }
    }

    for (final child in dirs) {
      _walk(child, buffer, icons);
    }
  }

  void _writeAnimation(
    Directory dir,
    List<File> files,
    File frameRateFile,
    StringBuffer buffer,
    List<_IconEntry> icons,
  ) {
    final iconName = 'A_${_symbol(_name(dir))}';
    final frameRate = int.parse(frameRateFile.readAsStringSync().trim());
    final frameNames = <String>[];
    int? width;
    int? height;

    for (final file in files) {
      if (!_isSupported(_name(file))) continue;
      final image = _toImage(file);
      width ??= image.width;
      height ??= image.height;
      if (width != image.width || height != image.height) {
        throw FormatException('Animation frames differ in size in ${dir.path}');
      }
      final frameName = '_${iconName}_${frameNames.length}';
      frameNames.add(frameName);
      buffer.write('const uint8_t $frameName[] = ${_carray(image.data)};\n');
    }

    if (frameRate <= 0 || frameNames.isEmpty) {
      throw FormatException('Invalid animation in ${dir.path}');
    }

    buffer
      ..write(
        'const uint8_t* const _$iconName[] = {${frameNames.join(',')}};\n',
      )
      ..write('\n');
    icons.add(
      _IconEntry(iconName, width!, height!, frameRate, frameNames.length),
    );
  }

  void _writeIcons(
    List<File> files,
    StringBuffer buffer,
    List<_IconEntry> icons,
  ) {
    for (final file in files) {
      final fileName = _name(file);
      if (!_isSupported(fileName)) continue;

      final parts = fileName.split('.');
      final iconName =
          'I_${_symbol(parts.sublist(0, parts.length - 1).join('_'))}';
      final image = _toImage(file);
      final frameName = '_${iconName}_0';

      buffer
        ..write('const uint8_t $frameName[] = ${_carray(image.data)};\n')
        ..write('const uint8_t* const _$iconName[] = {$frameName};\n')
        ..write('\n');
      icons.add(_IconEntry(iconName, image.width, image.height, 0, 1));
    }
  }

  FlipperImage _toImage(File file) {
    final image = codec.fileToImage(file);
    if (image.width > maxImageWidth || image.height > maxImageHeight) {
      throw FormatException(
        'Image ${file.path} is too big (${image.width}x${image.height} vs. '
        '${maxImageWidth}x$maxImageHeight)',
      );
    }
    return image;
  }

  static String _carray(List<int> data) {
    final buffer = StringBuffer('{');
    for (final byte in data) {
      buffer.write('0x${byte.toRadixString(16).padLeft(2, '0')},');
    }
    buffer.write('}');
    return buffer.toString();
  }

  static bool _isSupported(String fileName) =>
      supportedFormats.contains(fileName.toLowerCase().split('.').last);

  static String _symbol(String value) => value.replaceAll('-', '_');

  static String _name(FileSystemEntity entity) =>
      entity.path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty).last;
}

class _IconEntry {
  const _IconEntry(
    this.name,
    this.width,
    this.height,
    this.frameRate,
    this.frameCount,
  );

  final String name;
  final int width;
  final int height;
  final int frameRate;
  final int frameCount;
}
