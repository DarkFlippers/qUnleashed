import 'package:flutter/material.dart';

import '../../services/localization/l10n.dart';
import '../../theme/theme.dart';

/// Asks for one name, checked while it is typed.
///
/// Mirrors `QConfirmDialog.show` in shape - a static `show` that returns what
/// the user chose - and exists for the same reason. `lib/` held eight
/// hand-rolled `showDialog<String>` name prompts, seven of them the same
/// AlertDialog/TextField/two-TextButton skeleton with the same theming, and
/// only the eighth validated anything. The live checking, the fixed extension
/// suffix and the pre-selected suggestion were all locked behind a private
/// class in one page file, so the next feature needing a validated name prompt
/// would have written a ninth. #266
///
/// Per CLAUDE.md the seven existing prompts are not converted here; this gives
/// them somewhere to go when each is next touched.
class QNameDialog extends StatefulWidget {
  const QNameDialog({
    super.key,
    required this.title,
    this.initial = '',
    this.validate,
    this.helperText,
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
  /// It is never asked about an empty field: see [_QNameDialogState._message].
  final String? Function(String value)? validate;

  /// Shown under the field, for the rule the user has not broken yet - where
  /// the file lands, how long a name may be. Two lines, then it clips.
  final String? helperText;

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
  /// Trimmed because the name is what a file will be called and a trailing
  /// space is not a name the user meant - and because the value shown to them
  /// was judged trimmed, so returning the raw text would hand back something
  /// that was never approved.
  static Future<String?> show(
    BuildContext context, {
    required String title,
    String initial = '',
    String? Function(String value)? validate,
    String? helperText,
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

  /// The error to show, or null when there is nothing to say.
  ///
  /// Null covers two different states, which is why [_valid] is separate: a
  /// name that is fine, and an empty field. Nothing is said about an empty
  /// field - the confirm button is already disabled, and an error on a field
  /// the user has only just cleared reads as a complaint about their typing.
  /// Empty is also not a name on any storage this app writes to, so it is
  /// refused here rather than in every [QNameDialog.validate] separately.
  String? get _message =>
      _name.text.trim().isEmpty ? null : widget.validate?.call(_name.text);

  bool get _valid => _name.text.trim().isNotEmpty && _message == null;

  void _submit() {
    if (!_valid) return;
    Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    final valid = _valid;

    return AlertDialog(
      backgroundColor: colors.dialogBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(widget.title, style: TextStyle(color: colors.dialogText)),
      content: TextField(
        controller: _name,
        autofocus: true,
        // No `maxLength`: it enforces by truncation, which takes the tail off
        // a pasted name with nothing on screen saying so, and leaves the rule
        // it would be enforcing unsayable. `validate` says it instead.
        onChanged: (_) => setState(() {}),
        style: TextStyle(color: colors.dialogText),
        decoration: InputDecoration(
          suffixText: widget.suffixText,
          suffixStyle: TextStyle(color: colors.dialogMuted),
          helperText: widget.helperText,
          helperStyle: TextStyle(color: colors.dialogMuted),
          helperMaxLines: 2,
          errorText: _message,
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
          onPressed: valid ? _submit : null,
          child: Text(
            widget.confirmLabel ?? l10n.commonOk,
            style: TextStyle(color: valid ? colors.accent : colors.textMuted),
          ),
        ),
      ],
    );
  }
}
