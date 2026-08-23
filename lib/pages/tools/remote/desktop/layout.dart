import 'dart:math' as math;

import 'package:flutter/painting.dart';

enum RemoteControlsArrangement { inline, device }

class RemoteBlockMetrics {
  const RemoteBlockMetrics(this.slope, this.intercept);

  final double slope;
  final double intercept;

  double widthForHeight(double height) => slope * height + intercept;

  double heightForWidth(double width) => (width - intercept) / slope;
}

class RemoteScreenGeometry {
  static const double queueHeight = 28;
  static const double queueSpacing = 4;
  static const double strip = queueHeight + queueSpacing;
  static const double bezel = 38;
  static const double fixedHeight = strip + bezel;

  static double aspect(bool streamVertical) => streamVertical ? 0.5 : 2.0;

  static RemoteBlockMetrics metrics(bool streamVertical) {
    final a = aspect(streamVertical);
    return RemoteBlockMetrics(a, bezel - a * fixedHeight);
  }

  static double frameHeight(double height) => math.max(0, height - fixedHeight);

  static double frameWidth(double height, bool streamVertical) =>
      frameHeight(height) * aspect(streamVertical);
}

class RemoteControlsGeometry {
  static const double dpad = 162;
  static const double back = 54;
  static const double inlineGap = 16;

  static const double deviceDpad = 168;
  static const double deviceBack = 54;
  static const double deviceGap = 2;
  static const double deviceOverhang = 18;

  static const Size designInline = Size(dpad + inlineGap + back, dpad);
  static double deviceDpadDiameter(double blockHeight) =>
      blockHeight * deviceDpad / (deviceDpad + deviceGap + deviceBack);

  static const Size designDevice = Size(
    deviceDpad + deviceOverhang,
    deviceDpad + deviceGap + deviceBack,
  );

  static Size design(RemoteControlsArrangement arrangement) =>
      arrangement == RemoteControlsArrangement.inline
      ? designInline
      : designDevice;

  static RemoteBlockMetrics metrics(RemoteControlsArrangement arrangement) {
    final d = design(arrangement);
    return RemoteBlockMetrics(d.width / d.height, 0);
  }

  static const double screenShare = 0.8;
}

class RemoteActionsGeometry {
  static const int cells = 4;
  static const double cellWidth = 86;
  static const double cellHeight = 76;
  static const double rowGap = 12;

  static const Size designRow = Size(
    cells * cellWidth + (cells - 1) * rowGap,
    cellHeight,
  );
  static Size rowSize(double maxWidth) {
    final scale = math.min(1.0, math.max(0.0, maxWidth) / designRow.width);
    return designRow * scale;
  }
}

class RemoteActionBarGeometry {
  static const int cells = 4;
  static const double pillWidth = 152;
  static const double pillHeight = 50;
  static const double pillGap = 12;
  static const double pillRadius = 9;
  static const double backWidth = 130;
  static const double backGap = 24;

  static const double maxHeight = 68;

  static Size designFor(int cells) => Size(
    backWidth + backGap + cells * pillWidth + (cells - 1) * pillGap,
    pillHeight,
  );

  static double scaleFor(double maxWidth, int cells) => math.min(
    maxHeight / pillHeight,
    math.max(0.0, maxWidth) / designFor(cells).width,
  );

  static double heightFor(double maxWidth, int cells) =>
      pillHeight * scaleFor(maxWidth, cells);
}

class RemoteLayout {
  const RemoteLayout({
    required this.wide,
    required this.controlsArrangement,
    required this.screenSize,
    required this.controlsSize,
    required this.actionsSize,
    required this.padding,
  });

  static const double gap = 12;
  static const double actionsSpacing = 8;

  static const double infoIconSize = 32;
  static const double ledSize = 18;
  static const double ledGap = 4;
  static const double infoMargin = 14;
  static const double panelRadius = 12;
  static const EdgeInsets panelMargin = EdgeInsets.all(14);
  static const EdgeInsets panelPadding = EdgeInsets.all(20);

  static const EdgeInsets _narrowPadding = EdgeInsets.fromLTRB(12, 14, 12, 8);

  final bool wide;
  final RemoteControlsArrangement controlsArrangement;
  final Size screenSize;
  final Size controlsSize;
  final Size actionsSize;
  final EdgeInsets padding;

  static bool isWide(Size window) => window.width > window.height;

  static RemoteLayout resolve(
    Size available,
    bool streamVertical, {
    required bool wide,
    int actionCells = RemoteActionBarGeometry.cells,
  }) => wide
      ? _wide(available, streamVertical, actionCells)
      : _narrow(available, streamVertical);

  static RemoteLayout _wide(
    Size available,
    bool streamVertical,
    int actionCells,
  ) {
    final inset = panelMargin.horizontal + panelPadding.horizontal;
    final insetV = panelMargin.vertical + panelPadding.vertical;
    final width = math.max(0.0, available.width - inset);
    final height = math.max(0.0, available.height - insetV);

    const arrangement = RemoteControlsArrangement.device;
    final controls = RemoteControlsGeometry.metrics(arrangement);
    final screen = RemoteScreenGeometry.metrics(streamVertical);

    const share = RemoteControlsGeometry.screenShare;
    final denominator = screen.slope + controls.slope * share;

    double solve(double barHeight) => math.max(
      0.0,
      math.min(
        height - barHeight - actionsSpacing,
        (width - gap - screen.intercept) / denominator,
      ),
    );

    var barHeight = RemoteActionBarGeometry.pillHeight;
    var band = solve(barHeight);
    for (var i = 0; i < 4; i++) {
      barHeight = RemoteActionBarGeometry.heightFor(
        _screenWidth(band, streamVertical),
        actionCells,
      );
      band = solve(barHeight);
    }

    final screenSize = Size(_screenWidth(band, streamVertical), band);
    final controlsHeight = band * share;

    return RemoteLayout(
      wide: true,
      controlsArrangement: arrangement,
      screenSize: screenSize,
      controlsSize: Size(
        controls.widthForHeight(controlsHeight),
        controlsHeight,
      ),
      actionsSize: Size(screenSize.width, barHeight),
      padding: panelMargin,
    );
  }

  static RemoteLayout _narrow(Size available, bool streamVertical) {
    final width = available.width - _narrowPadding.horizontal;
    final height = available.height - _narrowPadding.vertical;

    final actionsSize = RemoteActionsGeometry.rowSize(width);

    const arrangement = RemoteControlsArrangement.inline;
    final controls = RemoteControlsGeometry.metrics(arrangement);
    final controlsHeight = math.max(
      0.0,
      math.min(
        math.min(
          streamVertical ? 150.0 : 174.0,
          available.height * (streamVertical ? 0.28 : 0.32),
        ),
        controls.heightForWidth(width),
      ),
    );

    final screen = RemoteScreenGeometry.metrics(streamVertical);
    final rest =
        height - actionsSize.height - actionsSpacing - controlsHeight - gap;
    final screenHeight = math.max(
      0.0,
      math.min(rest, screen.heightForWidth(width)),
    );

    return RemoteLayout(
      wide: false,
      controlsArrangement: arrangement,
      screenSize: Size(
        _screenWidth(screenHeight, streamVertical),
        screenHeight,
      ),
      controlsSize: Size(
        controls.widthForHeight(controlsHeight),
        controlsHeight,
      ),
      actionsSize: actionsSize,
      padding: _narrowPadding,
    );
  }

  static double _screenWidth(double height, bool streamVertical) =>
      RemoteScreenGeometry.frameWidth(height, streamVertical) +
      RemoteScreenGeometry.bezel;
}
