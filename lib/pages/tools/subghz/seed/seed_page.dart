import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../../components/dialogs/confirm.dart';
import '../../../../components/dialogs/name.dart';
import '../../../../components/notification.dart';
import '../../../../components/path.dart';
import '../../../../services/guarded.dart';
import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import 'faaccrack_recoverer.dart';
import 'seed_controller.dart';
import 'seed_models.dart';
import 'seed_sub_file.dart';

/// Recovers the seed of a FAAC SLH, Genius, BFT or Erreka remote from a capture
/// the Flipper-side app collected, and writes the result back as a
/// transmittable `.sub`.
class SeedPage extends StatefulWidget {
  const SeedPage({super.key, required this.client, this.recoverer});

  /// The Flipper this run belongs to. Required rather than defaulted: the route
  /// builder is handed a context with a DeviceScope above it, so a default
  /// would only hide which device a recovery ran against. ADR 0002.
  final FlipperClient client;

  /// The engine, for a widget test. Production leaves it null and the
  /// controller builds the native one; a test passes a fake, because a search
  /// that comes back `engineUnavailable` never reaches the Save button and the
  /// whole name-and-delete chain is then unreachable from the page.
  @visibleForTesting
  final FaaccrackRecoverer? recoverer;

  @override
  State<SeedPage> createState() => _SeedPageState();
}

class _SeedPageState extends State<SeedPage> {
  late final SeedController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SeedController(
      client: widget.client,
      recoverer: widget.recoverer,
    )..addListener(_onChanged);
    _controller.refresh();
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<bool> _confirmStop() => QConfirmDialog.show(
    context,
    title: context.l10n.seedStopTitle,
    message: context.l10n.seedStopMessage,
    confirmLabel: context.l10n.seedStop,
    cancelLabel: context.l10n.seedStopCancel,
  );

  /// Names the file, then writes it.
  ///
  /// The name is asked for rather than generated silently because the generated
  /// one says what the remote is and nothing about what it is *for*, and a
  /// Sub-GHz list is read by its names. The suggestion is the generated name,
  /// so a user with nothing to add presses Save twice.
  Future<void> _save() async {
    final suggested = _controller.suggestedName;
    // Null exactly when canSave is false, which is also when the button that
    // calls this is not built - so this is the race where a result changed
    // under a tap, not a state the user can sit in.
    if (suggested == null) return;

    final l10n = context.l10n;
    final chosen = await QNameDialog.show(
      context,
      title: l10n.seedNameTitle,
      initial: suggested,
      // The extension is shown and not editable, which is the whole reason the
      // field holds a base name.
      suffixText: SeedSubFile.fileExtension,
      helperText: l10n.seedNameHelp(
        seedSubGhzDir,
        SeedSubFile.maxBaseNameLength,
      ),
      confirmLabel: l10n.seedSave,
      validate: _nameProblem,
    );
    if (chosen == null || !mounted) return;

    await _controller.save(chosen);
    if (!mounted) return;

    // The controller refuses to clobber rather than asking, so the standing
    // file comes back as a failure and this is the answer to it. Asked once:
    // a second refusal under `replace` would be a different failure.
    final blocked = _controller.error;
    if (blocked == SeedFailure.nameTaken ||
        blocked == SeedFailure.nameUnchecked) {
      final replace = await QConfirmDialog.show(
        context,
        title: context.l10n.seedReplaceTitle,
        message: blocked == SeedFailure.nameTaken
            ? context.l10n.seedReplaceMessage(SeedSubFile.pathFor(chosen))
            : context.l10n.seedReplaceUnknown(SeedSubFile.pathFor(chosen)),
        confirmLabel: context.l10n.seedReplace,
        cancelLabel: context.l10n.commonCancel,
      );
      if (!replace || !mounted) return;
      await _controller.save(chosen, replace: true);
      if (!mounted) return;
    }

    if (_said(_controller.error)) return;
    await _offerToDeleteCapture();
  }

