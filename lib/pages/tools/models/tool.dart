import 'package:flutter/widgets.dart';

enum ToolPreviewType {
  mfKey,
  remoteLibrary,
}

class ToolCardModel {
  const ToolCardModel({
    required this.iconAsset,
    required this.iconColor,
    required this.title,
    required this.tool,
    this.compact = false,
  });

  final String iconAsset;
  final Color iconColor;
  final String title;
  final ToolItemModel tool;
  final bool compact;
}

class ToolItemModel {
  const ToolItemModel({
    this.preview,
    required this.title,
    required this.description,
    this.routeBuilder,
    this.badge,
  });

  final ToolPreviewType? preview;
  final String title;
  final String description;
  final WidgetBuilder? routeBuilder;
  final String? badge;
}
