import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

Future<void> openUrl(
  BuildContext context,
  String url, {
  bool inApp = true,
}) async {
  if (url.isEmpty) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;

  if (!_inAppSupported) {
    await _launchExternal(uri);
    return;
  }

  if (inApp) {
    await _launchInApp(uri);
    return;
  }

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => _OpenUrlMenu(uri: uri),
  );
}

bool get _inAppSupported {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return true;
    default:
      return false;
  }
}

Future<void> _launchInApp(Uri uri) async {
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!ok) await _launchExternal(uri);
  } catch (_) {
    await _launchExternal(uri);
  }
}

Future<void> _launchExternal(Uri uri) async {
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

class _OpenUrlMenu extends StatelessWidget {
  const _OpenUrlMenu({required this.uri});

  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Dialog(
      backgroundColor: colors.card,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              uri.toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          ListTile(
            leading: Icon(Icons.open_in_new, color: colors.textPrimary),
            title: Text(
              'Open in app',
              style: TextStyle(color: colors.textPrimary),
            ),
            onTap: () {
              Navigator.of(context).pop();
              _launchInApp(uri);
            },
          ),
          ListTile(
            leading: Icon(Icons.public, color: colors.textPrimary),
            title: Text(
              'Open in browser',
              style: TextStyle(color: colors.textPrimary),
            ),
            onTap: () {
              Navigator.of(context).pop();
              _launchExternal(uri);
            },
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
