// This is a generated file - do not edit.
//
// Generated from flipper.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use commandStatusDescriptor instead')
const CommandStatus$json = {
  '1': 'CommandStatus',
  '2': [
    {'1': 'OK', '2': 0},
    {'1': 'ERROR', '2': 1},
    {'1': 'ERROR_DECODE', '2': 2},
    {'1': 'ERROR_NOT_IMPLEMENTED', '2': 3},
    {'1': 'ERROR_BUSY', '2': 4},
    {'1': 'ERROR_CONTINUOUS_COMMAND_INTERRUPTED', '2': 14},
    {'1': 'ERROR_INVALID_PARAMETERS', '2': 15},
    {'1': 'ERROR_STORAGE_NOT_READY', '2': 5},
    {'1': 'ERROR_STORAGE_EXIST', '2': 6},
    {'1': 'ERROR_STORAGE_NOT_EXIST', '2': 7},
    {'1': 'ERROR_STORAGE_INVALID_PARAMETER', '2': 8},
    {'1': 'ERROR_STORAGE_DENIED', '2': 9},
    {'1': 'ERROR_STORAGE_INVALID_NAME', '2': 10},
    {'1': 'ERROR_STORAGE_INTERNAL', '2': 11},
    {'1': 'ERROR_STORAGE_NOT_IMPLEMENTED', '2': 12},
    {'1': 'ERROR_STORAGE_ALREADY_OPEN', '2': 13},
    {'1': 'ERROR_STORAGE_DIR_NOT_EMPTY', '2': 18},
    {'1': 'ERROR_APP_CANT_START', '2': 16},
    {'1': 'ERROR_APP_SYSTEM_LOCKED', '2': 17},
    {'1': 'ERROR_APP_NOT_RUNNING', '2': 21},
    {'1': 'ERROR_APP_CMD_ERROR', '2': 22},
    {'1': 'ERROR_VIRTUAL_DISPLAY_ALREADY_STARTED', '2': 19},
    {'1': 'ERROR_VIRTUAL_DISPLAY_NOT_STARTED', '2': 20},
    {'1': 'ERROR_GPIO_MODE_INCORRECT', '2': 58},
    {'1': 'ERROR_GPIO_UNKNOWN_PIN_MODE', '2': 59},
  ],
};

/// Descriptor for `CommandStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List commandStatusDescriptor = $convert.base64Decode(
    'Cg1Db21tYW5kU3RhdHVzEgYKAk9LEAASCQoFRVJST1IQARIQCgxFUlJPUl9ERUNPREUQAhIZCh'
    'VFUlJPUl9OT1RfSU1QTEVNRU5URUQQAxIOCgpFUlJPUl9CVVNZEAQSKAokRVJST1JfQ09OVElO'
    'VU9VU19DT01NQU5EX0lOVEVSUlVQVEVEEA4SHAoYRVJST1JfSU5WQUxJRF9QQVJBTUVURVJTEA'
    '8SGwoXRVJST1JfU1RPUkFHRV9OT1RfUkVBRFkQBRIXChNFUlJPUl9TVE9SQUdFX0VYSVNUEAYS'
    'GwoXRVJST1JfU1RPUkFHRV9OT1RfRVhJU1QQBxIjCh9FUlJPUl9TVE9SQUdFX0lOVkFMSURfUE'
    'FSQU1FVEVSEAgSGAoURVJST1JfU1RPUkFHRV9ERU5JRUQQCRIeChpFUlJPUl9TVE9SQUdFX0lO'
    'VkFMSURfTkFNRRAKEhoKFkVSUk9SX1NUT1JBR0VfSU5URVJOQUwQCxIhCh1FUlJPUl9TVE9SQU'
    'dFX05PVF9JTVBMRU1FTlRFRBAMEh4KGkVSUk9SX1NUT1JBR0VfQUxSRUFEWV9PUEVOEA0SHwob'
    'RVJST1JfU1RPUkFHRV9ESVJfTk9UX0VNUFRZEBISGAoURVJST1JfQVBQX0NBTlRfU1RBUlQQEB'
    'IbChdFUlJPUl9BUFBfU1lTVEVNX0xPQ0tFRBAREhkKFUVSUk9SX0FQUF9OT1RfUlVOTklORxAV'
    'EhcKE0VSUk9SX0FQUF9DTURfRVJST1IQFhIpCiVFUlJPUl9WSVJUVUFMX0RJU1BMQVlfQUxSRU'
    'FEWV9TVEFSVEVEEBMSJQohRVJST1JfVklSVFVBTF9ESVNQTEFZX05PVF9TVEFSVEVEEBQSHQoZ'
    'RVJST1JfR1BJT19NT0RFX0lOQ09SUkVDVBA6Eh8KG0VSUk9SX0dQSU9fVU5LTk9XTl9QSU5fTU'
    '9ERRA7');

@$core.Deprecated('Use emptyDescriptor instead')
const Empty$json = {
  '1': 'Empty',
};

/// Descriptor for `Empty`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List emptyDescriptor =
    $convert.base64Decode('CgVFbXB0eQ==');

@$core.Deprecated('Use stopSessionDescriptor instead')
const StopSession$json = {
  '1': 'StopSession',
};

/// Descriptor for `StopSession`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List stopSessionDescriptor =
    $convert.base64Decode('CgtTdG9wU2Vzc2lvbg==');

