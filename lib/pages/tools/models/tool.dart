import 'package:flutter/widgets.dart';

enum ToolPreviewType {
  mfKey,
  remoteLibrary,
  fileMap,
}

class ToolCardModel {
  const ToolCardModel({
    required this.iconAsset,
    required this.title,
    required this.tool,
  });

  final String iconAsset;
  final String title;
  final ToolItemModel tool;
}

class ToolItemModel {
  const ToolItemModel({
    required this.preview,
    required this.title,
    required this.description,
    this.routeBuilder,
    this.badge,
  });

  final ToolPreviewType preview;
  final String title;
  final String description;
  final WidgetBuilder? routeBuilder;
  final String? badge;
}
