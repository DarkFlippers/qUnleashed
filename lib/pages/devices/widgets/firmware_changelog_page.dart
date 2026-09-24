import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../services/localization/l10n.dart';
import '../../../components/config.dart';
import '../../../services/logging.dart';
import '../../../theme/theme.dart';
import '../firmware/directory.dart';

import 'package:qunleashed/components/appbar.dart';

import '../../../components/changelog_renderer.dart';
import 'firmware_update_button.dart';

class FirmwareChangelogPage extends StatefulWidget {
  const FirmwareChangelogPage({
    super.key,
    required this.entry,
    required this.version,
    required this.changelog,
    required this.fetchState,
    required this.latestVersion,
    required this.deviceVersion,
    required this.deviceInfo,
    required this.selectedChannelId,
    required this.selectedVariant,
    required this.client,
    @visibleForTesting this.renderHtml,
  });

  final FirmwareEntry entry;
  final FirmwareVersion version;
  final String changelog;
  final FirmwareFetchState fetchState;
  final String? latestVersion;
  final String? deviceVersion;
  final Map<String, String> deviceInfo;
  final String selectedChannelId;
  final UnleashedVariant selectedVariant;
  final FlipperClient client;

  /// Stands in for the markdown-to-HTML pass.
  ///
  /// For tests, and a constructor argument rather than a global so that
  /// nothing can replace the renderer for the whole process.
  /// [buildChangelogHtml] is `markdownToHtml` plus a sanitiser and no input is
  /// known to make it throw, so the fallback in [initState] is not reachable
  /// from a test any other way.
  @visibleForTesting
  final String Function(String source)? renderHtml;

  @override
  State<FirmwareChangelogPage> createState() => _FirmwareChangelogPageState();
}

class _FirmwareChangelogPageState extends State<FirmwareChangelogPage> {
  /// The rendered changelog, or null if rendering it threw.
  late final String? _html;

  /// What the markdown pass was handed.
  ///
  /// Not always the changelog: a version that ships without one is shown the
  /// localised "Empty changelog" instead, and that is then what the fallback
  /// renders too.
  ///
  /// A field resolved before the try below, not a getter read inside it: as a
  /// getter it was also re-read from [build], where a throw would escape the
  /// catch that is supposed to contain it and red-screen the page.
  late final String _source;

  @override
  void initState() {
    super.initState();
    // The bare `l10n` global rather than `context.l10n`: that one goes through
    // `Localizations.of`, and depending on an inherited widget before
    // initState has finished asserts in a debug build. It resolves against the
    // same locale, and it is what the update button already uses.
    _source = widget.changelog.trim().isEmpty
        ? l10n.firmwareEmptyChangelog
        : widget.changelog;
    // Rendered here and not through `compute`. The isolate hop was the whole
    // reason this page had a future to wait on, a spinner to show while it
    // waited, and - since nothing checked `hasError` - a spinner that ran
    // forever when the render failed. Nothing else in the app pays it:
    // pages/apps/catalog/detail_page.dart calls buildChangelogHtml three
    // times from inside `build`, on strings no smaller than these. #118.
    try {
      _html = (widget.renderHtml ?? buildChangelogHtml)(_source);
    } catch (e, st) {
      // The changelog is still in hand even though the markdown pass is not,
      // so [build] shows it unstyled rather than an error card nobody can act
      // on. Kept, because otherwise a render that broke for every user would
      // look to them like a plain-text changelog and be reported by nobody.
      // error, not warn: nothing here touches the network, so a throw is
      // this app's own doing and breaks for everyone at once - which is the
      // line FirmwareRepository._recordFailure draws for the same reason.
      LogService.error(
        '[Firmware] changelog render failed: ${LogService.describe(e, st)}',
      );
      _html = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: QPageAppBar(
        title: context.l10n.firmwareWhatsNewVersion(widget.version.version),
        backgroundColor: colors.card,
        foregroundColor: colors.textPrimary,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                child: switch (_html) {
                  final String html => ChangelogRenderer(
                    html: html,
                    textColor: colors.textPrimary,
                    mutedColor: colors.textSecondary,
                  ),
                  // The markdown pass threw; see [initState]. Said out
                  // loud rather than quietly degraded: a render that broke
                  // for everyone would otherwise look like a changelog that
                  // simply has no formatting, and be reported by nobody.
                  null => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.firmwareChangelogUnstyled,
                        style: TextStyle(fontSize: 12, color: colors.textMuted),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _source,
                        style: TextStyle(color: colors.textPrimary),
                      ),
                    ],
                  ),
                },
              ),
            ),
            Container(
              color: colors.card,
              padding: const EdgeInsets.only(bottom: 8),
              child: FirmwareUpdateButton(
                entry: widget.entry,
                fetchState: widget.fetchState,
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
