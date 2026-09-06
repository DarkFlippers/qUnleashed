import 'dart:async';

import 'package:flutter/material.dart';

import '../../../components/archive/category.dart';
import '../../../components/archive/models/key.dart';
import '../../../components/cardlist.dart';
import '../../../components/filelist/empty_view.dart';
import '../../../components/icon.dart';
import '../../../services/home_widget/service.dart';
import '../../../services/localization/l10n.dart';
import '../../../theme/theme.dart';
import '../overview/controller.dart';

/// Picks the file a home-screen widget added from the launcher will send.
/// Lists every archive key the Flipper can be handed over RPC, by category,
/// straight from the app's own archive.
class HomeWidgetPickerPage extends StatefulWidget {
  const HomeWidgetPickerPage({
    super.key,
    required this.widgetId,
    required this.controller,
  });

  final int widgetId;
  final ArchiveController controller;

  @override
  State<HomeWidgetPickerPage> createState() => _HomeWidgetPickerPageState();
}

class _HomeWidgetPickerPageState extends State<HomeWidgetPickerPage> {
  ArchiveController get _ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChanged);
    // Sub-GHz keys qualify by the protocol inside the file; they join the
    // list as their metadata gets parsed.
    for (final cat in ArchiveCategory.values) {
      if (cat.launch.hasProtocolRules) unawaited(_ctrl.loadMetaForCategory(cat));
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onChanged);
    super.dispose();
  }

  List<ArchiveKey> _keysFor(ArchiveCategory cat) => [
    for (final k in _ctrl.keysFor(cat))
      if (!k.isDeleted && k.launchMethod == LaunchMethod.rpc) k,
  ];

  Future<void> _pick(ArchiveKey key) async {
    await HomeWidgetService.instance.configure(
      widget.widgetId,
      WidgetKey.fromArchiveKey(key),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Widget _tile(BuildContext context, ArchiveKey k) {
    final colors = context.appColors;
    return Row(
      children: [
        QIconBadge(asset: k.category.asset, color: k.category.color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                k.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                k.remotePath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final groups = [
      for (final cat in ArchiveCategory.values)
        if (cat.emulatable) (cat: cat, keys: _keysFor(cat)),
    ].where((g) => g.keys.isNotEmpty).toList();

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(context.l10n.homeWidgetPickTitle),
        backgroundColor: colors.background,
        surfaceTintColor: colors.transparent,
      ),
      body: groups.isEmpty
          ? ArchiveEmptyView(
              icon: Icons.widgets_outlined,
              title: context.l10n.homeWidgetPickEmpty,
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 10),
              children: [
                for (var i = 0; i < groups.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  GroupedCardList<ArchiveKey>(
                    title: groups[i].cat.title,
                    items: groups[i].keys,
                    onTap: (k) => () => _pick(k),
                    itemBuilder: _tile,
                  ),
                ],
              ],
            ),
    );
  }
}
