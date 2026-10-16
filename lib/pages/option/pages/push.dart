import 'dart:async';

import 'package:flutter/material.dart';

import '../../../components/cardlist.dart';
import '../../../components/permission_notice.dart';
import '../../../services/localization/l10n.dart';
import '../../../services/notifications/push_service.dart';
import '../../../services/permissions/permission.dart';
import '../../../services/permissions/scope.dart';
import '../../../theme/theme.dart';

class _Toggle {
  const _Toggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
}

class NotificationsSettingsPage extends StatefulWidget {
  const NotificationsSettingsPage({super.key});

  @override
  State<NotificationsSettingsPage> createState() =>
      _NotificationsSettingsPageState();
}

class _NotificationsSettingsPageState extends State<NotificationsSettingsPage> {
  bool _appReleases = true;
  bool _appDev = false;
  bool _firmwareReleases = true;
  bool _firmwareDev = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The shared route, which also tells the user when it cannot open.
  void _openSettings() =>
      unawaited(openPermissionSettings(context, '[Push] opening app settings'));

  Future<void> _load() async {
    final appReleases = await PushService.instance.isAppReleasesEnabled();
    final appDev = await PushService.instance.isAppDevEnabled();
    final firmwareReleases = await PushService.instance
        .isFirmwareReleasesEnabled();
    final firmwareDev = await PushService.instance.isFirmwareDevEnabled();
    if (mounted) {
      setState(() {
        _appReleases = appReleases;
        _appDev = appDev;
        _firmwareReleases = firmwareReleases;
        _firmwareDev = firmwareDev;
      });
    }
  }

  void _setAppReleases(bool value) {
    setState(() => _appReleases = value);
    PushService.instance.setAppReleasesEnabled(value);
  }

  void _setAppDev(bool value) {
    setState(() => _appDev = value);
    PushService.instance.setAppDevEnabled(value);
  }

  void _setFirmwareReleases(bool value) {
    setState(() => _firmwareReleases = value);
    PushService.instance.setFirmwareReleasesEnabled(value);
  }

  void _setFirmwareDev(bool value) {
    setState(() => _firmwareDev = value);
    PushService.instance.setFirmwareDevEnabled(value);
  }

  Widget _tile(BuildContext context, _Toggle t) {
    final colors = context.appColors;
    final enabled = t.onChanged != null;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                t.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled ? colors.textPrimary : colors.textMuted,
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                t.subtitle,
                maxLines: 3,
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
        Switch(
          value: t.value,
          activeThumbColor: colors.accent,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: t.onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final unavailable = PushService.isUnavailable;
    // topicsSupported, not isSupported: macOS can raise a local notification
    // but can never receive a remote one, so the switches here would persist
    // a preference and then do nothing. pushUnsupportedPlatform already says
    // exactly that.
    final supported = PushService.topicsSupported && !unavailable;
    // A refused notification permission is the one cause this page used to
    // get wrong. `isUnavailable` is set for any throw out of `start` - a
    // missing Play Services, a network blip during Firebase init, a denial -
    // and the page asserted "this build is not signed for push" for all of
    // them. A confident claim about the wrong cause stops the reader
    // looking, so the denial is named first and the build sentence is kept
    // only for the case it is actually true of. #351.
    // `outcomeOf`, not `shouldNotice`. A dismissal is the user asking the
    // notice to stop nagging; it is not permission to state a false cause
    // instead. Keyed off `shouldNotice` this flipped to false on the first tap
    // of Dismiss and the page went straight back to asserting the
    // unsigned-build sentence to a user whose permission was still refused.
    final denied =
        PermissionScope.maybeOf(context)
            ?.outcomeOf(AppPermission.pushNotifications)
            .warrantsNotice ??
        false;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(context.l10n.settingsNotificationsTitle),
        backgroundColor: colors.background,
        surfaceTintColor: colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          PermissionNotice(
            permission: AppPermission.pushNotifications,
            severity: PermissionNoticeSeverity.informational,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            icon: Icons.notifications_off_outlined,
            title: context.l10n.permissionPushDeniedTitle,
            body: context.l10n.permissionPushDeniedBody,
            actionLabel: context.l10n.permissionPushTurnOn,
            onAction: _openSettings,
          ),
          // Only once the denial has been ruled out. Both of these are
          // true statements about a build or a platform; neither is true
          // of a user who said no, and saying one to them is the defect.
          if (!supported && !denied)
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 0, 26, 8),
              child: Text(
                unavailable
                    ? context.l10n.pushUnsignedBuild
                    : context.l10n.pushUnsupportedPlatform,
                style: TextStyle(fontSize: 12.5, color: colors.textMuted),
              ),
            ),
          GroupedCardList<_Toggle>(
            title: context.l10n.pushGroupApplication,
            items: [
              _Toggle(
                title: context.l10n.pushAppReleases,
                subtitle: context.l10n.pushAppReleasesSubtitle,
                value: _appReleases,
                onChanged: supported ? _setAppReleases : null,
              ),
              _Toggle(
                title: context.l10n.pushDevChannel,
                subtitle: context.l10n.pushAppDevSubtitle,
                value: _appDev,
                onChanged: (supported && _appReleases) ? _setAppDev : null,
              ),
            ],
            onTap: (t) =>
                t.onChanged == null ? null : () => t.onChanged!(!t.value),
            itemBuilder: _tile,
          ),
          const SizedBox(height: 10),
          GroupedCardList<_Toggle>(
            title: context.l10n.pushGroupFirmware,
            items: [
              _Toggle(
                title: context.l10n.pushFirmwareReleases,
                subtitle: context.l10n.pushFirmwareReleasesSubtitle,
                value: _firmwareReleases,
                onChanged: supported ? _setFirmwareReleases : null,
              ),
              _Toggle(
                title: context.l10n.pushDevChannel,
                subtitle: context.l10n.pushFirmwareDevSubtitle,
                value: _firmwareDev,
                onChanged: (supported && _firmwareReleases)
                    ? _setFirmwareDev
                    : null,
              ),
            ],
            onTap: (t) =>
                t.onChanged == null ? null : () => t.onChanged!(!t.value),
            itemBuilder: _tile,
          ),
        ],
      ),
    );
  }
}
