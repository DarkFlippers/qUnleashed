import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../../theme.dart';
import '../../widgets/info_line.dart';
import '../../widgets/notification.dart';
import '../../widgets/page_card.dart';
import '../../widgets/root_scaffold.dart';
import '../apps/page.dart';
import '../archive/controller.dart';
import '../archive/page.dart';
import '../tools/page.dart';
import '../remote/page.dart';
import 'widgets/connected_view.dart';
import 'widgets/connection_dialog.dart';
import 'widgets/disconnected_view.dart';
import 'widgets/full_info_sheet.dart';

class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  final FlipperClient _client = FlipperOneClient().get();
  final ArchiveController _archiveController = ArchiveController();

  FlipperRootTab _tab = FlipperRootTab.device;
  FlipperDevice? _device;
  bool _deviceDisconnected = false;
  bool _deviceLoading = false;
  bool _deviceInfoConnected = false;
  bool _alertPlaying = false;
  Map<String, String> _info = {};

  StreamSubscription<FlipperConnectionState>? _connectionSub;

  @override
  void initState() {
    super.initState();
    _device = _client.connectedDevice;
    _connectionSub = _client.connectionStream.listen(_onConnectionState);
    _archiveController.addListener(_onArchiveChanged);
    _archiveController.initialize();
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _archiveController.removeListener(_onArchiveChanged);
    _archiveController.dispose();
    _client.disconnect();
    super.dispose();
  }

  void _onArchiveChanged() {
    if (mounted) {
      setState(() {
        if (_archiveController.syncStatus != ArchiveSyncStatus.idle) {
          _deviceInfoConnected = false;
        }
      });
    }
  }

  Future<void> _openPicker() async {
    final selected = await showConnectionDialog(context);
    if (selected != null && mounted) {
      _connectTo(selected);
    }
  }

  Future<void> _connectTo(FlipperDevice device) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Connecting...'),
          ],
        ),
      ),
    );

    try {
      final connected = await _client.connect(device);
      if (!mounted) return;
      Navigator.of(context).pop();
      _setupDevice(connected);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      LogService.log('[DevicePage] connection failed: $e');
    }
  }

  void _setupDevice(FlipperDevice device) {
    setState(() {
      _device = device;
      _deviceDisconnected = false;
      _deviceLoading = true;
      _deviceInfoConnected = false;
      _info = {};
    });
    _requestAll();
  }

  Future<void> _requestAll() async {
    try {
      final results = await Future.wait<Object?>([
        _client.protobufVersion(timeout: const Duration(seconds: 15)),
        _client.deviceInfo(timeout: const Duration(seconds: 15)),
        _client.powerInfo(timeout: const Duration(seconds: 15)),
        _client.getDateTime(timeout: const Duration(seconds: 15)),
        _requestStorageInfo('/int/'),
        _requestStorageInfo('/ext/'),
      ]);

      final protobuf = results[0] as FlipperRpcBatch<ProtobufVersionResponse>;
      final deviceInfo = results[1] as FlipperRpcBatch<DeviceInfoResponse>;
      final powerInfo = results[2] as FlipperRpcBatch<PowerInfoResponse>;
      final dateTime = results[3] as FlipperRpcBatch<GetDateTimeResponse>;
      final internalStorage = results[4] as InfoResponse?;
      final sdCardStorage = results[5] as InfoResponse?;

      final info = <String, String>{
        'protobuf_version': '${protobuf.single.major}.${protobuf.single.minor}',
        'protobuf_version_major': '${protobuf.single.major}',
        'protobuf_version_minor': '${protobuf.single.minor}',
      };

      for (final item in deviceInfo.items) {
        info[item.key] = item.value;
      }
      for (final item in powerInfo.items) {
        info['power.${item.key}'] = item.value;
      }

      final dt = dateTime.single.datetime;
      info['datetime'] =
          '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
      _addStorageInfo(info, prefix: 'storage.internal', storage: internalStorage);
      _addStorageInfo(info, prefix: 'storage.sdcard', storage: sdCardStorage);

      if (!mounted) return;
      setState(() {
        _info = info;
        _deviceLoading = false;
        _deviceInfoConnected = true;
      });
      QAppThemeController.instance.syncFirmwareFromDeviceInfo(info);
    } catch (e) {
      LogService.log('[DevicePage] request failed: $e');
      if (!mounted) return;
      setState(() {
        _deviceLoading = false;
        _deviceInfoConnected = false;
      });
    }
  }

  Future<InfoResponse?> _requestStorageInfo(String path) async {
    try {
      final response = await _client.storageInfo(
        InfoRequest(path: path),
        timeout: const Duration(seconds: 15),
      );
      return response.single;
    } catch (e) {
      LogService.log('[DevicePage] storage info request failed for $path: $e');
      return null;
    }
  }

  void _onConnectionState(FlipperConnectionState state) {
    if (!mounted) return;
    if (state.connected) {
      setState(() {
        _device = state.device;
        _deviceDisconnected = false;
      });
      return;
    }
    setState(() {
      _deviceDisconnected = true;
      _deviceLoading = false;
      _deviceInfoConnected = false;
    });
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  String get _deviceFirmwareVersion =>
      _info['firmware_version'] ??
      _info['firmware.version'] ??
      _info['software_revision'] ??
      _info['protobuf_version'] ??
      '-';

  String get _buildDate =>
      _info['firmware_build_date'] ?? _info['build_date'] ?? _info['datetime'] ?? '-';

  String get _sdCard => _formatStorageUsedTotal('storage.sdcard');

  String get _deviceName {
    final value = _info['hardware_name'];
    if (value != null && value.trim().isNotEmpty) {
      return value;
    }
    return 'No device';
  }

  void _addStorageInfo(
    Map<String, String> info, {
    required String prefix,
    required InfoResponse? storage,
  }) {
    if (storage == null) return;

    final total = storage.totalSpace.toInt();
    final free = storage.freeSpace.toInt();
    final used = total >= free ? total - free : 0;

    info['$prefix.total'] = _formatBytes(total);
    info['$prefix.free'] = _formatBytes(free);
    info['$prefix.used'] = _formatBytes(used);
    info['$prefix.free_percent'] = _formatPercent(free, total);
    info['$prefix.used_percent'] = _formatPercent(used, total);
    info['$prefix.total_bytes'] = '$total';
    info['$prefix.available_bytes'] = '$free';
    info['$prefix.used_bytes'] = '$used';
  }

  String _formatStorageUsedTotal(String prefix) {
    final used = _info['$prefix.used'];
    final total = _info['$prefix.total'];
    if (used == null && total == null) {
      return '-';
    }
    return '${used ?? '?'} / ${total ?? '?'}';
  }

  List<MapEntry<String, String>> get _deviceInfoEntries {
    return [
      MapEntry('Firmware Version', _deviceFirmwareVersion),
      MapEntry('Build Date', _buildDate),
      MapEntry('SD Card (Used/Total)', _sdCard),
    ];
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;

    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }

    final precision = value >= 100 || unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(precision)} ${units[unitIndex]}';
  }

  String _formatPercent(int value, int total) {
    if (total <= 0) return '0%';
    final percent = (value * 100) / total;
    return '${percent.toStringAsFixed(1)}%';
  }

  String _lookupExportValue(List<String> aliases, {String fallback = '-'}) {
    for (final alias in aliases) {
      final value = _info[alias];
      if (value != null && value.trim().isNotEmpty) {
        return value;
      }
    }
    return fallback;
  }

  String _lookupProtobufPart(int index) {
    final combined = _info['protobuf_version'];
    if (combined == null || combined.isEmpty) return '-';
    final parts = combined.split('.');
    if (index >= parts.length) return '-';
    return parts[index];
  }

  String _buildExportDump() {
    final lines = <String>[];

    void add(String key, List<String> aliases, {String fallback = '-'}) {
      lines.add('$key: ${_lookupExportValue(aliases, fallback: fallback)}');
    }

    add('devinfo_format.major', ['devinfo_format.major', 'format.major', 'device_info_format.major']);
    add('devinfo_format.minor', ['devinfo_format.minor', 'format.minor', 'device_info_format.minor']);
    add('devinfo_hardware.model', ['devinfo_hardware.model', 'hardware.model', 'hardware_model', 'model', 'hardware_name']);
    add('devinfo_hardware.uid', ['devinfo_hardware.uid', 'hardware.uid', 'hardware_uid', 'uid']);
    add('devinfo_hardware.otp.ver', ['devinfo_hardware.otp.ver', 'hardware.otp.ver', 'hardware_otp_ver', 'otp.ver', 'otp_ver']);
    add('devinfo_hardware.timestamp', ['devinfo_hardware.timestamp', 'hardware.timestamp', 'hardware_timestamp', 'timestamp']);
    add('devinfo_hardware.ver', ['devinfo_hardware.ver', 'hardware.ver', 'hardware_ver', 'ver']);
    add('devinfo_hardware.target', ['devinfo_hardware.target', 'hardware.target', 'hardware_target', 'target']);
    add('devinfo_hardware.body', ['devinfo_hardware.body', 'hardware.body', 'hardware_body', 'body']);
    add('devinfo_hardware.connect', ['devinfo_hardware.connect', 'hardware.connect', 'hardware_connect', 'connect']);
    add('devinfo_hardware.display', ['devinfo_hardware.display', 'hardware.display', 'hardware_display', 'display']);
    add('devinfo_hardware.color', ['devinfo_hardware.color', 'hardware.color', 'hardware_color', 'color']);
    add(
      'devinfo_hardware.region.builtin',
      ['devinfo_hardware.region.builtin', 'hardware.region.builtin', 'hardware_region_builtin', 'region.builtin', 'region_builtin'],
    );
    add(
      'devinfo_hardware.region.provisioned',
      ['devinfo_hardware.region.provisioned', 'hardware.region.provisioned', 'hardware_region_provisioned', 'region.provisioned', 'region_provisioned'],
    );
    add('devinfo_hardware.name', ['devinfo_hardware.name', 'hardware.name', 'hardware_name', 'device_name', 'name']);
    add('devinfo_firmware.commit.hash', ['devinfo_firmware.commit.hash', 'firmware.commit.hash', 'firmware_commit_hash', 'commit.hash', 'commit_hash']);
    add(
      'devinfo_firmware.commit.dirty',
      ['devinfo_firmware.commit.dirty', 'firmware.commit.dirty', 'firmware_commit_dirty', 'commit.dirty', 'commit_dirty'],
    );
    add('devinfo_firmware.branch.name', ['devinfo_firmware.branch.name', 'firmware.branch.name', 'firmware_branch_name', 'branch.name', 'branch_name']);
    add('devinfo_firmware.branch.num', ['devinfo_firmware.branch.num', 'firmware.branch.num', 'firmware_branch_num', 'branch.num', 'branch_num']);
    add('devinfo_firmware.version', ['devinfo_firmware.version', 'firmware.version', 'firmware_version', 'software_revision']);
    add('devinfo_firmware.build.date', ['devinfo_firmware.build.date', 'firmware.build.date', 'firmware_build_date', 'build_date']);
    add('devinfo_firmware.target', ['devinfo_firmware.target', 'firmware.target', 'firmware_target']);
    add('devinfo_firmware.api.major', ['devinfo_firmware.api.major', 'firmware.api.major', 'firmware_api_major', 'api.major', 'api_major']);
    add('devinfo_firmware.api.minor', ['devinfo_firmware.api.minor', 'firmware.api.minor', 'firmware_api_minor', 'api.minor', 'api_minor']);
    add('devinfo_firmware.origin.fork', ['devinfo_firmware.origin.fork', 'firmware.origin.fork', 'firmware_origin_fork', 'origin.fork', 'origin_fork']);
    add('devinfo_firmware.origin.git', ['devinfo_firmware.origin.git', 'firmware.origin.git', 'firmware_origin_git', 'origin.git', 'origin_git']);
    add('devinfo_radio.alive', ['devinfo_radio.alive', 'radio.alive', 'radio_alive']);
    add('devinfo_radio.mode', ['devinfo_radio.mode', 'radio.mode', 'radio_mode']);
    add('devinfo_radio.fus.major', ['devinfo_radio.fus.major', 'radio.fus.major', 'radio_fus_major', 'fus.major', 'fus_major']);
    add('devinfo_radio.fus.minor', ['devinfo_radio.fus.minor', 'radio.fus.minor', 'radio_fus_minor', 'fus.minor', 'fus_minor']);
    add('devinfo_radio.fus.sub', ['devinfo_radio.fus.sub', 'radio.fus.sub', 'radio_fus_sub', 'fus.sub', 'fus_sub']);
    add('devinfo_radio.fus.sram2b', ['devinfo_radio.fus.sram2b', 'radio.fus.sram2b', 'radio_fus_sram2b', 'fus.sram2b', 'fus_sram2b']);
    add('devinfo_radio.fus.sram2a', ['devinfo_radio.fus.sram2a', 'radio.fus.sram2a', 'radio_fus_sram2a', 'fus.sram2a', 'fus_sram2a']);
    add('devinfo_radio.fus.flash', ['devinfo_radio.fus.flash', 'radio.fus.flash', 'radio_fus_flash', 'fus.flash', 'fus_flash']);
    add('devinfo_radio.stack.type', ['devinfo_radio.stack.type', 'radio.stack.type', 'radio_stack_type', 'stack.type', 'stack_type']);
    add('devinfo_radio.stack.major', ['devinfo_radio.stack.major', 'radio.stack.major', 'radio_stack_major', 'stack.major', 'stack_major']);
    add('devinfo_radio.stack.minor', ['devinfo_radio.stack.minor', 'radio.stack.minor', 'radio_stack_minor', 'stack.minor', 'stack_minor']);
    add('devinfo_radio.stack.sub', ['devinfo_radio.stack.sub', 'radio.stack.sub', 'radio_stack_sub', 'stack.sub', 'stack_sub']);
    add('devinfo_radio.stack.branch', ['devinfo_radio.stack.branch', 'radio.stack.branch', 'radio_stack_branch', 'stack.branch', 'stack_branch']);
    add('devinfo_radio.stack.release', ['devinfo_radio.stack.release', 'radio.stack.release', 'radio_stack_release', 'stack.release', 'stack_release']);
    add('devinfo_radio.stack.sram2b', ['devinfo_radio.stack.sram2b', 'radio.stack.sram2b', 'radio_stack_sram2b', 'stack.sram2b', 'stack_sram2b']);
    add('devinfo_radio.stack.sram2a', ['devinfo_radio.stack.sram2a', 'radio.stack.sram2a', 'radio_stack_sram2a', 'stack.sram2a', 'stack_sram2a']);
    add('devinfo_radio.stack.sram1', ['devinfo_radio.stack.sram1', 'radio.stack.sram1', 'radio_stack_sram1', 'stack.sram1', 'stack_sram1']);
    add('devinfo_radio.stack.flash', ['devinfo_radio.stack.flash', 'radio.stack.flash', 'radio_stack_flash', 'stack.flash', 'stack_flash']);
    add('devinfo_radio.ble.mac', ['devinfo_radio.ble.mac', 'radio.ble.mac', 'radio_ble_mac', 'ble.mac', 'ble_mac']);
    add('devinfo_enclave.keys.valid', ['devinfo_enclave.keys.valid', 'enclave.keys.valid', 'enclave_keys_valid', 'keys.valid', 'keys_valid']);
    add('devinfo_enclave.valid', ['devinfo_enclave.valid', 'enclave.valid', 'enclave_valid']);
    add('devinfo_system.debug', ['devinfo_system.debug', 'system.debug', 'system_debug', 'debug']);
    add('devinfo_system.lock', ['devinfo_system.lock', 'system.lock', 'system_lock', 'lock']);
    add('devinfo_system.orient', ['devinfo_system.orient', 'system.orient', 'system_orient', 'orient']);
    add('devinfo_system.sleep.legacy', ['devinfo_system.sleep.legacy', 'system.sleep.legacy', 'system_sleep_legacy', 'sleep.legacy', 'sleep_legacy']);
    add('devinfo_system.stealth', ['devinfo_system.stealth', 'system.stealth', 'system_stealth', 'stealth']);
    add('devinfo_system.heap.track', ['devinfo_system.heap.track', 'system.heap.track', 'system_heap_track', 'heap.track', 'heap_track']);
    add('devinfo_system.boot', ['devinfo_system.boot', 'system.boot', 'system_boot', 'boot']);
    add('devinfo_system.locale.time', ['devinfo_system.locale.time', 'system.locale.time', 'system_locale_time', 'locale.time', 'locale_time']);
    add('devinfo_system.locale.date', ['devinfo_system.locale.date', 'system.locale.date', 'system_locale_date', 'locale.date', 'locale_date']);
    add('devinfo_system.locale.unit', ['devinfo_system.locale.unit', 'system.locale.unit', 'system_locale_unit', 'locale.unit', 'locale_unit']);
    add('devinfo_system.log.level', ['devinfo_system.log.level', 'system.log.level', 'system_log_level', 'log.level', 'log_level']);
    add('devinfo_protobuf.version.major', ['devinfo_protobuf.version.major', 'protobuf_version_major'], fallback: _lookupProtobufPart(0));
    add('devinfo_protobuf.version.minor', ['devinfo_protobuf.version.minor', 'protobuf_version_minor'], fallback: _lookupProtobufPart(1));

    add('pwrinfo_format.major', ['pwrinfo_format.major', 'power.format.major', 'power_format.major', 'power.info.format.major']);
    add('pwrinfo_format.minor', ['pwrinfo_format.minor', 'power.format.minor', 'power_format.minor', 'power.info.format.minor']);
    add('pwrinfo_charge.level', ['pwrinfo_charge.level', 'power.charge.level', 'power_charge_level', 'charge.level', 'charge_level']);
    add('pwrinfo_charge.state', ['pwrinfo_charge.state', 'power.charge.state', 'power_charge_state', 'charge.state', 'charge_state']);
    add('pwrinfo_charge.voltage.limit', ['pwrinfo_charge.voltage.limit', 'power.charge.voltage.limit', 'power_charge_voltage_limit', 'charge.voltage.limit', 'charge_voltage_limit']);
    add('pwrinfo_battery.voltage', ['pwrinfo_battery.voltage', 'power.battery.voltage', 'power_battery_voltage', 'battery.voltage', 'battery_voltage']);
    add('pwrinfo_battery.current', ['pwrinfo_battery.current', 'power.battery.current', 'power_battery_current', 'battery.current', 'battery_current']);
    add('pwrinfo_battery.temp', ['pwrinfo_battery.temp', 'power.battery.temp', 'power_battery_temp', 'battery.temp', 'battery_temp']);
    add('pwrinfo_battery.health', ['pwrinfo_battery.health', 'power.battery.health', 'power_battery_health', 'battery.health', 'battery_health']);
    add('pwrinfo_capacity.remain', ['pwrinfo_capacity.remain', 'power.capacity.remain', 'power_capacity_remain', 'capacity.remain', 'capacity_remain']);
    add('pwrinfo_capacity.full', ['pwrinfo_capacity.full', 'power.capacity.full', 'power_capacity_full', 'capacity.full', 'capacity_full']);
    add('pwrinfo_capacity.design', ['pwrinfo_capacity.design', 'power.capacity.design', 'power_capacity_design', 'capacity.design', 'capacity_design']);

    add('pwrdebug_format.major', ['pwrdebug_format.major', 'power.debug.format.major', 'power_debug_format_major', 'power.gauge.format.major']);
    add('pwrdebug_format.minor', ['pwrdebug_format.minor', 'power.debug.format.minor', 'power_debug_format_minor', 'power.gauge.format.minor']);
    add('pwrdebug_charger.vbus', ['pwrdebug_charger.vbus', 'power.debug.charger.vbus', 'power_debug_charger_vbus', 'power.charger.vbus']);
    add('pwrdebug_charger.vsys', ['pwrdebug_charger.vsys', 'power.debug.charger.vsys', 'power_debug_charger_vsys', 'power.charger.vsys']);
    add('pwrdebug_charger.vbat', ['pwrdebug_charger.vbat', 'power.debug.charger.vbat', 'power_debug_charger_vbat', 'power.charger.vbat']);
    add('pwrdebug_charger.vreg', ['pwrdebug_charger.vreg', 'power.debug.charger.vreg', 'power_debug_charger_vreg', 'power.charger.vreg']);
    add('pwrdebug_charger.current', ['pwrdebug_charger.current', 'power.debug.charger.current', 'power_debug_charger_current', 'power.charger.current']);
    add('pwrdebug_charger.ntc', ['pwrdebug_charger.ntc', 'power.debug.charger.ntc', 'power_debug_charger_ntc', 'power.charger.ntc']);
    add('pwrdebug_gauge.calmd', ['pwrdebug_gauge.calmd', 'power.debug.gauge.calmd', 'power_debug_gauge_calmd', 'power.gauge.calmd']);
    add('pwrdebug_gauge.sec', ['pwrdebug_gauge.sec', 'power.debug.gauge.sec', 'power_debug_gauge_sec', 'power.gauge.sec']);
    add('pwrdebug_gauge.edv2', ['pwrdebug_gauge.edv2', 'power.debug.gauge.edv2', 'power_debug_gauge_edv2', 'power.gauge.edv2']);
    add('pwrdebug_gauge.vdq', ['pwrdebug_gauge.vdq', 'power.debug.gauge.vdq', 'power_debug_gauge_vdq', 'power.gauge.vdq']);
    add('pwrdebug_gauge.initcomp', ['pwrdebug_gauge.initcomp', 'power.debug.gauge.initcomp', 'power_debug_gauge_initcomp', 'power.gauge.initcomp']);
    add('pwrdebug_gauge.smth', ['pwrdebug_gauge.smth', 'power.debug.gauge.smth', 'power_debug_gauge_smth', 'power.gauge.smth']);
    add('pwrdebug_gauge.btpint', ['pwrdebug_gauge.btpint', 'power.debug.gauge.btpint', 'power_debug_gauge_btpint', 'power.gauge.btpint']);
    add('pwrdebug_gauge.cfgupdate', ['pwrdebug_gauge.cfgupdate', 'power.debug.gauge.cfgupdate', 'power_debug_gauge_cfgupdate', 'power.gauge.cfgupdate']);
    add('pwrdebug_gauge.chginh', ['pwrdebug_gauge.chginh', 'power.debug.gauge.chginh', 'power_debug_gauge_chginh', 'power.gauge.chginh']);
    add('pwrdebug_gauge.fc', ['pwrdebug_gauge.fc', 'power.debug.gauge.fc', 'power_debug_gauge_fc', 'power.gauge.fc']);
    add('pwrdebug_gauge.otd', ['pwrdebug_gauge.otd', 'power.debug.gauge.otd', 'power_debug_gauge_otd', 'power.gauge.otd']);
    add('pwrdebug_gauge.otc', ['pwrdebug_gauge.otc', 'power.debug.gauge.otc', 'power_debug_gauge_otc', 'power.gauge.otc']);
    add('pwrdebug_gauge.sleep', ['pwrdebug_gauge.sleep', 'power.debug.gauge.sleep', 'power_debug_gauge_sleep', 'power.gauge.sleep']);
    add('pwrdebug_gauge.ocvfail', ['pwrdebug_gauge.ocvfail', 'power.debug.gauge.ocvfail', 'power_debug_gauge_ocvfail', 'power.gauge.ocvfail']);
    add('pwrdebug_gauge.ocvcomp', ['pwrdebug_gauge.ocvcomp', 'power.debug.gauge.ocvcomp', 'power_debug_gauge_ocvcomp', 'power.gauge.ocvcomp']);
    add('pwrdebug_gauge.fd', ['pwrdebug_gauge.fd', 'power.debug.gauge.fd', 'power_debug_gauge_fd', 'power.gauge.fd']);
    add('pwrdebug_gauge.dsg', ['pwrdebug_gauge.dsg', 'power.debug.gauge.dsg', 'power_debug_gauge_dsg', 'power.gauge.dsg']);
    add('pwrdebug_gauge.sysdwn', ['pwrdebug_gauge.sysdwn', 'power.debug.gauge.sysdwn', 'power_debug_gauge_sysdwn', 'power.gauge.sysdwn']);
    add('pwrdebug_gauge.tda', ['pwrdebug_gauge.tda', 'power.debug.gauge.tda', 'power_debug_gauge_tda', 'power.gauge.tda']);
    add('pwrdebug_gauge.battpres', ['pwrdebug_gauge.battpres', 'power.debug.gauge.battpres', 'power_debug_gauge_battpres', 'power.gauge.battpres']);
    add('pwrdebug_gauge.authgd', ['pwrdebug_gauge.authgd', 'power.debug.gauge.authgd', 'power_debug_gauge_authgd', 'power.gauge.authgd']);
    add('pwrdebug_gauge.ocvgd', ['pwrdebug_gauge.ocvgd', 'power.debug.gauge.ocvgd', 'power_debug_gauge_ocvgd', 'power.gauge.ocvgd']);
    add('pwrdebug_gauge.tca', ['pwrdebug_gauge.tca', 'power.debug.gauge.tca', 'power_debug_gauge_tca', 'power.gauge.tca']);
    add('pwrdebug_gauge.rsvd', ['pwrdebug_gauge.rsvd', 'power.debug.gauge.rsvd', 'power_debug_gauge_rsvd', 'power.gauge.rsvd']);
    add('pwrdebug_gauge.capacity.full', ['pwrdebug_gauge.capacity.full', 'power.debug.gauge.capacity.full', 'power_debug_gauge_capacity_full', 'power.gauge.capacity.full']);
    add('pwrdebug_gauge.capacity.design', ['pwrdebug_gauge.capacity.design', 'power.debug.gauge.capacity.design', 'power_debug_gauge_capacity_design', 'power.gauge.capacity.design']);
    add('pwrdebug_gauge.capacity.remain', ['pwrdebug_gauge.capacity.remain', 'power.debug.gauge.capacity.remain', 'power_debug_gauge_capacity_remain', 'power.gauge.capacity.remain']);
    add('pwrdebug_gauge.state.charge', ['pwrdebug_gauge.state.charge', 'power.debug.gauge.state.charge', 'power_debug_gauge_state_charge', 'power.gauge.state.charge']);
    add('pwrdebug_gauge.state.health', ['pwrdebug_gauge.state.health', 'power.debug.gauge.state.health', 'power_debug_gauge_state_health', 'power.gauge.state.health']);
    add('pwrdebug_gauge.voltage', ['pwrdebug_gauge.voltage', 'power.debug.gauge.voltage', 'power_debug_gauge_voltage', 'power.gauge.voltage']);
    add('pwrdebug_gauge.current', ['pwrdebug_gauge.current', 'power.debug.gauge.current', 'power_debug_gauge_current', 'power.gauge.current']);
    add('pwrdebug_gauge.temperature', ['pwrdebug_gauge.temperature', 'power.debug.gauge.temperature', 'power_debug_gauge_temperature', 'power.gauge.temperature']);

    add('ext_available', ['ext_available', 'storage.sdcard.available_bytes', 'storage.sdcard.free_bytes']);
    add('ext_total', ['ext_total', 'storage.sdcard.total_bytes']);

    return lines.join('\n');
  }

  Future<void> _exportDeviceInfo() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      if (!mounted) return;
      context.showNotification(
        'Clipboard not available',
        type: QNotificationType.warning,
      );
      return;
    }

    final item = DataWriterItem()..add(Formats.plainText(_buildExportDump()));
    await clipboard.write([item]);
    if (!mounted) return;
    context.showNotification(
      'Device info copied to clipboard',
      type: QNotificationType.good,
    );
  }

  Future<void> _disconnect() async {
    await _client.disconnect();
    if (!mounted) return;
    setState(() {
      _device = null;
      _deviceDisconnected = false;
      _deviceLoading = false;
      _deviceInfoConnected = false;
      _info = {};
    });
  }

  Future<void> _openRemoteControl() async {
    if (_device == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RemoteControlPage()),
    );
  }

  void _openFullInfo() {
    showDeviceFullInfoSheet(
      context,
      title: 'Full Info',
      cards: [
        FlipperPageCard(
          title: 'Firmware',
          child: Column(
              children: [
              for (var i = 0; i < _deviceInfoEntries.length; i++) ...[
                FlipperInfoLine(
                  label: _deviceInfoEntries[i].key,
                  value: _deviceInfoEntries[i].value,
                ),
                if (i != _deviceInfoEntries.length - 1)
                  Divider(height: 1, color: context.appColors.divider),
              ],
            ],
          ),
        ),
        RawInfoCard(entries: _info),
      ],
    );
  }

  void _synchronizeDevice() {
    setState(() {
      _deviceLoading = true;
      _deviceInfoConnected = false;
      _info = {};
    });
    _requestAll();
  }

  Future<void> _playAlertOnFlipper() async {
    if (_device == null || _deviceDisconnected || _alertPlaying) {
      return;
    }

    setState(() => _alertPlaying = true);

    try {
      await _client.playAudiovisualAlert(
        PlayAudiovisualAlertRequest(),
        timeout: const Duration(seconds: 8),
      );
      if (!mounted) return;
      context.showNotification('Alert sent to Flipper', type: QNotificationType.good);
    } catch (e) {
      LogService.log('[DevicePage] play alert failed: $e');
      if (!mounted) return;
      context.showNotification(
        'Failed to play alert: $e',
        type: QNotificationType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _alertPlaying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = _device;
    final isConnected = device != null && !_deviceDisconnected;
    final deviceIconAsset = _deviceIconAsset(
      device: device,
      isConnected: isConnected,
    );
    final deviceLabel = _deviceLabel(device: device, isConnected: isConnected);

    return FlipperRootScaffold(
      currentTab: _tab,
      onTabSelected: (tab) => setState(() => _tab = tab),
      deviceIconAsset: deviceIconAsset,
      deviceLabel: deviceLabel,
      child: IndexedStack(
        index: _tab.index,
        children: [
          isConnected
              ? ConnectedDeviceView(
                  deviceName: _deviceName,
                  infoLoading: _deviceLoading,
                  deviceInfo: _info,
                  deviceInfoEntries: _deviceInfoEntries,
                  onSynchronize: _deviceLoading ? null : _synchronizeDevice,
                  onPlayAlert: _alertPlaying ? null : _playAlertOnFlipper,
                  onOpenRemoteControl: _openRemoteControl,
                  onOpenFullInfo: _openFullInfo,
                  onExport: _exportDeviceInfo,
                  onDisconnect: _disconnect,
                )
              : DisconnectedDeviceView(onConnect: _openPicker),
          ArchivePage(controller: _archiveController),
          const AppsPage(),
          const ToolsPage(),
        ],
      ),
    );
  }

  String _deviceIconAsset({
    required FlipperDevice? device,
    required bool isConnected,
  }) {
    if (!isConnected) {
      if (device != null) {
        return 'assets/flipper_svg/connection/ic_disconnected_filled.svg';
      }
      return 'assets/flipper_svg/connection/ic_no_device_filled.svg';
    }
    if (_deviceLoading) {
      return 'assets/flipper_svg/connection/ic_syncing_filled.svg';
    }
    switch (_syncStatus) {
      case ArchiveSyncStatus.syncing:
        return 'assets/flipper_svg/connection/ic_syncing_filled.svg';
      case ArchiveSyncStatus.synced:
        if (_deviceInfoConnected) {
          return 'assets/flipper_svg/connection/ic_connected_filled.svg';
        }
        return 'assets/flipper_svg/connection/ic_synced_filled.svg';
      case ArchiveSyncStatus.idle:
        return 'assets/flipper_svg/connection/ic_connected_filled.svg';
    }
  }

  String _deviceLabel({
    required FlipperDevice? device,
    required bool isConnected,
  }) {
    if (!isConnected) {
      if (device != null) {
        return 'Disconnected';
      }
      return 'No device';
    }
    if (_deviceLoading) {
      return 'Syncing';
    }
    switch (_syncStatus) {
      case ArchiveSyncStatus.syncing:
        return 'Syncing';
      case ArchiveSyncStatus.synced:
        if (_deviceInfoConnected) {
          return 'Connected';
        }
        return 'Synced';
      case ArchiveSyncStatus.idle:
        return 'Connected';
    }
  }

  ArchiveSyncStatus get _syncStatus => _archiveController.syncStatus;
}
