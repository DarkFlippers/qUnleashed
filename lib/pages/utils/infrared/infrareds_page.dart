import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import 'package:qunleashed/components/appbar.dart';
import '../../../widgets/notification.dart';
import '../../../models/category.dart';
import 'backend/infrared_backend_api.dart';
import 'backend/infrared_backend_models.dart';
import 'ir_content_page.dart';

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
  int? _fetchingId;

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
    setState(() => _fetchingId = f.id);
    try {
      final content = await _api.getKeyContent(f.id);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => IrContentPage(
            fileName: f.fileName,
            subtitle: '${widget.category.displayName} В· ${widget.brand.name}',
            content: content,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      context.showNotification(
        'Failed to load: $e',
        type: QNotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _fetchingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: QPageAppBar(
        title: widget.brand.name,
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final colors = context.appColors;
    final ir = ArchiveCategory.infrared;
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (_error != null && _files.isEmpty) {
      return _ErrorView(message: _error!, onRetry: _load);
    }
    if (_files.isEmpty) {
      return Center(
        child: Text(
          'No remotes available',
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
          final fetching = _fetchingId == f.id;
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
                        color: ir.color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SvgPicture.asset(
                        ir.asset,
                        width: 22,
                        height: 22,
                        colorFilter: ColorFilter.mode(
                          ir.color,
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
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
