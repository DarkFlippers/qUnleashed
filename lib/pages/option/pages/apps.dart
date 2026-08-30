import 'dart:async';

import 'package:flutter/material.dart';

import '../../../components/cardlist.dart';
import '../../../services/localization/l10n.dart';
import '../../../theme/theme.dart';
import '../../apps/data/apps_backend.dart';
import '../../apps/data/catalog_mode.dart';

class AppsSettingsPage extends StatefulWidget {
  const AppsSettingsPage({super.key});

  @override
  State<AppsSettingsPage> createState() => _AppsSettingsPageState();
}

class _AppsSettingsPageState extends State<AppsSettingsPage> {
  static String _title(L10n s, CatalogModePreference value) => switch (value) {
    CatalogModePreference.auto => s.appsModeAuto,
    CatalogModePreference.catalog => s.appsModeCatalog,
    CatalogModePreference.sourceBuild => s.appsModeSourceBuild,
    CatalogModePreference.manager => s.appsModeManager,
  };

  static String _subtitle(L10n s, CatalogModePreference value) =>
      switch (value) {
        CatalogModePreference.auto => s.appsModeAutoSubtitle,
        CatalogModePreference.catalog => s.appsModeCatalogSubtitle,
        CatalogModePreference.sourceBuild => s.appsModeSourceBuildSubtitle,
        CatalogModePreference.manager => s.appsModeManagerSubtitle,
      };

  final AppsBackend _backend = AppsBackend.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _backend.loadPreference();
      if (mounted) setState(() {});
      // The page can be the first screen that asks, so the mode is resolved
      // here too instead of waiting for the catalog to be opened.
      unawaited(_backend.resolveMode());
    });
  }

  Future<void> _select(CatalogModePreference value) async {
    await _backend.setPreference(value);
    if (mounted) setState(() {});
  }

  Future<void> _recheck() async {
    await _backend.resolveMode(force: true);
    if (mounted) setState(() {});
  }

  Widget _modeTile(BuildContext context, CatalogModePreference value) {
    final colors = context.appColors;
    final selected = _backend.preference == value;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _title(context.l10n, value),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _subtitle(context.l10n, value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 12,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            size: 22,
            color: selected ? colors.accent : colors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _statusRow(
    BuildContext context,
    String label,
    String value, {
    bool ok = false,
  }) {
    final colors = context.appColors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              height: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            color: ok ? colors.success : colors.textMuted,
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }

  Widget _apiChips(BuildContext context) {
    final colors = context.appColors;
    final target = _backend.deviceTarget;
    final apis =
        {
          for (final sdk in _backend.serverSdks)
            if (target == null || sdk.target == target) sdk.api,
        }.toList()..sort((a, b) => b.compareTo(a));
    if (apis.isEmpty) {
      return SizedBox(
        width: double.infinity,
        child: Text(
          _backend.catalogOffline
              ? context.l10n.appsStatusNoAnswer
              : context.l10n.appsStatusNone,
          style: TextStyle(color: colors.textMuted, fontSize: 12.5),
        ),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final api in apis)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: api == _backend.api.api ? colors.accent : colors.card,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              api,
              style: TextStyle(
                color: api == _backend.api.api
                    ? colors.onAccent
                    : colors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: _backend.mode,
      builder: (context, _) {
        final resolving = _backend.mode.value == CatalogMode.resolving;
        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            title: Text(context.l10n.settingsAppsTitle),
            backgroundColor: colors.background,
            surfaceTintColor: colors.transparent,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 10),
            children: [
              GroupedCardList<CatalogModePreference>(
                title: context.l10n.appsGroupCatalogMode,
                items: CatalogModePreference.values,
                onTap: (value) => () => unawaited(_select(value)),
                itemBuilder: _modeTile,
              ),
              const SizedBox(height: 14),
              GroupedCardList<Widget>(
                title: context.l10n.appsGroupStatus,
                items: [
                  _statusRow(
                    context,
                    context.l10n.appsStatusMode,
                    _backend.mode.value.label,
                    ok: _backend.mode.value == CatalogMode.normal,
                  ),
                  _statusRow(
                    context,
                    context.l10n.appsStatusFirmware,
                    _backend.deviceApi == null
                        ? context.l10n.appsStatusNotConnected
                        : '${_backend.deviceApi} · ${_backend.deviceTarget}',
                    ok: _backend.deviceApi != null,
                  ),
                  _statusRow(
                    context,
                    context.l10n.appsStatusCatalog,
                    _backend.catalogOffline
                        ? context.l10n.appsStatusNoAnswer
                        : _backend.serverApi ?? '—',
                    ok: !_backend.catalogOffline,
                  ),
                ],
                itemBuilder: (context, tile) => tile,
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: kGroupedHorizontalPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: kGroupedTitlePadding,
                      child: Text(
                        context.l10n.appsCatalogApis,
                        style: TextStyle(
                          fontSize: kGroupedTitleSize,
                          fontWeight: kGroupedTitleWeight,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    _apiChips(context),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: kGroupedHorizontalPadding,
                ),
                child: SizedBox(
                  width: 200,
                  child: OutlinedButton(
                    onPressed: resolving ? null : () => unawaited(_recheck()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.textSecondary,
                      side: BorderSide(color: colors.divider),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      resolving
                          ? context.l10n.appsChecking
                          : context.l10n.appsRecheck,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}