@$core.Deprecated('Use mainDescriptor instead')
const Main$json = {
  '1': 'Main',
  '2': [
    {'1': 'command_id', '3': 1, '4': 1, '5': 13, '10': 'commandId'},
    {
      '1': 'command_status',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.PB.CommandStatus',
      '10': 'commandStatus'
    },
    {'1': 'has_next', '3': 3, '4': 1, '5': 8, '10': 'hasNext'},
    {
      '1': 'empty',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.PB.Empty',
      '9': 0,
      '10': 'empty'
    },
    {
      '1': 'stop_session',
      '3': 19,
      '4': 1,
      '5': 11,
      '6': '.PB.StopSession',
      '9': 0,
      '10': 'stopSession'
    },
    {
      '1': 'system_ping_request',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.PB_System.PingRequest',
      '9': 0,
      '10': 'systemPingRequest'
    },
    {
      '1': 'system_ping_response',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.PB_System.PingResponse',
      '9': 0,
      '10': 'systemPingResponse'
    },
    {
      '1': 'system_reboot_request',
      '3': 31,
      '4': 1,
      '5': 11,
      '6': '.PB_System.RebootRequest',
      '9': 0,
      '10': 'systemRebootRequest'
    },
    {
      '1': 'system_device_info_request',
      '3': 32,
      '4': 1,
      '5': 11,
      '6': '.PB_System.DeviceInfoRequest',
      '9': 0,
      '10': 'systemDeviceInfoRequest'
    },
    {
      '1': 'system_device_info_response',
      '3': 33,
      '4': 1,
      '5': 11,
      '6': '.PB_System.DeviceInfoResponse',
      '9': 0,
      '10': 'systemDeviceInfoResponse'
    },
    {
      '1': 'system_factory_reset_request',
      '3': 34,
      '4': 1,
      '5': 11,
      '6': '.PB_System.FactoryResetRequest',
      '9': 0,
      '10': 'systemFactoryResetRequest'
    },
    {
      '1': 'system_get_datetime_request',
      '3': 35,
      '4': 1,
      '5': 11,
      '6': '.PB_System.GetDateTimeRequest',
      '9': 0,
      '10': 'systemGetDatetimeRequest'
    },
    {
      '1': 'system_get_datetime_response',
      '3': 36,
      '4': 1,
      '5': 11,
      '6': '.PB_System.GetDateTimeResponse',
      '9': 0,
      '10': 'systemGetDatetimeResponse'
    },
    {
      '1': 'system_set_datetime_request',
      '3': 37,
      '4': 1,
      '5': 11,
      '6': '.PB_System.SetDateTimeRequest',
      '9': 0,
      '10': 'systemSetDatetimeRequest'
    },
    {
      '1': 'system_play_audiovisual_alert_request',
      '3': 38,
      '4': 1,
      '5': 11,
      '6': '.PB_System.PlayAudiovisualAlertRequest',
      '9': 0,
      '10': 'systemPlayAudiovisualAlertRequest'
    },
    {
      '1': 'system_protobuf_version_request',
      '3': 39,
      '4': 1,
      '5': 11,
      '6': '.PB_System.ProtobufVersionRequest',
      '9': 0,
      '10': 'systemProtobufVersionRequest'
    },
    {
      '1': 'system_protobuf_version_response',
      '3': 40,
      '4': 1,
      '5': 11,
      '6': '.PB_System.ProtobufVersionResponse',
      '9': 0,
      '10': 'systemProtobufVersionResponse'
    },
    {
      '1': 'system_update_request',
      '3': 41,
      '4': 1,
      '5': 11,
      '6': '.PB_System.UpdateRequest',
      '9': 0,
      '10': 'systemUpdateRequest'
    },
    {
      '1': 'system_update_response',
      '3': 46,
      '4': 1,
      '5': 11,
      '6': '.PB_System.UpdateResponse',
      '9': 0,
      '10': 'systemUpdateResponse'
    },
    {
      '1': 'system_power_info_request',
      '3': 44,
      '4': 1,
      '5': 11,
      '6': '.PB_System.PowerInfoRequest',
      '9': 0,
      '10': 'systemPowerInfoRequest'
    },
    {
      '1': 'system_power_info_response',
      '3': 45,
      '4': 1,
      '5': 11,
      '6': '.PB_System.PowerInfoResponse',
      '9': 0,
      '10': 'systemPowerInfoResponse'
    },
    {
      '1': 'storage_info_request',
      '3': 28,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.InfoRequest',
      '9': 0,
      '10': 'storageInfoRequest'
    },
    {
      '1': 'storage_info_response',
      '3': 29,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.InfoResponse',
      '9': 0,
      '10': 'storageInfoResponse'
    },
    {
      '1': 'storage_timestamp_request',
      '3': 59,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.TimestampRequest',
      '9': 0,
      '10': 'storageTimestampRequest'
    },
    {
      '1': 'storage_timestamp_response',
      '3': 60,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.TimestampResponse',
      '9': 0,
      '10': 'storageTimestampResponse'
    },
    {
      '1': 'storage_stat_request',
      '3': 24,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.StatRequest',
      '9': 0,
      '10': 'storageStatRequest'
    },
    {
      '1': 'storage_stat_response',
      '3': 25,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.StatResponse',
      '9': 0,
      '10': 'storageStatResponse'
    },
    {
      '1': 'storage_list_request',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.ListRequest',
      '9': 0,
      '10': 'storageListRequest'
    },
    {
      '1': 'storage_list_response',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.ListResponse',
      '9': 0,
      '10': 'storageListResponse'
    },
    {
      '1': 'storage_read_request',
      '3': 9,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.ReadRequest',
      '9': 0,
      '10': 'storageReadRequest'
    },
    {
      '1': 'storage_read_response',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.ReadResponse',
      '9': 0,
      '10': 'storageReadResponse'
    },
    {
      '1': 'storage_write_request',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.WriteRequest',
      '9': 0,
      '10': 'storageWriteRequest'
    },
    {
      '1': 'storage_delete_request',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.DeleteRequest',
      '9': 0,
      '10': 'storageDeleteRequest'
    },
    {
      '1': 'storage_mkdir_request',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.MkdirRequest',
      '9': 0,
      '10': 'storageMkdirRequest'
    },
    {
      '1': 'storage_md5sum_request',
      '3': 14,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.Md5sumRequest',
      '9': 0,
      '10': 'storageMd5sumRequest'
    },
    {
      '1': 'storage_md5sum_response',
      '3': 15,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.Md5sumResponse',
      '9': 0,
      '10': 'storageMd5sumResponse'
    },
    {
      '1': 'storage_rename_request',
      '3': 30,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.RenameRequest',
      '9': 0,
      '10': 'storageRenameRequest'
    },
    {
      '1': 'storage_backup_create_request',
      '3': 42,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.BackupCreateRequest',
      '9': 0,
      '10': 'storageBackupCreateRequest'
    },
    {
      '1': 'storage_backup_restore_request',
      '3': 43,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.BackupRestoreRequest',
      '9': 0,
      '10': 'storageBackupRestoreRequest'
    },
    {
      '1': 'storage_tar_extract_request',
      '3': 71,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.TarExtractRequest',
      '9': 0,
      '10': 'storageTarExtractRequest'
    },
    {
      '1': 'app_start_request',
      '3': 16,
      '4': 1,
      '5': 11,
      '6': '.PB_App.StartRequest',
      '9': 0,
      '10': 'appStartRequest'
    },
    {
      '1': 'app_lock_status_request',
      '3': 17,
      '4': 1,
      '5': 11,
      '6': '.PB_App.LockStatusRequest',
      '9': 0,
      '10': 'appLockStatusRequest'
    },
    {
      '1': 'app_lock_status_response',
      '3': 18,
      '4': 1,
      '5': 11,
      '6': '.PB_App.LockStatusResponse',
      '9': 0,
      '10': 'appLockStatusResponse'
    },
    {
      '1': 'app_exit_request',
      '3': 47,
      '4': 1,
      '5': 11,
      '6': '.PB_App.AppExitRequest',
      '9': 0,
      '10': 'appExitRequest'
    },
    {
      '1': 'app_load_file_request',
      '3': 48,
      '4': 1,
      '5': 11,
      '6': '.PB_App.AppLoadFileRequest',
      '9': 0,
      '10': 'appLoadFileRequest'
    },
    {
      '1': 'app_button_press_request',
      '3': 49,
      '4': 1,
      '5': 11,
      '6': '.PB_App.AppButtonPressRequest',
      '9': 0,
      '10': 'appButtonPressRequest'
    },
    {
      '1': 'app_button_release_request',
      '3': 50,
      '4': 1,
      '5': 11,
      '6': '.PB_App.AppButtonReleaseRequest',
      '9': 0,
      '10': 'appButtonReleaseRequest'
    },
    {
      '1': 'app_button_press_release_request',
      '3': 75,
      '4': 1,
      '5': 11,
      '6': '.PB_App.AppButtonPressReleaseRequest',
      '9': 0,
      '10': 'appButtonPressReleaseRequest'
    },
    {
      '1': 'app_get_error_request',
      '3': 63,
      '4': 1,
      '5': 11,
      '6': '.PB_App.GetErrorRequest',
      '9': 0,
      '10': 'appGetErrorRequest'
    },
    {
      '1': 'app_get_error_response',
      '3': 64,
      '4': 1,
      '5': 11,
      '6': '.PB_App.GetErrorResponse',
      '9': 0,
      '10': 'appGetErrorResponse'
    },
    {
      '1': 'app_data_exchange_request',
      '3': 65,
      '4': 1,
      '5': 11,
      '6': '.PB_App.DataExchangeRequest',
      '9': 0,
      '10': 'appDataExchangeRequest'
    },
    {
      '1': 'gui_start_screen_stream_request',
      '3': 20,
      '4': 1,
      '5': 11,
      '6': '.PB_Gui.StartScreenStreamRequest',
      '9': 0,
      '10': 'guiStartScreenStreamRequest'
    },
    {
      '1': 'gui_stop_screen_stream_request',
      '3': 21,
      '4': 1,
      '5': 11,
      '6': '.PB_Gui.StopScreenStreamRequest',
      '9': 0,
      '10': 'guiStopScreenStreamRequest'
    },
    {
      '1': 'gui_screen_frame',
      '3': 22,
      '4': 1,
      '5': 11,
      '6': '.PB_Gui.ScreenFrame',
      '9': 0,
      '10': 'guiScreenFrame'
    },
    {
      '1': 'gui_send_input_event_request',
      '3': 23,
      '4': 1,
      '5': 11,
      '6': '.PB_Gui.SendInputEventRequest',
      '9': 0,
      '10': 'guiSendInputEventRequest'
    },
    {
      '1': 'gui_start_virtual_display_request',
      '3': 26,
      '4': 1,
      '5': 11,
      '6': '.PB_Gui.StartVirtualDisplayRequest',
      '9': 0,
      '10': 'guiStartVirtualDisplayRequest'
    },
    {
      '1': 'gui_stop_virtual_display_request',
      '3': 27,
      '4': 1,
      '5': 11,
      '6': '.PB_Gui.StopVirtualDisplayRequest',
      '9': 0,
      '10': 'guiStopVirtualDisplayRequest'
    },
    {
      '1': 'gpio_set_pin_mode',
      '3': 51,
      '4': 1,
      '5': 11,
      '6': '.PB_Gpio.SetPinMode',
      '9': 0,
      '10': 'gpioSetPinMode'
    },
    {
      '1': 'gpio_set_input_pull',
      '3': 52,
      '4': 1,
      '5': 11,
      '6': '.PB_Gpio.SetInputPull',
      '9': 0,
      '10': 'gpioSetInputPull'
    },
    {
      '1': 'gpio_get_pin_mode',
      '3': 53,
      '4': 1,
      '5': 11,
      '6': '.PB_Gpio.GetPinMode',
      '9': 0,
      '10': 'gpioGetPinMode'
    },
    {
      '1': 'gpio_get_pin_mode_response',
      '3': 54,
      '4': 1,
      '5': 11,
      '6': '.PB_Gpio.GetPinModeResponse',
      '9': 0,
      '10': 'gpioGetPinModeResponse'
    },
    {
      '1': 'gpio_read_pin',
      '3': 55,
      '4': 1,
      '5': 11,
      '6': '.PB_Gpio.ReadPin',
      '9': 0,
      '10': 'gpioReadPin'
    },
    {
      '1': 'gpio_read_pin_response',
      '3': 56,
      '4': 1,
      '5': 11,
      '6': '.PB_Gpio.ReadPinResponse',
      '9': 0,
      '10': 'gpioReadPinResponse'
    },
    {
      '1': 'gpio_write_pin',
      '3': 57,
      '4': 1,
      '5': 11,
      '6': '.PB_Gpio.WritePin',
      '9': 0,
      '10': 'gpioWritePin'
    },
    {
      '1': 'gpio_get_otg_mode',
      '3': 72,
      '4': 1,
      '5': 11,
      '6': '.PB_Gpio.GetOtgMode',
      '9': 0,
      '10': 'gpioGetOtgMode'
    },
    {
      '1': 'gpio_get_otg_mode_response',
      '3': 73,
      '4': 1,
      '5': 11,
      '6': '.PB_Gpio.GetOtgModeResponse',
      '9': 0,
      '10': 'gpioGetOtgModeResponse'
    },
    {
      '1': 'gpio_set_otg_mode',
      '3': 74,
      '4': 1,
      '5': 11,
      '6': '.PB_Gpio.SetOtgMode',
      '9': 0,
      '10': 'gpioSetOtgMode'
    },
    {
      '1': 'app_state_response',
      '3': 58,
      '4': 1,
      '5': 11,
      '6': '.PB_App.AppStateResponse',
      '9': 0,
      '10': 'appStateResponse'
    },
    {
      '1': 'property_get_request',
      '3': 61,
      '4': 1,
      '5': 11,
      '6': '.PB_Property.GetRequest',
      '9': 0,
      '10': 'propertyGetRequest'
    },
    {
      '1': 'property_get_response',
      '3': 62,
      '4': 1,
      '5': 11,
      '6': '.PB_Property.GetResponse',
      '9': 0,
      '10': 'propertyGetResponse'
    },
    {
      '1': 'desktop_is_locked_request',
      '3': 66,
      '4': 1,
      '5': 11,
      '6': '.PB_Desktop.IsLockedRequest',
      '9': 0,
      '10': 'desktopIsLockedRequest'
    },
    {
      '1': 'desktop_unlock_request',
      '3': 67,
      '4': 1,
      '5': 11,
      '6': '.PB_Desktop.UnlockRequest',
      '9': 0,
      '10': 'desktopUnlockRequest'
    },
    {
      '1': 'desktop_status_subscribe_request',
      '3': 68,
      '4': 1,
      '5': 11,
      '6': '.PB_Desktop.StatusSubscribeRequest',
      '9': 0,
      '10': 'desktopStatusSubscribeRequest'
    },
    {
      '1': 'desktop_status_unsubscribe_request',
      '3': 69,
      '4': 1,
      '5': 11,
      '6': '.PB_Desktop.StatusUnsubscribeRequest',
      '9': 0,
      '10': 'desktopStatusUnsubscribeRequest'
    },
    {
      '1': 'desktop_status',
      '3': 70,
      '4': 1,
      '5': 11,
      '6': '.PB_Desktop.Status',
      '9': 0,
      '10': 'desktopStatus'
    },
  ],
  '8': [
    {'1': 'content'},
  ],
};