  /// Says a failure where the user is looking, and reports whether there was
  /// one.
  ///
  /// The banner lives at the top of a scrolling list while the buttons that
  /// cause these are further down it, so on a phone with a long capture a
  /// failed save draws off-screen and the press looks like it did not register
  /// - the shape of #118/#134. The archive pages reach for the same overlay
  /// for the same reason (`archive/overview/failure_toast.dart`, #110).
  bool _said(SeedFailure? failure) {
    if (failure == null) return false;
    context.showNotification(
      _failureText(context, failure),
      type: QNotificationType.error,
    );
    return true;
  }

  /// Offers to remove the capture now that its remote is saved.
  ///
  /// Asked rather than done: the capture is the only record of a remote the
  /// user had to be standing next to, and a wrong guess here cannot be undone
  /// from this page. Asked rather than left alone because the Flipper-side app
  /// never cleans up, so the folder fills with captures whose remotes are
  /// already saved and the list stops saying which ones still need work.
  Future<void> _offerToDeleteCapture() async {
    // Only after a save that actually landed; `save` reports its own failure
    // and leaves savedTo null, and offering to delete the source then would be
    // offering to delete the only copy. The two nulls below are that same
    // condition, read again for promotion.
    final file = _controller.openedFile;
    final savedTo = _controller.savedTo;
    if (file == null || savedTo == null) return;
    await _confirmDelete(file, savedTo: savedTo);
  }

  /// Asks, then deletes [file].
  ///
  /// One dialog for both entry points, because the controller has one delete.
  /// What differs is what can honestly be said: straight after a save the app
  /// knows where the remote went and can offer to keep the capture instead;
  /// from a row it knows neither, so the message carries the stake and the
  /// decline is an ordinary cancel. `seedDeleteFailed` was already merged into
  /// one string for the same reason.
  Future<void> _confirmDelete(SeedCaptureFile file, {String? savedTo}) async {
    final l10n = context.l10n;
    final remove = await QConfirmDialog.show(
      context,
      title: l10n.seedDeleteCaptureTitle,
      message: savedTo == null
          ? l10n.seedDeleteRowMessage(file.name)
          : l10n.seedDeleteCaptureMessage(savedTo, file.name),
      confirmLabel: l10n.seedDeleteCapture,
      cancelLabel: savedTo == null ? l10n.commonCancel : l10n.seedKeepCapture,
    );
    if (!remove || !mounted) return;
    await _controller.deleteCapture(file);
    if (!mounted) return;
    if (_said(_controller.error)) return;
    // Not a failure, so not `_said`: the row has gone and probably is gone, but
    // the device stopped answering before it could be checked, and the clean
    // removal the user is looking at is the same one a verified delete gives.
    if (_controller.deleteUnconfirmed) {
      context.showNotification(l10n.seedDeleteUnconfirmed(file.name));
    }
  }

  /// Re-reads the capture folder and says what it found.
  ///
  /// The spinner alone was not an answer: the listing usually returns the same
  /// folder it returned last time, and quickly, so the icon swaps back before
  /// anyone sees it and the button still looks dead. The count is the thing
  /// that is always different from nothing, even when nothing changed.
  Future<void> _refresh() async {
    // The gesture and the toolbar button share this, and the gesture cannot be
    // disabled - a RefreshIndicator fires whatever its child's state - so the
    // guard the button carries in `onPressed` has to be here too. Without it a
    // pull during a search overwrote SeedStage.searching: the progress bar and
    // Stop went away while the sweep ran on, Start came back enabled, and
    // PopScope let the page be popped without the stop confirmation.
    if (_searching || _listing) return;
    await _controller.refresh();
    if (!mounted) return;
    // Only for a listing that answered. A count is an assertion about the
    // device, and "No captures on the device" after a listing that failed is
    // the wrong turn the controller's own catch exists to prevent.
    if (_said(_controller.error)) return;
    context.showNotification(
      context.l10n.seedRefreshed(_controller.files.length),
    );
  }

