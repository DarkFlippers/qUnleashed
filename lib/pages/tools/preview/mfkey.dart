import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';

class MfKeyPreview extends StatelessWidget {
  const MfKeyPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SvgPicture.asset(
      colors.isDark
          ? 'assets/pic/tool/detect-reader-dark.svg'
          : 'assets/pic/tool/detect-reader.svg',
    );
  }
}
