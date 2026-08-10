import 'package:file_picker/file_picker.dart';
import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../components/appbar.dart';
import '../../../components/cardlist.dart';
import '../../../components/dialogs/action.dart';
import '../../../components/icon.dart';
import '../../../components/navigation.dart';
import '../../../theme/theme.dart';
import '../../../components/notification.dart';
import '../../../components/progress_button.dart';
import '../../../components/fap_facts.dart';
import '../page.dart';
import 'controller.dart';

class FliblerProjectPage extends StatefulWidget {
  const FliblerProjectPage({super.key});

  @override
  State<FliblerProjectPage> createState() => _FliblerProjectPageState();
}

class _FliblerProjectPageState extends State<FliblerProjectPage> {
  final FliblerProjectController _ctrl = FliblerProjectController();
  final TextEditingController _repoField = TextEditingController();

  @override
  void initState() {
    super.initState();
    _repoField.addListener(() => _ctrl.setRepo(_repoField.text));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ctrl.assembler.refreshStatus();
      _ctrl.loadRecent();
    });
  }

  @override
  void dispose() {
    _repoField.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Pick a project folder',
    );
    if (path == null) return;
    _repoField.clear();
    _ctrl.setFolder(path);
    await _ctrl.loadProject();
  }

  Future<void> _pasteLink() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (mounted) {
        context.showNotification(
          'Clipboard is empty',
          type: QNotificationType.warning,
        );
      }
      return;
    }
    _repoField.text = text;
    await _ctrl.loadProject();
  }

  Future<void> _useRecent(FliblerRecentSource entry) async {
    if (entry.kind == FliblerSourceKind.folder) {
      _repoField.clear();
      _ctrl.setFolder(entry.value);
    } else {
      _repoField.text = entry.value;
    }
    await _ctrl.loadProject();
  }

  Future<void> _build() async {
    if (_ctrl.app == null && !await _ctrl.loadProject()) return;
    await _ctrl.build();
  }

  Future<void> _openOnDevice() async {
    try {
      await _ctrl.launchOnDevice();
      if (!mounted) return;
      openRoute(context, AppRoute.remoteControl);
    } on FlipperRpcAppSystemLockedException {
      if (!mounted) return;
      final colors = context.appColors;
      await showDialog<void>(
        context: context,
        barrierColor: colors.dialogBarrier,
        builder: (dialogContext) => FlipperActionDialog(
          imageAssetPath: kFlipperBusyAssetPath,
          title: kFlipperBusyTitle,
          text: kFlipperBusyMessage,
          actionText: kFlipperBusyAction,
          onAction: () {
            Navigator.of(dialogContext).pop();
            openRoute(context, AppRoute.remoteControl);
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      context.showNotification(
        'Open failed: $e',
        type: QNotificationType.error,
      );
    }
  }

  void _openConsole() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AssemblerConsolePage()));
  }

  void _openSettings() {
    openRoute(context, AppRoute.assemblerSettings);
  }

  Widget _padded(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: kGroupedHorizontalPadding),
    child: child,
  );

  Widget _sourceField(BuildContext context) {
    final colors = context.appColors;
    return TextField(
      controller: _repoField,
      enabled: !_ctrl.busy,
      keyboardType: TextInputType.url,
      onSubmitted: (_) => _ctrl.loadProject(),
      style: TextStyle(color: colors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        hintText: 'https://github.com/user/repo/tree/main/app',
        hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
        filled: true,
        fillColor: colors.card,
        prefixIcon: Icon(Icons.link, size: 20, color: colors.textMuted),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Paste and load',
              icon: Icon(
                Icons.content_paste_go,
                size: 20,
                color: colors.textSecondary,
              ),
              onPressed: _ctrl.busy ? null : _pasteLink,
            ),
            IconButton(
              tooltip: 'Choose folder',
              icon: Icon(
                Icons.folder_open,
                size: 20,
                color: colors.textSecondary,
              ),
              onPressed: _ctrl.busy ? null : _pickFolder,
            ),
            const SizedBox(width: 4),
          ],
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _folderCaption(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        Icon(Icons.folder_outlined, size: 15, color: colors.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _ctrl.folderPath,
            maxLines: 1,
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

  Widget _header(BuildContext context) {
    final colors = context.appColors;
    final app = _ctrl.app!;
    final icon = _ctrl.icon;
    final version = app.fapVersion.join('.');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null)
          QIconBadge.xbm(
            bytes: icon.xbm,
            width: icon.width,
            height: icon.height,
            cacheKey: 'flibler:${app.appid}:${icon.xbm.length}',
            color: colors.accent,
            size: 64,
            iconSize: 44,
            borderRadius: 14,
          )
        else
          QIconBadge(
            asset: 'assets/ic/fileformat/plugins.svg',
            color: colors.accent,
            size: 64,
            iconSize: 36,
            borderRadius: 14,
          ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                app.name.isEmpty ? app.appid : app.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (version.isNotEmpty)
                    _Meta(label: 'Version', value: version),
                  if (app.fapAuthor.isNotEmpty)
                    _Meta(label: 'By', value: app.fapAuthor),
                  if (app.fapCategory.isNotEmpty)
                    _Meta(label: 'Category', value: app.fapCategory),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _ctrl.targetPath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 11.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bigButton(String label, Color color, VoidCallback onTap) {
    return ProgressButton(
      text: label,
      color: color,
      onPressed: onTap,
      height: 48,
      borderRadius: 10,
      horizontalPadding: 24,
    );
  }

  Widget _bigProgress(String label, Color color, {double? progress}) {
    return ProgressButton(
      text: label,
      color: color,
      progress: progress,
      indeterminate: progress == null,
      showPercent: progress != null,
      height: 48,
      borderRadius: 10,
      horizontalPadding: 12,
    );
  }

  Widget _actions(BuildContext context) {
    final colors = context.appColors;
    if (_ctrl.uploading) {
      return _bigProgress(
        'UPLOAD',
        colors.accent,
        progress: _ctrl.uploadProgress,
      );
    }
    if (_ctrl.loading) return _bigProgress('LOAD', colors.accent);
    if (_ctrl.assembler.busy) return _bigProgress('BUILD', colors.accent);

    final built = _ctrl.fap != null;
    final sent = _ctrl.installedPath != null;

    if (built && sent) {
      return Row(
        children: [
          Expanded(child: _bigButton('OPEN', colors.accent, _openOnDevice)),
          const SizedBox(width: 12),
          _SquareAction(
            icon: Icons.upload,
            tooltip: 'Send again',
            onTap: () => _ctrl.sendToDevice(),
          ),
          const SizedBox(width: 8),
          _SquareAction(icon: Icons.refresh, tooltip: 'Rebuild', onTap: _build),
        ],
      );
    }
    if (built) {
      return Row(
        children: [
          Expanded(
            child: _bigButton('SEND', colors.success, () {
              _ctrl.sendToDevice();
            }),
          ),
          const SizedBox(width: 12),
          _SquareAction(icon: Icons.refresh, tooltip: 'Rebuild', onTap: _build),
        ],
      );
    }
    return _bigButton('BUILD', colors.accent, () {
      if (!_ctrl.canBuild && !_ctrl.canLoad) {
        context.showNotification(
          'Paste a repository link or pick a project folder',
          type: QNotificationType.warning,
        );
        return;
      }
      _build();
    });
  }

  Widget _status(BuildContext context) {
    final colors = context.appColors;
    final error = _ctrl.error;
    final installed = _ctrl.installedPath;
    final app = _ctrl.result?.app;
    final text =
        error ??
        (installed != null
            ? 'Sent to $installed'
            : app != null
            ? 'Built ${app.name.isEmpty ? app.appid : app.name} '
                  '(${_ctrl.fap?.lengthSync() ?? 0} bytes)'
            : null);
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        text,
        style: TextStyle(
          color: error != null ? colors.danger : colors.success,
          fontSize: 12.5,
        ),
      ),
    );
  }

  Widget _recentTile(BuildContext context, FliblerRecentSource entry) {
    final colors = context.appColors;
    return Row(
      children: [
        Icon(
          entry.kind == FliblerSourceKind.folder
              ? Icons.folder_outlined
              : Icons.link,
          size: 20,
          color: colors.textSecondary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.name.isEmpty ? entry.value : entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (entry.name.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  entry.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 11.5,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Remove from recent',
          icon: Icon(Icons.close, size: 16, color: colors.textMuted),
          onPressed: () => _ctrl.removeRecent(entry),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: Listenable.merge([_ctrl, _ctrl.assembler]),
      builder: (context, _) {
        final app = _ctrl.app;
        return Scaffold(
          backgroundColor: colors.background,
          appBar: QPageAppBar(
            title: 'Flibler',
            backgroundColor: colors.accent,
            foregroundColor: colors.onAccent,
            actions: [
              QPageAppBarAction(
                tooltip: 'Console',
                icon: const Icon(Icons.terminal),
                onPressed: _openConsole,
              ),
              QPageAppBarAction(
                tooltip: 'Assembler settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: _openSettings,
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 14, 0, 24),
              children: [
                _padded(_sourceField(context)),
                if (_ctrl.kind == FliblerSourceKind.folder &&
                    _ctrl.folderPath.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _padded(_folderCaption(context)),
                ],
                if (app != null) ...[
                  const SizedBox(height: 18),
                  _padded(_header(context)),
                ],
                const SizedBox(height: 16),
                _padded(_actions(context)),
                _padded(_status(context)),
                if (_ctrl.builtInfo != null) ...[
                  const SizedBox(height: 18),
                  GroupedCardList<int>(
                    title: 'Application',
                    items: const [0],
                    cardPadding: const EdgeInsets.all(12),
                    itemBuilder: (context, _) => FapFactsPanel(
                      info: _ctrl.builtInfo,
                      showVerdict: false,
                      author: app?.fapAuthor,
                    ),
                  ),
                ],
                if (_ctrl.recent.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  GroupedCardList<FliblerRecentSource>(
                    title: 'Recent projects',
                    items: _ctrl.recent,
                    onTap: (entry) =>
                        _ctrl.busy ? null : () => _useRecent(entry),
                    itemBuilder: _recentTile,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SquareAction extends StatelessWidget {
  const _SquareAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = BorderRadius.circular(10);
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.divider, width: 1.25),
        borderRadius: radius,
      ),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon, color: colors.textSecondary, size: 22),
          ),
        ),
      ),
    );
  }
}
