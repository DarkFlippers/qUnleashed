import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../models/archive_key.dart';
import 'emulate_service.dart';

class EmulatePage extends StatefulWidget {
  const EmulatePage({super.key, required this.flipperKey});

  final ArchiveKey flipperKey;

  @override
  State<EmulatePage> createState() => _EmulatePageState();
}

class _EmulatePageState extends State<EmulatePage> {
  final EmulateService _service = EmulateService();
  bool _starting = true;
  bool _running = false;
  EmulateError? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final result = await _service.start(widget.flipperKey);
    if (!mounted) return;
    setState(() {
      _starting = false;
      _running = result.isOk;
      _error = result.error;
    });
  }

  Future<void> _stopAndClose() async {
    await _service.stop();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    if (_running) {
      _service.stop();
    }
    super.dispose();
  }

  String _errorMessage(EmulateError? e) {
    switch (e) {
      case EmulateError.notConnected:
        return 'Flipper не подключён';
      case EmulateError.notEmulatable:
        return 'Этот тип файла нельзя эмулировать';
      case EmulateError.appStartFailed:
        return 'Не удалось открыть приложение на Flipper';
      case EmulateError.loadFileFailed:
        return 'Не удалось загрузить файл в приложение';
      case null:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final k = widget.flipperKey;

    return PopScope(
      canPop: !_running,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _stopAndClose();
      },
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          title: Text('Emulate · ${k.category.title}'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: k.category.color.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SvgPicture.asset(
                          k.category.asset,
                          width: 32,
                          height: 32,
                          colorFilter: ColorFilter.mode(
                              k.category.color, BlendMode.srcIn),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              k.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              k.remotePath,
                              style: TextStyle(
                                  color: colors.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(child: _buildStatus(context)),
                if (_running)
                  ElevatedButton.icon(
                    onPressed: _stopAndClose,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop emulation'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.danger,
                      foregroundColor: colors.onAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  )
                else
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.card,
                      foregroundColor: colors.textPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Close'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatus(BuildContext context) {
    final colors = context.appColors;
    if (_starting) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colors.accent),
            const SizedBox(height: 16),
            Text('Запуск приложения на Flipper…',
                style: TextStyle(color: colors.textSecondary)),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: colors.danger),
            const SizedBox(height: 12),
            Text(
              _errorMessage(_error),
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.contactless,
            size: 64,
            color: colors.accent,
          ),
          const SizedBox(height: 16),
          Text(
            'Файл загружен на Flipper',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Используйте кнопки Flipper для запуска.\nStop закроет приложение.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textMuted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}