/// Descriptor for `Main`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mainDescriptor = $convert.base64Decode(
    'CgRNYWluEh0KCmNvbW1hbmRfaWQYASABKA1SCWNvbW1hbmRJZBI4Cg5jb21tYW5kX3N0YXR1cx'
    'gCIAEoDjIRLlBCLkNvbW1hbmRTdGF0dXNSDWNvbW1hbmRTdGF0dXMSGQoIaGFzX25leHQYAyAB'
    'KAhSB2hhc05leHQSIQoFZW1wdHkYBCABKAsyCS5QQi5FbXB0eUgAUgVlbXB0eRI0CgxzdG9wX3'
    'Nlc3Npb24YEyABKAsyDy5QQi5TdG9wU2Vzc2lvbkgAUgtzdG9wU2Vzc2lvbhJIChNzeXN0ZW1f'
    'cGluZ19yZXF1ZXN0GAUgASgLMhYuUEJfU3lzdGVtLlBpbmdSZXF1ZXN0SABSEXN5c3RlbVBpbm'
    'dSZXF1ZXN0EksKFHN5c3RlbV9waW5nX3Jlc3BvbnNlGAYgASgLMhcuUEJfU3lzdGVtLlBpbmdS'
    'ZXNwb25zZUgAUhJzeXN0ZW1QaW5nUmVzcG9uc2USTgoVc3lzdGVtX3JlYm9vdF9yZXF1ZXN0GB'
    '8gASgLMhguUEJfU3lzdGVtLlJlYm9vdFJlcXVlc3RIAFITc3lzdGVtUmVib290UmVxdWVzdBJb'
    'ChpzeXN0ZW1fZGV2aWNlX2luZm9fcmVxdWVzdBggIAEoCzIcLlBCX1N5c3RlbS5EZXZpY2VJbm'
    'ZvUmVxdWVzdEgAUhdzeXN0ZW1EZXZpY2VJbmZvUmVxdWVzdBJeChtzeXN0ZW1fZGV2aWNlX2lu'
    'Zm9fcmVzcG9uc2UYISABKAsyHS5QQl9TeXN0ZW0uRGV2aWNlSW5mb1Jlc3BvbnNlSABSGHN5c3'
    'RlbURldmljZUluZm9SZXNwb25zZRJhChxzeXN0ZW1fZmFjdG9yeV9yZXNldF9yZXF1ZXN0GCIg'
    'ASgLMh4uUEJfU3lzdGVtLkZhY3RvcnlSZXNldFJlcXVlc3RIAFIZc3lzdGVtRmFjdG9yeVJlc2'
    'V0UmVxdWVzdBJeChtzeXN0ZW1fZ2V0X2RhdGV0aW1lX3JlcXVlc3QYIyABKAsyHS5QQl9TeXN0'
    'ZW0uR2V0RGF0ZVRpbWVSZXF1ZXN0SABSGHN5c3RlbUdldERhdGV0aW1lUmVxdWVzdBJhChxzeX'
    'N0ZW1fZ2V0X2RhdGV0aW1lX3Jlc3BvbnNlGCQgASgLMh4uUEJfU3lzdGVtLkdldERhdGVUaW1l'
    'UmVzcG9uc2VIAFIZc3lzdGVtR2V0RGF0ZXRpbWVSZXNwb25zZRJeChtzeXN0ZW1fc2V0X2RhdG'
    'V0aW1lX3JlcXVlc3QYJSABKAsyHS5QQl9TeXN0ZW0uU2V0RGF0ZVRpbWVSZXF1ZXN0SABSGHN5'
    'c3RlbVNldERhdGV0aW1lUmVxdWVzdBJ6CiVzeXN0ZW1fcGxheV9hdWRpb3Zpc3VhbF9hbGVydF'
    '9yZXF1ZXN0GCYgASgLMiYuUEJfU3lzdGVtLlBsYXlBdWRpb3Zpc3VhbEFsZXJ0UmVxdWVzdEgA'
    'UiFzeXN0ZW1QbGF5QXVkaW92aXN1YWxBbGVydFJlcXVlc3QSagofc3lzdGVtX3Byb3RvYnVmX3'
    'ZlcnNpb25fcmVxdWVzdBgnIAEoCzIhLlBCX1N5c3RlbS5Qcm90b2J1ZlZlcnNpb25SZXF1ZXN0'
    'SABSHHN5c3RlbVByb3RvYnVmVmVyc2lvblJlcXVlc3QSbQogc3lzdGVtX3Byb3RvYnVmX3Zlcn'
    'Npb25fcmVzcG9uc2UYKCABKAsyIi5QQl9TeXN0ZW0uUHJvdG9idWZWZXJzaW9uUmVzcG9uc2VI'
    'AFIdc3lzdGVtUHJvdG9idWZWZXJzaW9uUmVzcG9uc2USTgoVc3lzdGVtX3VwZGF0ZV9yZXF1ZX'
    'N0GCkgASgLMhguUEJfU3lzdGVtLlVwZGF0ZVJlcXVlc3RIAFITc3lzdGVtVXBkYXRlUmVxdWVz'
    'dBJRChZzeXN0ZW1fdXBkYXRlX3Jlc3BvbnNlGC4gASgLMhkuUEJfU3lzdGVtLlVwZGF0ZVJlc3'
    'BvbnNlSABSFHN5c3RlbVVwZGF0ZVJlc3BvbnNlElgKGXN5c3RlbV9wb3dlcl9pbmZvX3JlcXVl'
    'c3QYLCABKAsyGy5QQl9TeXN0ZW0uUG93ZXJJbmZvUmVxdWVzdEgAUhZzeXN0ZW1Qb3dlckluZm'
    '9SZXF1ZXN0ElsKGnN5c3RlbV9wb3dlcl9pbmZvX3Jlc3BvbnNlGC0gASgLMhwuUEJfU3lzdGVt'
    'LlBvd2VySW5mb1Jlc3BvbnNlSABSF3N5c3RlbVBvd2VySW5mb1Jlc3BvbnNlEksKFHN0b3JhZ2'
    'VfaW5mb19yZXF1ZXN0GBwgASgLMhcuUEJfU3RvcmFnZS5JbmZvUmVxdWVzdEgAUhJzdG9yYWdl'
    'SW5mb1JlcXVlc3QSTgoVc3RvcmFnZV9pbmZvX3Jlc3BvbnNlGB0gASgLMhguUEJfU3RvcmFnZS'
    '5JbmZvUmVzcG9uc2VIAFITc3RvcmFnZUluZm9SZXNwb25zZRJaChlzdG9yYWdlX3RpbWVzdGFt'
    'cF9yZXF1ZXN0GDsgASgLMhwuUEJfU3RvcmFnZS5UaW1lc3RhbXBSZXF1ZXN0SABSF3N0b3JhZ2'
    'VUaW1lc3RhbXBSZXF1ZXN0El0KGnN0b3JhZ2VfdGltZXN0YW1wX3Jlc3BvbnNlGDwgASgLMh0u'
    'UEJfU3RvcmFnZS5UaW1lc3RhbXBSZXNwb25zZUgAUhhzdG9yYWdlVGltZXN0YW1wUmVzcG9uc2'
    'USSwoUc3RvcmFnZV9zdGF0X3JlcXVlc3QYGCABKAsyFy5QQl9TdG9yYWdlLlN0YXRSZXF1ZXN0'
    'SABSEnN0b3JhZ2VTdGF0UmVxdWVzdBJOChVzdG9yYWdlX3N0YXRfcmVzcG9uc2UYGSABKAsyGC'
    '5QQl9TdG9yYWdlLlN0YXRSZXNwb25zZUgAUhNzdG9yYWdlU3RhdFJlc3BvbnNlEksKFHN0b3Jh'
    'Z2VfbGlzdF9yZXF1ZXN0GAcgASgLMhcuUEJfU3RvcmFnZS5MaXN0UmVxdWVzdEgAUhJzdG9yYW'
    'dlTGlzdFJlcXVlc3QSTgoVc3RvcmFnZV9saXN0X3Jlc3BvbnNlGAggASgLMhguUEJfU3RvcmFn'
    'ZS5MaXN0UmVzcG9uc2VIAFITc3RvcmFnZUxpc3RSZXNwb25zZRJLChRzdG9yYWdlX3JlYWRfcm'
    'VxdWVzdBgJIAEoCzIXLlBCX1N0b3JhZ2UuUmVhZFJlcXVlc3RIAFISc3RvcmFnZVJlYWRSZXF1'
    'ZXN0Ek4KFXN0b3JhZ2VfcmVhZF9yZXNwb25zZRgKIAEoCzIYLlBCX1N0b3JhZ2UuUmVhZFJlc3'
    'BvbnNlSABSE3N0b3JhZ2VSZWFkUmVzcG9uc2USTgoVc3RvcmFnZV93cml0ZV9yZXF1ZXN0GAsg'
    'ASgLMhguUEJfU3RvcmFnZS5Xcml0ZVJlcXVlc3RIAFITc3RvcmFnZVdyaXRlUmVxdWVzdBJRCh'
    'ZzdG9yYWdlX2RlbGV0ZV9yZXF1ZXN0GAwgASgLMhkuUEJfU3RvcmFnZS5EZWxldGVSZXF1ZXN0'
    'SABSFHN0b3JhZ2VEZWxldGVSZXF1ZXN0Ek4KFXN0b3JhZ2VfbWtkaXJfcmVxdWVzdBgNIAEoCz'
    'IYLlBCX1N0b3JhZ2UuTWtkaXJSZXF1ZXN0SABSE3N0b3JhZ2VNa2RpclJlcXVlc3QSUQoWc3Rv'
    'cmFnZV9tZDVzdW1fcmVxdWVzdBgOIAEoCzIZLlBCX1N0b3JhZ2UuTWQ1c3VtUmVxdWVzdEgAUh'
    'RzdG9yYWdlTWQ1c3VtUmVxdWVzdBJUChdzdG9yYWdlX21kNXN1bV9yZXNwb25zZRgPIAEoCzIa'
    'LlBCX1N0b3JhZ2UuTWQ1c3VtUmVzcG9uc2VIAFIVc3RvcmFnZU1kNXN1bVJlc3BvbnNlElEKFn'
    'N0b3JhZ2VfcmVuYW1lX3JlcXVlc3QYHiABKAsyGS5QQl9TdG9yYWdlLlJlbmFtZVJlcXVlc3RI'
    'AFIUc3RvcmFnZVJlbmFtZVJlcXVlc3QSZAodc3RvcmFnZV9iYWNrdXBfY3JlYXRlX3JlcXVlc3'
    'QYKiABKAsyHy5QQl9TdG9yYWdlLkJhY2t1cENyZWF0ZVJlcXVlc3RIAFIac3RvcmFnZUJhY2t1'
    'cENyZWF0ZVJlcXVlc3QSZwoec3RvcmFnZV9iYWNrdXBfcmVzdG9yZV9yZXF1ZXN0GCsgASgLMi'
    'AuUEJfU3RvcmFnZS5CYWNrdXBSZXN0b3JlUmVxdWVzdEgAUhtzdG9yYWdlQmFja3VwUmVzdG9y'
    'ZVJlcXVlc3QSXgobc3RvcmFnZV90YXJfZXh0cmFjdF9yZXF1ZXN0GEcgASgLMh0uUEJfU3Rvcm'
    'FnZS5UYXJFeHRyYWN0UmVxdWVzdEgAUhhzdG9yYWdlVGFyRXh0cmFjdFJlcXVlc3QSQgoRYXBw'
    'X3N0YXJ0X3JlcXVlc3QYECABKAsyFC5QQl9BcHAuU3RhcnRSZXF1ZXN0SABSD2FwcFN0YXJ0Um'
    'VxdWVzdBJSChdhcHBfbG9ja19zdGF0dXNfcmVxdWVzdBgRIAEoCzIZLlBCX0FwcC5Mb2NrU3Rh'
    'dHVzUmVxdWVzdEgAUhRhcHBMb2NrU3RhdHVzUmVxdWVzdBJVChhhcHBfbG9ja19zdGF0dXNfcm'
    'VzcG9uc2UYEiABKAsyGi5QQl9BcHAuTG9ja1N0YXR1c1Jlc3BvbnNlSABSFWFwcExvY2tTdGF0'
    'dXNSZXNwb25zZRJCChBhcHBfZXhpdF9yZXF1ZXN0GC8gASgLMhYuUEJfQXBwLkFwcEV4aXRSZX'
    'F1ZXN0SABSDmFwcEV4aXRSZXF1ZXN0Ek8KFWFwcF9sb2FkX2ZpbGVfcmVxdWVzdBgwIAEoCzIa'
    'LlBCX0FwcC5BcHBMb2FkRmlsZVJlcXVlc3RIAFISYXBwTG9hZEZpbGVSZXF1ZXN0ElgKGGFwcF'
    '9idXR0b25fcHJlc3NfcmVxdWVzdBgxIAEoCzIdLlBCX0FwcC5BcHBCdXR0b25QcmVzc1JlcXVl'
    'c3RIAFIVYXBwQnV0dG9uUHJlc3NSZXF1ZXN0El4KGmFwcF9idXR0b25fcmVsZWFzZV9yZXF1ZX'
    'N0GDIgASgLMh8uUEJfQXBwLkFwcEJ1dHRvblJlbGVhc2VSZXF1ZXN0SABSF2FwcEJ1dHRvblJl'
    'bGVhc2VSZXF1ZXN0Em4KIGFwcF9idXR0b25fcHJlc3NfcmVsZWFzZV9yZXF1ZXN0GEsgASgLMi'
    'QuUEJfQXBwLkFwcEJ1dHRvblByZXNzUmVsZWFzZVJlcXVlc3RIAFIcYXBwQnV0dG9uUHJlc3NS'
    'ZWxlYXNlUmVxdWVzdBJMChVhcHBfZ2V0X2Vycm9yX3JlcXVlc3QYPyABKAsyFy5QQl9BcHAuR2'
    'V0RXJyb3JSZXF1ZXN0SABSEmFwcEdldEVycm9yUmVxdWVzdBJPChZhcHBfZ2V0X2Vycm9yX3Jl'
    'c3BvbnNlGEAgASgLMhguUEJfQXBwLkdldEVycm9yUmVzcG9uc2VIAFITYXBwR2V0RXJyb3JSZX'
    'Nwb25zZRJYChlhcHBfZGF0YV9leGNoYW5nZV9yZXF1ZXN0GEEgASgLMhsuUEJfQXBwLkRhdGFF'
    'eGNoYW5nZVJlcXVlc3RIAFIWYXBwRGF0YUV4Y2hhbmdlUmVxdWVzdBJoCh9ndWlfc3RhcnRfc2'
    'NyZWVuX3N0cmVhbV9yZXF1ZXN0GBQgASgLMiAuUEJfR3VpLlN0YXJ0U2NyZWVuU3RyZWFtUmVx'
    'dWVzdEgAUhtndWlTdGFydFNjcmVlblN0cmVhbVJlcXVlc3QSZQoeZ3VpX3N0b3Bfc2NyZWVuX3'
    'N0cmVhbV9yZXF1ZXN0GBUgASgLMh8uUEJfR3VpLlN0b3BTY3JlZW5TdHJlYW1SZXF1ZXN0SABS'
    'Gmd1aVN0b3BTY3JlZW5TdHJlYW1SZXF1ZXN0Ej8KEGd1aV9zY3JlZW5fZnJhbWUYFiABKAsyEy'
    '5QQl9HdWkuU2NyZWVuRnJhbWVIAFIOZ3VpU2NyZWVuRnJhbWUSXwocZ3VpX3NlbmRfaW5wdXRf'
    'ZXZlbnRfcmVxdWVzdBgXIAEoCzIdLlBCX0d1aS5TZW5kSW5wdXRFdmVudFJlcXVlc3RIAFIYZ3'
    'VpU2VuZElucHV0RXZlbnRSZXF1ZXN0Em4KIWd1aV9zdGFydF92aXJ0dWFsX2Rpc3BsYXlfcmVx'
    'dWVzdBgaIAEoCzIiLlBCX0d1aS5TdGFydFZpcnR1YWxEaXNwbGF5UmVxdWVzdEgAUh1ndWlTdG'
    'FydFZpcnR1YWxEaXNwbGF5UmVxdWVzdBJrCiBndWlfc3RvcF92aXJ0dWFsX2Rpc3BsYXlfcmVx'
    'dWVzdBgbIAEoCzIhLlBCX0d1aS5TdG9wVmlydHVhbERpc3BsYXlSZXF1ZXN0SABSHGd1aVN0b3'
    'BWaXJ0dWFsRGlzcGxheVJlcXVlc3QSQAoRZ3Bpb19zZXRfcGluX21vZGUYMyABKAsyEy5QQl9H'
    'cGlvLlNldFBpbk1vZGVIAFIOZ3Bpb1NldFBpbk1vZGUSRgoTZ3Bpb19zZXRfaW5wdXRfcHVsbB'
    'g0IAEoCzIVLlBCX0dwaW8uU2V0SW5wdXRQdWxsSABSEGdwaW9TZXRJbnB1dFB1bGwSQAoRZ3Bp'
    'b19nZXRfcGluX21vZGUYNSABKAsyEy5QQl9HcGlvLkdldFBpbk1vZGVIAFIOZ3Bpb0dldFBpbk'
    '1vZGUSWQoaZ3Bpb19nZXRfcGluX21vZGVfcmVzcG9uc2UYNiABKAsyGy5QQl9HcGlvLkdldFBp'
    'bk1vZGVSZXNwb25zZUgAUhZncGlvR2V0UGluTW9kZVJlc3BvbnNlEjYKDWdwaW9fcmVhZF9waW'
    '4YNyABKAsyEC5QQl9HcGlvLlJlYWRQaW5IAFILZ3Bpb1JlYWRQaW4STwoWZ3Bpb19yZWFkX3Bp'
    'bl9yZXNwb25zZRg4IAEoCzIYLlBCX0dwaW8uUmVhZFBpblJlc3BvbnNlSABSE2dwaW9SZWFkUG'
    'luUmVzcG9uc2USOQoOZ3Bpb193cml0ZV9waW4YOSABKAsyES5QQl9HcGlvLldyaXRlUGluSABS'
    'DGdwaW9Xcml0ZVBpbhJAChFncGlvX2dldF9vdGdfbW9kZRhIIAEoCzITLlBCX0dwaW8uR2V0T3'
    'RnTW9kZUgAUg5ncGlvR2V0T3RnTW9kZRJZChpncGlvX2dldF9vdGdfbW9kZV9yZXNwb25zZRhJ'
    'IAEoCzIbLlBCX0dwaW8uR2V0T3RnTW9kZVJlc3BvbnNlSABSFmdwaW9HZXRPdGdNb2RlUmVzcG'
    '9uc2USQAoRZ3Bpb19zZXRfb3RnX21vZGUYSiABKAsyEy5QQl9HcGlvLlNldE90Z01vZGVIAFIO'
    'Z3Bpb1NldE90Z01vZGUSSAoSYXBwX3N0YXRlX3Jlc3BvbnNlGDogASgLMhguUEJfQXBwLkFwcF'
    'N0YXRlUmVzcG9uc2VIAFIQYXBwU3RhdGVSZXNwb25zZRJLChRwcm9wZXJ0eV9nZXRfcmVxdWVz'
    'dBg9IAEoCzIXLlBCX1Byb3BlcnR5LkdldFJlcXVlc3RIAFIScHJvcGVydHlHZXRSZXF1ZXN0Ek'
    '4KFXByb3BlcnR5X2dldF9yZXNwb25zZRg+IAEoCzIYLlBCX1Byb3BlcnR5LkdldFJlc3BvbnNl'
    'SABSE3Byb3BlcnR5R2V0UmVzcG9uc2USWAoZZGVza3RvcF9pc19sb2NrZWRfcmVxdWVzdBhCIA'
    'EoCzIbLlBCX0Rlc2t0b3AuSXNMb2NrZWRSZXF1ZXN0SABSFmRlc2t0b3BJc0xvY2tlZFJlcXVl'
    'c3QSUQoWZGVza3RvcF91bmxvY2tfcmVxdWVzdBhDIAEoCzIZLlBCX0Rlc2t0b3AuVW5sb2NrUm'
    'VxdWVzdEgAUhRkZXNrdG9wVW5sb2NrUmVxdWVzdBJtCiBkZXNrdG9wX3N0YXR1c19zdWJzY3Jp'
    'YmVfcmVxdWVzdBhEIAEoCzIiLlBCX0Rlc2t0b3AuU3RhdHVzU3Vic2NyaWJlUmVxdWVzdEgAUh'
    '1kZXNrdG9wU3RhdHVzU3Vic2NyaWJlUmVxdWVzdBJzCiJkZXNrdG9wX3N0YXR1c191bnN1YnNj'
    'cmliZV9yZXF1ZXN0GEUgASgLMiQuUEJfRGVza3RvcC5TdGF0dXNVbnN1YnNjcmliZVJlcXVlc3'
    'RIAFIfZGVza3RvcFN0YXR1c1Vuc3Vic2NyaWJlUmVxdWVzdBI7Cg5kZXNrdG9wX3N0YXR1cxhG'
    'IAEoCzISLlBCX0Rlc2t0b3AuU3RhdHVzSABSDWRlc2t0b3BTdGF0dXNCCQoHY29udGVudA==');