  bool get _searching => _controller.stage == SeedStage.searching;
  bool get _listing => _controller.stage == SeedStage.listing;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmStop() && mounted) {
          _controller.stop();
          navigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          title: Text(context.l10n.seedTitle),
          actions: [
            // A spinner in its place while it runs. The folder usually comes
            // back exactly as it went out, so without this the button did its
            // whole job and looked broken.
            IconButton(
              tooltip: context.l10n.seedRefresh,
              onPressed: _searching || _listing ? null : _refresh,
              icon: _listing
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onAccent,
                      ),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        // Pull to re-list, the way the archive and apps pages do. Flutter's
        // default drag devices exclude the mouse, so the toolbar button is not
        // redundant - it is the only way to refresh on the desktop targets.
        body: RefreshIndicator(
          // `guarded`, as the two apps pages that pull to refresh do:
          // RefreshIndicator does not catch a rejected onRefresh, so a throw
          // would reach the zone as `[uncaught]` naming no operation (#23).
          onRefresh: () => guarded('[Seed] pull to refresh', _refresh),
          child: ListView(
            padding: const EdgeInsets.all(16),
            // So the gesture works when the content is shorter than the
            // viewport, which on this page is the usual case: an empty capture
            // folder is exactly when someone reaches for a refresh.
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              // Before anything else: three operations can fail, and until this
              // existed each of them left the page looking exactly as it had.
              if (_controller.error != null) ...[
                _Banner(_failureText(context, _controller.error!)),
                const SizedBox(height: 12),
              ],
              // A capture that would not parse has no card to hang its reasons
              // off, and those reasons are the actionable half - "unknown
              // Manufacturer Nice" tells the user what to do, a red line does
              // not.
              if (_controller.capture == null &&
                  _controller.captureWarnings.isNotEmpty) ...[
                for (final warning in _controller.captureWarnings)
                  _Hint(warning),
                const SizedBox(height: 12),
              ],
              if (_controller.stage == SeedStage.loading) ...[
                Text(
                  context.l10n.seedLoading,
                  style: TextStyle(fontSize: 13, color: colors.textMuted),
                ),
                const SizedBox(height: 12),
              ],
              if (_controller.capture != null) ...[
                _CaptureCard(controller: _controller),
                const SizedBox(height: 12),
                _ActionBlock(
                  controller: _controller,
                  confirmStop: _confirmStop,
                ),
                const SizedBox(height: 12),
                if (_controller.result != null)
                  _ResultCard(controller: _controller, onSave: _save),
                const SizedBox(height: 20),
              ],
              _CaptureList(controller: _controller, onDelete: _confirmDelete),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the capture holds, before anything is attacked.
class _CaptureCard extends StatelessWidget {
  const _CaptureCard({required this.controller});

  final SeedController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final capture = controller.capture!;
    final frequency = capture.frequencyHz;
    return _Card(
      children: [
        _Row(
          label: context.l10n.seedManufacturer,
          value: capture.manufacturer.label,
        ),
        // Fix, seed and counter are the three figures the result is read for;
        // the fix is known before the search and is shown from the start so a
        // user can check they opened the right capture.
        _Row(label: context.l10n.seedFix, value: seedHex(capture.fix, 8)),
        _Row(
          label: context.l10n.seedHops(capture.hops.length),
          value: capture.hops.map((h) => seedHex(h, 8)).join('  '),
          wrap: true,
        ),
        if (frequency != null)
          _Row(
            label: context.l10n.seedFrequency,
            value: '${(frequency / 1000000).toStringAsFixed(2)} MHz',
          ),
        // The reasons, not only the count. A file four of whose nine hops were
        // dropped may no longer have consecutive ones, so the search will find
        // nothing for a reason that is not about the remote - and "unreadable
        // hop: 4010" is the half the user can act on.
        if (controller.captureWarnings.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              context.l10n.seedSkippedLines(controller.captureWarnings.length),
              style: TextStyle(fontSize: 12, color: colors.info),
            ),
          ),
          for (final warning in controller.captureWarnings) _Hint(warning),
        ],
      ],
    );
  }
}

/// Start, progress and stop.
class _ActionBlock extends StatelessWidget {
  const _ActionBlock({required this.controller, required this.confirmStop});

  final SeedController controller;
  final Future<bool> Function() confirmStop;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (controller.stage == SeedStage.searching) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.seedSearching,
            style: TextStyle(fontSize: 13, color: colors.textMuted),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: controller.progress,
            color: colors.accent,
            backgroundColor: colors.divider,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: controller.cancelled
                ? null
                : () async {
                    if (await confirmStop()) controller.stop();
                  },
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.danger,
              disabledForegroundColor: colors.textMuted,
              side: BorderSide(
                color: controller.cancelled ? colors.divider : colors.danger,
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(
              context.l10n.seedStop,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    }

    // Not offered when the engine's own checks failed: they run per search, so
    // every attempt gives the same answer, and the header says as much.
    final broken =
        controller.result?.outcome == SeedOutcome.engineSelfTestFailed;
    return FilledButton(
      onPressed: controller.capture!.isSolvable && !broken
          ? controller.search
          : null,
      style: FilledButton.styleFrom(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: Text(
        context.l10n.seedStart,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// What came back, and what can be done with it.
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.controller, required this.onSave});

  final SeedController controller;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    final result = controller.result!;
    final capture = controller.capture!;

    final (headline, tint) = switch (result.outcome) {
      SeedOutcome.found => (l10n.seedFound, colors.success),
      SeedOutcome.unverified => (l10n.seedUnverified, colors.info),
      SeedOutcome.nothingMatched => (l10n.seedNothingMatched, colors.textMuted),
      SeedOutcome.stopped => (l10n.seedStopped, colors.textMuted),
      SeedOutcome.engineBusy => (l10n.seedEngineBusy, colors.info),
      SeedOutcome.engineUnavailable => (
        l10n.seedEngineUnavailable,
        colors.danger,
      ),
      SeedOutcome.engineSelfTestFailed => (
        l10n.seedEngineBroken,
        colors.danger,
      ),
      SeedOutcome.engineFault => (l10n.seedEngineFault, colors.danger),
    };

    final seed = result.seed;
    final counter = result.counter;
    final hopsUsed = result.hopsUsed;

    return _Card(
      children: [
        Text(
          headline,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: tint,
          ),
        ),
        const SizedBox(height: 8),
        if (seed != null) ...[
          _Row(label: l10n.seedFix, value: seedHex(capture.fix, 8)),
          _Row(label: l10n.seedSeed, value: seedHex(seed, 8)),
          if (counter != null)
            _Row(
              label: l10n.seedCounter,
              value: seedHex(counter, capture.manufacturer.counterDigits),
            ),
        ],
        // A no-match is the result most likely to be misread as a verdict on
        // the remote, so it is the one that gets an explanation rather than a
        // line of status.
        if (result.outcome == SeedOutcome.nothingMatched)
          _Hint(l10n.seedNothingMatchedHint),
        if (result.outcome == SeedOutcome.unverified)
          _Hint(l10n.seedUnverifiedHint),
        // The gate is per process and has no reset, so the only cure for a
        // stranded one is restarting - which the bare status does not say.
        if (result.outcome == SeedOutcome.engineBusy)
          _Hint(l10n.seedEngineBusyHint),
        if (result.outcome == SeedOutcome.engineSelfTestFailed ||
            result.outcome == SeedOutcome.engineUnavailable)
          _Hint(l10n.seedEngineBrokenHint),
        if (seed != null && hopsUsed != null && hopsUsed < seedHopsConfident)
          _Hint(l10n.seedLowConfidence(hopsUsed, seedHopsConfident)),
        if (result.outcome == SeedOutcome.found && capture.frequencyHz == null)
          _Hint(l10n.seedSaveNoFrequency),
        if (controller.canSave) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            // `saving`, not just `savedTo`: the stat and the write take a
            // moment, and a second press in that window starts a second
            // independent write of the same file.
            onPressed: controller.savedTo == null && !controller.saving
                ? onSave
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.onAccent,
              // Both axes. With only the vertical one the horizontal padding
              // is overridden to zero, and the label - which is sized by the
              // text, not the button - draws wider than the pill behind it.
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            icon: const Icon(Icons.save_alt, size: 18),
            label: Text(
              l10n.seedSave,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
        if (controller.savedTo != null)
          _Hint(l10n.seedSaved(controller.savedTo!)),
      ],
    );
  }
}

/// The captures the device is holding.
class _CaptureList extends StatelessWidget {
  const _CaptureList({required this.controller, required this.onDelete});

  final SeedController controller;
  final void Function(SeedCaptureFile file) onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    // Not just "searching": a read carries a two-minute timeout, so deleting
    // the row being read ended with the read reporting a failure for a file the
    // list had already dropped.
    final busy = controller.busy;

    if (controller.files.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.seedNoCaptures,
            style: TextStyle(fontSize: 14, color: colors.textMuted),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.seedNoCapturesHint,
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.seedCapturesTitle,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        for (final file in controller.files)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              file.name,
              style: TextStyle(fontSize: 13, color: colors.textPrimary),
            ),
            onTap: busy ? null : () => controller.open(file),
            // On the row, because that is where the whole folder is visible -
            // and where a capture that cannot be solved at all can be reached,
            // which the post-save prompt by construction never could.
            //
            // Disabled rather than hidden once the link these rows were listed
            // over has gone: a button that vanishes reads as a feature that is
            // not there, and the banner says what to do instead.
            trailing: IconButton(
              tooltip: l10n.seedDeleteCapture,
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              color: colors.textMuted,
              onPressed: busy || !controller.canDeleteCaptures
                  ? null
                  : () => onDelete(file),
              icon: controller.deleting(file)
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
            ),
          ),
      ],
    );
  }
}

