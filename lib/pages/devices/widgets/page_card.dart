import 'package:flutter/material.dart';

import '../../../theme/theme.dart';

class FlipperPageCard extends StatelessWidget {
  const FlipperPageCard({
    super.key,
    this.title,
    this.trailing,
    this.trailingValue,
    required this.child,
  }) : assert(
         trailing == null || trailingValue == null,
         'The header has one trailing slot. Pass trailing or trailingValue, '
         'whichever the widget is - not both.',
       ),
       // There is no header without a title - `build` renders one only
       // `if (title != null)` - so a trailing passed without one is dropped
       // and nothing says so. Pre-existing, and loud now rather than fixed,
       // because no call site wants a trailing alone: `connect_card.dart` is
       // the one titleless card and it passes neither.
       assert(
         title != null || (trailing == null && trailingValue == null),
         'A trailing is drawn in the title row, so it needs a title.',
       );

  final String? title;

  /// A control whose **position is part of its meaning**, kept in the corner
  /// however little room the title leaves.
  ///
  /// A dismiss button is the case: `cards/auto_connect_hint.dart` passes an
  /// `IconButton`, and an "X" that has moved to the bottom-left of a card is
  /// not a dismiss affordance any more even though tapping it still works.
  /// So this slot keeps [_cornerHeader]'s arrangement - inflexible, against
  /// the trailing edge, with the title taking what is left.
  ///
  /// **Which means it must not grow with the text scale.** That arrangement
  /// has no answer for a trailing wider than the row: the title is already
  /// down to nothing and the `Row` overflows. An `IconButton` is 40x40 and
  /// stays 40x40 at every scaler - measured at 1.0, 1.3, 2.0 and 3.1 - which
  /// is why that card never overflowed and why this slot is safe for it. The
  /// 40 is `_IconButtonDefaultsM3.minimumSize`, a literal in Material rather
  /// than a scaling value; it is not `kMinInteractiveDimension`, which is 48
  /// and is the *tap target* `MaterialTapTargetSize.padded` grows around that
  /// box. Text in a chip does grow, and is what [trailingValue] is for. #474
  final Widget? trailing;

  /// Something the title *describes*, which may drop onto a line of its own
  /// when the two no longer fit one.
  ///
  /// The firmware card's "What's new" chip is the case, and the overflow is
  /// the reason this slot exists: text in a bordered chip follows the text
  /// scaler while the card's width does not, so as [trailing] it took its
  /// whole intrinsic width, squeezed the title to nothing and then ran the
  /// header 102 pixels off the right at a 360 dp window and a scaler of 3.1 -
  /// reached at 2.0 on a 320. Nothing reported it: `Flex.clipBehavior` is
  /// `Clip.none` so release neither throws nor clips, and the card's own
  /// `Clip.antiAlias` cut the excess off at the rounded corner rather than
  /// drawing it over a neighbour.
  ///
  /// The `Wrap` is the same answer, and the same shape, as #463's two setting
  /// rows one level down - `SettingsDropdown` in `firmware_card.dart` carries
  /// the argument for why a `Wrap` rather than a measured breakpoint.
  ///
  /// **A caller in this slot still has to let its own label wrap.** `Wrap`
  /// bounds what it hands a child, but an inflexible `Text` inside that
  /// child's own `Row` does not use the bound, so the chip overflowed *itself*
  /// by the same 102 pixels once the header stopped overflowing - which is
  /// why `_WhatsNewButton`'s label is `Flexible`. #474
  final Widget? trailingValue;

  final Widget child;

  /// The least the title and [trailingValue] keep between them while they
  /// share a line, and so the width at which they stop sharing one.
  ///
  /// The same 8 `SettingsDropdown` uses for the rows below this header, which
  /// is where the number came from rather than from a measurement here.
  static const double _gap = 8;

  /// The gap between the title and a [trailingValue] that has dropped below
  /// it.
  static const double _runGap = 6;

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
                // `trailing != null` first, so that the pinned slot wins
                // if both ever arrive together. The assert above is the real
                // answer and it is compiled out of a release build, which is
                // the one build where this matters: dropping a value chip
                // costs a label, and dropping a dismiss button costs the only
                // way to get rid of the card.
                child: trailing != null || trailingValue == null
                    ? _cornerHeader(colors)
                    : _sharedHeader(colors),
              ),
            child,
          ],
        ),
      ),
    );
  }

  /// The title with [trailing] pinned beside it, which is the arrangement this
  /// header has always had.
  ///
  /// Also the arrangement for a header with no trailing at all, where the
  /// `Expanded` is the whole of it and the title simply wraps in the card's
  /// width. Three of the five call sites pass no trailing and two of those
  /// reach this: `connect_card.dart` passes no title either, so it gets no
  /// header at all.
  Widget _cornerHeader(QAppColors colors) => Row(
    children: [
      Expanded(child: _title(colors)),
      ?trailing,
    ],
  );

  /// The title and [trailingValue] sharing a line while both fit it whole.
  ///
  /// [_gap] to spare and no more, from `WrapAlignment.spaceBetween`: it holds
  /// the value against the trailing edge while the two share a run, which is
  /// what the `Expanded` did. With one child on a run there is nothing to
  /// space, so a stacked value sits at the leading edge - the same place
  /// #463's stacked dropdown sits, and the reason that is acceptable for a
  /// value and not for [trailing].
  ///
  /// `width: double.infinity` because a `Wrap` is as wide as its widest run,
  /// and without it a header whose title and value both fit would shrink to
  /// them and lose the `spaceBetween` it is here for.
  Widget _sharedHeader(QAppColors colors) => SizedBox(
    width: double.infinity,
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: _gap,
      runSpacing: _runGap,
      children: [_title(colors), trailingValue!],
    ),
  );

  Widget _title(QAppColors colors) => Text(
    title!,
    style: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: colors.textPrimary,
    ),
  );
}
