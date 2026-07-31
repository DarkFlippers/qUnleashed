import 'package:dartufbt/dartufbt.dart';
import 'package:flutter/material.dart';

import '../../components/cardlist.dart';
import '../../theme/theme.dart';
import 'controller.dart';
import 'page.dart';

class AssemblerSettingsPage extends StatefulWidget {
  const AssemblerSettingsPage({super.key, this.fromConsole = false});

  /// Set when the console pushed this page, so a job started here goes back to
  /// it instead of stacking a second console on top.
  final bool fromConsole;

  @override
  State<AssemblerSettingsPage> createState() => _AssemblerSettingsPageState();
}

class _AssemblerSettingsPageState extends State<AssemblerSettingsPage> {
  final AssemblerController _ctrl = AssemblerController.instance;

  static const Map<UfbtUpdateChannel, String> _channelTitles = {
    UfbtUpdateChannel.release: 'Release',
    UfbtUpdateChannel.dev: 'Development',
  };

  static const Map<UfbtUpdateChannel, String> _channelSubtitles = {
    UfbtUpdateChannel.release: 'Stable SDK, matches released firmware.',
    UfbtUpdateChannel.dev: 'Latest builds, may be unstable.',
  };

  static const Map<AssemblerSdkSource, String> _sourceTitles = {
    AssemblerSdkSource.unleashed: 'Unleashed',
    AssemblerSdkSource.official: 'Official',
    AssemblerSdkSource.custom: 'Custom',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ctrl.refreshStatus();
      _ctrl.loadSettings();
    });
  }

  void _showConsole() {
    final navigator = Navigator.of(context);
    if (widget.fromConsole) {
      if (navigator.canPop()) navigator.pop();
      return;
    }
    navigator.push(
      MaterialPageRoute(builder: (_) => const AssemblerConsolePage()),
    );
  }

  Widget _intro(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(kGroupedOuterRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.construction, size: 22, color: colors.accent),
              const SizedBox(width: 8),
              Text(
                'Flibler (Flipper Assembler Tool)',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Flibler uses the uFBT utility to build an app for the firmware '
            'you pick: it downloads the app source bundle instead of a ready '
            'FAP and compiles it locally against the SDK of that firmware.\n\n'
            'It needs two one-time downloads: the firmware SDK (~22 MB) and '
            'the ARM toolchain (~340 MB). They are stored in the same place '
            'ufbt uses, so an existing ufbt setup is reused as is.',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _radioTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool selected,
  }) {
    final colors = context.appColors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
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

  Widget _channelTile(BuildContext context, UfbtUpdateChannel channel) {
    return _radioTile(
      context,
      title: _channelTitles[channel]!,
      subtitle: _channelSubtitles[channel]!,
      selected: _ctrl.channel == channel,
    );
  }

  Widget _sourceTile(BuildContext context, AssemblerSdkSource source) {
    final custom = source == AssemblerSdkSource.custom;
    return _radioTile(
      context,
      title: _sourceTitles[source]!,
      subtitle: custom
          ? (_ctrl.customIndexUrl.isEmpty
                ? 'Tap to set a directory.json URL'
                : _ctrl.customIndexUrl)
          : source.url!,
      selected: _ctrl.sdkSource == source,
    );
  }

  Future<void> _selectSource(AssemblerSdkSource source) async {
    await _ctrl.setSdkSource(source);
    if (source == AssemblerSdkSource.custom && mounted) {
      await _editCustomIndexUrl();
    }
  }

  Future<void> _editCustomIndexUrl() async {
    final colors = context.appColors;
    final field = TextEditingController(text: _ctrl.customIndexUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: colors.dialogBackground,
        title: Text(
          'Custom SDK index',
          style: TextStyle(color: colors.dialogText),
        ),
        content: TextField(
          controller: field,
          autofocus: true,
          keyboardType: TextInputType.url,
          style: TextStyle(color: colors.dialogText),
          decoration: InputDecoration(
            hintText: 'https://server/directory.json',
            hintStyle: TextStyle(color: colors.textMuted),
          ),
          onSubmitted: (v) => Navigator.pop(c, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, field.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    field.dispose();
    if (url != null) await _ctrl.setCustomIndexUrl(url);
  }

  Widget _action(
    BuildContext context, {
    required String label,
    required String caption,
    required bool primary,
    required VoidCallback? onPressed,
  }) {
    final colors = context.appColors;
    const style = TextStyle(fontSize: 13);
    return Row(
      children: [
        SizedBox(
          width: 200,
          child: primary
              ? FilledButton(
                  onPressed: onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(label, style: style),
                )
              : OutlinedButton(
                  onPressed: onPressed,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.textSecondary,
                    side: BorderSide(color: colors.divider),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(label, style: style),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sdkAction(BuildContext context) {
    final status = _ctrl.status;
    final deployed = status?.sdkDeployed ?? false;
    final running = _ctrl.job == AssemblerJob.sdk;
    final channel = _channelTitles[_ctrl.channel]!.toLowerCase();
    return _action(
      context,
      label: running
          ? 'Downloading SDK…'
          : deployed
          ? 'Update SDK'
          : 'Download SDK',
      caption: deployed
          ? 'Have ${status?.version ?? '—'}, looks up the $channel channel'
          : 'SDK zip of the $channel channel, ~22 MB',
      primary: !deployed,
      onPressed: () async {
        _showConsole();
        await _ctrl.downloadSdk();
      },
    );
  }

  Widget _toolchainAction(BuildContext context) {
    final toolchain = _ctrl.status?.toolchain;
    final running = _ctrl.job == AssemblerJob.toolchain;
    final deployed = toolchain?.isDeployed ?? false;
    final upToDate = toolchain?.isUpToDate ?? false;
    return _action(
      context,
      label: running
          ? 'Downloading toolchain…'
          : upToDate
          ? 'Toolchain ready'
          : deployed
          ? 'Update toolchain'
          : 'Download toolchain',
      caption: upToDate
          ? 'Have v${toolchain?.installedVersion}, nothing to download'
          : deployed
          ? 'Have v${toolchain?.installedVersion}, replaces with '
                'v${toolchain?.version}, ~340 MB'
          : 'ARM toolchain v${toolchain?.version ?? '?'}, ~340 MB',
      primary: !upToDate,
      onPressed: () async {
        _showConsole();
        await _ctrl.downloadToolchain();
      },
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
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ok ? colors.success : colors.textMuted,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _statusTiles(BuildContext context) {
    final status = _ctrl.status;
    if (status == null) {
      return [_statusRow(context, 'State', 'Not checked yet')];
    }
    final toolchain = status.toolchain;
    return [
      _statusRow(
        context,
        'SDK',
        status.sdkDeployed
            ? '${status.version ?? '—'} · ${status.target ?? '—'}'
            : 'Not installed',
        ok: status.sdkDeployed,
      ),
      _statusRow(
        context,
        'Toolchain',
        toolchain.isUpToDate
            ? 'v${toolchain.installedVersion}'
            : toolchain.isDeployed
            ? 'v${toolchain.installedVersion} → v${toolchain.version}'
            : 'Not installed',
        ok: toolchain.isUpToDate,
      ),
      _statusRow(context, 'State dir', status.stateDir),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final supported = AssemblerController.isSupported;
        final busy = _ctrl.busy;
        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            title: const Text('Assembler settings'),
            backgroundColor: colors.background,
            surfaceTintColor: colors.transparent,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 10),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: kGroupedHorizontalPadding,
                ),
                child: _intro(context),
              ),
              const SizedBox(height: 14),
              if (!supported)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: kGroupedHorizontalPadding,
                  ),
                  child: Text(
                    'Local builds are available on desktop only — the ARM '
                    'toolchain has no Android build.',
                    style: TextStyle(color: colors.danger, fontSize: 12.5),
                  ),
                )
              else ...[
                GroupedCardList<UfbtUpdateChannel>(
                  title: 'SDK channel',
                  items: const [
                    UfbtUpdateChannel.release,
                    UfbtUpdateChannel.dev,
                  ],
                  onTap: (channel) =>
                      busy ? null : () => _ctrl.setChannel(channel),
                  itemBuilder: _channelTile,
                ),
                const SizedBox(height: 14),
                GroupedCardList<AssemblerSdkSource>(
                  title: 'SDK index',
                  items: AssemblerSdkSource.values,
                  onTap: (source) => busy ? null : () => _selectSource(source),
                  itemBuilder: _sourceTile,
                ),
                const SizedBox(height: 14),
                GroupedCardList<Widget>(
                  title: 'Status',
                  items: _statusTiles(context),
                  itemBuilder: (context, tile) => tile,
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: kGroupedHorizontalPadding,
                  ),
                  child: Column(
                    children: [
                      _sdkAction(context),
                      const SizedBox(height: 10),
                      _toolchainAction(context),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}
