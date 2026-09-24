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
import '../../../../services/guarded.dart';
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

  FlipperCliChannel? _channel;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  /// Says something in the terminal itself, on its own line and in red.
  ///
  /// The one surface the user is actually looking at. Everything below used to
  /// reach `LogService` only, which drew nothing at all in a release build —
  /// and since #89 keeps the error in a buffer instead, still nothing the user
  /// sees while it is happening. A terminal that silently eats keystrokes is
  /// indistinguishable from a Flipper that has hung.
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
  ///
  /// This page is where the sync-versus-async split that shaped [guarded] came
  /// from. `FlipperClient.writeCliBytes` is not async, so a session that is
  /// already gone throws before there is a future to attach a handler to, while
  /// a session whose transport has been torn down, one already back in RPC
  /// mode, and the write itself all reject instead. The first two both read
  /// "No active transport", so which of them happened is easy to mistake; the
  /// Future.sync inside [guarded] puts all four in one place.
  void _fireAndShow(Future<void> Function() send, String what) =>
      unawaited(guarded('[CLI] $what', send, onFailure: _reportWriteFailure));

  void _reportWriteFailure(Object error) {
    if (!mounted || _writeFailureShown) return;
    _writeFailureShown = true;
    _notice(l10n.cliWriteFailed('$error'));
  }

  @override
  void dispose() {
    _textSub?.cancel();
    _connSub?.cancel();

    // dispose() cannot be async, so there is nowhere to await either of these
    // and no UI left to report into if they fail. Best effort, logged.
    //
    // The interrupt goes first and the close waits for it. Unsequenced, the
    // two raced: the RPC switch inside close flips mode partway through, so
    // the ctrl-c either arrived after it and died on "Cannot send CLI bytes
    // while in RPC mode" - logged as though the cable had been pulled - or
    // landed as a stray 0x03 inside an RPC stream.
    //
    // The wait is bounded because the write need not ever finish: desktop USB
    // hands it to an isolate and waits on a completer with no timeout of its
    // own, where Android's has ten seconds. Bounding it narrows the race
    // rather than closing it, since a timeout abandons the wait without
    // cancelling the write - the bytes are still in the transport's pump and
    // can still land late. Holding the close open for the life of the process
    // is the worse trade. Note for tests: a dispose with a write in flight
    // leaves this timer pending, so they have to pump past it.
    final channel = _channel;
    final awaitingInterrupt = _awaitingInterrupt;

    Future<void> teardown() async {
      if (channel == null) return;
      if (awaitingInterrupt) {
        // The bound is inside the task rather than around guarded, so a
        // TimeoutException is reported like any other failure here.
        await guarded(
          '[CLI] ctrl-c on dispose',
          () => channel.write(_ctrlC).timeout(const Duration(seconds: 2)),
        );
      }
      // The channel is bound to the session this page opened, so a fresh CLI
      // page on another device is never handed back to RPC under itself.
      await guarded('[CLI] leaving cli mode', channel.close);
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
    final channel = _channel;
    if (!_ready || channel == null) return;
    // utf8.encode returns a Uint8List already; wrapping it in
    // Uint8List.fromList copied the buffer once per keystroke.
    final bytes = utf8.encode(data);
    _fireAndShow(() => channel.write(bytes), 'write');
  }

  Future<void> _bootstrap() async {
    if (_busy) return;
    _busy = true;
    try {
      final device = _client.connectedDevice;
      if (device == null || !device.isUsb) {
        await _promptForDevice();
        return;
      }
      await _openChannel(device);
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
    final selected = await showConnectionDialog(context, usbOnly: true);
    if (!mounted) return;
    if (selected == null || !selected.isUsb) {
      Navigator.of(context).maybePop();
      return;
    }
    await _openChannel(selected);
  }

  /// One call whatever the link is in: no session opens one, a session in RPC
  /// is switched over, a session already in CLI is used as it is.
  Future<void> _openChannel(FlipperDevice device) async {
    final FlipperCliChannel channel;
    try {
      channel = await _client.openCli(device);
    } catch (e, st) {
      LogService.error('[CLI] open failed: $e\n$st');
      // Into the terminal before the dialog, not after: if the dialog itself
      // throws, this is the only place the real reason survives - the outer
      // catch would otherwise draw the dialog's failure instead.
      if (mounted) _notice(l10n.cliStartFailed('$e'));
      await _showConnectionFailedDialog(device, e);
      if (mounted) {
        Navigator.of(context).maybePop();
      }
      return;
    }
    if (!mounted) {
      unawaited(guarded('[CLI] close after leaving', channel.close));
      return;
    }
    _channel = channel;
    _connSub = channel.connection.listen(_onConnectionState);
    _textSub = channel.text.listen(_onText);
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
    final channel = _channel;
    if (!mounted || channel == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    try {
      await channel.write(_cliNudge);
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
    // Losing CLI, not just losing the link. A session switched to RPC under
    // this page - FlipperConnectionEvent.modeChanged - leaves it connected to a
    // stream that is no longer text, and a terminal that silently swallows
    // keystrokes is worse than one that says why it stopped. Asking cliReady
    // rather than watching for that event also covers the case where it was
    // raised before this page subscribed.
    //
    // The other direction needs no handling of its own: the firmware has no
    // RPC-to-CLI switch, so going that way tears the session down and arrives
    // as a real disconnect, which fails this check too.
    if (!state.cliReady && _ready) {
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
    final channel = _channel;
    if (!_ready || channel == null) return;
    _fireAndShow(() => channel.write(_ctrlC), 'ctrl-c');
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
