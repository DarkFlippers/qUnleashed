import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';

class FliblerPreview extends StatelessWidget {
  const FliblerPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SvgPicture.asset(
      colors.isDark
          ? 'assets/flipper_svg/tools/pic_flibler_dark.svg'
          : 'assets/flipper_svg/tools/pic_flibler_light.svg',
    );
  }
}
