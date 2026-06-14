import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../theme.dart';
import 'package:qunleashed/components/appbar.dart';
import 'package:qunleashed/models/colors/category.dart';
import '../../../../widgets/notification.dart';
import '../../../../widgets/progress_button.dart';

typedef IrFileSendHandler =
    Future<bool> Function({
      required List<int> bytes,
      required void Function(double progress) onProgress,
    });

typedef IrFileAfterSend = Future<void> Function(List<int> bytes);

const _infraredAsset = 'assets/ic/fileformat/ir.svg';

class IrFileViewer extends StatefulWidget {
  const IrFileViewer({
    super.key,
    required this.fileName,
    required this.subtitle,
    required this.loading,
    required this.error,
    required this.text,
    required this.bytes,
    required this.isConnected,
    required this.onSend,
    this.onAfterSend,
  });

  final String fileName;
  final String subtitle;
  final bool loading;
  final String? error;
  final String text;
  final List<int>? bytes;
  final bool isConnected;
  final IrFileSendHandler onSend;
  final IrFileAfterSend? onAfterSend;

  @override
  State<IrFileViewer> createState() => _IrFileViewerState();
}

class _IrFileViewerState extends State<IrFileViewer> {
  final FlipperClient _client = FlipperOneClient().get();
  bool _sending = false;
  bool _connected = false;
  double _sendProgress = 0;
  final ScrollController _viewScroll = ScrollController();
  StreamSubscription<FlipperConnectionState>? _connectionSub;

  @override
  void initState() {
    super.initState();
    _connected = widget.isConnected && _client.isConnected;
    _connectionSub = _client.connectionStream.listen(_onConnectionState);
  }

  @override
  void didUpdateWidget(covariant IrFileViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isConnected != widget.isConnected) {
      _connected = widget.isConnected && _client.isConnected;
    }
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _viewScroll.dispose();
    super.dispose();
  }

  void _onConnectionState(FlipperConnectionState state) {
    if (!mounted) return;
    setState(() {
      _connected = state.connected;
      if (!state.connected) {
        _sending = false;
        _sendProgress = 0;
      }
    });
  }

  Future<void> _send() async {
    final bytes = widget.bytes;
    if (bytes == null) return;
    if (!_connected) {
      context.showNotification(
        'Connect a Flipper first',
        type: QNotificationType.warning,
      );
      return;
    }
    setState(() {
      _sending = true;
      _sendProgress = 0;
    });
    final ok = await widget.onSend(
      bytes: bytes,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _sendProgress = p);
      },
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok && widget.onAfterSend != null) {
      await widget.onAfterSend!(bytes);
    }
    if (!mounted) return;
    context.showNotification(
      ok ? 'Sent to Flipper' : 'Failed to send to Flipper',
      type: ok ? QNotificationType.good : QNotificationType.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: QPageAppBar(
        title: widget.fileName,
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
      ),
      body: _buildBody(colors),
    );
  }

  Widget _buildBody(QAppColors colors) {
    if (widget.loading) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (widget.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            widget.error!,
            style: TextStyle(color: colors.danger),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final infraredColor = ArchiveCategoryColor.infrared.color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: infraredColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SvgPicture.asset(
                  _infraredAsset,
                  width: 22,
                  height: 22,
                  colorFilter: ColorFilter.mode(infraredColor, BlendMode.srcIn),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      widget.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
          child: ProgressButton(
            text: 'SEND TO DEVICE',
            color: colors.accent,
            progress: _sending ? _sendProgress : null,
            showPercent: _sending,
            onPressed: _sending ? null : _send,
            height: 48,
            borderRadius: 10,
            horizontalPadding: 16,
            textStyle: ProgressButton.defaultTextStyle.copyWith(fontSize: 22),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                width: constraints.maxWidth - 28,
                decoration: BoxDecoration(
                  color: colors.terminalBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.divider),
                ),
                child: Scrollbar(
                  controller: _viewScroll,
                  child: SingleChildScrollView(
                    controller: _viewScroll,
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: SelectableText(
                        widget.text,
                        style: TextStyle(
                          color: colors.terminalText,
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
