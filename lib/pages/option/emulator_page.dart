import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/emulator/emulator_settings.dart';
import '../../theme/theme.dart';
import 'widgets/settings_group.dart';
import 'widgets/settings_tile.dart';

class EmulatorSettingsPage extends StatefulWidget {
  const EmulatorSettingsPage({super.key});

  @override
  State<EmulatorSettingsPage> createState() => _EmulatorSettingsPageState();
}

class _EmulatorSettingsPageState extends State<EmulatorSettingsPage> {
  final _settings = EmulatorSettings.instance;
  final _nameController = TextEditingController();

  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final enabled = await _settings.isEnabled();
    final name = await _settings.name();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _nameController.text = name;
    });
  }

  void _setEnabled(bool value) {
    setState(() => _enabled = value);
    _settings.setEnabled(value);
  }

  void _commitName() {
    final clean = EmulatorSettings.sanitizeName(_nameController.text);
    _settings.setName(clean);
    if (_nameController.text != clean) {
      _nameController.text = clean;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final supported = _settings.isSupported;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Emulator'),
        backgroundColor: colors.background,
        surfaceTintColor: colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          if (!supported)
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 0, 26, 8),
              child: Text(
                'The embedded emulator is not available on this platform.',
                style: TextStyle(fontSize: 12.5, color: colors.textMuted),
              ),
            ),
          SettingsGroup(
            title: 'Virtual Flipper',
            children: [
              SettingsSwitchTile(
                title: 'Enable emulator',
                subtitle:
                    'Show an in-app virtual Flipper in the device picker.',
                value: _enabled,
                onChanged: supported ? _setEnabled : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SettingsGroup(
            title: 'Device name',
            children: [
              _NameTile(
                controller: _nameController,
                enabled: supported && _enabled,
                onCommit: _commitName,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 8, 26, 0),
            child: Text(
              'Written into the emulated firmware’s OTP as the unique '
              'device name. Up to 8 characters (a–z, 0–9, dot). '
              'Applied the next time you connect to the emulator.',
              style: TextStyle(fontSize: 12.5, color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _NameTile extends StatelessWidget {
  const _NameTile({
    required this.controller,
    required this.enabled,
    required this.onCommit,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SettingsTileShell(
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              'Name',
              style: TextStyle(
                color: enabled ? colors.textPrimary : colors.textMuted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              textAlign: TextAlign.end,
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              maxLength: EmulatorSettings.nameMaxLength,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9.]')),
              ],
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                border: InputBorder.none,
                hintText: EmulatorSettings.defaultName,
                hintStyle: TextStyle(color: colors.textMuted, fontSize: 14),
              ),
              onEditingComplete: onCommit,
              onSubmitted: (_) => onCommit(),
              onTapOutside: (_) => onCommit(),
            ),
          ),
        ],
      ),
    );
  }
}
