import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import 'mfkey32_controller.dart';
import 'mfkey32_models.dart';

class MfKey32Page extends StatefulWidget {
  const MfKey32Page({super.key});

  @override
  State<MfKey32Page> createState() => _MfKey32PageState();
}

class _MfKey32PageState extends State<MfKey32Page> {
  late final MfKey32Controller _controller;

  @override
  void initState() {
    super.initState();
    _controller = MfKey32Controller()..addListener(_onControllerChanged);
    _controller.start();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<bool> _onWillPop() async {
    if (!_controller.running) return true;
    final abort = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.appColors.dialogBackground,
        title: Text(
          'Stop Keys Calculation?',
          style: TextStyle(color: context.appColors.dialogText),
        ),
        content: Text(
          'You can restart it later',
          style: TextStyle(color: context.appColors.dialogMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Stop'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return abort ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          title: const Text('Mfkey32 (Extract MF Keys)'),
        ),
        body: ListView(
          children: [
            _MfKey32Progress(
              state: _controller.state,
              onDone: () => Navigator.of(context).maybePop(),
              onRetry: _controller.running ? null : _controller.start,
            ),
            if (_controller.foundedInformation.keys.isNotEmpty)
              _AllKeys(keys: _controller.foundedInformation.keys),
            if (_controller.foundedInformation.uniqueKeys.isNotEmpty)
              _UniqueKeys(keys: _controller.foundedInformation.uniqueKeys),
            if (_controller.foundedInformation.duplicated.isNotEmpty)
              _DuplicatedKeys(keys: _controller.foundedInformation.duplicated),
          ],
        ),
      ),
    );
  }
}

class _MfKey32Progress extends StatelessWidget {
  const _MfKey32Progress({
    required this.state,
    required this.onDone,
    required this.onRetry,
  });

  final MfKey32State state;
  final VoidCallback onDone;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      MfKey32WaitingForFlipper() => const _WaitingForFlipper(),
      MfKey32Calculating(:final percent) => _ProgressBlock(
          title: 'Calculation Started...',
          description: 'Calculating...',
          iconAsset: 'assets/flipper_svg/tools/mifare/pic_key.svg',
          percent: percent,
          accentColor: context.appColors.accent,
          secondColor: context.appColors.accent.withOpacity(0.54),
        ),
      MfKey32DownloadingRawFile(:final percent) => _ProgressBlock(
          title: 'Calculation Started...',
          description: 'Downloading raw file from Flipper...',
          iconAsset: 'assets/flipper_svg/tools/mifare/pic_download.svg',
          percent: percent,
          accentColor: context.appColors.info,
          secondColor: context.appColors.info.withOpacity(0.32),
        ),
      MfKey32Uploading() => _ProgressBlock(
          title: 'Calculation Completed',
          description: 'Syncing with Flipper...',
          iconAsset: 'assets/flipper_svg/tools/mifare/pic_key.svg',
          percent: null,
          accentColor: context.appColors.accent,
          secondColor: context.appColors.accent.withOpacity(0.54),
        ),
      MfKey32Saved(:final keys) => keys.isEmpty
          ? _CompleteNotFound(onDone: onDone)
          : _CompleteAttack(keys: keys, onDone: onDone),
      MfKey32Error(:final errorType) => _ErrorBlock(
          errorType: errorType,
          onRetry: onRetry,
        ),
    };
  }
}

class _ProgressBlock extends StatelessWidget {
  const _ProgressBlock({
    required this.title,
    required this.description,
    required this.iconAsset,
    required this.percent,
    required this.accentColor,
    required this.secondColor,
  });

  final String title;
  final String description;
  final String iconAsset;
  final double? percent;
  final Color accentColor;
  final Color secondColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: _FlipperProgressIndicator(
            iconAsset: iconAsset,
            percent: percent,
            accentColor: accentColor,
            secondColor: secondColor,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
          child: Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ),
        Divider(height: 1, indent: 14, endIndent: 14, color: colors.divider),
      ],
    );
  }
}

class _WaitingForFlipper extends StatelessWidget {
  const _WaitingForFlipper();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 32, bottom: 18),
          child: Text(
            'Connecting Flipper...',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _FlipperMockup(
          active: false,
          child: Center(
            child: SizedBox(
              width: 92,
              child: LinearProgressIndicator(
                color: colors.accent,
                backgroundColor: colors.divider,
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({
    required this.errorType,
    required this.onRetry,
  });

  final MfKey32ErrorType errorType;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (errorType) {
      MfKey32ErrorType.notFoundFile => _NotFoundError(onRetry: onRetry),
      MfKey32ErrorType.readWrite => _SimpleError(
          title: 'SD Card is Full or Not Accessible',
          description:
              'Unable to save keys. The SD Card is not accessible or there is not enough space',
          onRetry: onRetry,
        ),
      MfKey32ErrorType.flipperConnection => _SimpleError(
          title: 'Flipper Not Connected',
          description:
              "1. Check Bluetooth connection with Flipper\n2. Make sure Flipper is Turned on\n3. If Flipper doesn't respond, reboot it and connect to the app via Bluetooth\n4. Restart Mfkey32 (Extract MF Keys)",
          onRetry: onRetry,
        ),
    };
  }
}

class _NotFoundError extends StatelessWidget {
  const _NotFoundError({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 32, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Reader Data Not Found',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: SvgPicture.asset(
              colors.isDark
                  ? 'assets/flipper_svg/tools/mifare/pic_flipper_nfc_detect_reader_black.svg'
                  : 'assets/flipper_svg/tools/mifare/pic_flipper_nfc_detect_reader_white.svg',
              width: 347,
              fit: BoxFit.fitWidth,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'To extract keys from the reader, collect nonces with your Flipper Zero first:',
            style: TextStyle(color: colors.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 12),
          for (final line in const [
            '1. On your Flipper Zero, go to NFC -> Extract MF Keys',
            '2. Hold Flipper Zero close to the reader',
            '3. Wait until you collect enough nonces',
            '4. Complete nonce collection',
            '5. In Flipper Mobile App, synchronize with your Flipper Zero and run the Mfkey32 (Extract MF Keys)',
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                line,
                style: TextStyle(color: colors.textMuted, fontSize: 16),
              ),
            ),
          const SizedBox(height: 18),
          _PrimaryButton(text: 'Retry', onPressed: onRetry),
        ],
      ),
    );
  }
}

class _SimpleError extends StatelessWidget {
  const _SimpleError({
    required this.title,
    required this.description,
    required this.onRetry,
  });

  final String title;
  final String description;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          _FlipperMockup(
            active: false,
            child: Icon(
              Icons.warning_amber_rounded,
              color: colors.screenBorder,
              size: 32,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            description,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 16,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),
          _PrimaryButton(text: 'Retry', onPressed: onRetry),
        ],
      ),
    );
  }
}

