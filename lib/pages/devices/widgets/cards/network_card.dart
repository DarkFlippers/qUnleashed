import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../../theme/theme.dart';
import 'summary_card.dart';

class NetworkSummaryCard extends StatelessWidget {
  const NetworkSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ValueListenableBuilder<NetworkTrafficSnapshot>(
      valueListenable: NetworkTrafficMonitor.instance.snapshot,
      builder: (context, traffic, _) {
        final host = traffic.host;
        return DashboardCard(
          title: 'Network',
          icon: Icons.public,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _Metric(label: 'TX', value: _bytes(traffic.txBytes)),
                        const SizedBox(width: 12),
                        _TrafficArrow(
                          direction: NetworkDirection.tx,
                          bytes: traffic.txBytes,
                          color: colors.accent,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _Metric(label: 'RX', value: _bytes(traffic.rxBytes)),
                        const SizedBox(width: 12),
                        _TrafficArrow(
                          direction: NetworkDirection.rx,
                          bytes: traffic.rxBytes,
                          color: colors.success,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Divider(height: 1, color: colors.divider),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Field(
                      label: 'Domain',
                      value: host == null || host.isEmpty ? '—' : host,
                      muted: host == null || host.isEmpty,
                      align: CrossAxisAlignment.start,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _Field(
                    label: 'Total',
                    value: _bytes(traffic.txBytes + traffic.rxBytes),
                    align: CrossAxisAlignment.end,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static String _bytes(int value) {
    if (value < 1024) return '$value B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var size = value / 1024;
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[unit]}';
  }
}

/// A chunky arrow tile that pulses on each burst of traffic and fades back
/// while idle. Up arrow = TX (uplink), down arrow = RX (downlink).
class _TrafficArrow extends StatefulWidget {
  const _TrafficArrow({
    required this.direction,
    required this.bytes,
    required this.color,
  });

  final NetworkDirection direction;
  final int bytes;
  final Color color;

  @override
  State<_TrafficArrow> createState() => _TrafficArrowState();
}

class _TrafficArrowState extends State<_TrafficArrow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: 0,
  );

  @override
  void didUpdateWidget(_TrafficArrow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bytes > oldWidget.bytes) _pulse();
  }

  void _pulse() {
    _controller
      ..stop()
      ..value = 1.0;
    _controller.animateTo(0.0, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isTx = widget.direction == NetworkDirection.tx;
    final icon = isTx
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final pulse = Curves.easeOut.transform(_controller.value);
        final scale = 1.0 + 0.12 * pulse;
        return Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Color.lerp(colors.divider, widget.color, pulse),
            borderRadius: BorderRadius.circular(14),
            boxShadow: pulse > 0
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.45 * pulse),
                      blurRadius: 14 * pulse,
                      spreadRadius: 1 * pulse,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Transform.scale(
            scale: scale,
            child: Icon(
              icon,
              size: 30,
              color: Color.lerp(colors.textMuted, colors.onAccent, pulse),
            ),
          ),
        );
      },
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    required this.align,
    this.muted = false,
  });

  final String label;
  final String value;
  final CrossAxisAlignment align;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isEnd = align == CrossAxisAlignment.end;
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: isEnd ? TextAlign.end : TextAlign.start,
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: .5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: isEnd ? TextAlign.end : TextAlign.start,
          style: TextStyle(
            color: muted ? colors.textMuted : colors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: .5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 12,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
