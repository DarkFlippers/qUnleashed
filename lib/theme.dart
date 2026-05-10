import 'package:flutter/material.dart';

import 'config.dart';

class QAppThemeController extends ChangeNotifier {
  QAppThemeController._();

  static final QAppThemeController instance = QAppThemeController._();

  final FirmwareConfig _config = QAppConfig.firmware;
  FirmwareEntry _activeFirmware = QAppConfig.defaultFirmware;

  FirmwareConfig get config => _config;
  FirmwareEntry get activeFirmware => _activeFirmware;

  void setActiveFirmware(FirmwareEntry? firmware) {
    if (firmware == null) return;
    if (identical(_activeFirmware, firmware)) return;
    if (_activeFirmware.shortName == firmware.shortName) return;
    _activeFirmware = firmware;
    notifyListeners();
  }

  void setActiveFirmwareByShortName(String? shortName) {
    final normalized = shortName?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return;
    FirmwareEntry? match;
    final firmwares = _config.firmwares;
    for (final firmware in firmwares) {
      if (firmware.shortName.toLowerCase() == normalized) {
        match = firmware;
        break;
      }
    }
    setActiveFirmware(match);
  }

  void syncFirmwareFromDeviceInfo(Map<String, String> info) {
    final match = _matchFirmware(info);
    if (match != null) {
      setActiveFirmware(match);
    }
  }

  FirmwareEntry? _matchFirmware(Map<String, String> info) {
    final firmwares = _config.firmwares;
    if (firmwares.isEmpty) return null;

    final haystack = info.entries
        .map((entry) => '${entry.key} ${entry.value}'.toLowerCase())
        .join(' ');

    if (haystack.isEmpty) return null;

    FirmwareEntry? best;
    var bestScore = 0;

    for (final firmware in firmwares) {
      final score = _scoreFirmwareMatch(firmware, haystack);
      if (score > bestScore) {
        bestScore = score;
        best = firmware;
      }
    }

    return bestScore > 0 ? best : null;
  }

  int _scoreFirmwareMatch(FirmwareEntry firmware, String haystack) {
    final keywords = <String>{
      firmware.shortName.toLowerCase(),
      firmware.name.toLowerCase(),
      ...firmware.matchKeywords.map((keyword) => keyword.toLowerCase()),
    };

    var score = 0;
    for (final keyword in keywords) {
      if (keyword.isEmpty) continue;
      if (haystack.contains(keyword)) {
        score += keyword.length >= 8 ? 3 : 2;
      }
    }

    return score;
  }
}

@immutable
class QAppColors extends ThemeExtension<QAppColors> {
  const QAppColors({
    required this.background,
    required this.card,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.divider,
    required this.info,
    required this.success,
    required this.danger,
    required this.screenBackground,
    required this.screenBorder,
    required this.screenOptionBackground,
    required this.dialogBarrier,
    required this.dialogBackground,
    required this.dialogDivider,
    required this.dialogText,
    required this.dialogMuted,
    required this.terminalBackground,
    required this.terminalHeader,
    required this.terminalText,
    required this.onAccent,
    required this.transparent,
    required this.firmwarePrimary,
    required this.firmwareSecondary,
    required this.firmwareTertiary,
    required this.isDark,
  });

  final Color background;
  final Color card;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color divider;
  final Color info;
  final Color success;
  final Color danger;
  final Color screenBackground;
  final Color screenBorder;
  final Color screenOptionBackground;
  final Color dialogBarrier;
  final Color dialogBackground;
  final Color dialogDivider;
  final Color dialogText;
  final Color dialogMuted;
  final Color terminalBackground;
  final Color terminalHeader;
  final Color terminalText;
  final Color onAccent;
  final Color transparent;
  final Color firmwarePrimary;
  final Color firmwareSecondary;
  final Color firmwareTertiary;
  final bool isDark;

