import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../models/firmware_config.dart';
import '../../../models/firmware_directory.dart';
import '../../../theme.dart';
import '../../../widgets/simple_markdown.dart';
import 'firmware_update_button.dart';

class FirmwareChangelogPage extends StatelessWidget {
  const FirmwareChangelogPage({
    super.key,
    required this.entry,
    required this.version,
    required this.changelog,
    required this.fetchLoading,
    required this.latestVersion,
    required this.deviceVersion,
    required this.selectedChannel,
    required this.selectedVariant,
    required this.client,
  });

  final FirmwareEntry entry;
  final FirmwareVersion version;
  final String changelog;
  final bool fetchLoading;
  final String? latestVersion;
  final String? deviceVersion;
  final FirmwareChannel selectedChannel;
  final UnleashedVariant selectedVariant;
  final FlipperClient client;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.card,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        centerTitle: true,
        titleSpacing: 0,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'What\'s New',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              version.version,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: entry.colors.primary,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                child: SimpleMarkdown(
                  data: changelog.trim().isEmpty ? 'Empty changelog' : changelog,
                  textColor: colors.textPrimary,
                  mutedColor: colors.textSecondary,
                ),
              ),
            ),
            Container(
              color: colors.card,
              padding: const EdgeInsets.only(bottom: 8),
              child: FirmwareUpdateButton(
                entry: entry,
                fetchLoading: fetchLoading,
                latestVersion: latestVersion,
                deviceVersion: deviceVersion,
                selectedChannel: selectedChannel,
                selectedVariant: selectedVariant,
                client: client,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
