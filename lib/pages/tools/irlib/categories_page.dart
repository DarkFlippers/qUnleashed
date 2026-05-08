import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import 'backend/infrared_backend_api.dart';
import 'backend/infrared_backend_models.dart';
import 'brands_page.dart';
import 'irlib_page.dart';

class IrCategoriesPage extends StatefulWidget {
  const IrCategoriesPage({super.key});

  @override
  State<IrCategoriesPage> createState() => _IrCategoriesPageState();
}

class _IrCategoriesPageState extends State<IrCategoriesPage> {
  final InfraredBackendApi _api = InfraredBackendApi();
  bool _loading = true;
  String? _error;
  List<DeviceCategory> _categories = const [];

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
      final cats = await _api.getCategories();
      if (!mounted) return;
      setState(() {
        _categories = cats;
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

  void _openCategory(DeviceCategory c) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => IrBrandsPage(category: c)),
    );
  }

  void _openIrdb() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const IrLibPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        title: const Text('Remote Library'),
      ),
      body: RefreshIndicator(
        color: colors.accent,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _IrdbButton(onTap: _openIrdb)),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _LoadingGrid(),
              )
            else if (_error != null && _categories.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _ErrorView(message: _error!, onRetry: _load),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.3,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _DeviceCategoryCard(
                      category: _categories[i],
                      onTap: () => _openCategory(_categories[i]),
                    ),
                    childCount: _categories.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IrdbButton extends StatelessWidget {
  const _IrdbButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Material(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SvgPicture.asset(
                    'assets/flipper_svg/tools/ic_fileformat_ir.svg',
                    width: 24,
                    height: 24,
                    colorFilter:
                        ColorFilter.mode(colors.accent, BlendMode.srcIn),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'IRDB',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Browse the community Flipper-IRDB repository',
                        style: TextStyle(color: colors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceCategoryCard extends StatelessWidget {
  const _DeviceCategoryCard({required this.category, required this.onTap});

  final DeviceCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final image = _decodeIcon(category.meta.iconPngBase64);
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (image != null)
                ColorFiltered(
                  colorFilter:
                      ColorFilter.mode(colors.textPrimary, BlendMode.srcIn),
                  child: Image.memory(
                    image,
                    width: 40,
                    height: 40,
                    filterQuality: FilterQuality.medium,
                    fit: BoxFit.contain,
                  ),
                )
              else
                Icon(Icons.error_outline, size: 36, color: colors.textPrimary),
              const SizedBox(height: 8),
              Text(
                category.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Uint8List? _decodeIcon(String b64) {
    if (b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }
}

class _LoadingGrid extends StatelessWidget {
  const _LoadingGrid();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(child: CircularProgressIndicator(color: colors.accent));
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
