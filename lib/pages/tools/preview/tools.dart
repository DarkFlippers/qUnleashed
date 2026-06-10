import 'package:flutter/material.dart';

import '../models/tool.dart';
import '../widgets/mf_key_preview.dart';

import 'remote.dart';
import 'flibler.dart';

class ToolPreview extends StatelessWidget {
  const ToolPreview({
    super.key,
    required this.type,
  });

  final ToolPreviewType type;

  @override
  Widget build(BuildContext context) {
    return switch (type) {
      ToolPreviewType.mfKey => const MfKeyPreview(),
      ToolPreviewType.remoteLibrary => const RemoteLibraryPreview(),
      ToolPreviewType.flibler => const FliblerPreview(),
    };
  }
}
