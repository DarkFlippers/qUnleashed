import 'package:flutter/material.dart';

import '../../services/localization/l10n.dart';
import '../../theme/theme.dart';
import '../name_rule.dart';

/// Asks for one name, checked while it is typed.
///
/// Mirrors `QConfirmDialog.show` in shape - a static `show` that returns what
/// the user chose - for familiarity rather than for that one's reason, which
/// is folding a `bool?` into a `bool`.
///
/// `lib/` held eight hand-rolled `showDialog<String>` prompts sharing one
/// AlertDialog/TextField/two-TextButton skeleton, and only the seed one
/// validated anything - its live checking, fixed extension suffix and
/// pre-selected suggestion locked behind a private class in one page file, so
/// the next feature needing a validated prompt would have written a ninth.
/// #266
///
/// Three of the eight are converted: the file manager's new-folder prompt and
/// the two archive renames, which wrote user-typed names to the device with no
/// rule at all. #277 is why, and #278 is why the rule arrives as a value. Four
/// hand-rolled prompts remain - a hex offset, a URL, a set of API keys, and
/// the paint editor's host folder name, which has a rule of its own - and
/// `test/name_prompt_budget_test.dart` is what keeps that number from rising.
/// [hintText] is here for them rather than for the seed page, which does not
/// pass one.
class QNameDialog extends StatefulWidget {
  const QNameDialog({
    super.key,
    required this.title,
    required this.rule,
    this.initial = '',
    this.validate,
    this.helperText,
    this.hintText,
    this.suffixText,
    this.confirmLabel,
    this.cancelLabel,
  });

  final String title;

  /// What the name may be. Defaults to what the Flipper's storage will carry,
  /// which is the answer for every prompt that writes to the device; a caller
  /// writing through a layer with a narrower limit passes its own budget.
  ///
  /// A value and not a callback, which is what this took before: the rule is
  /// the thing callers were each inventing, so handing it over as data is what
  /// stops the ninth caller writing the ninth rule. #278
  ///
  /// Required, and not defaulted to [deviceNameRule], for the reason
  /// [deviceNameProblem] makes `maxBytes` required one layer down: a prompt
  /// that forgets it would get the device's rule by omission, and the first
  /// caller whose name is *not* going to the device - the paint editor's host
  /// folder is the one waiting - would have ASCII-only and the nine applied to
  /// a host path with nothing saying so.
  final NameRule rule;

  /// What the field starts with, selected rather than merely filled.
  final String initial;

  /// One more thing wrong with the typed value, past what [rule] already
  /// judges: that the name is taken, or a convention only this caller has.
  ///
  /// Called on every keystroke, so it does no I/O - it judges the characters,
  /// not whether the name is free, unless the caller already knows the names
  /// that are. Gets the text **as typed**, untrimmed, so a rule that cares
  /// about surrounding space can see it; a rule that does not trims for
  /// itself, as the caller's own check will have to anyway.
  ///
  /// Runs after [rule], so a name breaking both is reported as the storage
  /// problem first: that one is refused whatever it is called, where "taken"
  /// is fixed by a different name.
  ///
  /// It is never asked about an empty field - the dialog refuses that itself,
  /// and says nothing about it.
  final String? Function(String value)? validate;

  /// Shown under the field, for the rule the user has not broken yet - where
  /// the file lands, how long a name may be. Two lines, then it clips.
  final String? helperText;

  /// Shown inside the field while it is empty.
  ///
  /// Not used by the seed page, whose field is never empty on open.
  /// [helperText] is not a substitute - it renders underneath.
  final String? hintText;

  /// A fixed tail shown inside the field and not part of the result, e.g.
  /// `.sub`.
  ///
  /// This is what makes a field hold a *base* name: it tells the user what
  /// they will get without inviting them to type it a second time, and a
  /// caller that appends an extension to the result cannot produce
  /// `gate.sub.sub`.
  final String? suffixText;

  /// Defaults to `commonOk`. A caller whose dialog is one step of something
  /// longer passes the verb for that step instead.
  final String? confirmLabel;

