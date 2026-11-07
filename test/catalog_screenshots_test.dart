import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/apps/catalog/widgets/card.dart';
import 'package:qunleashed/pages/apps/catalog/widgets/screenshot_frame.dart';
import 'package:qunleashed/pages/apps/catalog/widgets/screenshots_viewer.dart';
import 'package:qunleashed/pages/apps/data/models/card.dart';
import 'package:qunleashed/theme/theme.dart';

const _shots = ['https://catalog.test/one.png', 'https://catalog.test/two.png'];

Widget _wrap(Widget home) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  home: home,
);

Future<void> _cacheScreenshots(WidgetTester tester) async {
  // A monochrome screenshot: black ink on transparency. It must remain
  // legible when the gallery around it has a black background.
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 64, 64), Paint()..color = Colors.black);
  final picture = recorder.endRecording();
  final image = (await tester.runAsync(() => picture.toImage(128, 64)))!;
  picture.dispose();
  for (final url in _shots) {
    PaintingBinding.instance.imageCache.putIfAbsent(
      NetworkImage(url),
      () => OneFrameImageStreamCompleter(
        Future.value(ImageInfo(image: image.clone())),
      ),
    );
  }
  image.dispose();
  await tester.pump();
  addTearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
}

void main() {
  testWidgets(
    'transparent screenshots remain visible in the fullscreen gallery',
    (tester) async {
      await _cacheScreenshots(tester);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: _wrap(
            const ScreenshotsViewer(screenshots: _shots, initialIndex: 0),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final frame = tester.getRect(find.byType(ScreenshotFrame).first);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final rendered = (await tester.runAsync(() => boundary.toImage()))!;
      final pixels = (await tester.runAsync(
        () => rendered.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      List<int> pixel(double fraction) {
        final offset =
            (frame.center.dy.floor() * rendered.width +
                (frame.left + frame.width * fraction).floor()) *
            4;
        return pixels.buffer
            .asUint8List(pixels.offsetInBytes + offset, 4)
            .toList();
      }

      expect(pixel(0.25), [0, 0, 0, 255]);
      expect(pixel(0.75), [223, 223, 223, 255]);
      rendered.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a screenshot tap opens that image, while a card tap opens the app',
    (tester) async {
      await _cacheScreenshots(tester);
      var appOpens = 0;
      const card = AppCard(
        id: 'demo',
        alias: 'demo',
        categoryId: '',
        author: '',
        createdAt: 0,
        updatedAt: 0,
        currentVersion: AppCurrentVersion(
          id: 'v1',
          name: 'Demo app',
          version: '1.0',
          shortDescription: '',
          iconUri: '',
          screenshots: _shots,
        ),
      );
      await tester.pumpWidget(
        _wrap(
          Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                height: 240,
                child: AppCardView(
                  app: card,
                  onTap: () => appOpens++,
                  action: const SizedBox(width: 50, height: 32),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ScreenshotFrame).at(1));
      await tester.pumpAndSettle();
      expect(appOpens, 0);
      final gallery = tester.widget<ScreenshotsViewer>(
        find.byType(ScreenshotsViewer),
      );
      expect(gallery.initialIndex, 1);
      expect(gallery.screenshots, _shots);
      expect(find.text('Demo app 2/2'), findsOneWidget);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Demo app'));
      await tester.pumpAndSettle();
      expect(appOpens, 1);
      expect(find.byType(ScreenshotsViewer), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
