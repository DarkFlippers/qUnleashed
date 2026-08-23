import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../../theme/theme.dart';
import '../layout.dart';

const List<(String, String)> _kShortcuts = [
  ('up', 'W    ↑'),
  ('down', 'S    ↓'),
  ('left', 'A    ←'),
  ('right', 'D    →'),
  ('ok', 'Space    Enter'),
  ('back', 'Esc    Backspace'),
];

class RemoteInfoHint extends StatefulWidget {
  const RemoteInfoHint({super.key});

  @override
  State<RemoteInfoHint> createState() => _RemoteInfoHintState();
}

class _RemoteInfoHintState extends State<RemoteInfoHint> {
  final OverlayPortalController _controller = OverlayPortalController();
  final LayerLink _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        overlayChildBuilder: (_) => Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.topRight,
            followerAnchor: Alignment.bottomRight,
            offset: const Offset(0, -10),
            child: const _HintPanel(),
          ),
        ),
        child: MouseRegion(
          onEnter: (_) => _controller.show(),
          onExit: (_) => _controller.hide(),
          child: GestureDetector(
            onTap: _controller.toggle,
            child: SizedBox(
              width: RemoteLayout.infoIconSize,
              height: RemoteLayout.infoIconSize,
              child: SvgPicture.asset(
                'assets/ic/info/lg.svg',
                colorFilter: ColorFilter.mode(colors.accent, BlendMode.srcIn),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HintPanel extends StatelessWidget {
  const _HintPanel();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.dialogBackground,
          border: Border.all(color: colors.dialogDivider),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (asset, keys) in _kShortcuts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: SvgPicture.asset(
                        'assets/ic/control/hint/$asset.svg',
                        colorFilter: ColorFilter.mode(
                          colors.accent,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      keys,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.1,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
