import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../config.dart';
import '../../../theme/theme.dart';
import '../firmware/directory.dart';
import 'package:qunleashed/components/appbar.dart';
import 'changelog_renderer.dart';
import 'firmware_update_button.dart';

class FirmwareChangelogPage extends StatefulWidget {
  const FirmwareChangelogPage({
    super.key,
    required this.entry,
    required this.version,
    required this.changelog,
    required this.fetchLoading,
    required this.latestVersion,
    required this.deviceVersion,
    required this.deviceInfo,
    required this.selectedChannelId,
    required this.selectedVariant,
    required this.client,
  });

  final FirmwareEntry entry;
  final FirmwareVersion version;
  final String changelog;
  final bool fetchLoading;
  final String? latestVersion;
  final String? deviceVersion;
  final Map<String, String> deviceInfo;
  final String selectedChannelId;
  final UnleashedVariant selectedVariant;
  final FlipperClient client;

  @override
  State<FirmwareChangelogPage> createState() => _FirmwareChangelogPageState();
}

class _FirmwareChangelogPageState extends State<FirmwareChangelogPage> {
  late final Future<String> _preparedHtml;

  @override
  void initState() {
    super.initState();
    _preparedHtml = compute(
      buildChangelogHtml,
      widget.changelog.trim().isEmpty ? 'Empty changelog' : widget.changelog,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: QPageAppBar(
        title: 'What\'s New · ${widget.version.version}',
        backgroundColor: colors.card,
        foregroundColor: colors.textPrimary,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder<String>(
                future: _preparedHtml,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                    child: ChangelogRenderer(
                      html: snapshot.data!,
                      textColor: colors.textPrimary,
                      mutedColor: colors.textSecondary,
                    ),
                  );
                },
              ),
            ),
            Container(
              color: colors.card,
              padding: const EdgeInsets.only(bottom: 8),
              child: FirmwareUpdateButton(
                entry: widget.entry,
                fetchLoading: widget.fetchLoading,
                latestVersion: widget.latestVersion,
                deviceVersion: widget.deviceVersion,
                deviceInfo: widget.deviceInfo,
                selectedChannelId: widget.selectedChannelId,
                selectedVariant: widget.selectedVariant,
                client: widget.client,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
