import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show Mode, highlight;

import 'colors.dart';

const _duckyscriptCommands = [
  'ALT',
  'BACKSPACE',
  'CAPSLOCK',
  'COMMAND',
  'CTRL',
  'CONTROL',
  'DELAY',
  'DELETE',
  'DOWN',
  'END',
  'ENTER',
  'ESC',
  'ESCAPE',
  'F1',
  'F2',
  'F3',
  'F4',
  'F5',
  'F6',
  'F7',
  'F8',
  'F9',
  'F10',
  'F11',
  'F12',
  'GUI',
  'HOME',
  'INSERT',
  'LEFT',
  'MENU',
  'PAGEUP',
  'PAGEDOWN',
  'REM',
  'RIGHT',
  'SHIFT',
  'SPACE',
  'STRING',
  'TAB',
  'UP',
  'WINDOWS',
];

final duckyscript = Mode(
  aliases: ['badusb', 'ducky'],
  case_insensitive: true,
  disableAutodetect: true,
  contains: [
    Mode(className: 'comment', begin: r'^\s*(REM\b|#)', end: r'$'),
    Mode(className: 'number', begin: r'\b\d+\b', relevance: 0),
    Mode(
      className: 'keyword',
      begin: '\\b(${_duckyscriptCommands.join('|')})\\b',
      relevance: 0,
    ),
    Mode(className: 'string', begin: r'[A-Za-z0-9_-]+', relevance: 0),
  ],
);

final duckyscriptEditorTheme = {
  ...dartEditorTheme,
  'keyword': dartEditorTheme['doctag']!.copyWith(fontWeight: FontWeight.w600),
  'comment': dartEditorTheme['comment']!,
  'number': dartEditorTheme['title.function']!,
  'string': dartEditorTheme['root']!.copyWith(backgroundColor: null),
};

void registerDuckyscriptLanguage() {
  highlight.registerLanguage('duckyscript', duckyscript);
}