@$core.Deprecated('Use regionDescriptor instead')
const Region$json = {
  '1': 'Region',
  '2': [
    {'1': 'country_code', '3': 1, '4': 1, '5': 12, '10': 'countryCode'},
    {
      '1': 'bands',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.PB.Region.Band',
      '10': 'bands'
    },
  ],
  '3': [Region_Band$json],
};

@$core.Deprecated('Use regionDescriptor instead')
const Region_Band$json = {
  '1': 'Band',
  '2': [
    {'1': 'start', '3': 1, '4': 1, '5': 13, '10': 'start'},
    {'1': 'end', '3': 2, '4': 1, '5': 13, '10': 'end'},
    {'1': 'power_limit', '3': 3, '4': 1, '5': 5, '10': 'powerLimit'},
    {'1': 'duty_cycle', '3': 4, '4': 1, '5': 13, '10': 'dutyCycle'},
  ],
};

/// Descriptor for `Region`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List regionDescriptor = $convert.base64Decode(
    'CgZSZWdpb24SIQoMY291bnRyeV9jb2RlGAEgASgMUgtjb3VudHJ5Q29kZRIlCgViYW5kcxgCIA'
    'MoCzIPLlBCLlJlZ2lvbi5CYW5kUgViYW5kcxpuCgRCYW5kEhQKBXN0YXJ0GAEgASgNUgVzdGFy'
    'dBIQCgNlbmQYAiABKA1SA2VuZBIfCgtwb3dlcl9saW1pdBgDIAEoBVIKcG93ZXJMaW1pdBIdCg'
    'pkdXR5X2N5Y2xlGAQgASgNUglkdXR5Q3ljbGU=');
