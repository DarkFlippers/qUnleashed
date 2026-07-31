import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/asembler/project/controller.dart';
import 'package:qunleashed/pages/asembler/project/git_source.dart';
import 'package:qunleashed/pages/asembler/project/page.dart';
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

  testWidgets('project page offers both sources', (tester) async {
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
    expect(find.text('Local folder'), findsOneWidget);
    expect(find.text('Repository link'), findsOneWidget);
    expect(find.text('Choose folder'), findsOneWidget);
    expect(find.text('Build and send'), findsOneWidget);
    expect(find.text('Pick a project folder first'), findsOneWidget);

    await tester.tap(find.text('Repository link'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Choose folder'), findsNothing);

    expect(tester.takeException(), isNull);
  });

  test('building waits for a loaded project', () {
    final controller = FliblerProjectController();
    expect(controller.targetPath, isEmpty);
    expect(controller.canLoad, isFalse);
    expect(controller.canBuild, isFalse);

    controller.setKind(FliblerSourceKind.repository);
    controller.setRepo('https://github.com/user/repo');
    expect(controller.canLoad, isTrue);
    expect(controller.canBuild, isFalse);
  });
}
