import 'package:flutter/widgets.dart';

enum ToolPreviewType {
  mfKey,
  remoteLibrary,
  flibler,
}

sealed class ToolCardModel {
  const ToolCardModel();
}

class ToolCardGroup extends ToolCardModel {
  const ToolCardGroup({
    required this.header,
    required this.items,
  }) : assert(items.length > 0, 'A tool group must contain at least one item');

  final ToolCardHeader header;
  final List<ToolItemModel> items;
}

class ToolCard extends ToolCardModel {
  const ToolCard({
    required this.iconAsset,
    required this.iconColor,
    required this.title,
    required this.description,
    this.routeBuilder,
    this.onTap,
    this.badge,
  });

  final String iconAsset;
  final Color iconColor;
  final String title;
  final String description;
  final WidgetBuilder? routeBuilder;
  final Future<void> Function(BuildContext context)? onTap;
  final String? badge;
}

class ToolCardHeader {
  const ToolCardHeader({
    required this.iconAsset,
    required this.iconColor,
    required this.title,
  });

  final String iconAsset;
  final Color iconColor;
  final String title;
}

class ToolItemModel {
  const ToolItemModel({
    required this.title,
    required this.description,
    this.preview,
    this.iconAsset,
    this.iconColor,
    this.routeBuilder,
    this.onTap,
    this.badge,
  }) : assert(
          (preview == null) != (iconAsset == null),
          'A tool item needs exactly one leading visual: a preview or an icon',
        );

  final String title;
  final String description;
  final ToolPreviewType? preview;
  final String? iconAsset;
  final Color? iconColor;
  final WidgetBuilder? routeBuilder;
  final Future<void> Function(BuildContext context)? onTap;
  final String? badge;
}
