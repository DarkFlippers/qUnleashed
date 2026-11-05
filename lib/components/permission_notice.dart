import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;

import '../services/guarded.dart';
import '../services/localization/l10n.dart';
import '../services/permissions/center.dart';
import '../services/permissions/permission.dart';
import '../services/permissions/scope.dart';
import '../theme/theme.dart';
import 'notification.dart';
import 'progress_button.dart';

/// The notice surface: a 12 % fill, a 40 % border and radius 8, at padding 12.
///
/// One function because this shape appeared three times in new code — the
/// notice body, the gate's hint box, and the explainer — before it was worth
/// naming. It is also `_StrandedNotice`'s anatomy, which still builds its own
/// copy; rebuilding that on this is the follow-up the notice's doc mentions.
Widget _noticeBox({required Color tone, required Widget child}) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: tone.withValues(alpha: 0.4)),
    ),
    child: child,
  );
}

/// The round glyph a blocking screen or an explainer leads with.
Widget permissionBadge({
  required IconData icon,
  required Color tone,
  required double size,
}) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: tone.withValues(alpha: 0.12),
      border: Border.all(color: tone.withValues(alpha: 0.4)),
    ),
    child: Icon(icon, size: size * 0.46, color: tone),
  );
}

/// Opens this app's page in system settings, and says so when it cannot.
///
/// The one route every permission surface uses. Each of them had its own
/// `guarded(... openAppSettings)`, which never rejects — but a failure there
/// reached only the log, and on a blocking notice or the Tier 1 gate that
/// button is the user's only way forward. A dead button with no feedback is
/// CLAUDE.md's #118/#134 shape one step removed: the UI is waiting and nothing
/// resolves it.
///
/// [what] names the operation in the log line, so a report says which surface
/// the tap came from.
Future<void> openPermissionSettings(BuildContext context, String what) async {
  await guarded(
    what,
    openAppSettings,
    onFailure: (_) {
      if (!context.mounted) return;
      // A notification and not a dialog: the notice itself stays on screen
      // with its button, so this is a comment on the tap rather than a new
      // thing to dismiss. The sentence names the manual route, because that
      // is the only remaining one.
      context.showNotification(
        context.l10n.permissionSettingsOpenFailed,
        type: QNotificationType.error,
        duration: const Duration(seconds: 5),
      );
    },
  );
}

/// How a permission notice is drawn. One of three, and the choice is the
/// [PermissionTier], not how bad the denial feels.
///
/// The anatomy is `_StrandedNotice`'s, which was the first of these in the
/// codebase: a 12 % fill, a 40 % border, radius 8, 12 padding and an 18 px
/// icon. What this adds is a heading line and up to two actions.
///
/// Those figures are a second copy, not a shared one - `_StrandedNotice`
/// still builds its own `Container`. Rebuilding it on this widget is the
/// obvious follow-up and is deliberately not part of #351; until then a
/// theme change to either side makes the two drift.
enum PermissionNoticeSeverity {
  /// The user asked for something that cannot happen. Accent fill, an action,
  /// and no dismiss — the thing they wanted still does not work, so putting
  /// the notice away would only hide the reason.
  ///
  /// Tier 2's severity, and the body of Tier 1's screen.
  blocking,

  /// Nothing the user asked for failed. Info fill, dismissible.
  ///
  /// Tier 3 where there is something to turn on.
  informational,

  /// A capability went quietly and there is nothing to tap. Danger fill, no
  /// action.
  ///
  /// Tier 3 where the app cannot offer a route — the foreground service
  /// running without its location type is the case this exists for.
  degraded,
}

