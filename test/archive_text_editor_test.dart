import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/archive/editor/document.dart';
import 'package:qunleashed/pages/archive/editor/page.dart';
import 'package:qunleashed/pages/archive/editor/style.dart';
import 'package:qunleashed/pages/archive/editor/widgets/line_row.dart';
import 'package:qunleashed/theme/theme.dart';

const String _zwsp = '\u200b';

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

Finder _rowWithNumber(int number) =>
    find.byWidgetPredicate((w) => w is EditorLineView && w.number == number);

List<int> _lineNumbers(WidgetTester tester) => tester
    .widgetList<EditorLineView>(find.byType(EditorLineView))
    .map((w) => w.number)
    .toList();

TextField _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

Future<void> _pumpEditor(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(_wrap(page));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.save));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String value) async {
  final field = _field(tester);
  field.controller!.value = TextEditingValue(
    text: value,
    selection: TextSelection.collapsed(offset: value.length),
  );
  field.onChanged!(value);
  await tester.pump();
}

void main() {
  group('EditorDocument', () {
    test('tracks modified lines per line, not by diffing the file', () {
      final doc = EditorDocument.fromText('a\nb\nc');
      expect(doc.length, 3);
      expect(doc.isModified(1), isFalse);

      doc.replace(1, 'B');
      expect(doc.isModified(1), isTrue);
      expect(doc.isModified(0), isFalse);

      doc.replace(1, 'b');
      expect(doc.isModified(1), isFalse);
    });

    test('splits a line into several and marks the new ones', () {
      final doc = EditorDocument.fromText('one\ntwo');
      doc.replaceWithLines(0, ['on', 'e']);
      expect(doc.text, 'on\ne\ntwo');
      expect(doc.isModified(0), isTrue);
      expect(doc.isModified(1), isTrue);
      expect(doc.isModified(2), isFalse);
    });

    test('merges a line into the previous one and reports the caret', () {
      final doc = EditorDocument.fromText('ab\ncd');
      expect(doc.mergeWithPrevious(1), 2);
      expect(doc.text, 'abcd');
      expect(doc.length, 1);
    });

    test('markSaved clears the modified marks', () {
      final doc = EditorDocument.fromText('a\nb');
      doc.replaceWithLines(1, ['b', 'c']);
      doc.markSaved();
      expect(doc.isModified(0), isFalse);
      expect(doc.isModified(1), isFalse);
      expect(doc.isModified(2), isFalse);
    });
  });

  group('TextEditorPage', () {
    testWidgets('builds only the visible lines of a large file', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(500, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final lines = List<String>.generate(
        20000,
        (i) => 'REM line $i with some text to make the file large',
      );
      final file = _tempFile('big.txt', lines.join('\n'));
      expect(file.lengthSync(), greaterThan(512 * 1024));

      await _pumpEditor(tester, TextEditorPage(localPath: file.path));

      final visible = _lineNumbers(tester);
      expect(visible.length, lessThan(120));
      expect(visible.first, 1);
      expect(visible.last, lessThan(120));

      await tester.drag(find.byType(ListView), const Offset(0, -4000));
      await tester.pump();
      final scrolled = _lineNumbers(tester);
      expect(scrolled, isNotEmpty);
      expect(scrolled.first, greaterThan(100));
    });

    testWidgets('edits a line and saves it back through the hook', (
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

      await tester.tap(find.byType(EditorLineView).at(1));
      await tester.pump();
      expect(_field(tester).controller!.text, '${_zwsp}STRING hi');

      await _type(tester, '${_zwsp}STRING bye');
      await _save(tester);

      expect(file.readAsStringSync(), 'DELAY 100\nSTRING bye\nENTER');
      expect(uploaded, isNotNull);
      expect(String.fromCharCodes(uploaded!), contains('STRING bye'));
    });

    testWidgets('newline splits the line and keeps editing the tail', (
      tester,
    ) async {
      final file = _tempFile('split.txt', 'ab');

      await _pumpEditor(
        tester,
        TextEditorPage(localPath: file.path, onSave: (_) async => true),
      );

      await tester.tap(find.byType(EditorLineView).first);
      await tester.pump();
      expect(_field(tester).focusNode!.hasFocus, isTrue);

      await _type(tester, '${_zwsp}a\nb');
      expect(_field(tester).controller!.text, '${_zwsp}b');
      expect(_field(tester).focusNode!.hasFocus, isTrue);
      expect(find.byType(EditorLineView), findsOneWidget);

      await _save(tester);
      expect(file.readAsStringSync(), 'a\nb');
    });

    testWidgets('backspace at the line start merges into the previous line', (
      tester,
    ) async {
      final file = _tempFile('merge.txt', 'ab\ncd');

      await _pumpEditor(
        tester,
        TextEditorPage(localPath: file.path, onSave: (_) async => true),
      );

      await tester.tap(find.byType(EditorLineView).at(1));
      await tester.pump();

      final controller = _field(tester).controller!;
      controller.value = const TextEditingValue(
        text: 'cd',
        selection: TextSelection.collapsed(offset: 0),
      );
      _field(tester).onChanged!('cd');
      await tester.pump();

      expect(_field(tester).controller!.text, '${_zwsp}abcd');
      expect(_field(tester).controller!.selection.baseOffset, 3);

      await _save(tester);
      expect(file.readAsStringSync(), 'abcd');
    });

    testWidgets('the caret line keeps the font and box of the shown line', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final wrapped = 'STRING ${'word ' * 40}';
      final file = _tempFile('font.txt', 'STRING abc\n\n$wrapped\nlast');

      await _pumpEditor(tester, TextEditorPage(localPath: file.path));

      final shown = [
        for (var i = 0; i < 4; i++)
          tester.getRect(find.byType(EditorLineView).at(i)),
      ];

      for (final index in [0, 2]) {
        await tester.tap(_rowWithNumber(index + 1));
        await tester.pump();
        expect(
          tester.widget<EditableText>(find.byType(EditableText)).style,
          kEditorTextStyle,
        );
        final field = tester.getRect(find.byType(EditableText));
        expect(field.top, shown[index].top);
        expect(field.height, shown[index].height);
        for (final row in tester.widgetList<EditorLineView>(
          find.byType(EditorLineView),
        )) {
          final rect = tester.getRect(find.byWidget(row));
          expect(rect, shown[row.number - 1]);
        }
      }
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