class _FlipperProgressIndicator extends StatelessWidget {
  const _FlipperProgressIndicator({
    required this.iconAsset,
    required this.percent,
    required this.accentColor,
    required this.secondColor,
  });

  final String iconAsset;
  final double? percent;
  final Color accentColor;
  final Color secondColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final currentPercent = percent;
    final value = currentPercent == null
        ? null
        : currentPercent.clamp(0.0001, 1.0).toDouble();
    final text =
        currentPercent == null ? '...' : '${(currentPercent * 100).round()}%';
    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: secondColor,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: accentColor, width: 3),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (value != null)
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: value,
                heightFactor: 1,
                child: ColoredBox(color: accentColor),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: SvgPicture.asset(
                iconAsset,
                width: 28,
                height: 28,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 5, bottom: 6),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onAccent,
                fontSize: 40,
                fontWeight: FontWeight.w700,
                fontFamily: 'FlipperBold',
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlipperMockup extends StatelessWidget {
  const _FlipperMockup({
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final template = colors.isDark
        ? active
            ? 'assets/flipper_svg/mockup/template_black_flipper_active.svg'
            : 'assets/flipper_svg/mockup/template_black_flipper_disabled.svg'
        : active
            ? 'assets/flipper_svg/mockup/template_white_flipper_active.svg'
            : 'assets/flipper_svg/mockup/template_white_flipper_disabled.svg';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: AspectRatio(
        aspectRatio: 238 / 100,
        child: Stack(
          children: [
            Positioned.fill(
              child: SvgPicture.asset(template, fit: BoxFit.contain),
            ),
            Positioned(
              left: 61,
              top: 11,
              width: 85,
              height: 46,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: ColoredBox(
                  color: colors.screenBackground,
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompleteAttack extends StatelessWidget {
  const _CompleteAttack({
    required this.keys,
    required this.onDone,
  });

  final List<String> keys;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final title = keys.length == 1
        ? '1 New Key added to User Dict.'
        : '${keys.length} New Keys added to User Dict.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.appColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [for (final key in keys) _KeyPill(keyValue: key)],
          ),
          const SizedBox(height: 24),
          _PrimaryButton(text: 'Done', onPressed: onDone),
        ],
      ),
    );
  }
}

class _CompleteNotFound extends StatelessWidget {
  const _CompleteNotFound({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      child: Column(
        children: [
          Text(
            'New Keys Not Found',
            style: TextStyle(
              color: context.appColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),
          SvgPicture.asset(
            context.appColors.isDark
                ? 'assets/flipper_svg/tools/mifare/pic_shrug_black.svg'
                : 'assets/flipper_svg/tools/mifare/pic_shrug_white.svg',
            width: 154,
            height: 100,
          ),
          const SizedBox(height: 24),
          _PrimaryButton(text: 'Done', onPressed: onDone),
        ],
      ),
    );
  }
}

class _AllKeys extends StatelessWidget {
  const _AllKeys({required this.keys});

  final List<FoundedKey> keys;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 24, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Calculated Keys (${keys.length})',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 10),
          for (final key in keys)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SelectableText(
                'Sector ${_titlecase(key.sectorName)} - Key ${key.keyName.toUpperCase()} - ${key.key ?? 'Not found'}',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UniqueKeys extends StatelessWidget {
  const _UniqueKeys({required this.keys});

  final Set<String> keys;

  @override
  Widget build(BuildContext context) {
    return _KeysSection(
      title: 'Unique (${keys.length})',
      children: [for (final key in keys) _KeyPill(keyValue: key)],
    );
  }
}

class _DuplicatedKeys extends StatelessWidget {
  const _DuplicatedKeys({required this.keys});

  final Map<String, DuplicatedSource> keys;

  @override
  Widget build(BuildContext context) {
    return _KeysSection(
      title: 'Duplicated (${keys.length})',
      children: [
        for (final entry in keys.entries)
          _KeyPill(
            keyValue:
                '${entry.key} - ${entry.value == DuplicatedSource.flipper ? 'Found in Flipper Dict.' : 'Found in User Dict.'}',
          ),
      ],
    );
  }
}

class _KeysSection extends StatelessWidget {
  const _KeysSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: context.appColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: children),
        ],
      ),
    );
  }
}

class _KeyPill extends StatelessWidget {
  const _KeyPill({required this.keyValue});

  final String keyValue;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/flipper_svg/tools/mifare/pic_encrypted_key.svg',
            width: 18,
            height: 18,
          ),
          const SizedBox(width: 8),
          SelectableText(
            keyValue,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.text,
    required this.onPressed,
  });

  final String text;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(text),
      ),
    );
  }
}

String _titlecase(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}