  factory QAppColors.fromFirmware(FirmwareEntry? firmware) {
    final isDark = firmware?.shortName.toLowerCase() == 'unlshd';
    final primary = firmware?.colors.primary ?? const Color(0xFFFF8200);
    final secondary = firmware?.colors.secondary ?? const Color(0xFF589DFF);
    final tertiary = firmware?.colors.tertiary ?? const Color(0xFFFFD580);

    if (isDark) {
      return QAppColors(
        background: const Color(0xFF090909),
        card: const Color(0xFF151515),
        accent: primary,
        textPrimary: const Color(0xFFFFFFFF),
        textSecondary: const Color(0xFFC8C8C8),
        textMuted: const Color(0xFF6F6F6F),
        divider: const Color(0xFF2C2C2C),
        info: secondary,
        success: tertiary,
        danger: const Color(0xFFE85858),
        screenBackground: const Color(0xFFDFDFDF),
        screenBorder: const Color(0xFF000000),
        screenOptionBackground: const Color(0xFF2A1A1A),
        dialogBarrier: const Color(0x8A000000),
        dialogBackground: const Color(0xFF1A1A1A),
        dialogDivider: const Color(0xFF2C2C2C),
        dialogText: const Color(0xFFFFFFFF),
        dialogMuted: const Color(0xFF8D8D8D),
        terminalBackground: const Color(0xFF090909),
        terminalHeader: const Color(0xFF151515),
        terminalText: const Color(0xFF90EE90),
        onAccent: const Color(0xFFFFFFFF),
        transparent: Colors.transparent,
        firmwarePrimary: primary,
        firmwareSecondary: secondary,
        firmwareTertiary: tertiary,
        isDark: true,
      );
    }

    return QAppColors(
      background: const Color(0xFFF1F1F1),
      card: const Color(0xFFFFFFFF),
      accent: primary,
      textPrimary: const Color(0xFF000000),
      textSecondary: const Color(0xFF616161),
      textMuted: const Color(0xFFAAAAAA),
      divider: const Color(0xFFDFDFDF),
      info: secondary,
      success: const Color(0xFF2ED34A),
      danger: const Color(0xFFE85858),
      screenBackground: const Color(0xFFDFDFDF),
      screenBorder: const Color(0xFF000000),
      screenOptionBackground: const Color(0xFFFFF0DE),
      dialogBarrier: const Color(0x8A000000),
      dialogBackground: const Color(0xFFFFFFFF),
      dialogDivider: const Color(0xFFDFDFDF),
      dialogText: const Color(0xFF000000),
      dialogMuted: const Color(0xFF7A7A7A),
      terminalBackground: const Color(0xFFF4F4F4),
      terminalHeader: const Color(0xFFFFFFFF),
      terminalText: const Color(0xFF267A26),
      onAccent: const Color(0xFFFFFFFF),
      transparent: Colors.transparent,
      firmwarePrimary: primary,
      firmwareSecondary: secondary,
      firmwareTertiary: tertiary,
      isDark: false,
    );
  }

