import 'package:flutter/widgets.dart';

/// M3 window size classes: compact and medium windows keep a 16dp margin,
/// expanded ones (840dp and wider) a 24dp one.
const double kExpandedWindow = 840;

double catalogGutter(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kExpandedWindow ? 24 : 16;