/// What is wrong with [value] as a name for the recovered remote, in words.
///
/// Lives here rather than in `seed_sub_file.dart` because it is the only part
/// of the rule that needs strings: the check itself is a pure function of the
/// string. Reads the global `l10n` rather than taking one, the way
/// `describeConnectError` does, so it can be passed to [QNameDialog] by name.
///
/// The switch is exhaustive, so a new [SeedNameProblem] is a compile error
/// here rather than a silently unexplained refusal.
String? _nameProblem(String value) =>
    switch (SeedSubFile.checkBaseName(value)) {
      // Nothing to say: either the name is fine, or the field is empty - which
      // the dialog gates itself and deliberately does not complain about.
      null || SeedNameProblem.empty => null,
      SeedNameProblem.tooLong => l10n.seedNameTooLong(
        SeedSubFile.maxBaseNameLength,
      ),
      SeedNameProblem.illegalCharacter => l10n.commonNameIllegal(
        reservedNameCharsSpelled,
      ),
      SeedNameProblem.controlCharacter => l10n.commonNameControlChar,
      SeedNameProblem.nonAscii => l10n.commonNameNonAscii,
      SeedNameProblem.dotEdge => l10n.commonNameDotEdge,
    };

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.wrap = false});

  final String label;
  final String value;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              softWrap: wrap,
              overflow: wrap ? TextOverflow.clip : TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: colors.textMuted),
      ),
    );
  }
}

