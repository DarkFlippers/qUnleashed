import '../services/localization/l10n.dart';
import 'path.dart';

/// What a name may be, as a value a prompt can be handed.
///
/// [QNameDialog] took the rule as a `String? Function(String)`, so the ninth
/// caller wrote the ninth *rule* and the shared dialog rendered it faithfully:
/// the widget was prevented, the rule was not. Four prompts that write a
/// user-named file to the device wrote no rule at all - the file manager's
/// new-folder prompt and its inline rename, the archive overview's rename and
/// its category page's copy - and a fifth, the replace dialog's rename field,
/// wrote a weak one. All five reached the firmware with names it refuses.
/// #277, #278
///
/// Carrying a rule rather than describing one: the character set, the dot rule
/// and the counting are [deviceNameProblem]'s, and the only thing that varies
/// between callers today is the budget. A caller needing something genuinely
/// its own - that the name is already taken, or a convention only it has - can
/// pass `QNameDialog.validate` as well, which runs after this; no caller in
/// `lib/` does.
class NameRule {
  /// The budget in **bytes**, named at the call site so the unit cannot be
  /// mistaken for a character count.
  ///
  /// Both asserts are checked when the compiler evaluates a `const` rule,
  /// which is every rule in `lib/`, so a bad budget is a build error rather
  /// than a prompt that behaves oddly. The upper one closes the one direction
  /// in which this type could put #277 back: a budget wider than the volume
  /// accepts a name the volume will not, which is a write that fails with
  /// nothing useful said.
  const NameRule.ofBytes(this.maxBytes)
    : assert(maxBytes > 0, 'a rule that refuses every name is not a rule'),
      assert(
        maxBytes <= deviceNameMaxBytes,
        'a layer is narrower than the volume, never wider',
      );

  /// How many bytes the name may run to, for the layer this caller writes
  /// through.
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
///
/// The one place the default budget is spelled, so that a prompt which passes
/// no rule and one which passes this get the same answer by construction.
const deviceNameRule = NameRule.ofBytes(deviceNameMaxBytes);
