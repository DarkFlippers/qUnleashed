import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../theme.dart';

/// Row of two storage entry cards (Internal `/int` + External `/ext`) shown on
/// the archive screen. A single [FlipperWatchApi.watchStorage] subscription
/// feeds both cards: `/ext` reports a real used/total (so it gets a usage bar),
/// while `/int` only exposes a used figure (the firmware aliases `/int` onto the
/// SD card for capacity), so it shows the used size without a fill bar.
class StorageUsageCards extends StatefulWidget {
  const StorageUsageCards({
    super.key,
    required this.enabled,
    required this.onOpenInternal,
    required this.onOpenExternal,
  });

  final bool enabled;
  final VoidCallback onOpenInternal;
  final VoidCallback onOpenExternal;

  @override
  State<StorageUsageCards> createState() => _StorageUsageCardsState();
}

class _StorageUsageCardsState extends State<StorageUsageCards> {
  final FlipperClient _client = FlipperOneClient().get();
  StreamSubscription<Map<String, String>>? _sub;
  Map<String, String> _info = const {};

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _subscribe();
  }

  @override
  void didUpdateWidget(covariant StorageUsageCards old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !old.enabled) {
      _subscribe();
    } else if (!widget.enabled && old.enabled) {
      _sub?.cancel();
      _sub = null;
      setState(() => _info = const {});
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = _client.watchStorage().listen(
      (data) {
        if (!mounted || data.isEmpty) return;
        setState(() => _info = {..._info, ...data});
      },
      onError: (e) => LogService.log('[StorageCards] watchStorage: $e'),
    );
  }

  double? _percent(String prefix) {
    final raw = _info['$prefix.used_percent'];
    if (raw != null) {
      final parsed = double.tryParse(raw.replaceAll('%', '').trim());
      if (parsed != null) return parsed.clamp(0.0, 100.0);
    }
    final used = int.tryParse(_info['$prefix.used_bytes'] ?? '');
    final total = int.tryParse(_info['$prefix.total_bytes'] ?? '');
    if (used != null && total != null && total > 0) {
      return (used / total * 100).clamp(0.0, 100.0);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final loading = enabled && _info.isEmpty;

    final extPercent = _percent('storage.sdcard');
    final extUsed = _info['storage.sdcard.used'];
    final intUsed = _info['storage.internal.used'];

    return Row(
      children: [
        Expanded(
          child: _StorageCard(
            title: 'Internal',
            icon: Icons.smartphone,
            enabled: enabled,
            loading: loading,
            onTap: widget.onOpenInternal,
            // `/int` capacity isn't exposed, so no fill bar — just used size.
            percent: null,
            usageText: intUsed,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StorageCard(
            title: 'External',
            icon: Icons.sd_card,
            enabled: enabled,
            loading: loading,
            onTap: widget.onOpenExternal,
            percent: extPercent,
            usageText: extUsed,
          ),
        ),
      ],
    );
  }
}

class _StorageCard extends StatelessWidget {
  const _StorageCard({
    required this.title,
    required this.icon,
    required this.enabled,
    required this.loading,
    required this.onTap,
    required this.percent,
    required this.usageText,
  });

  static const double _iconSize = 38;

  final String title;
  final IconData icon;
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;
  final double? percent;
  final String? usageText;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tint = enabled ? colors.accent : colors.textMuted;
    final barColor = (percent != null && percent! > 90)
        ? colors.danger
        : colors.accent;

    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: _iconSize,
                height: _iconSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 21, color: tint),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: enabled
                                  ? colors.textPrimary
                                  : colors.textMuted,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _usageLabel(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: _barValue(),
                        minHeight: 5,
                        color: barColor,
                        backgroundColor: colors.divider,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `null` → indeterminate (loading). Internal has no capacity, so its bar
  /// rests at 0 once loaded; external reflects the real usage ratio.
  double? _barValue() {
    if (!enabled) return 0;
    if (percent != null) return (percent! / 100).clamp(0.0, 1.0);
    if (loading && usageText == null) return null;
    return 0;
  }

  String _usageLabel() {
    if (!enabled) return '—';
    if (usageText != null) return usageText!;
    return loading ? '…' : '';
  }
}
