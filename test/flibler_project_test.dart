import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qunleashed/pages/flibler/project/controller.dart';
import 'package:qunleashed/pages/flibler/project/git_source.dart';
import 'package:qunleashed/pages/flibler/project/page.dart';
import 'package:qunleashed/theme/theme.dart';

void main() {
  group('repository links', () {
    test('keeps a plain remote as is', () {
      final target = GitSource.parse('https://github.com/user/repo.git');
      expect(target.remote, 'https://github.com/user/repo.git');
      expect(target.ref, isNull);
      expect(target.subdir, isEmpty);
      expect(target.name, 'repo');
    });

    test('splits a github folder link', () {
      final target = GitSource.parse(
        'https://github.com/user/repo/tree/main/apps/hello',
      );
      expect(target.remote, 'https://github.com/user/repo');
      expect(target.ref, 'main');
      expect(target.subdir, 'apps/hello');
      expect(target.name, 'repo');
    });

    test('splits a gitlab folder link', () {
      final target = GitSource.parse('https://gitlab.com/o/r/-/tree/dev/app/');
      expect(target.remote, 'https://gitlab.com/o/r');
      expect(target.ref, 'dev');
      expect(target.subdir, 'app');
    });

    test('accepts an ssh remote', () {
      final target = GitSource.parse('git@github.com:user/repo.git');
      expect(target.remote, 'git@github.com:user/repo.git');
      expect(target.name, 'repo');
    });

    test('rejects anything that is not a link', () {
      expect(() => GitSource.parse(''), throwsA(isA<GitSourceException>()));
      expect(
        () => GitSource.parse('just some text'),
        throwsA(isA<GitSourceException>()),
      );
    });
  });

  testWidgets('project page takes a link, a folder and recents in one tap', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'flibler_recent_sources': [
        jsonEncode({
          'kind': 'repository',
          'value': 'https://github.com/user/repo',
          'name': 'Hello App',
        }),
        jsonEncode({'kind': 'folder', 'value': '/tmp/project'}),
      ],
    });
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
        home: const FliblerProjectPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Flibler'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('Paste and load'), findsOneWidget);
    expect(find.byTooltip('Choose folder'), findsOneWidget);
    expect(find.text('BUILD'), findsOneWidget);

    expect(find.text('Recent projects'), findsOneWidget);
    expect(find.text('Hello App'), findsOneWidget);
    expect(find.text('https://github.com/user/repo'), findsOneWidget);
    expect(find.text('/tmp/project'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  test('building waits for a loaded project', () {
    final controller = FliblerProjectController();
    expect(controller.targetPath, isEmpty);
    expect(controller.canLoad, isFalse);
    expect(controller.canBuild, isFalse);

    controller.setRepo('https://github.com/user/repo');
    expect(controller.kind, FliblerSourceKind.repository);
    expect(controller.canLoad, isTrue);
    expect(controller.canBuild, isFalse);
  });

  test('typing a link switches the source, clearing it returns the folder', () {
    final controller = FliblerProjectController();
    controller.setFolder('/tmp/project');
    expect(controller.kind, FliblerSourceKind.folder);

    controller.setRepo('https://github.com/user/repo');
    expect(controller.kind, FliblerSourceKind.repository);

    controller.setRepo('');
    expect(controller.kind, FliblerSourceKind.folder);
    expect(controller.canLoad, isTrue);
  });

  test('recent sources survive a reload and can be removed', () async {
    SharedPreferences.setMockInitialValues({
      'flibler_recent_sources': [
        jsonEncode({
          'kind': 'repository',
          'value': 'https://github.com/user/repo',
          'name': 'Hello App',
        }),
        jsonEncode({'kind': 'folder', 'value': '/tmp/project'}),
        'not a json entry',
      ],
    });
    final controller = FliblerProjectController();
    await controller.loadRecent();

    expect(controller.recent, hasLength(2));
    expect(controller.recent.first.name, 'Hello App');
    expect(controller.recent.last.kind, FliblerSourceKind.folder);

    await controller.removeRecent(controller.recent.first);
    expect(controller.recent, hasLength(1));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('flibler_recent_sources'), hasLength(1));
  });
}
