import '../services/localization/l10n.dart';
import 'path.dart';

/// What a name may be, as a value a prompt can be handed.
///
/// [QNameDialog] took the rule as a `String? Function(String)`, so the ninth
/// caller wrote the ninth *rule* and the shared dialog rendered it faithfully:
/// the widget was prevented, the rule was not. Four prompts that write a
/// user-named file to the device wrote no rule at all and reached the firmware
/// with whatever was typed. #277, #278
///
/// Carrying a rule rather than describing one: the character set, the dot rule
/// and the counting are [deviceNameProblem]'s, and the only thing that varies
/// between callers is the budget. A caller that needs something genuinely its
/// own - "that name is taken", the paint editor's `_` collapsing - passes
/// `QNameDialog.validate` as well, which runs after this.
class NameRule {
  const NameRule({this.maxBytes = deviceNameMaxBytes});

  /// The Sub-GHz app's own limit, which is narrower than the volume's. See
  /// `SeedSubFile.maxBaseNameLength`.
  const NameRule.ofBytes(this.maxBytes);

  /// How many bytes the name may run to, for the layer this caller writes
  /// through. Defaults to what the volume will carry.
  final int maxBytes;

  /// What is wrong with [value], in the user's language, or null when nothing
  /// is.
  ///
  /// Exhaustive over [DeviceNameProblem] on purpose: a problem added to the
  /// rule is a compile error here rather than a name refused with nothing on
  /// screen. [DeviceNameProblem.empty] has a sentence of its own even though
  /// `QNameDialog` never asks about one - it disables its confirm button
  /// instead - because the prompts that are not that dialog do ask, and a
  /// caller is free to render it.
  ///
  /// Takes the text as typed. [deviceNameProblem] trims before judging, which
  /// is the same thing the dialog's result does, so a name is never refused
  /// for space the caller will not keep.
  String? describe(L10n l10n, String value) =>
      switch (deviceNameProblem(value, maxBytes: maxBytes)) {
        null => null,
        DeviceNameProblem.empty => l10n.commonNameEmpty,
        DeviceNameProblem.tooLong => l10n.commonNameTooLong(maxBytes),
        DeviceNameProblem.illegalCharacter => l10n.commonNameIllegal(
          reservedNameCharsSpelled,
        ),
        DeviceNameProblem.controlCharacter => l10n.commonNameControlChar,
        DeviceNameProblem.nonAscii => l10n.commonNameNonAscii,
        DeviceNameProblem.dotEdge => l10n.commonNameDotEdge,
      };
}

/// The rule for a name written straight to the Flipper's storage: everything
/// the volume and the RPC layer refuse, and nothing a feature adds.
const deviceNameRule = NameRule();
