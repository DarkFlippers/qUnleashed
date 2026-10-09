import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../components/clipboard.dart';
import '../../../../services/build_identity.dart';
import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../../../../services/guarded.dart';

/// The line at the foot of the Tools screen that says which binary this is.
///
/// Version, build number, channel and the short commit, because a bug report
/// that names only the version cannot be traced to a build. The number orders
/// builds (0014 §6) and the commit names the tree they came from (§3), and a
/// dev build's name carries neither — §2 gives every dev build in a cycle the
/// same version.
///
/// Tapping it copies the whole line. That is the point of showing it — nobody
/// retypes a SHA off a phone screen, and the alternative is a report that says
/// "latest".
///
/// Stateful only to hold the future. Created in [State.initState] rather than
/// in `build`, because a fresh future per build resets the [FutureBuilder] to
/// `waiting` and collapses the line for a frame — and because a platform call
/// from `build` is the `#135/#136` shape CLAUDE.md lists, which
/// `test/build_io_budget_test.dart` cannot see here: its scan is per file, so a
/// call into another library does not count. The `const` constructor at the
/// call site hid the cost rather than removing it.
class AppVersionLabel extends StatefulWidget {
  const AppVersionLabel({super.key, this.stamp});

  /// The identity to show, or null to read it.
  ///
  /// A parameter whose default is the reach, which is the shape
  /// [0002](../../../../../docs/adr/0002-dependencies-are-passed-in.md)
  /// prescribes. It is here for the tests rather than for a second caller:
  /// `package_info_plus` caches its answer in a static of its own, so mocking
  /// the platform channel per test fights the plugin instead of exercising
  /// this widget — and the branches worth covering are the formatting ones.
  final BuildStamp? stamp;

  @override
  State<AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<AppVersionLabel> {
  late final Future<BuildStamp> _stamp = widget.stamp == null
      ? BuildIdentity.resolve()
      : Future.value(widget.stamp);

  static String get _platformName {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return Platform.operatingSystem;
  }

  /// `qUnleashed for Android v0.14.1-dev (14001 · abc1234)`.
  ///
  /// Built from the existing one-line format rather than a new string, so the
  /// translations of it keep working: the version takes the channel suffix the
  /// way 0014 §2 spells it, and the build number and commit go in the slot the
  /// format already has for a bracketed suffix.
  static String _versionText(BuildStamp stamp) {
    final detail = [
      if (stamp.build.isNotEmpty) stamp.build,
      if (stamp.shortCommit.isNotEmpty) stamp.shortCommit,
    ].join(' · ');
    return l10n.appVersionLine(
      _platformName,
      stamp.displayVersion,
      detail.isEmpty ? '' : ' ($detail)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return FutureBuilder<BuildStamp>(
      future: _stamp,
      builder: (context, snapshot) {
        final stamp = snapshot.data;
        if (stamp == null) return const SizedBox.shrink();
        final text = _versionText(stamp);
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          // Semantics, because a bare Text with a tap handler announces
          // nothing: the doc above says tapping it is the point, and a screen
          // reader had no way to find that out.
          child: GestureDetector(
            // `guarded`, because the slot is a VoidCallback and the future would
            // otherwise be dropped - landing as `[uncaught]` with nothing naming the
            // operation. The three other copies of this call in the diff are wrapped
            // the same way; this one was missed. CLAUDE.md, #23.
            onTap: () => guarded(
              '[About] copying the build identity',
              () => copyTextToClipboard(context, text),
            ),
            child: Semantics(
              button: true,
              label: context.l10n.commonCopy,
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
          ),
        );
      },
    );
  }
}
