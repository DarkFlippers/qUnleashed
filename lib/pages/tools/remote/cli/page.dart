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

  /// Whether the terminal has already said that a write did not arrive.
  ///
  /// One line, not one per keystroke. Clearing [_ready] instead would stop new
  /// input but not the writes already in flight — on Android a write can sit
  /// for ten seconds before it rejects, so a whole burst fails at once — and it
  /// would not be safe anyway: Android USB fails a single write on a
  /// PlatformException without raising a transport fault, so one transient
  /// error would leave the page permanently dead with nothing on screen saying
  /// how to revive it. A session that has really gone raises a disconnect, and
  /// [_onConnectionState] is what acts on that.
  ///
  /// Cleared when the device says anything, since that proves the link works
  /// and makes the next failure news again.
  bool _writeFailureShown = false;

  static final Uint8List _ctrlC = Uint8List.fromList(const [0x03]);
  static final Uint8List _cliNudge = Uint8List.fromList(const [0x01]);

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
    void Function(Object error)? onFailure,
  }) {
    final call = Future.sync(send);
    return (timeout == null ? call : call.timeout(timeout)).catchError((
      Object e,
      StackTrace st,
    ) {
      LogService.error('[CLI] $what failed: $e\n$st');
      onFailure?.call(e);
    });
  }

  /// Says something in the terminal itself, on its own line and in red.
  ///
  /// The one surface the user is actually looking at. Everything below used to
  /// reach `LogService` only, and `LogService.enabled` is
  /// `bool.fromEnvironment('QLOG', defaultValue: kDebugMode)` — so in a release
  /// build a failed write drew nothing at all, and a terminal that silently
  /// eats keystrokes is indistinguishable from a Flipper that has hung.
  ///
  /// Not a `QNotification`, which is how the rest of the app reports a failure:
  /// a toast that dismisses itself after two seconds and closes the one before
  /// it is the wrong shape here. A terminal's errors belong in the scrollback,
  /// beside the output they interrupted, for as long as the output lasts.
  ///
  /// Control characters are stripped from [message] before it goes in. It
  /// carries exception text, and that in turn carries driver and OS strings —
  /// anything holding an escape byte would otherwise break out of the colour
  /// and drive the emulator.
  void _notice(String message) => _terminal.write(
    '\r\n\x1b[31m${message.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')}'
    '\x1b[0m\r\n',
  );

  /// Sends something the user is waiting on, and says so when it does not
  /// arrive.
  void _fireAndShow(Future<void> Function() send, String what) =>
      unawaited(_guarded(send, what, onFailure: _reportWriteFailure));

  void _reportWriteFailure(Object error) {
    if (!mounted || _writeFailureShown) return;
    _writeFailureShown = true;
    _notice(l10n.cliWriteFailed('$error'));
  }

  @override
  void dispose() {
    _textSub?.cancel();
    _connSub?.cancel();
    // Stays ahead of enterRpcMode: switchToRpcMode refuses outright while
    // cliExclusive is set, so reordering these two breaks every USB teardown.
    _client.cliExclusive = false;

    // dispose() cannot be async, so there is nowhere to await either of these
    // and no UI left to report into if they fail. Best effort, logged.
    //
    // The interrupt goes first and the switch waits for it. Unsequenced, the
    // two raced: _doSwitchToRpcMode flips mode partway through, so the ctrl-c
    // either arrived after it and died on "Cannot send CLI bytes while in RPC
    // mode" - logged as though the cable had been pulled - or landed as a
    // stray 0x03 inside an RPC stream.
    //
    // The wait is bounded because the write need not ever finish: desktop USB
    // hands it to an isolate and waits on a completer with no timeout of its
    // own, where Android's has ten seconds. Bounding it narrows the race
    // rather than closing it, since a timeout abandons the wait without
    // cancelling the write - the bytes are still in the transport's pump and
    // can still land late. Holding the restore open for the life of the
    // process is the worse trade. Note for tests: a dispose with a write in
    // flight leaves this timer pending, so they have to pump past it.
    //
    // Everything about the client is read here, synchronously, rather than
    // inside the chain. Read two seconds later, connectedDevice may be null
    // and the BLE test would invert; and holding _client in the closure keeps
    // a disposed State alive with it.
    final client = _client;
    final device = client.connectedDevice;
    final restoreRpc = device?.isBle != true;

    Future<void> teardown() async {
      if (_awaitingInterrupt) {
        await _guarded(
          () => client.writeCliBytes(_ctrlC),
          'ctrl-c on dispose',
          timeout: const Duration(seconds: 2),
        );
      }
      // Not the session this page had, by now: the wait above can span a
      // couple of seconds, and cliExclusive is re-read from whatever session
      // is active, so a fresh CLI page would not be protected from this. It
      // would be switched to RPC mode under itself and its nudge would fail.
      if (!restoreRpc || !identical(client.connectedDevice, device)) return;
      // enterRpcMode returns quietly when the session is already gone, but the
      // switch it returns can still reject.
      await _guarded(client.enterRpcMode, 'leaving cli mode');
    }

    unawaited(teardown());
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
    // utf8.encode returns a Uint8List already; wrapping it in
    // Uint8List.fromList copied the buffer once per keystroke.
    final bytes = utf8.encode(data);
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
    } catch (e, st) {
      LogService.error('[CLI] connect failed: $e\n$st');
      // Into the terminal before the dialog, not after: if the dialog itself
      // throws, this is the only place the real reason survives - the outer
      // catch would otherwise draw the dialog's failure instead.
      if (mounted) _notice(l10n.cliStartFailed('$e'));
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
    } catch (e, st) {
      LogService.error('[CLI] reconnect failed: $e\n$st');
      // As above: the reason reaches the scrollback before anything that could
      // throw on the way to showing it.
      if (mounted) _notice(l10n.cliStartFailed('$e'));
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
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    try {
      await _client.writeCliBytes(_cliNudge);
    } catch (e, st) {
      // Ready is claimed after the nudge lands, not before it is sent. Claimed
      // first, a nudge that failed left a black terminal that took every
      // keystroke and posted it into a session that had never been opened.
      LogService.error('[CLI] init nudge failed: $e\n$st');
      if (mounted) _notice(l10n.cliStartFailed('$e'));
      return;
    }
    // The write is a second suspension point, and the page can be backed out
    // of while it is in flight. Without this the setState below throws
    // "called after dispose()", which unwinds all the way to _bootstrap's
    // catch and is reported there as a bootstrap failure.
    if (!mounted) return;
    setState(() {
      _ready = true;
    });
    // After the session is known good, not before it is opened: registered
    // ahead of any setState, this asked for focus on a terminal that might
    // never accept anything.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _terminalFocusNode.requestFocus();
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
    // The device answered, so the link works and the next write that does not
    // arrive is news again rather than more of the same failure.
    _writeFailureShown = false;
    _terminal.write(text);
  }

  void _clearOutput() {
    _terminal.write('\x1b[2J\x1b[H');
    _terminalFocusNode.requestFocus();
  }

  void _sendCtrlC() {
    if (!_ready) return;
    _fireAndShow(() => _client.writeCliBytes(_ctrlC), 'ctrl-c');
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
