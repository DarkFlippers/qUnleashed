import 'dart:async';

import 'package:dartufbt/dartufbt.dart';
import 'package:flutter/material.dart';

import '../../../components/cardlist.dart';
import '../../../components/navigation.dart';
import '../../../theme/theme.dart';
import '../../../services/assembler/controller.dart';
import '../../../services/assembler/remote_build_service.dart';

class AssemblerSettingsPage extends StatefulWidget {
  const AssemblerSettingsPage({
    super.key,
    this.fromConsole = false,
    this.remote,
  });

  /// Set when the console pushed this page, so a job started here goes back to
  /// it instead of stacking a second console on top.
  final bool fromConsole;

  /// Injectable for tests; the app always uses the configured singleton.
  final RemoteBuildService? remote;

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

  static const Map<AssemblerBackendPreference, String> _backendTitles = {
    AssemblerBackendPreference.auto: 'Automatic',
    AssemblerBackendPreference.server: 'Build server',
  };

  static const Map<AssemblerBackendPreference, String> _backendSubtitles = {
    AssemblerBackendPreference.auto:
        'This computer when its SDK and toolchain are ready, else the server',
    AssemblerBackendPreference.server: 'Always waits in the server queue',
  };

  RemoteBuildService get _remote =>
      widget.remote ?? RemoteBuildService.instance;
  RemoteServerStatus? _serverStatus;
  String? _serverError;
  bool _serverLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ctrl.refreshStatus();
      unawaited(_loadServerStatus());
    });
  }

  Future<void> _loadServerStatus() async {
    if (_serverLoading) return;
    setState(() {
      _serverLoading = true;
      _serverError = null;
    });
    RemoteServerStatus? status;
    String? error;
    try {
      status = await _remote.serverStatus();
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    setState(() {
      _serverStatus = status;
      _serverError = error;
      _serverLoading = false;
    });
  }

  Future<void> _selectBackend(AssemblerBackendPreference preference) async {
    await _ctrl.setPreference(preference);
    if (_ctrl.usesServerBuild && _serverStatus == null) {
      unawaited(_loadServerStatus());
    }
  }

  Widget _backendTile(
    BuildContext context,
    AssemblerBackendPreference preference,
  ) {
    return _radioTile(
      context,
      title: _backendTitles[preference]!,
      subtitle: _backendSubtitles[preference]!,
      selected: _ctrl.preference == preference,
    );
  }

  void _showConsole() {
    final navigator = Navigator.of(context);
    if (widget.fromConsole) {
      if (navigator.canPop()) navigator.pop();
      return;
    }
    openRoute(context, AppRoute.assemblerConsole);
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

  /// Says where the next build actually goes, since "Automatic" only becomes
  /// an answer once the local ufbt state is known.
  Widget _activeBackendNote(BuildContext context) {
    final choice = _ctrl.backendChoice;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kGroupedHorizontalPadding + 4,
        8,
        kGroupedHorizontalPadding + 4,
        0,
      ),
      child: Text(
        'Now: ${choice.isLocal ? 'this computer' : 'build server'} '
        '— ${choice.reason.label}',
        style: TextStyle(
          color: context.appColors.textMuted,
          fontSize: 12,
          height: 1.2,
        ),
      ),
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
          ? 'Reinstall toolchain'
          : deployed
          ? 'Update toolchain'
          : 'Download toolchain',
      caption: upToDate
          ? 'Have v${toolchain?.installedVersion}, downloads and unpacks it '
                'again, ~340 MB'
          : deployed
          ? 'Have v${toolchain?.installedVersion}, replaces with '
                'v${toolchain?.version}, ~340 MB'
          : 'ARM toolchain v${toolchain?.version ?? '?'}, ~340 MB',
      primary: !upToDate,
      onPressed: () async {
        _showConsole();
        await _ctrl.downloadToolchain(force: upToDate);
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

  List<Widget> _localStatusTiles(BuildContext context) {
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

  List<Widget> _remoteStatusTiles(BuildContext context) {
    final status = _serverStatus;
    return [
      _statusRow(context, 'Address', Uri.parse(_remote.serverUrl).host),
      if (!_remote.canBuild)
        _statusRow(context, 'Signing key', 'Missing in this build'),
      _statusRow(
        context,
        'Server',
        _serverLoading
            ? 'Checking…'
            : _serverError != null
            ? 'Unreachable'
            : status != null
            ? 'Online · v${status.version}'
            : 'Not checked yet',
        ok: _serverError == null && status != null,
      ),
      _statusRow(
        context,
        'Deployed SDK',
        status == null
            ? '—'
            : status.sdkVersions.isEmpty
            ? 'Deploys on first build'
            : status.sdkVersions.join(', '),
        ok: status != null && status.sdkVersions.isNotEmpty,
      ),
      _statusRow(
        context,
        'Queue',
        status == null ? '—' : '${status.queueLength} in line',
      ),
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
              GroupedCardList<AssemblerBackendPreference>(
                title: 'Build with',
                items: AssemblerBackendPreference.values,
                onTap: (preference) =>
                    busy ? null : () => _selectBackend(preference),
                itemBuilder: _backendTile,
              ),
              _activeBackendNote(context),
              const SizedBox(height: 14),
              // The local controls stay on desktop whatever the resolved
              // backend is: this is the only place the SDK can be downloaded,
              // and until it is, builds keep going to the server.
              if (supported) ...[
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
                  title: 'This computer',
                  items: _localStatusTiles(context),
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
                const SizedBox(height: 14),
              ],
              GroupedCardList<Widget>(
                title: 'Server',
                items: _remoteStatusTiles(context),
                itemBuilder: (context, tile) => tile,
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: kGroupedHorizontalPadding,
                ),
                child: _action(
                  context,
                  label: _serverLoading ? 'Checking…' : 'Check server',
                  caption:
                      _serverError ??
                      (_remote.canBuild
                          ? 'Apps are compiled remotely, nothing to '
                                'download here'
                          : 'Builds need a signing key: rebuild the app '
                                'with --dart-define=QU_BUILD_SERVER_KEY'),
                  primary: false,
                  onPressed: _serverLoading ? null : _loadServerStatus,
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}
