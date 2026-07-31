import 'package:dartufbt/dartufbt.dart';
import 'package:flutter/material.dart';

import '../../components/cardlist.dart';
import '../../theme/theme.dart';
import 'controller.dart';
import 'page.dart';
import 'widgets/progress_panel.dart';

class AssemblerIntroPage extends StatefulWidget {
  const AssemblerIntroPage({super.key});

  @override
  State<AssemblerIntroPage> createState() => _AssemblerIntroPageState();
}

class _AssemblerIntroPageState extends State<AssemblerIntroPage> {
  final AssemblerController _ctrl = AssemblerController.instance;

  static const Map<UfbtUpdateChannel, String> _channelTitles = {
    UfbtUpdateChannel.release: 'Release',
    UfbtUpdateChannel.dev: 'Development',
  };

  static const Map<UfbtUpdateChannel, String> _channelSubtitles = {
    UfbtUpdateChannel.release: 'Stable SDK, matches released firmware.',
    UfbtUpdateChannel.dev: 'Latest builds, may be unstable.',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ctrl.refreshStatus());
  }

  void _openConsole() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AssemblerConsolePage()));
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
                'Build apps from source',
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
            'When the catalog has no build for your firmware API, the '
            'assembler downloads the app source bundle instead of a ready '
            'FAP and compiles it locally against the SDK of your firmware.\n\n'
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

  Widget _channelTile(BuildContext context, UfbtUpdateChannel channel) {
    final colors = context.appColors;
    final selected = _ctrl.channel == channel;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _channelTitles[channel]!,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _channelSubtitles[channel]!,
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
            title: const Text('Assembler'),
            backgroundColor: colors.background,
            surfaceTintColor: colors.transparent,
            actions: [
              IconButton(
                tooltip: 'Build console',
                icon: Icon(Icons.terminal, color: colors.textPrimary),
                onPressed: _openConsole,
              ),
            ],
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
                  child: AssemblerProgressPanel(
                    controller: _ctrl,
                    idleLabel: 'Nothing running',
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: kGroupedHorizontalPadding,
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  _openConsole();
                                  await _ctrl.downloadSdk();
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.accent,
                            foregroundColor: colors.onAccent,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            _ctrl.job == AssemblerJob.sdk
                                ? 'Downloading SDK…'
                                : 'Download SDK',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  _openConsole();
                                  await _ctrl.downloadToolchain();
                                },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.textSecondary,
                            side: BorderSide(color: colors.divider),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            _ctrl.job == AssemblerJob.toolchain
                                ? 'Downloading toolchain…'
                                : 'Download toolchain (~340 MB)',
                          ),
                        ),
                      ),
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
