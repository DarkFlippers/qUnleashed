import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../components/cardlist.dart';
import '../../../components/icon.dart';
import '../../../theme/theme.dart';
import '../page.dart';
import '../settings_page.dart';
import 'controller.dart';

class FliblerProjectPage extends StatefulWidget {
  const FliblerProjectPage({super.key});

  @override
  State<FliblerProjectPage> createState() => _FliblerProjectPageState();
}

class _FliblerProjectPageState extends State<FliblerProjectPage> {
  final FliblerProjectController _ctrl = FliblerProjectController();
  final TextEditingController _repoField = TextEditingController();

  static const Map<FliblerSourceKind, String> _titles = {
    FliblerSourceKind.folder: 'Local folder',
    FliblerSourceKind.repository: 'Repository link',
  };

  static const Map<FliblerSourceKind, String> _subtitles = {
    FliblerSourceKind.folder: 'A project folder with application.fam',
    FliblerSourceKind.repository:
        'Repo URL, a link to a folder inside it works',
  };

  @override
  void initState() {
    super.initState();
    _repoField.addListener(() => _ctrl.setRepo(_repoField.text));
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _ctrl.assembler.refreshStatus(),
    );
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
    _ctrl.setFolder(path);
    await _ctrl.loadProject();
  }

  Widget _sourceTile(BuildContext context, FliblerSourceKind kind) {
    final colors = context.appColors;
    final selected = _ctrl.kind == kind;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _titles[kind]!,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _subtitles[kind]!,
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

  Widget _sourceInput(BuildContext context) {
    final colors = context.appColors;
    if (_ctrl.kind == FliblerSourceKind.folder) {
      return Row(
        children: [
          SizedBox(
            width: 200,
            child: OutlinedButton(
              onPressed: _ctrl.busy ? null : _pickFolder,
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.textSecondary,
                side: BorderSide(color: colors.divider),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                'Choose folder',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _ctrl.folderPath.isEmpty ? 'Nothing picked' : _ctrl.folderPath,
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
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      ),
    );
  }

  void _openConsole() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AssemblerConsolePage()));
  }

  Widget _action(
    BuildContext context, {
    required String label,
    required String caption,
    required VoidCallback? onPressed,
  }) {
    final colors = context.appColors;
    return Row(
      children: [
        SizedBox(
          width: 200,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.onAccent,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(label, style: const TextStyle(fontSize: 13)),
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

  Widget _actions(BuildContext context) {
    final loaded = _ctrl.app != null;
    return _action(
      context,
      label: _ctrl.loading
          ? 'Loading…'
          : _ctrl.assembler.busy
          ? 'Building…'
          : _ctrl.uploading
          ? 'Sending…'
          : 'Build and send',
      caption: loaded
          ? 'Compiles it and writes ${_ctrl.targetPath}'
          : _ctrl.kind == FliblerSourceKind.folder
          ? 'Pick a project folder first'
          : 'Paste a repository link and press Enter',
      onPressed: _ctrl.canBuild || _ctrl.canLoad
          ? () async {
              _openConsole();
              if (_ctrl.app == null && !await _ctrl.loadProject()) return;
              await _ctrl.build();
            }
          : null,
    );
  }

  Widget _appCard(BuildContext context) {
    final app = _ctrl.app;
    if (app == null) return const SizedBox.shrink();
    final colors = context.appColors;
    final icon = _ctrl.icon;
    final version = app.fapVersion.join('.');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(kGroupedOuterRadius),
      ),
      child: Row(
        children: [
          if (icon != null)
            QIconBadge.xbm(
              bytes: icon.xbm,
              width: icon.width,
              height: icon.height,
              cacheKey: 'flibler:${app.appid}:${icon.xbm.length}',
              color: colors.accent,
              size: 44,
              iconSize: 30,
            )
          else
            QIconBadge(
              asset: 'assets/ic/fileformat/plugins.svg',
              color: colors.accent,
              size: 44,
              iconSize: 26,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.name.isEmpty ? app.appid : app.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (app.fapAuthor.isNotEmpty) app.fapAuthor,
                    if (version.isNotEmpty) 'v$version',
                    if (app.fapCategory.isNotEmpty) app.fapCategory,
                  ].join(' · '),
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
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: Listenable.merge([_ctrl, _ctrl.assembler]),
      builder: (context, _) {
        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            title: const Text('Flibler'),
            backgroundColor: colors.background,
            surfaceTintColor: colors.transparent,
            actions: [
              IconButton(
                tooltip: 'Assembler settings',
                icon: Icon(Icons.settings_outlined, color: colors.textPrimary),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AssemblerSettingsPage(),
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10),
              children: [
                GroupedCardList<FliblerSourceKind>(
                  title: 'Source',
                  items: FliblerSourceKind.values,
                  onTap: (kind) =>
                      _ctrl.busy ? null : () => _ctrl.setKind(kind),
                  itemBuilder: _sourceTile,
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: kGroupedHorizontalPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sourceInput(context),
                      if (_ctrl.app != null) ...[
                        const SizedBox(height: 14),
                        _appCard(context),
                      ],
                      const SizedBox(height: 14),
                      _actions(context),
                      _status(context),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}
