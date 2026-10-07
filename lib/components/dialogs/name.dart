import 'package:flutter/material.dart';

import '../../services/localization/l10n.dart';
import '../../theme/theme.dart';

/// Asks for one name, checked while it is typed.
///
/// Mirrors `QConfirmDialog.show` in shape - a static `show` that returns what
/// the user chose - for familiarity rather than for that one's reason, which
/// is folding a `bool?` into a `bool`.
///
/// `lib/` held eight hand-rolled `showDialog<String>` prompts sharing one
/// AlertDialog/TextField/two-TextButton skeleton. Four ask for a name
/// (`archive/browser`, `archive/overview`, its `category_page` copy, and the
/// paint editor); the other three ask for a hex offset, a URL and a set of API
/// keys. Only the seed one validated anything, and its live checking, fixed
/// extension suffix and pre-selected suggestion were locked behind a private
/// class in one page file - so the next feature needing a validated prompt
/// would have written a ninth. #266
///
/// Per CLAUDE.md the seven existing prompts are not converted here; this gives
/// them somewhere to go when each is next touched. [hintText] is here for that
/// reason and not for the seed page, which does not pass one: all seven do.
class QNameDialog extends StatefulWidget {
  const QNameDialog({
    super.key,
    required this.title,
    this.initial = '',
    this.validate,
    this.helperText,
    this.hintText,
    this.suffixText,
    this.confirmLabel,
    this.cancelLabel,
  });

  final String title;

  /// What the field starts with, selected rather than merely filled.
  final String initial;

  /// What is wrong with the typed value, in the user's language, or null when
  /// nothing is.
  ///
  /// Called on every keystroke, so it does no I/O - it judges the characters,
  /// not whether the name is free. Gets the text **as typed**, untrimmed, so a
  /// rule that cares about surrounding space can see it; a rule that does not
  /// trims for itself, as the caller's own check will have to anyway.
  ///
  /// It is never asked about an empty field - the dialog refuses that itself,
  /// and says nothing about it.
  final String? Function(String value)? validate;

  /// Shown under the field, for the rule the user has not broken yet - where
  /// the file lands, how long a name may be. Two lines, then it clips.
  final String? helperText;

  /// Shown inside the field while it is empty.
  ///
  /// Not used by the seed page, whose field is never empty on open. Every one
  /// of the seven prompts waiting to adopt this dialog passes one, and
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
  /// refused here rather than in every [QNameDialog.validate] separately, and
  /// `validate` is never asked about one.
  ///
  /// Computed once per build rather than per read: `validate` runs on every
  /// keystroke and is the caller's code.
  ({String? message, bool valid}) get _check {
    if (_name.text.trim().isEmpty) return (message: null, valid: false);
    final message = widget.validate?.call(_name.text);
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
        // it would be enforcing unsayable. `validate` says it instead.
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
