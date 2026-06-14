import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';

const Duration _kRepeatGap = Duration(milliseconds: 60);

final Map<LogicalKeyboardKey, RemoteButton> _kKeyMap = {
  LogicalKeyboardKey.keyW: RemoteButton.up,
  LogicalKeyboardKey.arrowUp: RemoteButton.up,
  LogicalKeyboardKey.keyA: RemoteButton.left,
  LogicalKeyboardKey.arrowLeft: RemoteButton.left,
  LogicalKeyboardKey.keyS: RemoteButton.down,
  LogicalKeyboardKey.arrowDown: RemoteButton.down,
  LogicalKeyboardKey.keyD: RemoteButton.right,
  LogicalKeyboardKey.arrowRight: RemoteButton.right,
  LogicalKeyboardKey.space: RemoteButton.ok,
  LogicalKeyboardKey.enter: RemoteButton.ok,
  LogicalKeyboardKey.numpadEnter: RemoteButton.ok,
  LogicalKeyboardKey.escape: RemoteButton.back,
  LogicalKeyboardKey.backspace: RemoteButton.back,
};

class RemoteKeyboardListener extends StatefulWidget {
  const RemoteKeyboardListener({
    super.key,
    required this.onHoldBegin,
    required this.onHoldEnd,
    required this.child,
  });

  final void Function(RemoteButton) onHoldBegin;
  final void Function(RemoteButton) onHoldEnd;
  final Widget child;

  @override
  State<RemoteKeyboardListener> createState() => _RemoteKeyboardListenerState();
}

class _RemoteKeyboardListenerState extends State<RemoteKeyboardListener> {
  final Map<RemoteButton, Timer> _releaseTimers = {};
  final Set<RemoteButton> _held = {};

  @override
  void dispose() {
    for (final t in _releaseTimers.values) {
      t.cancel();
    }
    _releaseTimers.clear();
    for (final b in _held) {
      widget.onHoldEnd(b);
    }
    _held.clear();
    super.dispose();
  }

  KeyEventResult _onKey(KeyEvent event) {
    final button = _kKeyMap[event.logicalKey];
    if (button == null) return KeyEventResult.ignored;

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _onDown(button);
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _scheduleRelease(button);
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  void _onDown(RemoteButton button) {
    _releaseTimers.remove(button)?.cancel();
    if (_held.add(button)) {
      widget.onHoldBegin(button);
    }
  }

  void _scheduleRelease(RemoteButton button) {
    _releaseTimers.remove(button)?.cancel();
    _releaseTimers[button] = Timer(_kRepeatGap, () {
      _releaseTimers.remove(button);
      if (_held.remove(button)) {
        widget.onHoldEnd(button);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) => _onKey(event),
      child: widget.child,
    );
  }
}
