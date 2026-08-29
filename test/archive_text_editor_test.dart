import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/archive/editor/document.dart';
import 'package:qunleashed/pages/archive/editor/find_panel.dart';
import 'package:qunleashed/pages/archive/editor/line_numbers.dart';
import 'package:qunleashed/pages/archive/editor/page.dart';
import 'package:qunleashed/pages/archive/editor/syntax.dart';
import 'package:qunleashed/theme/theme.dart';
import 'package:re_editor/re_editor.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  home: child,
);

io.File _tempFile(String name, String content) {
  final dir = io.Directory.systemTemp.createTempSync('qunleashed_editor');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = io.File('${dir.path}${io.Platform.pathSeparator}$name')
    ..writeAsStringSync(content);
  return file;
}

Future<void> _pumpEditor(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(_wrap(page));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

CodeLineEditingController _editor(WidgetTester tester) =>
    tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!;

EditorLineNumbers _gutter(WidgetTester tester) =>
    tester.widget<EditorLineNumbers>(find.byType(EditorLineNumbers));

EditorDocument _document(WidgetTester tester) => _gutter(tester).document;

/// The search runs in an isolate, which needs real time to spin up.
Future<void> _waitForMatches(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
    final value = tester
        .widget<CodeEditor>(find.byType(CodeEditor))
        .findController
        ?.value;
    if (value != null && !value.searching) return;
  }
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.save));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('EditorDocument', () {
    test('marks the lines that differ from the saved file', () {
      final doc = EditorDocument.fromText('a\nb\nc');
      doc.update(CodeLines.fromText('a\nb\nc'));
      expect(doc.isModified, isFalse);
      expect(doc.isLineModified(1), isFalse);

      doc.update(CodeLines.fromText('a\nB\nc'));
      expect(doc.isLineModified(0), isFalse);
      expect(doc.isLineModified(1), isTrue);
      expect(doc.isLineModified(2), isFalse);
    });

    test('marks only the edited lines, not the untouched ones between', () {
      final doc = EditorDocument.fromText('1\n2\n3\n4\n5\n6\n7\n8');
      doc.update(CodeLines.fromText('1\nX\n3\n4\n5\n6\nY\n8'));

      expect(
        [for (var i = 0; i < 8; i++) doc.isLineModified(i)],
        [false, true, false, false, false, false, true, false],
      );
    });

    test('marks the inserted line only', () {
      final doc = EditorDocument.fromText('a\nb\nc');
      doc.update(CodeLines.fromText('a\nnew\nb\nc'));
      expect(
        [for (var i = 0; i < 4; i++) doc.isLineModified(i)],
        [false, true, false, false],
      );
    });

    test('marks the two halves when a line is split', () {
      final doc = EditorDocument.fromText('ab\ntail');
      doc.update(CodeLines.fromText('a\nb\ntail'));
      expect(
        [for (var i = 0; i < 3; i++) doc.isLineModified(i)],
        [true, true, false],
      );
    });

    test('marks nothing when a line is deleted', () {
      final doc = EditorDocument.fromText('a\nb\nc');
      doc.update(CodeLines.fromText('a\nc'));
      expect(doc.isModified, isFalse);
    });

    test('markSaved clears the marks', () {
      final doc = EditorDocument.fromText('a\nb');
      final lines = CodeLines.fromText('a\nB\nc');
      doc.update(lines);
      expect(doc.isModified, isTrue);

      doc.markSaved(lines);
      expect(doc.isModified, isFalse);
      doc.update(CodeLines.fromText('a\nB\nc'));
      expect(doc.isModified, isFalse);
    });

    test('diffs a 20k line file fast enough to run on every keystroke', () {
      final lines = List<String>.generate(20000, (i) => 'REM line $i');
      final doc = EditorDocument.fromText(lines.join('\n'));
      final edited = List<String>.of(lines)..[9000] = 'REM edited';
      final code = CodeLines.fromText(edited.join('\n'));

      final watch = Stopwatch()..start();
      doc.update(code);
      watch.stop();

      expect(doc.isLineModified(9000), isTrue);
      expect(doc.isLineModified(8999), isFalse);
      expect(
        watch.elapsedMilliseconds,
        lessThan(100),
        reason: 'line diff took ${watch.elapsedMilliseconds} ms',
      );
    });
  });

  group('syntax', () {
    test('picks the language from the file extension', () {
      expect(editorLanguageFor('payload.txt'), 'duckyscript');
      expect(editorLanguageFor('demo.js'), 'javascript');
      expect(editorLanguageFor('Key.sub'), 'keyfile');
      expect(editorLanguageFor('remote.ir'), 'keyfile');
      expect(editorLanguageFor('dump.bin'), 'plaintext');
      expect(editorLanguageFor('noext'), 'plaintext');
    });

    test('builds a highlight theme with a single language', () {
      final theme = editorHighlightTheme('payload.txt');
      expect(theme.languages.keys, ['duckyscript']);
      expect(theme.theme['keyword'], isNotNull);
    });
  });

  group('TextEditorPage', () {
    testWidgets('loads the whole file into one editor', (tester) async {
      final file = _tempFile('demo.txt', 'DELAY 100\nSTRING hi\nENTER');

      await _pumpEditor(tester, TextEditorPage(localPath: file.path));

      expect(find.byType(CodeEditor), findsOneWidget);
      expect(_editor(tester).text, 'DELAY 100\nSTRING hi\nENTER');
      expect(_editor(tester).lineCount, 3);
    });

    testWidgets('selects text across several lines', (tester) async {
      final file = _tempFile('demo.txt', 'one\ntwo\nthree');

      await _pumpEditor(tester, TextEditorPage(localPath: file.path));

      final controller = _editor(tester);
      controller.selectLines(0, 1);
      expect(controller.selectedText, 'one\ntwo');

      controller.selectAll();
      expect(controller.selectedText, 'one\ntwo\nthree');
    });

    testWidgets('opens a big file without building every line', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final lines = List<String>.generate(
        20000,
        (i) => 'REM line $i with some text to make the file large',
      );
      final file = _tempFile('big.txt', lines.join('\n'));
      expect(file.lengthSync(), greaterThan(512 * 1024));

      await _pumpEditor(tester, TextEditorPage(localPath: file.path));

      expect(_editor(tester).lineCount, 20000);
      final rendered = _gutter(tester).notifier.value?.paragraphs ?? const [];
      expect(rendered, isNotEmpty);
      expect(rendered.length, lessThan(120));
    });

    testWidgets('marks an edited line and saves it back through the hook', (
      tester,
    ) async {
      final file = _tempFile('demo.txt', 'DELAY 100\nSTRING hi\nENTER');
      List<int>? uploaded;

      await _pumpEditor(
        tester,
        TextEditorPage(
          localPath: file.path,
          onSave: (bytes) async {
            uploaded = bytes;
            return true;
          },
        ),
      );

      _editor(tester).text = 'DELAY 100\nSTRING bye\nENTER';
      await tester.pump();

      final doc = _document(tester);
      expect(doc.isLineModified(0), isFalse);
      expect(doc.isLineModified(1), isTrue);
      expect(doc.isLineModified(2), isFalse);

      await _save(tester);

      expect(file.readAsStringSync(), 'DELAY 100\nSTRING bye\nENTER');
      expect(uploaded, isNotNull);
      expect(String.fromCharCodes(uploaded!), contains('STRING bye'));
    });

    testWidgets('keeps the line break the file came with', (tester) async {
      final file = _tempFile('crlf.txt', 'DELAY 100\r\nSTRING hi\r\nENTER');

      await _pumpEditor(
        tester,
        TextEditorPage(localPath: file.path, onSave: (_) async => true),
      );

      expect(_editor(tester).lineCount, 3);
      expect(_document(tester).isModified, isFalse);

      _editor(tester).text = 'DELAY 100\nSTRING bye\nENTER';
      await tester.pump();
      await _save(tester);

      expect(file.readAsStringSync(), 'DELAY 100\r\nSTRING bye\r\nENTER');
    });

    testWidgets('finds matches from the app bar', (tester) async {
      final file = _tempFile('demo.txt', 'STRING hi\nSTRING bye\nENTER');

      await _pumpEditor(tester, TextEditorPage(localPath: file.path));

      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();
      expect(find.byType(EditorFindPanel), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Find'), 'STRING');
      await _waitForMatches(tester);
      expect(find.text('1/2'), findsOneWidget);
    });

    testWidgets('reports a failed save and stays on the page', (tester) async {
      final file = _tempFile('fail.txt', 'x');

      await _pumpEditor(
        tester,
        TextEditorPage(localPath: file.path, onSave: (_) async => false),
      );

      await _save(tester);

      expect(find.text('Save failed'), findsOneWidget);
      expect(find.byType(TextEditorPage), findsOneWidget);
    });
  });
}