  @override
  QAppColors copyWith({
    Color? background,
    Color? card,
    Color? accent,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? divider,
    Color? info,
    Color? success,
    Color? danger,
    Color? screenBackground,
    Color? screenBorder,
    Color? screenOptionBackground,
    Color? dialogBarrier,
    Color? dialogBackground,
    Color? dialogDivider,
    Color? dialogText,
    Color? dialogMuted,
    Color? terminalBackground,
    Color? terminalHeader,
    Color? terminalText,
    Color? onAccent,
    Color? transparent,
    Color? firmwarePrimary,
    Color? firmwareSecondary,
    Color? firmwareTertiary,
    bool? isDark,
  }) {
    return QAppColors(
      background: background ?? this.background,
      card: card ?? this.card,
      accent: accent ?? this.accent,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      divider: divider ?? this.divider,
      info: info ?? this.info,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      screenBackground: screenBackground ?? this.screenBackground,
      screenBorder: screenBorder ?? this.screenBorder,
      screenOptionBackground: screenOptionBackground ?? this.screenOptionBackground,
      dialogBarrier: dialogBarrier ?? this.dialogBarrier,
      dialogBackground: dialogBackground ?? this.dialogBackground,
      dialogDivider: dialogDivider ?? this.dialogDivider,
      dialogText: dialogText ?? this.dialogText,
      dialogMuted: dialogMuted ?? this.dialogMuted,
      terminalBackground: terminalBackground ?? this.terminalBackground,
      terminalHeader: terminalHeader ?? this.terminalHeader,
      terminalText: terminalText ?? this.terminalText,
      onAccent: onAccent ?? this.onAccent,
      transparent: transparent ?? this.transparent,
      firmwarePrimary: firmwarePrimary ?? this.firmwarePrimary,
      firmwareSecondary: firmwareSecondary ?? this.firmwareSecondary,
      firmwareTertiary: firmwareTertiary ?? this.firmwareTertiary,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  QAppColors lerp(ThemeExtension<QAppColors>? other, double t) {
    if (other is! QAppColors) return this;
    return QAppColors(
      background: Color.lerp(background, other.background, t) ?? background,
      card: Color.lerp(card, other.card, t) ?? card,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textMuted: Color.lerp(textMuted, other.textMuted, t) ?? textMuted,
      divider: Color.lerp(divider, other.divider, t) ?? divider,
      info: Color.lerp(info, other.info, t) ?? info,
      success: Color.lerp(success, other.success, t) ?? success,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
      screenBackground: Color.lerp(screenBackground, other.screenBackground, t) ?? screenBackground,
      screenBorder: Color.lerp(screenBorder, other.screenBorder, t) ?? screenBorder,
      screenOptionBackground: Color.lerp(screenOptionBackground, other.screenOptionBackground, t) ?? screenOptionBackground,
      dialogBarrier: Color.lerp(dialogBarrier, other.dialogBarrier, t) ?? dialogBarrier,
      dialogBackground: Color.lerp(dialogBackground, other.dialogBackground, t) ?? dialogBackground,
      dialogDivider: Color.lerp(dialogDivider, other.dialogDivider, t) ?? dialogDivider,
      dialogText: Color.lerp(dialogText, other.dialogText, t) ?? dialogText,
      dialogMuted: Color.lerp(dialogMuted, other.dialogMuted, t) ?? dialogMuted,
      terminalBackground: Color.lerp(terminalBackground, other.terminalBackground, t) ?? terminalBackground,
      terminalHeader: Color.lerp(terminalHeader, other.terminalHeader, t) ?? terminalHeader,
      terminalText: Color.lerp(terminalText, other.terminalText, t) ?? terminalText,
      onAccent: Color.lerp(onAccent, other.onAccent, t) ?? onAccent,
      transparent: Color.lerp(transparent, other.transparent, t) ?? transparent,
      firmwarePrimary: Color.lerp(firmwarePrimary, other.firmwarePrimary, t) ?? firmwarePrimary,
      firmwareSecondary: Color.lerp(firmwareSecondary, other.firmwareSecondary, t) ?? firmwareSecondary,
      firmwareTertiary: Color.lerp(firmwareTertiary, other.firmwareTertiary, t) ?? firmwareTertiary,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

ThemeData buildAppTheme(FirmwareEntry? firmware) {
  final colors = QAppColors.fromFirmware(firmware);
  final colorScheme = (colors.isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
    primary: colors.accent,
    onPrimary: colors.onAccent,
    secondary: colors.info,
    onSecondary: colors.onAccent,
    error: colors.danger,
    onError: colors.onAccent,
    surface: colors.card,
    onSurface: colors.textPrimary,
  );
  return ThemeData(
    useMaterial3: false,
    scaffoldBackgroundColor: colors.background,
    colorScheme: colorScheme,
    dividerColor: colors.divider,
    dialogTheme: DialogThemeData(backgroundColor: colors.dialogBackground),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: colors.accent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.accent),
    extensions: [colors],
  );
}

class FlipperOriginalColors {
  static QAppColors get _colors => QAppColors.fromFirmware(QAppThemeController.instance.activeFirmware);

  static Color get background => _colors.background;
  static Color get card => _colors.card;
  static Color get accent => _colors.accent;
  static Color get text100 => _colors.textPrimary;
  static Color get text60 => _colors.textSecondary;
  static Color get text30 => _colors.textMuted;
  static Color get text16 => _colors.textMuted;
  static Color get divider => _colors.divider;
  static Color get blue => _colors.info;
  static Color get green => _colors.success;
  static Color get danger => _colors.danger;
  static Color get flipperScreenBackground => _colors.screenBackground;
  static Color get flipperScreenBorder => _colors.screenBorder;
  static Color get flipperScreenOptionsBackground => _colors.screenOptionBackground;
  static Color get dialogBackground => _colors.dialogBackground;
  static Color get dialogDivider => _colors.dialogDivider;
  static Color get dialogText => _colors.dialogText;
  static Color get dialogMuted => _colors.dialogMuted;
  static Color get terminalBackground => _colors.terminalBackground;
  static Color get terminalHeader => _colors.terminalHeader;
  static Color get terminalText => _colors.terminalText;
  static Color get barrier => _colors.dialogBarrier;
  static Color get onAccent => _colors.onAccent;
  static Color get transparent => _colors.transparent;
}

extension QThemeContext on BuildContext {
  QAppColors get appColors => Theme.of(this).extension<QAppColors>()!;
}
