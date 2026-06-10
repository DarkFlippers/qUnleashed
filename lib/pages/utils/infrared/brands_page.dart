import 'package:flutter/material.dart';

import '../../../theme.dart';
import 'backend/infrared_backend_api.dart';
import 'backend/infrared_backend_models.dart';
import 'infrareds_page.dart';
import 'widgets/ir_search_field.dart';

class IrBrandsPage extends StatefulWidget {
  const IrBrandsPage({super.key, required this.category});

  final DeviceCategory category;

  @override
  State<IrBrandsPage> createState() => _IrBrandsPageState();
}

class _IrBrandsPageState extends State<IrBrandsPage> {
  final InfraredBackendApi _api = InfraredBackendApi();
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  List<BrandModel> _brands = const [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _api.close();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final brands = await _api.getBrands(widget.category.id);
      brands.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _brands = brands;
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

  void _open(BrandModel b) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IrInfraredsPage(category: widget.category, brand: b),
      ),
    );
  }

  List<BrandModel> get _filtered {
    if (_query.trim().isEmpty) return _brands;
    final q = _query.toLowerCase();
    return _brands.where((b) => b.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        title: Text(widget.category.displayName),
      ),
      body: Column(
        children: [
          IrSearchField(
            controller: _searchCtrl,
            hintText: 'Search brand…',
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            onChanged: (v) => setState(() => _query = v),
          ),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final colors = context.appColors;
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (_error != null && _brands.isEmpty) {
      return _ErrorView(message: _error!, onRetry: _load);
    }
    final list = _filtered;
    if (list.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty ? 'No brands available' : 'No matches',
          style: TextStyle(color: colors.textMuted),
        ),
      );
    }
    return RefreshIndicator(
      color: colors.accent,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, i) {
          final b = list[i];
          return Material(
            color: colors.card,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => _open(b),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        b.name,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
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
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textPrimary)),
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
