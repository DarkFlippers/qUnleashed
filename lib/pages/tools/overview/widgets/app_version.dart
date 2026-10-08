import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../components/clipboard.dart';
import '../../../../services/build_identity.dart';
import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';

/// The line at the foot of the Tools screen that says which binary this is.
///
/// Version, build number, channel and the short commit, because a bug report
/// that names only the version cannot be traced to a build: the build number is
/// derived from the version under the formula in place today, so every build of
/// `0.14.1` carries `14001` and only the commit separates them. ADR 0014 §3.
///
/// Tapping it copies the whole line. That is the point of showing it — nobody
/// retypes a SHA off a phone screen, and the alternative is a report that says
/// "latest".
class AppVersionLabel extends StatelessWidget {
  const AppVersionLabel({super.key});

  static String get _platformName {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return Platform.operatingSystem;
  }

  /// `qUnleashed for Android v0.14.1+14001 (dev · abc1234)`.
  ///
  /// Built from the existing one-line format rather than a new string, so the
  /// twelve translations of it keep working: the channel and the commit go in
  /// the suffix the format already has a slot for.
  static String _versionText(BuildStamp stamp) {
    final detail = stamp.shortCommit.isEmpty
        ? stamp.channel
        : '${stamp.channel} · ${stamp.shortCommit}';
    return l10n.appVersionLine(
      _platformName,
      stamp.versionWithBuild,
      ' ($detail)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return FutureBuilder<BuildStamp>(
      future: BuildIdentity.resolve(),
      builder: (context, snapshot) {
        final stamp = snapshot.data;
        if (stamp == null) return const SizedBox.shrink();
        final text = _versionText(stamp);
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: GestureDetector(
            onTap: () => copyTextToClipboard(context, text),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 12,
                height: 1.2,
              ),
            ),
          ),
        );
      },
    );
  }
}
