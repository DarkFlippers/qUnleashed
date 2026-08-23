import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/remote/desktop/gif_recorder.dart';
import 'package:qunleashed/pages/tools/remote/desktop/layout.dart';
import 'package:qunleashed/pages/tools/remote/desktop/models/models.dart';
import 'package:qunleashed/pages/tools/remote/desktop/widgets/action_bar.dart';
import 'package:qunleashed/pages/tools/remote/desktop/widgets/actions.dart';
import 'package:qunleashed/pages/tools/remote/desktop/widgets/controls.dart';
import 'package:qunleashed/pages/tools/remote/desktop/widgets/screen.dart';
import 'package:qunleashed/theme/theme.dart';

const _tolerance = 0.5;

double _bandWidth(RemoteLayout layout) =>
    layout.screenSize.width + RemoteLayout.gap + layout.controlsSize.width;

double _wideInset(EdgeInsets margin) =>
    margin.horizontal + RemoteLayout.panelPadding.horizontal;

double _wideInsetV(EdgeInsets margin) =>
    margin.vertical + RemoteLayout.panelPadding.vertical;

Widget _wrap(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('wide layout', () {
    const sizes = <Size>[
      Size(1280, 664),
      Size(1600, 820),
      Size(1024, 500),
      Size(900, 420),
      Size(800, 304),
      Size(740, 260),
      Size(640, 244),
      Size(600, 200),
    ];

    test('the screen leads and the controls never outgrow it', () {
      for (final streamVertical in [false, true]) {
        for (final size in sizes) {
          final layout = RemoteLayout.resolve(size, streamVertical, wide: true);
          expect(layout.wide, isTrue, reason: '$size');
          expect(
            layout.controlsSize.height,
            lessThanOrEqualTo(layout.screenSize.height + _tolerance),
            reason: '$size vertical=$streamVertical',
          );
          expect(
            layout.controlsSize.height,
            closeTo(
              layout.screenSize.height * RemoteControlsGeometry.screenShare,
              _tolerance,
            ),
            reason: '$size vertical=$streamVertical',
          );
        }
      }
    });

    test('band and action bar fit the panel', () {
      for (final streamVertical in [false, true]) {
        for (final size in sizes) {
          final layout = RemoteLayout.resolve(size, streamVertical, wide: true);
          final innerWidth = size.width - _wideInset(layout.padding);
          final innerHeight = size.height - _wideInsetV(layout.padding);

          expect(
            _bandWidth(layout),
            lessThanOrEqualTo(innerWidth + _tolerance),
            reason: '$size vertical=$streamVertical',
          );
          expect(
            layout.actionsSize.width,
            lessThanOrEqualTo(innerWidth + _tolerance),
            reason: '$size vertical=$streamVertical',
          );
          expect(
            layout.screenSize.height +
                RemoteLayout.actionsSpacing +
                layout.actionsSize.height,
            lessThanOrEqualTo(innerHeight + _tolerance),
            reason: '$size vertical=$streamVertical',
          );
        }
      }
    });

    test('a wider window never shrinks the screen', () {
      var previous = 0.0;
      for (var width = 620.0; width <= 1800; width += 20) {
        final layout = RemoteLayout.resolve(
          Size(width, 600),
          false,
          wide: true,
        );
        expect(
          layout.screenSize.height,
          greaterThanOrEqualTo(previous - _tolerance),
        );
        previous = layout.screenSize.height;
      }
    });
  });

  group('narrow layout', () {
    const sizes = <Size>[
      Size(360, 740),
      Size(390, 844),
      Size(320, 568),
      Size(430, 932),
    ];

    test('every block fits the width and the column fits the height', () {
      for (final streamVertical in [false, true]) {
        for (final size in sizes) {
          final layout = RemoteLayout.resolve(
            size,
            streamVertical,
            wide: false,
          );
          expect(layout.wide, isFalse, reason: '$size');

          final maxWidth = size.width - layout.padding.horizontal;
          expect(
            layout.screenSize.width,
            lessThanOrEqualTo(maxWidth + _tolerance),
          );
          expect(
            layout.controlsSize.width,
            lessThanOrEqualTo(maxWidth + _tolerance),
          );
          expect(
            layout.actionsSize.width,
            lessThanOrEqualTo(maxWidth + _tolerance),
          );

          final used =
              layout.actionsSize.height +
              RemoteLayout.actionsSpacing +
              layout.screenSize.height +
              RemoteLayout.gap +
              layout.controlsSize.height;
          expect(
            used,
            lessThanOrEqualTo(
              size.height - layout.padding.vertical + _tolerance,
            ),
            reason: '$size vertical=$streamVertical',
          );
        }
      }
    });
  });

  group('blocks render at the size the solver gave them', () {
    const surfaces = <Size>[
      Size(1280, 664),
      Size(1600, 820),
      Size(800, 304),
      Size(640, 244),
      Size(390, 790),
      Size(320, 568),
    ];

    for (final surface in surfaces) {
      for (final streamVertical in [false, true]) {
        testWidgets('$surface stream vertical=$streamVertical', (tester) async {
          await tester.binding.setSurfaceSize(
            Size(surface.width + 200, surface.height + 200),
          );
          addTearDown(() => tester.binding.setSurfaceSize(null));

          final layout = RemoteLayout.resolve(
            surface,
            streamVertical,
            wide: RemoteLayout.isWide(surface),
          );
          final orientation = streamVertical
              ? StreamOrientation.vertical
              : StreamOrientation.horizontal;

          await tester.pumpWidget(
            _wrap(
              RemoteScreen(
                size: layout.screenSize,
                frameListenable: ValueNotifier(null),
                queue: const [],
                orientation: orientation,
              ),
            ),
          );
          expect(tester.getSize(find.byType(RemoteScreen)), layout.screenSize);

          await tester.pumpWidget(
            _wrap(
              RemoteControls(
                size: layout.controlsSize,
                arrangement: layout.controlsArrangement,
                onHoldBegin: (_) {},
                onHoldEnd: (_) {},
              ),
            ),
          );
          expect(
            tester.getSize(find.byType(RemoteControls)),
            layout.controlsSize,
          );

          for (final state in [
            GifRecordingState.idle,
            GifRecordingState.recording,
          ]) {
            await tester.pumpWidget(
              _wrap(
                layout.wide
                    ? RemoteActionBar(
                        size: layout.actionsSize,
                        showSession: false,
                        sessionBusy: false,
                        onRequestSession: () {},
                        gifState: state,
                        gifElapsedMs: 12300,
                        justUnlocked: false,
                        savingScreenshot: false,
                        onBack: () {},
                        onCopy: () async {},
                        onSave: () async {},
                        onUnlock: () async {},
                        onStartGif: () {},
                        onPauseResumeGif: () {},
                        onStopGif: () async {},
                        onCancelGif: () {},
                      )
                    : RemoteActions(
                        size: layout.actionsSize,
                        gifState: state,
                        gifElapsedMs: 12300,
                        justUnlocked: false,
                        savingScreenshot: false,
                        onCopy: () async {},
                        onSave: () async {},
                        onUnlock: () async {},
                        onStartGif: () {},
                        onPauseResumeGif: () {},
                        onStopGif: () async {},
                        onCancelGif: () {},
                      ),
              ),
            );
            expect(
              tester.getSize(
                find.byType(layout.wide ? RemoteActionBar : RemoteActions),
              ),
              layout.actionsSize,
              reason: '$state',
            );
          }
        });
      }
    }
  });
}
