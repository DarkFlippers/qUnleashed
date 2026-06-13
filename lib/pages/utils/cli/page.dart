import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../../theme.dart';
import 'package:qunleashed/components/appbar.dart';
import '../../../widgets/flipper_action_dialog.dart';
import '../../../components/dialogs/connection.dart';

const _kBackgroundColor = Color(0xFF000000);
const _kForegroundColor = Color(0xFFE0E0E0);

class CliPage extends StatefulWidget {
  const CliPage({super.key});

  @override
  State<CliPage> createState() => _CliPageState();
}

class _CliPageState extends State<CliPage> {
  final FlipperClient _client = FlipperOneClient().get();
  final FocusNode _terminalFocusNode = FocusNode(debugLabel: 'cli-terminal');

  late final Terminal _terminal;
  late final TerminalController _terminalController;

  StreamSubscription<String>? _textSub;
  StreamSubscription<FlipperConnectionState>? _connSub;

  bool _ready = false;
  bool _busy = false;
  bool _awaitingInterrupt = false;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(
      maxLines: 10000,
      onOutput: _onTerminalOutput,
      platform: _platform,
    );
    _terminalController = TerminalController();
    _client.cliExclusive = true;
    _connSub = _client.connectionStream.listen(_onConnectionState);
    _textSub = _client.textStream.listen(_onText);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _textSub?.cancel();
    _connSub?.cancel();
    if (_awaitingInterrupt) {
      try {
        _client.writeCliBytes(Uint8List.fromList([0x03]));
      } catch (_) {}
    }
    _client.cliExclusive = false;
    if (_client.connectedDevice?.isBle != true) {
      unawaited(_client.enterRpcMode());
    }
    _terminalController.dispose();
    _terminalFocusNode.dispose();
    super.dispose();
  }

  TerminalTargetPlatform get _platform {
    if (kIsWeb) return TerminalTargetPlatform.unknown;
    if (Platform.isAndroid) return TerminalTargetPlatform.android;
    if (Platform.isIOS) return TerminalTargetPlatform.ios;
    if (Platform.isWindows) return TerminalTargetPlatform.windows;
    if (Platform.isMacOS) return TerminalTargetPlatform.macos;
    if (Platform.isLinux) return TerminalTargetPlatform.linux;
    return TerminalTargetPlatform.unknown;
  }

  void _onTerminalOutput(String data) {
    if (!_ready) return;
    final bytes = Uint8List.fromList(utf8.encode(data));
    unawaited(
      _client.writeCliBytes(bytes).catchError((Object e) {
        LogService.log('[CLI] write error: $e');
      }),
    );
  }

  Future<void> _bootstrap() async {
    if (_busy) return;
    _busy = true;
    try {
      final device = _client.connectedDevice;
      if (device == null) {
        await _promptForDevice();
        return;
      }
      if (device.isBle) {
        if (mounted) {
          Navigator.of(context).maybePop();
        }
        return;
      }
      await _resetUsbCliSession(device);
    } catch (e) {
      LogService.log('[CLI] bootstrap failed: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _promptForDevice() async {
    if (!mounted) return;
    final selected = await showConnectionDialog(
      context,
      usbOnly: true,
      skipRpc: true,
    );
    if (!mounted) return;
    if (selected == null) {
      Navigator.of(context).maybePop();
      return;
    }
    if (selected.isBle) {
      return;
    }
    try {
      await _client.connect(selected);
    } catch (e) {
      LogService.log('[CLI] connect failed: $e');
      await _showConnectionFailedDialog(selected);
      if (mounted) {
        Navigator.of(context).maybePop();
      }
      return;
    }
    await _enterCliReady();
  }

  Future<void> _resetUsbCliSession(FlipperDevice device) async {
    try {
      await _client.disconnect();
      await _client.connect(device);
    } catch (e) {
      LogService.log('[CLI] reconnect failed: $e');
      await _showConnectionFailedDialog(device);
      if (mounted) {
        Navigator.of(context).maybePop();
      }
      return;
    }
    await _enterCliReady();
  }

  Future<void> _showConnectionFailedDialog(FlipperDevice device) async {
    if (!mounted) return;

    final text = device.isBle
        ? 'Turn Bluetooth off and on in the Flipper Zero system menu, then connect again. Restart the app only if that does not help.'
        : 'Unplug the device and plug it back in, then connect again. Restart the app only if that does not help.';

    await showDialog<void>(
      context: context,
      barrierColor: context.appColors.dialogBarrier,
      builder: (dialogContext) {
        return FlipperActionDialog(
          imageAssetPath: 'assets/pic/mifare/shrug-black.svg',
          imageSize: const Size(147.5, 95.8),
          title: 'Connection failed',
          text: text,
          actionText: 'OK',
          onAction: () => Navigator.of(dialogContext).pop(),
        );
      },
    );
  }

  Future<void> _enterCliReady() async {
    if (!mounted) return;
    setState(() {
      _ready = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _terminalFocusNode.requestFocus();
    });
    await Future<void>.delayed(const Duration(milliseconds: 500));
    try {
      await _client.writeCliBytes(Uint8List.fromList([0x01]));
    } catch (e) {
      LogService.log('[CLI] init nudge failed: $e');
    }
  }

  void _onConnectionState(FlipperConnectionState state) {
    if (!mounted) return;
    if (!state.connected && _ready) {
      setState(() {
        _ready = false;
      });
    }
  }

  void _onText(String text) {
    _awaitingInterrupt = !text.contains('>:');
    _terminal.write(text);
  }

  void _clearOutput() {
    _terminal.write('\x1b[2J\x1b[H');
    _terminalFocusNode.requestFocus();
  }

  void _sendCtrlC() {
    if (!_ready) return;
    unawaited(
      _client
          .writeCliBytes(Uint8List.fromList([0x03]))
          .catchError((Object e) => LogService.log('[CLI] ctrl-c failed: $e')),
    );
    _terminalFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackgroundColor,
      appBar: QPageAppBar(
        title: 'CLI',
        backgroundColor: _kBackgroundColor,
        foregroundColor: Colors.white,
        actions: [
          QPageAppBarAction(
            tooltip: 'Send Ctrl+C',
            onPressed: _ready ? _sendCtrlC : null,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
          QPageAppBarAction(
            tooltip: 'Clear',
            onPressed: _clearOutput,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return _buildTerminal();
  }

  Widget _buildTerminal() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 800;
        final fontSize = isCompact ? 6.0 : 13.0;
        final padding = isCompact ? 3.0 : 8.0;
        return TerminalView(
          _terminal,
          controller: _terminalController,
          focusNode: _terminalFocusNode,
          autofocus: true,
          backgroundOpacity: 1.0,
          padding: EdgeInsets.all(padding),
          cursorType: TerminalCursorType.block,
          alwaysShowCursor: true,
          keyboardType: TextInputType.text,
          hardwareKeyboardOnly: _useHardwareKeyboardOnly,
          theme: _terminalTheme,
          textStyle: TerminalStyle(
            fontSize: fontSize,
            fontFamily: _monospaceFontFamily,
            fontFamilyFallback: _monospaceFallback,
          ),
        );
      },
    );
  }
}

bool get _useHardwareKeyboardOnly {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}

const String _monospaceFontFamily = 'monospace';

const List<String> _monospaceFallback = [
  'Cascadia Mono',
  'Consolas',
  'Courier New',
  'Menlo',
  'Monaco',
  'DejaVu Sans Mono',
  'Liberation Mono',
  'Roboto Mono',
  'monospace',
];

const TerminalTheme _terminalTheme = TerminalTheme(
  cursor: _kForegroundColor,
  selection: Color(0x66BBBBBB),
  foreground: _kForegroundColor,
  background: _kBackgroundColor,
  black: Color(0xFF000000),
  red: Color(0xFFE06C75),
  green: Color(0xFF98C379),
  yellow: Color(0xFFE5C07B),
  blue: Color(0xFF61AFEF),
  magenta: Color(0xFFC678DD),
  cyan: Color(0xFF56B6C2),
  white: Color(0xFFD0D0D0),
  brightBlack: Color(0xFF5C6370),
  brightRed: Color(0xFFE06C75),
  brightGreen: Color(0xFF98C379),
  brightYellow: Color(0xFFE5C07B),
  brightBlue: Color(0xFF61AFEF),
  brightMagenta: Color(0xFFC678DD),
  brightCyan: Color(0xFF56B6C2),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFF888888),
  searchHitBackgroundCurrent: Color(0xFFFFFFFF),
  searchHitForeground: Color(0xFF000000),
);