  /// Defaults to `commonCancel`.
  final String? cancelLabel;

  /// The trimmed name, or null if the user dismissed the dialog.
  ///
  /// Trimmed because the name is what a file will be called, and a leading or
  /// trailing space is not a name the user meant. [validate] still sees the
  /// text untrimmed, so a caller may refuse one rather than accept the tidying.
  static Future<String?> show(
    BuildContext context, {
    required String title,
    required NameRule rule,
    String initial = '',
    String? Function(String value)? validate,
    String? helperText,
    String? hintText,
    String? suffixText,
    String? confirmLabel,
    String? cancelLabel,
  }) => showDialog<String>(
    context: context,
    builder: (_) => QNameDialog(
      title: title,
      rule: rule,
      initial: initial,
      validate: validate,
      helperText: helperText,
      hintText: hintText,
      suffixText: suffixText,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    ),
  );

  @override
  State<QNameDialog> createState() => _QNameDialogState();
}

/// Stateful because the name is checked as it is typed: a dialog that accepts
/// anything and fails afterwards reports the problem through whatever the
/// caller's write failure is, which cannot say which character was wrong.
class _QNameDialogState extends State<QNameDialog> {
  // Selected, not just filled: the suggestion is the common answer, and the
  // user who wants their own should not have to clear it first.
  late final TextEditingController _name =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initial.length,
        );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Whether the field may be confirmed, and what to say about it if not.
  ///
  /// One value rather than two getters, because "nothing to say" and "may be
  /// confirmed" are not the same thing and two getters that must agree about
  /// the difference is how one of them ends up simplified into the other. The
  /// case they differ on is an empty field: it may not be confirmed, and
  /// nothing is said about it - the confirm button is already disabled, and an
  /// error on a field the user has only just cleared reads as a complaint
  /// about their typing.
  ///
  /// Empty is also not a name on any storage this app writes to, so it is
  /// refused here rather than by each caller separately.
  ///
  /// Computed once per build rather than per read: `validate` runs on every
  /// keystroke and is the caller's code.
  ({String? message, bool valid}) get _check {
    if (_name.text.trim().isEmpty) return (message: null, valid: false);
    final message =
        widget.rule.describe(context.l10n, _name.text) ??
        widget.validate?.call(_name.text);
    return (message: message, valid: message == null);
  }

  void _submit() {
    if (!_check.valid) return;
    Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    final check = _check;

    // No `backgroundColor`: `buildAppTheme` already sets it on `dialogTheme`,
    // so passing it again is a no-op that reads as a requirement. No `shape`
    // either - the radius is left to the framework default, which is what
    // `QConfirmDialog` uses, because the seed page opens one straight into the
    // other and a 14 here made the corners change mid-gesture.
    return AlertDialog(
      title: Text(widget.title, style: TextStyle(color: colors.dialogText)),
      content: TextField(
        controller: _name,
        // Without this the keyboard does not appear, so the user taps the
        // field - which collapses the selection the controller just made.
        autofocus: true,
        // No `maxLength`: it enforces by truncation, which takes the tail off
        // a pasted name with nothing on screen saying so, and leaves the rule
        // it would be enforcing unsayable. [rule] says it instead.
        onChanged: (_) => setState(() {}),
        style: TextStyle(color: colors.dialogText),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: TextStyle(color: colors.dialogMuted),
          suffixText: widget.suffixText,
          suffixStyle: TextStyle(color: colors.dialogMuted),
          helperText: widget.helperText,
          helperStyle: TextStyle(color: colors.dialogMuted),
          helperMaxLines: 2,
          errorText: check.message,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            widget.cancelLabel ?? l10n.commonCancel,
            style: TextStyle(color: colors.dialogMuted),
          ),
        ),
        TextButton(
          onPressed: check.valid ? _submit : null,
          child: Text(
            widget.confirmLabel ?? l10n.commonOk,
            style: TextStyle(
              color: check.valid ? colors.accent : colors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}
