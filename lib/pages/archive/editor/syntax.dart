import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/plaintext.dart';
import 'package:re_highlight/languages/properties.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/re_highlight.dart';

import '../../../theme/colors/editor.dart';

const Set<String> duckyscriptCommands = {
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
};

final Mode langDuckyScript = Mode(
  refs: {},
  name: 'DuckyScript',
  disableAutodetect: true,
  keywords: {'keyword': duckyscriptCommands.toList()},
  contains: <Mode>[
    Mode(scope: 'comment', begin: r'^\s*(?:REM\b|#)', end: r'$'),
    Mode(scope: 'number', match: r'\b\d+\b'),
  ],
);

final Map<String, TextStyle> duckyscriptEditorTheme = {
  ...dartEditorTheme,
  'keyword': dartEditorTheme['doctag']!.copyWith(fontWeight: FontWeight.w600),
  'comment': dartEditorTheme['comment']!,
  'number': dartEditorTheme['title.function']!,
};

final Map<String, TextStyle> keyFileEditorTheme = {
  ...dartEditorTheme,
  'attr': dartEditorTheme['title']!,
  'meta': dartEditorTheme['title']!,
};

const Map<String, String> _kLanguageByExtension = {
  'txt': 'duckyscript',
  'js': 'javascript',
  'dart': 'dart',
  'py': 'python',
  'json': 'json',
  'md': 'markdown',
  'xml': 'xml',
  'svg': 'xml',
  'html': 'xml',
  'sub': 'keyfile',
  'ir': 'keyfile',
  'nfc': 'keyfile',
  'rfid': 'keyfile',
  'ibtn': 'keyfile',
  'fmf': 'keyfile',
  'u2f': 'keyfile',
  'badusb': 'keyfile',
  'ini': 'keyfile',
  'conf': 'keyfile',
  'properties': 'keyfile',
};

final Map<String, Mode> _kModeByLanguage = {
  'duckyscript': langDuckyScript,
  'javascript': langJavascript,
  'dart': langDart,
  'python': langPython,
  'json': langJson,
  'markdown': langMarkdown,
  'xml': langXml,
  'keyfile': langProperties,
  'plaintext': langPlaintext,
};

final Map<String, Map<String, TextStyle>> _kThemeByLanguage = {
  'duckyscript': duckyscriptEditorTheme,
  'keyfile': keyFileEditorTheme,
};

String editorLanguageFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return 'plaintext';
  final extension = fileName.substring(dot + 1).toLowerCase();
  return _kLanguageByExtension[extension] ?? 'plaintext';
}

CodeHighlightTheme editorHighlightTheme(String fileName) {
  final language = editorLanguageFor(fileName);
  return CodeHighlightTheme(
    languages: {
      language: CodeHighlightThemeMode(mode: _kModeByLanguage[language]!),
    },
    theme: _kThemeByLanguage[language] ?? dartEditorTheme,
  );
}
