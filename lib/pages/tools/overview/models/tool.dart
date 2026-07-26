import 'package:flutter/widgets.dart';

class ToolGroup {
  const ToolGroup({this.header, required this.items})
    : assert(items.length > 0, 'A tool group must contain at least one item');

  final ToolCardHeader? header;
  final List<ToolItemModel> items;
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