/// A notice that says what is out of reach, and what to do about it.
///
/// The shared element #351 asks for, and the reason it is one widget: all five
/// sites want the same three things first — say what is out of reach, name
/// what still works, and route into system settings — and without a shared
/// one each feature invents its own. Four of the five had invented nothing at
/// all.
///
/// Not a toast. `QNotification` times out after two seconds, and these must
/// stay until the user resolves them or puts them away.
///
/// Rules this widget keeps so no caller has to remember them:
///
///  * **It draws nothing unless the outcome warrants it.** An unknown or
///    unavailable permission is silent, so a surface can mount this
///    unconditionally and a denial is the only thing that makes it appear.
///    Guessing is the wrong-cause failure the issue is about.
///  * **It redraws itself.** It listens to [PermissionCenter], so a grant made
///    in system settings clears it when the user comes back — without the
///    screen being rebuilt for any other reason.
///  * **A dismissal is per install**, and [dismissible] decides whether one
///    is offered at all. [PermissionCenter.dismiss] persists it.
///
/// What it deliberately does **not** do is name the permission constant.
/// "MANAGE_EXTERNAL_STORAGE" means nothing to a user; [title] says what is out
/// of reach instead.
class PermissionNotice extends StatelessWidget {
  const PermissionNotice({
    super.key,
    required this.permission,
    required this.severity,
    required this.title,
    required this.body,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.dismissible,
    this.padding = const EdgeInsets.only(top: 14),
  });

  /// Which permission this is about. Decides whether anything is drawn, and
  /// what a dismissal is remembered against.
  final AppPermission permission;

  final PermissionNoticeSeverity severity;

  /// What is out of reach, in the user's terms. One line.
  final String title;

  /// What still works, and how to fix it. The sentence that stops a denial
  /// reading as a broken app.
  final String body;

  /// Overrides the severity's default glyph, for a surface where a more
  /// specific one says more — a crossed-out Bluetooth mark on the picker.
  final IconData? icon;

  /// The primary action's label. Omitted for
  /// [PermissionNoticeSeverity.degraded], which has nothing to offer.
  final String? actionLabel;

  final VoidCallback? onAction;

  /// Whether the user may put this notice away for good.
  ///
  /// Defaults to the permission's tier rather than to the severity, and the
  /// distinction is a bug that shipped: dismissibility used to be derived from
  /// [severity], so choosing `degraded` for a Tier 3 permission silently
  /// removed the Dismiss button and left a permanent red warning on Settings
  /// -> Device for something the tier's own definition calls "dismissible and
  /// never nags". Severity is how a notice is drawn; whether it can be put
  /// away is a fact about what the user lost.
  ///
  /// A feature gate is never dismissible whatever is passed: the thing the
  /// user asked for still does not work, so hiding the reason would only
  /// strand them.
  final bool? dismissible;

  /// Space above the notice, so a caller that stacks it under a text field
  /// does not have to wrap it.
  ///
  /// This belongs to the notice and not to the host, which is why it exists.
  /// A caller that passes `EdgeInsets.zero` and wraps the widget in its own
  /// `Padding` leaves that padding behind when nothing is drawn - the notice
  /// returns `SizedBox.shrink()` *inside* it - so every user on the normal
  /// granted path pays for dead whitespace.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final center = PermissionScope.maybeOf(context);
    // No scope at all draws nothing, the same as an unknown outcome. A widget
    // test that puts up a bare `MaterialApp` is the case, and `L10nContext`
    // makes the same choice for the same reason.
    if (center == null) return const SizedBox.shrink();

    // The cheap test first. Both branches below require a denial, and this is
    // the path every user who granted everything takes on six surfaces - so
    // it is one map lookup and an enum compare, with the tier never computed.
    if (!center.isDenied(permission)) return const SizedBox.shrink();
    // A dismissible notice respects the dismissal; a gate does not, because
    // the thing the user asked for still does not work and hiding the reason
    // would only strand them.
    final canDismiss = _canDismiss(center);
    if (canDismiss && center.isDismissed(permission)) {
      return const SizedBox.shrink();
    }

