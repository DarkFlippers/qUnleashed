import 'package:flutter/material.dart';

import '../../../theme/theme.dart';

class FlipperPageCard extends StatelessWidget {
  const FlipperPageCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
  });

  final String? title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      child: Material(
        color: colors.card,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                // A `Wrap` rather than a `Row`, for the reason
                // `SettingsDropdown` in `firmware_card.dart` is one: this was
                // an `Expanded` title beside an inflexible `trailing`, so the
                // trailing widget took its whole intrinsic width and the
                // title got the remainder. Every `trailing` passed here is
                // text in a bordered chip, which grows with the text scaler
                // while the room does not - so at a large scale the title ran
                // out of width and the row overflowed to the right. Measured
                // on the firmware card: 102 pixels at a 360 dp window and a
                // scaler of 3.1, and it is reached at 2.0 on a 320. #463.
                //
                // `spaceBetween` keeps the trailing widget on the trailing
                // edge while the two share a run, which is what the
                // `Expanded` did, and a `trailing` that no longer fits drops
                // below the title instead of squeezing it.
                //
                // The `SizedBox` is not decoration. A `Row` with no
                // `mainAxisSize` takes the width it is offered; a `Wrap`
                // takes the width of its children, and this `Column`
                // centres what is narrower than itself - so without it a
                // header with no `trailing` stops being left-aligned and
                // sits in the middle of the card. The card's own
                // `Container` is `width: double.infinity`, so the width
                // offered here is always bounded.
                child: SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(
                        title!,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}
