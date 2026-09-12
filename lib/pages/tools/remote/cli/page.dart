import '../../../../services/localization/l10n.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import 'package:qunleashed/components/appbar.dart';
import '../../../../components/dialogs/connection_error.dart';
import '../../../../components/dialogs/connection.dart';
import '../../../../services/logging.dart';

const _kBackgroundColor = Color(0xFF000000);
const _kForegroundColor = Color(0xFFE0E0E0);

class CliPage extends StatefulWidget {
  const CliPage({super.key, this.client});

  /// Supplied by tests only; the app always uses the shared client, which is
  /// otherwise reached through a singleton no test can replace.
  final FlipperClient? client;

  @override
  State<CliPage> createState() => _CliPageState();
}

class _CliPageState extends State<CliPage> {
  late final FlipperClient _client = widget.client ?? FlipperOneClient().get();
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

  /// Runs [send] and puts whatever it throws in the log, so the future it
  /// returns never rejects and something else can be chained behind it.
  ///
  /// [Future.sync] is the point. `FlipperClient.writeCliBytes` is not async,
  /// so a session that is gone throws before there is a future to attach a
  /// handler to, while a session whose transport has been torn down, one
  /// already back in RPC mode, and the write itself all reject instead. Both
  /// StateErrors read "No active transport", so the difference is easy to
  /// miss; running the call inside Future.sync puts both in the same place.
  static Future<void> _guarded(
    Future<void> Function() send,
    String what, {
    Duration? timeout,
  }) {
    final call = Future.sync(send);
    return (timeout == null ? call : call.timeout(timeout)).catchError(
      (Object e, StackTrace st) =>
          LogService.error('[CLI] $what failed: $e\n$st'),
    );
  }

  /// Says something in the terminal itself, on its own line and in red.
  ///
  /// The one surface the user is actually looking at. Everything below used to
  /// reach `LogService` only, and `LogService.enabled` is
  /// `bool.fromEnvironment('QLOG', defaultValue: kDebugMode)` — so in a release
  /// build a failed write drew nothing at all, and a terminal that silently
  /// eats keystrokes is indistinguishable from a Flipper that has hung.
  void _notice(String message) =>
      _terminal.write('\r\n\x1b[31m$message\x1b[0m\r\n');

  /// Sends something the user is waiting on, and says so when it does not
  /// arrive.
  ///
  /// Drops [_ready] as well. Every way `writeCliBytes` fails means the session
  /// is gone — no transport, or already back in RPC mode — so leaving it set
  /// gives a terminal that keeps taking keystrokes it cannot deliver and draws
  /// one more red line for each. Backing out and re-entering the page is how a
  /// working session is got back, which is what a disconnect already required.
  void _fireAndShow(Future<void> Function() send, String what) {
    unawaited(
      Future.sync(send).catchError((Object e, StackTrace st) {
        LogService.error('[CLI] $what failed: $e\n$st');
        if (!mounted) return;
        _notice(l10n.cliWriteFailed('$e'));
        if (_ready) setState(() => _ready = false);
      }),
    );
  }

  @override
  void dispose() {
    _textSub?.cancel();
    _connSub?.cancel();
    // Stays ahead of enterRpcMode: switchToRpcMode refuses outright while
    // cliExclusive is set, so reordering these two breaks every USB teardown.
    _client.cliExclusive = false;

    // dispose() cannot be async, so there is nowhere to await this and no UI
    // left to report into if it fails. Best effort, logged.
    //
    // Chained ahead of the switch rather than fired alongside it. Unsequenced,
    // the two raced: _doSwitchToRpcMode flips mode partway through, so the
    // interrupt either arrived after it and died on "Cannot send CLI bytes
    // while in RPC mode" - logged as though the cable had been pulled - or
    // landed as a stray 0x03 inside an RPC stream.
    //
    // The wait is bounded because the write need not ever finish. Desktop USB
    // hands it to an isolate and waits on a completer with no timeout of its
    // own (Android's has ten seconds), so a wedged port would otherwise hold
    // the RPC restore open for the life of the process.
    final interrupt = _awaitingInterrupt
        ? _guarded(
            () => _client.writeCliBytes(Uint8List.fromList([0x03])),
            'ctrl-c on dispose',
            timeout: const Duration(seconds: 2),
          )
        : Future<void>.value();

    if (_client.connectedDevice?.isBle != true) {
      // enterRpcMode returns quietly when the session is already gone, but the
      // switch it returns can still reject, and unawaited silences the lint
      // rather than the error.
      unawaited(
        interrupt.then(
          (_) => _guarded(_client.enterRpcMode, 'leaving cli mode'),
        ),
      );
    } else {
      unawaited(interrupt);
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
    _fireAndShow(() => _client.writeCliBytes(bytes), 'write');
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
    } catch (e, st) {
      // Everything the inner handlers do not already report: a throw out of
      // the connection dialog, a Navigator error, setState on a dead element -
      // or _showConnectionFailedDialog itself failing, which is the bad one.
      // That downgrades a connection error the user never saw to a log line
      // and leaves the page mounted, black and not ready, with nothing to do
      // but back out. The stack is what separates those from one another.
      LogService.error('[CLI] bootstrap failed: $e\n$st');
      if (mounted) _notice(l10n.cliStartFailed('$e'));
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
      await _client.connect(selected, autoRpc: false);
    } catch (e) {
      LogService.log('[CLI] connect failed: $e');
      await _showConnectionFailedDialog(selected, e);
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
      await _client.connect(device, autoRpc: false);
    } catch (e) {
      LogService.log('[CLI] reconnect failed: $e');
      await _showConnectionFailedDialog(device, e);
      if (mounted) {
        Navigator.of(context).maybePop();
      }
      return;
    }
    await _enterCliReady();
  }

  Future<void> _showConnectionFailedDialog(
    FlipperDevice device,
    Object error,
  ) async {
    if (!mounted) return;
    await showConnectionFailedDialog(context, error, isBle: device.isBle);
  }

  Future<void> _enterCliReady() async {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _terminalFocusNode.requestFocus();
    });
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    try {
      await _client.writeCliBytes(Uint8List.fromList([0x01]));
    } catch (e, st) {
      // Ready is claimed after the nudge lands, not before it is sent. Claimed
      // first, a nudge that failed left a black terminal that took every
      // keystroke and posted it into a session that had never been opened.
      LogService.error('[CLI] init nudge failed: $e\n$st');
      _notice(l10n.cliStartFailed('$e'));
      return;
    }
    setState(() {
      _ready = true;
    });
  }

  void _onConnectionState(FlipperConnectionState state) {
    if (!mounted) return;
    if (!state.connected && _ready) {
      // One line here explains every failure that would otherwise follow it,
      // and without it the terminal simply stops answering.
      _notice(l10n.cliDisconnected);
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
    _fireAndShow(
      () => _client.writeCliBytes(Uint8List.fromList([0x03])),
      'ctrl-c',
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
            tooltip: context.l10n.cliSendCtrlC,
            onPressed: _ready ? _sendCtrlC : null,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
          QPageAppBarAction(
            tooltip: context.l10n.commonClear,
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
