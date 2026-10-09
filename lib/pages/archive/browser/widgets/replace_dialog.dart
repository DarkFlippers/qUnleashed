import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../components/format.dart';
import '../../../../components/path.dart';
import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../controller.dart';
import 'file_row.dart';

/// Walks the user through every file a transfer would overwrite, one at a
/// time, and hands back a [ConflictResolution].
class ReplaceFilesDialog extends StatefulWidget {
  const ReplaceFilesDialog({
    super.key,
    required this.destination,
    required this.items,
    required this.conflicts,
  });

  final String destination;
  final int items;
  final List<FileConflict> conflicts;

  static Future<ConflictResolution?> show(
    BuildContext context, {
    required String destination,
    required int items,
    required List<FileConflict> conflicts,
  }) => showDialog<ConflictResolution>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ReplaceFilesDialog(
      destination: destination,
      items: items,
      conflicts: conflicts,
    ),
  );

  @override
  State<ReplaceFilesDialog> createState() => _ReplaceFilesDialogState();
}

class _ReplaceFilesDialogState extends State<ReplaceFilesDialog> {
  final List<ConflictChoice> _choices = [];
  final TextEditingController _name = TextEditingController();
  bool _forAll = false;
  bool _skipIdentical = true;
  bool _renaming = false;

  int get _index => _choices.length;
  FileConflict get _conflict => widget.conflicts[_index];
  int get _remaining => widget.conflicts.length - _index;
  bool get _many => _forAll && _remaining > 1;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _decide(ConflictChoice choice) {
    final count = _many ? _remaining : 1;
    _choices.addAll(List.filled(count, choice));
    _advance();
  }

  void _advance() {
    if (_choices.length >= widget.conflicts.length) {
      _finish();
      return;
    }
    setState(() => _renaming = false);
  }

  void _finish() {
    final choices = [
      ..._choices,
      ...List.filled(
        widget.conflicts.length - _choices.length,
        const ConflictChoice.skip(),
      ),
    ];
    final resolution = ConflictResolution(
      choices: choices,
      skipIdentical: _skipIdentical,
    );
    Navigator.of(context).pop(resolution);
  }

  String _folderOf(String relative) {
    final parent = dirname(relative);
    return parent.isEmpty ? '' : '$parent/';
  }

  bool _isTaken(String name) {
    if (_conflict.siblings.contains(name)) return true;
    final path = '${_folderOf(_conflict.name)}$name';
    for (var i = 0; i < _choices.length; i++) {
      final chosen = _choices[i].newName;
      if (chosen == null) continue;
      if ('${_folderOf(widget.conflicts[i].name)}$chosen' == path) return true;
    }
    return false;
  }

  String _suggest() {
    final name = basename(_conflict.name);
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var n = 2; ; n++) {
      final candidate = '$stem ($n)$ext';
      if (!_isTaken(candidate)) return candidate;
    }
  }

  void _startRename() {
    final suggested = _suggest();
    final dot = suggested.lastIndexOf('.');
    _name.value = TextEditingValue(
      text: suggested,
      selection: TextSelection(
        baseOffset: 0,
        extentOffset: dot > 0 ? dot : suggested.length,
      ),
    );
    setState(() => _renaming = true);
  }

  String? _problem(L10n l) {
    final name = _name.text.trim();
    if (name.isEmpty || name == '.' || name == '..' || name.contains('/')) {
      return l.fmConflictRenameInvalid;
    }
    if (_isTaken(name)) return l.fmConflictRenameTaken;
    return null;
  }

  void _applyRename() {
    if (_problem(context.l10n) != null) return;
    _choices.add(ConflictChoice.rename(_name.text.trim()));
    _advance();
  }

  ButtonStyle _primary(QAppColors colors) => ElevatedButton.styleFrom(
    elevation: 0,
    backgroundColor: colors.accent,
    foregroundColor: colors.onAccent,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
  );

  Widget _buildChecks(L10n l) {
    return Wrap(
      spacing: 12,
      children: [
        if (_remaining > 1)
          _Check(
            value: _forAll,
            label: l.fmConflictForAll(_remaining),
            onChanged: (v) => setState(() {
              _forAll = v;
              _renaming = false;
            }),
          ),
        _Check(
          value: _skipIdentical,
          label: l.fmConflictMd5,
          onChanged: (v) => setState(() => _skipIdentical = v),
        ),
      ],
    );
  }

  Widget _buildChoices(L10n l, QAppColors colors) {
    return Row(
      children: [
        if (!_many)
          TextButton.icon(
            onPressed: _startRename,
            icon: SvgPicture.asset(
              'assets/ic/action/edit.svg',
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(colors.accent, BlendMode.srcIn),
            ),
            label: Text(
              l.fmRename,
              style: TextStyle(
                color: colors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Expanded(
          child: OverflowBar(
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => _decide(const ConflictChoice.skip()),
                child: Text(
                  _many ? l.fmConflictSkipAll : l.fmConflictSkip,
                  style: TextStyle(
                    color: colors.dialogMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => _decide(const ConflictChoice.replace()),
                style: _primary(colors),
                child: Text(
                  _many ? l.fmConflictReplaceAll : l.fmConflictReplace,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRenameField(L10n l, QAppColors colors) {
    final problem = _problem(l);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _name,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _applyRename(),
            style: TextStyle(color: colors.dialogText, fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              errorText: problem,
              errorMaxLines: 2,
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => setState(() => _renaming = false),
          child: Text(
            l.fmConflictBack,
            style: TextStyle(
              color: colors.dialogMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: problem == null ? _applyRename : null,
          style: _primary(colors),
          child: Text(l.commonOk),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l = context.l10n;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: AlertDialog(
        backgroundColor: colors.dialogBackground,
        title: Text(
          l.fmConflictTitle,
          style: TextStyle(color: colors.dialogText),
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.fmConflictCopying(widget.items, widget.destination),
                  style: TextStyle(color: colors.dialogMuted, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  l.fmConflictSummary(widget.conflicts.length),
                  style: TextStyle(
                    color: colors.dialogText,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                _ConflictCard(
                  conflict: _conflict,
                  index: _index + 1,
                  total: widget.conflicts.length,
                ),
                const SizedBox(height: 8),
                _buildChecks(l),
                const SizedBox(height: 12),
                if (_renaming && !_many)
                  _buildRenameField(l, colors)
                else
                  _buildChoices(l, colors),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.conflict,
    required this.index,
    required this.total,
  });

  final FileConflict conflict;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l = context.l10n;
    final detail = TextStyle(color: colors.dialogMuted, fontSize: 12);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FileIconBadge(
            entry: RemoteEntry(
              name: basename(conflict.name),
              size: conflict.size,
              isDir: false,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conflict.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.dialogText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l.fmConflictSource(formatBytes(conflict.size)),
                  style: detail,
                ),
                Text(
                  l.fmConflictExisting(formatBytes(conflict.existingSize)),
                  style: detail,
                ),
              ],
            ),
          ),
          if (total > 1) Text(l.fmConflictIndex(index, total), style: detail),
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: value,
              activeColor: colors.accent,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => onChanged(v ?? false),
            ),
            Text(
              label,
              style: TextStyle(color: colors.dialogText, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