    return Padding(padding: padding, child: _body(context, center, canDismiss));
  }

  /// Whether a Dismiss button is offered.
  ///
  /// A feature gate never is, whatever the caller asked for. Otherwise the
  /// caller's choice wins, and failing that the tier decides - which is what
  /// keeps `PermissionTier.informOnce`'s promise executable rather than prose.
  bool _canDismiss(PermissionCenter center) {
    final tier = center.tierOf(permission);
    if (tier != PermissionTier.informOnce) return false;
    return dismissible ?? true;
  }

  Widget _body(BuildContext context, PermissionCenter center, bool canDismiss) {
    final colors = context.appColors;
    final tone = _tone(colors);
    return _noticeBox(
      tone: tone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Every meaning colour carries a glyph as well. `success` and
              // `danger` are not reliably distinguishable by hue alone, and
              // two of the three severities here are reds.
              Icon(icon ?? _glyph, size: 18, color: tone),
              const SizedBox(width: 10),
              Expanded(child: _text(context, colors)),
            ],
          ),
          if (onAction != null || canDismiss) ...[
            const SizedBox(height: 10),
            _actions(context, center, tone, colors, canDismiss),
          ],
        ],
      ),
    );
  }

  Widget _text(BuildContext context, QAppColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 13,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        // Selectable, like `_StrandedNotice`'s body was: these sentences name
        // a folder or a settings path the user may want to copy.
        SelectableText(
          body,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 13,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _actions(
    BuildContext context,
    PermissionCenter center,
    Color tone,
    QAppColors colors,
    bool canDismiss,
  ) {
    final action = onAction;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (action != null)
          OutlinedButton(
            onPressed: action,
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.textPrimary,
              side: BorderSide(color: tone),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              actionLabel ?? context.l10n.permissionOpenSettings,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        if (canDismiss)
          TextButton(
            onPressed: () => center.dismiss(permission),
            style: TextButton.styleFrom(
              foregroundColor: colors.textSecondary,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              context.l10n.permissionDismiss,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }

  Color _tone(QAppColors colors) => switch (severity) {
    PermissionNoticeSeverity.blocking => colors.accent,
    PermissionNoticeSeverity.informational => colors.info,
    PermissionNoticeSeverity.degraded => colors.danger,
  };

  IconData get _glyph => switch (severity) {
    PermissionNoticeSeverity.blocking => Icons.lock_outline,
    PermissionNoticeSeverity.informational => Icons.info_outline,
    PermissionNoticeSeverity.degraded => Icons.warning_amber_outlined,
  };
}

/// The Tier 1 screen: a denial with no route around it.
///
/// A screen and not a modal, because there is nothing usable behind it.
/// `PermissionTier.blocking` is reached by exactly one permission today —
/// Bluetooth on iOS, where `transport/usb/ios.dart` throws `UnsupportedError`
/// so every screen behind the prompt is furniture.
///
/// Built from the same parts as [PermissionNotice] rather than beside it: the
/// hint box is the notice's own anatomy at a larger size, and the sentence
/// rules are identical — say what is out of reach, never name the permission
/// constant, and route into system settings.
///
/// It does not decide whether to show itself. Whoever mounts it has already
/// decided that the app has nothing else to offer, and a gate that could
/// silently choose not to appear would leave the user on an empty screen
/// with no explanation — which is the state this replaces.
class PermissionGate extends StatelessWidget {
  const PermissionGate({
    super.key,
    required this.title,
    required this.body,
    required this.icon,
    required this.actionLabel,
    required this.onAction,
    this.hint,
  });

  final String title;
  final String body;
  final IconData icon;
  final String actionLabel;
  final VoidCallback onAction;

  /// Where in system settings the switch is, when the path is worth naming.
  /// `Settings › qUnleashed › Bluetooth` saves a hunt through a list.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  // Scrollable so a short window or a long translation gives
                  // way rather than overflowing. Every string here is longer
                  // in every other language, and this is the one screen that
                  // has to stay readable for the app to be usable at all.
                  child: SingleChildScrollView(
                    child: _content(context, colors),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ProgressButton(
                text: actionLabel,
                color: colors.accent,
                onPressed: onAction,
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.permissionRecheckedOnReturn,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 12,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, QAppColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        permissionBadge(icon: icon, tone: colors.danger, size: 104),
        const SizedBox(height: 24),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 24,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 14,
              height: 1.3,
            ),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: _noticeBox(
              tone: colors.info,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: colors.info),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectableText(
                      hint!,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