/// What a failed operation is called, in the user's language.
///
/// A switch rather than a map so a new [SeedFailure] is a compile error here
/// rather than a blank banner.
String _failureText(BuildContext context, SeedFailure failure) =>
    switch (failure) {
      SeedFailure.disconnected => context.l10n.seedDisconnected,
      SeedFailure.unreadableCapture => context.l10n.seedUnreadableCapture,
      SeedFailure.readFailed => context.l10n.seedReadFailed,
      SeedFailure.listFailed => context.l10n.seedListFailed,
      SeedFailure.invalidName => context.l10n.seedInvalidName,
      // Both are answered with a prompt rather than shown, so they reach
      // `_failureText` only if one outlives the flow that asked about it.
      SeedFailure.nameTaken => context.l10n.seedSaveFailed,
      SeedFailure.nameUnchecked => context.l10n.seedSaveFailed,
      SeedFailure.saveFailed => context.l10n.seedSaveFailed,
      SeedFailure.deleteFailed => context.l10n.seedDeleteFailed,
      SeedFailure.listingStale => context.l10n.seedListingStale,
    };

/// A failure, said once, where the user is already looking.
class _Banner extends StatelessWidget {
  const _Banner(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.danger),
      ),
      child: Text(text, style: TextStyle(fontSize: 13, color: colors.danger)),
    );
  }
}
