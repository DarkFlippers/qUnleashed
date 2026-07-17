import 'package:flutter/material.dart';

import '../../../theme/theme.dart';

class SettingsGroupCorners extends InheritedWidget {
  const SettingsGroupCorners({
    super.key,
    required this.radius,
    required super.child,
  });

  final BorderRadius radius;

  static const outer = Radius.circular(12);
  static const inner = Radius.circular(4);

  static BorderRadius of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SettingsGroupCorners>()
          ?.radius ??
      const BorderRadius.all(outer);

  @override
  bool updateShouldNotify(SettingsGroupCorners oldWidget) =>
      radius != oldWidget.radius;
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final last = children.length - 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
              child: Text(
                title!,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
            ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 3),
            SettingsGroupCorners(
              radius: BorderRadius.vertical(
                top: i == 0
                    ? SettingsGroupCorners.outer
                    : SettingsGroupCorners.inner,
                bottom: i == last
                    ? SettingsGroupCorners.outer
                    : SettingsGroupCorners.inner,
              ),
              child: children[i],
            ),
          ],
        ],
      ),
    );
  }
}
