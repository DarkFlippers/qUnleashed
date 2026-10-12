import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../services/localization/l10n.dart';
import '../../../theme/theme.dart';

import 'package:qunleashed/components/appbar.dart';
import 'package:qunleashed/components/icon.dart';
import 'package:qunleashed/theme/colors/category.dart';

import '../../../components/notification.dart';
import 'backend/infrared_backend_api.dart';
import 'backend/infrared_backend_models.dart';
import 'ir_content_page.dart';
import '../../devices/device_scope.dart';

const _infraredAsset = 'assets/ic/fileformat/ir.svg';

class IrInfraredsPage extends StatefulWidget {
  const IrInfraredsPage({
    super.key,
    required this.category,
    required this.brand,
  });

  final DeviceCategory category;
  final BrandModel brand;

  @override
  State<IrInfraredsPage> createState() => _IrInfraredsPageState();
}

class _IrInfraredsPageState extends State<IrInfraredsPage> {
  final InfraredBackendApi _api = InfraredBackendApi();
  bool _loading = true;
  String? _error;
  List<IfrFileModel> _files = const [];

  /// The files whose content is being fetched.
  ///
  /// A set and not the single `int?` slot this was: the guard allows a
  /// *different* file to be fetched meanwhile, which is the path that defeats
  /// one slot. Tap A, tap B while A is out, and A's completion clears the slot
  /// while B is still in flight - B's tile re-enables and B can be opened
  /// twice over. The error path is the reachable one, since a failed fetch
  /// leaves the whole list on screen. #244.
  final Set<int> _fetching = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.getInfrareds(widget.brand.id);
      list.sort(
        (a, b) => a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        _files = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _open(IfrFileModel f) async {
    // The tile is disabled while its own fetch runs, which is the call-site
    // half of this repository's idiom and was all this had. The handler half
    // closes the rest: a rebuild is only scheduled by setState, so two
    // activations before it lands both see an enabled tile, and this awaits a
    // backend fetch before pushing.
    if (!_fetching.add(f.id)) return;
    setState(() {});
    try {
      final content = await _api.getKeyContent(f.id);
      if (!mounted) return;
      final client = DeviceScope.of(context).client;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => IrContentPage(
            client: client,
            fileName: f.fileName,
            subtitle: context.l10n.irBreadcrumb(
              widget.category.displayName,
              widget.brand.name,
            ),
            content: content,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      context.showNotification(
        context.l10n.irLoadFailed('$e'),
        type: QNotificationType.error,
      );
    } finally {
      _fetching.remove(f.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: QPageAppBar(
        client: DeviceScope.of(context).client,
        title: widget.brand.name,
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
      ),
      body: SafeArea(top: false, child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    final colors = context.appColors;
    final infraredColor = ArchiveCategoryColor.infrared.color;
    final badge = QIconBadgeStyle.of(context, infraredColor);
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (_error != null && _files.isEmpty) {
      return _ErrorView(message: _error!, onRetry: _load);
    }
    if (_files.isEmpty) {
      return Center(
        child: Text(
          context.l10n.irNoRemotes,
          style: TextStyle(color: colors.textMuted),
        ),
      );
    }
    return RefreshIndicator(
      color: colors.accent,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        itemCount: _files.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, i) {
          final f = _files[i];
          final fetching = _fetching.contains(f.id);
          return Material(
            color: colors.card,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: fetching ? null : () => _open(f),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: badge.background,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SvgPicture.asset(
                        _infraredAsset,
                        width: 22,
                        height: 22,
                        colorFilter: ColorFilter.mode(
                          badge.foreground,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            f.folderName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (fetching)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: colors.accent,
                          strokeWidth: 2,
                        ),
                      )
                    else
                      Icon(Icons.chevron_right, color: colors.textMuted),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 44, color: colors.danger),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textPrimary),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onRetry,
              child: Text(context.l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}
