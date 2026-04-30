// This is a generated file - do not edit.
//
// Generated from flipper.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'application.pb.dart' as $2;
import 'desktop.pb.dart' as $6;
import 'flipper.pbenum.dart';
import 'gpio.pb.dart' as $4;
import 'gui.pb.dart' as $3;
import 'property.pb.dart' as $5;
import 'storage.pb.dart' as $1;
import 'system.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'flipper.pbenum.dart';

/// There are Server commands (e.g. Storage_write), which have no body message
/// in response. But 'oneof' obligate to have at least 1 encoded message
/// in scope. For this needs Empty message is implemented.
class Empty extends $pb.GeneratedMessage {
  factory Empty() => create();

  Empty._();

  factory Empty.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Empty.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Empty',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Empty clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Empty copyWith(void Function(Empty) updates) =>
      super.copyWith((message) => updates(message as Empty)) as Empty;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Empty create() => Empty._();
  @$core.override
  Empty createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Empty getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Empty>(create);
  static Empty? _defaultInstance;
}

class StopSession extends $pb.GeneratedMessage {
  factory StopSession() => create();

  StopSession._();

  factory StopSession.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StopSession.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StopSession',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StopSession clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StopSession copyWith(void Function(StopSession) updates) =>
      super.copyWith((message) => updates(message as StopSession))
          as StopSession;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StopSession create() => StopSession._();
  @$core.override
  StopSession createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StopSession getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StopSession>(create);
  static StopSession? _defaultInstance;
}

enum Main_Content {
  empty,
  systemPingRequest,
  systemPingResponse,
  storageListRequest,
  storageListResponse,
  storageReadRequest,
  storageReadResponse,
  storageWriteRequest,
  storageDeleteRequest,
  storageMkdirRequest,
  storageMd5sumRequest,
  storageMd5sumResponse,
  appStartRequest,
  appLockStatusRequest,
  appLockStatusResponse,
  stopSession,
  guiStartScreenStreamRequest,
  guiStopScreenStreamRequest,
  guiScreenFrame,
  guiSendInputEventRequest,
  storageStatRequest,
  storageStatResponse,
  guiStartVirtualDisplayRequest,
  guiStopVirtualDisplayRequest,
  storageInfoRequest,
  storageInfoResponse,
  storageRenameRequest,
  systemRebootRequest,
  systemDeviceInfoRequest,
  systemDeviceInfoResponse,
  systemFactoryResetRequest,
  systemGetDatetimeRequest,
  systemGetDatetimeResponse,
  systemSetDatetimeRequest,
  systemPlayAudiovisualAlertRequest,
  systemProtobufVersionRequest,
  systemProtobufVersionResponse,
  systemUpdateRequest,
  storageBackupCreateRequest,
  storageBackupRestoreRequest,
  systemPowerInfoRequest,
  systemPowerInfoResponse,
  systemUpdateResponse,
  appExitRequest,
  appLoadFileRequest,
  appButtonPressRequest,
  appButtonReleaseRequest,
  gpioSetPinMode,
  gpioSetInputPull,
  gpioGetPinMode,
  gpioGetPinModeResponse,
  gpioReadPin,
  gpioReadPinResponse,
  gpioWritePin,
  appStateResponse,
  storageTimestampRequest,
  storageTimestampResponse,
  propertyGetRequest,
  propertyGetResponse,
  appGetErrorRequest,
  appGetErrorResponse,
  appDataExchangeRequest,
  desktopIsLockedRequest,
  desktopUnlockRequest,
  desktopStatusSubscribeRequest,
  desktopStatusUnsubscribeRequest,
  desktopStatus,
  storageTarExtractRequest,
  gpioGetOtgMode,
  gpioGetOtgModeResponse,
  gpioSetOtgMode,
  appButtonPressReleaseRequest,
  notSet
}

class Main extends $pb.GeneratedMessage {
  factory Main({
    $core.int? commandId,
    CommandStatus? commandStatus,
    $core.bool? hasNext,
    Empty? empty,
    $0.PingRequest? systemPingRequest,
    $0.PingResponse? systemPingResponse,
    $1.ListRequest? storageListRequest,
    $1.ListResponse? storageListResponse,
    $1.ReadRequest? storageReadRequest,
    $1.ReadResponse? storageReadResponse,
    $1.WriteRequest? storageWriteRequest,
    $1.DeleteRequest? storageDeleteRequest,
    $1.MkdirRequest? storageMkdirRequest,
    $1.Md5sumRequest? storageMd5sumRequest,
    $1.Md5sumResponse? storageMd5sumResponse,
    $2.StartRequest? appStartRequest,
    $2.LockStatusRequest? appLockStatusRequest,
    $2.LockStatusResponse? appLockStatusResponse,
    StopSession? stopSession,
    $3.StartScreenStreamRequest? guiStartScreenStreamRequest,
    $3.StopScreenStreamRequest? guiStopScreenStreamRequest,
    $3.ScreenFrame? guiScreenFrame,
    $3.SendInputEventRequest? guiSendInputEventRequest,
    $1.StatRequest? storageStatRequest,
    $1.StatResponse? storageStatResponse,
    $3.StartVirtualDisplayRequest? guiStartVirtualDisplayRequest,
    $3.StopVirtualDisplayRequest? guiStopVirtualDisplayRequest,
    $1.InfoRequest? storageInfoRequest,
    $1.InfoResponse? storageInfoResponse,
    $1.RenameRequest? storageRenameRequest,
    $0.RebootRequest? systemRebootRequest,
    $0.DeviceInfoRequest? systemDeviceInfoRequest,
    $0.DeviceInfoResponse? systemDeviceInfoResponse,
    $0.FactoryResetRequest? systemFactoryResetRequest,
    $0.GetDateTimeRequest? systemGetDatetimeRequest,
    $0.GetDateTimeResponse? systemGetDatetimeResponse,
    $0.SetDateTimeRequest? systemSetDatetimeRequest,
    $0.PlayAudiovisualAlertRequest? systemPlayAudiovisualAlertRequest,
    $0.ProtobufVersionRequest? systemProtobufVersionRequest,
    $0.ProtobufVersionResponse? systemProtobufVersionResponse,
    $0.UpdateRequest? systemUpdateRequest,
    $1.BackupCreateRequest? storageBackupCreateRequest,
    $1.BackupRestoreRequest? storageBackupRestoreRequest,
    $0.PowerInfoRequest? systemPowerInfoRequest,
    $0.PowerInfoResponse? systemPowerInfoResponse,
    $0.UpdateResponse? systemUpdateResponse,
    $2.AppExitRequest? appExitRequest,
    $2.AppLoadFileRequest? appLoadFileRequest,
    $2.AppButtonPressRequest? appButtonPressRequest,
    $2.AppButtonReleaseRequest? appButtonReleaseRequest,
    $4.SetPinMode? gpioSetPinMode,
    $4.SetInputPull? gpioSetInputPull,
    $4.GetPinMode? gpioGetPinMode,
    $4.GetPinModeResponse? gpioGetPinModeResponse,
    $4.ReadPin? gpioReadPin,
    $4.ReadPinResponse? gpioReadPinResponse,
    $4.WritePin? gpioWritePin,
    $2.AppStateResponse? appStateResponse,
    $1.TimestampRequest? storageTimestampRequest,
    $1.TimestampResponse? storageTimestampResponse,
    $5.GetRequest? propertyGetRequest,
    $5.GetResponse? propertyGetResponse,
    $2.GetErrorRequest? appGetErrorRequest,
    $2.GetErrorResponse? appGetErrorResponse,
    $2.DataExchangeRequest? appDataExchangeRequest,
    $6.IsLockedRequest? desktopIsLockedRequest,
    $6.UnlockRequest? desktopUnlockRequest,
    $6.StatusSubscribeRequest? desktopStatusSubscribeRequest,
    $6.StatusUnsubscribeRequest? desktopStatusUnsubscribeRequest,
    $6.Status? desktopStatus,
    $1.TarExtractRequest? storageTarExtractRequest,
    $4.GetOtgMode? gpioGetOtgMode,
    $4.GetOtgModeResponse? gpioGetOtgModeResponse,
    $4.SetOtgMode? gpioSetOtgMode,
    $2.AppButtonPressReleaseRequest? appButtonPressReleaseRequest,
  }) {
    final result = create();
    if (commandId != null) result.commandId = commandId;
    if (commandStatus != null) result.commandStatus = commandStatus;
    if (hasNext != null) result.hasNext = hasNext;
    if (empty != null) result.empty = empty;
    if (systemPingRequest != null) result.systemPingRequest = systemPingRequest;
    if (systemPingResponse != null)
      result.systemPingResponse = systemPingResponse;
    if (storageListRequest != null)
      result.storageListRequest = storageListRequest;
    if (storageListResponse != null)
      result.storageListResponse = storageListResponse;
    if (storageReadRequest != null)
      result.storageReadRequest = storageReadRequest;
    if (storageReadResponse != null)
      result.storageReadResponse = storageReadResponse;
    if (storageWriteRequest != null)
      result.storageWriteRequest = storageWriteRequest;
    if (storageDeleteRequest != null)
      result.storageDeleteRequest = storageDeleteRequest;
    if (storageMkdirRequest != null)
      result.storageMkdirRequest = storageMkdirRequest;
    if (storageMd5sumRequest != null)
      result.storageMd5sumRequest = storageMd5sumRequest;
    if (storageMd5sumResponse != null)
      result.storageMd5sumResponse = storageMd5sumResponse;
    if (appStartRequest != null) result.appStartRequest = appStartRequest;
    if (appLockStatusRequest != null)
      result.appLockStatusRequest = appLockStatusRequest;
    if (appLockStatusResponse != null)
      result.appLockStatusResponse = appLockStatusResponse;
    if (stopSession != null) result.stopSession = stopSession;
    if (guiStartScreenStreamRequest != null)
      result.guiStartScreenStreamRequest = guiStartScreenStreamRequest;
    if (guiStopScreenStreamRequest != null)
      result.guiStopScreenStreamRequest = guiStopScreenStreamRequest;
    if (guiScreenFrame != null) result.guiScreenFrame = guiScreenFrame;
    if (guiSendInputEventRequest != null)
      result.guiSendInputEventRequest = guiSendInputEventRequest;
    if (storageStatRequest != null)
      result.storageStatRequest = storageStatRequest;
    if (storageStatResponse != null)
      result.storageStatResponse = storageStatResponse;
    if (guiStartVirtualDisplayRequest != null)
      result.guiStartVirtualDisplayRequest = guiStartVirtualDisplayRequest;
    if (guiStopVirtualDisplayRequest != null)
      result.guiStopVirtualDisplayRequest = guiStopVirtualDisplayRequest;
    if (storageInfoRequest != null)
      result.storageInfoRequest = storageInfoRequest;
    if (storageInfoResponse != null)
      result.storageInfoResponse = storageInfoResponse;
    if (storageRenameRequest != null)
      result.storageRenameRequest = storageRenameRequest;
    if (systemRebootRequest != null)
      result.systemRebootRequest = systemRebootRequest;
    if (systemDeviceInfoRequest != null)
      result.systemDeviceInfoRequest = systemDeviceInfoRequest;
    if (systemDeviceInfoResponse != null)
      result.systemDeviceInfoResponse = systemDeviceInfoResponse;
    if (systemFactoryResetRequest != null)
      result.systemFactoryResetRequest = systemFactoryResetRequest;
    if (systemGetDatetimeRequest != null)
      result.systemGetDatetimeRequest = systemGetDatetimeRequest;
    if (systemGetDatetimeResponse != null)
      result.systemGetDatetimeResponse = systemGetDatetimeResponse;
    if (systemSetDatetimeRequest != null)
      result.systemSetDatetimeRequest = systemSetDatetimeRequest;
    if (systemPlayAudiovisualAlertRequest != null)
      result.systemPlayAudiovisualAlertRequest =
          systemPlayAudiovisualAlertRequest;
    if (systemProtobufVersionRequest != null)
      result.systemProtobufVersionRequest = systemProtobufVersionRequest;
    if (systemProtobufVersionResponse != null)
      result.systemProtobufVersionResponse = systemProtobufVersionResponse;
    if (systemUpdateRequest != null)
      result.systemUpdateRequest = systemUpdateRequest;
    if (storageBackupCreateRequest != null)
      result.storageBackupCreateRequest = storageBackupCreateRequest;
    if (storageBackupRestoreRequest != null)
      result.storageBackupRestoreRequest = storageBackupRestoreRequest;
    if (systemPowerInfoRequest != null)
      result.systemPowerInfoRequest = systemPowerInfoRequest;
    if (systemPowerInfoResponse != null)
      result.systemPowerInfoResponse = systemPowerInfoResponse;
    if (systemUpdateResponse != null)
      result.systemUpdateResponse = systemUpdateResponse;
    if (appExitRequest != null) result.appExitRequest = appExitRequest;
    if (appLoadFileRequest != null)
      result.appLoadFileRequest = appLoadFileRequest;
    if (appButtonPressRequest != null)
      result.appButtonPressRequest = appButtonPressRequest;
    if (appButtonReleaseRequest != null)
      result.appButtonReleaseRequest = appButtonReleaseRequest;
    if (gpioSetPinMode != null) result.gpioSetPinMode = gpioSetPinMode;
    if (gpioSetInputPull != null) result.gpioSetInputPull = gpioSetInputPull;
    if (gpioGetPinMode != null) result.gpioGetPinMode = gpioGetPinMode;
    if (gpioGetPinModeResponse != null)
      result.gpioGetPinModeResponse = gpioGetPinModeResponse;
    if (gpioReadPin != null) result.gpioReadPin = gpioReadPin;
    if (gpioReadPinResponse != null)
      result.gpioReadPinResponse = gpioReadPinResponse;
    if (gpioWritePin != null) result.gpioWritePin = gpioWritePin;
    if (appStateResponse != null) result.appStateResponse = appStateResponse;
    if (storageTimestampRequest != null)
      result.storageTimestampRequest = storageTimestampRequest;
    if (storageTimestampResponse != null)
      result.storageTimestampResponse = storageTimestampResponse;
    if (propertyGetRequest != null)
      result.propertyGetRequest = propertyGetRequest;
    if (propertyGetResponse != null)
      result.propertyGetResponse = propertyGetResponse;
    if (appGetErrorRequest != null)
      result.appGetErrorRequest = appGetErrorRequest;
    if (appGetErrorResponse != null)
      result.appGetErrorResponse = appGetErrorResponse;
    if (appDataExchangeRequest != null)
      result.appDataExchangeRequest = appDataExchangeRequest;
    if (desktopIsLockedRequest != null)
      result.desktopIsLockedRequest = desktopIsLockedRequest;
    if (desktopUnlockRequest != null)
      result.desktopUnlockRequest = desktopUnlockRequest;
    if (desktopStatusSubscribeRequest != null)
      result.desktopStatusSubscribeRequest = desktopStatusSubscribeRequest;
    if (desktopStatusUnsubscribeRequest != null)
      result.desktopStatusUnsubscribeRequest = desktopStatusUnsubscribeRequest;
    if (desktopStatus != null) result.desktopStatus = desktopStatus;
    if (storageTarExtractRequest != null)
      result.storageTarExtractRequest = storageTarExtractRequest;
    if (gpioGetOtgMode != null) result.gpioGetOtgMode = gpioGetOtgMode;
    if (gpioGetOtgModeResponse != null)
      result.gpioGetOtgModeResponse = gpioGetOtgModeResponse;
    if (gpioSetOtgMode != null) result.gpioSetOtgMode = gpioSetOtgMode;
    if (appButtonPressReleaseRequest != null)
      result.appButtonPressReleaseRequest = appButtonPressReleaseRequest;
    return result;
  }

  Main._();

  factory Main.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Main.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, Main_Content> _Main_ContentByTag = {
    4: Main_Content.empty,
    5: Main_Content.systemPingRequest,
    6: Main_Content.systemPingResponse,
    7: Main_Content.storageListRequest,
    8: Main_Content.storageListResponse,
    9: Main_Content.storageReadRequest,
    10: Main_Content.storageReadResponse,
    11: Main_Content.storageWriteRequest,
    12: Main_Content.storageDeleteRequest,
    13: Main_Content.storageMkdirRequest,
    14: Main_Content.storageMd5sumRequest,
    15: Main_Content.storageMd5sumResponse,
    16: Main_Content.appStartRequest,
    17: Main_Content.appLockStatusRequest,
    18: Main_Content.appLockStatusResponse,
    19: Main_Content.stopSession,
    20: Main_Content.guiStartScreenStreamRequest,
    21: Main_Content.guiStopScreenStreamRequest,
    22: Main_Content.guiScreenFrame,
    23: Main_Content.guiSendInputEventRequest,
    24: Main_Content.storageStatRequest,
    25: Main_Content.storageStatResponse,
    26: Main_Content.guiStartVirtualDisplayRequest,
    27: Main_Content.guiStopVirtualDisplayRequest,
    28: Main_Content.storageInfoRequest,
    29: Main_Content.storageInfoResponse,
    30: Main_Content.storageRenameRequest,
    31: Main_Content.systemRebootRequest,
    32: Main_Content.systemDeviceInfoRequest,
    33: Main_Content.systemDeviceInfoResponse,
    34: Main_Content.systemFactoryResetRequest,
    35: Main_Content.systemGetDatetimeRequest,
    36: Main_Content.systemGetDatetimeResponse,
    37: Main_Content.systemSetDatetimeRequest,
    38: Main_Content.systemPlayAudiovisualAlertRequest,
    39: Main_Content.systemProtobufVersionRequest,
    40: Main_Content.systemProtobufVersionResponse,
    41: Main_Content.systemUpdateRequest,
    42: Main_Content.storageBackupCreateRequest,
    43: Main_Content.storageBackupRestoreRequest,
    44: Main_Content.systemPowerInfoRequest,
    45: Main_Content.systemPowerInfoResponse,
    46: Main_Content.systemUpdateResponse,
    47: Main_Content.appExitRequest,
    48: Main_Content.appLoadFileRequest,
    49: Main_Content.appButtonPressRequest,
    50: Main_Content.appButtonReleaseRequest,
    51: Main_Content.gpioSetPinMode,
    52: Main_Content.gpioSetInputPull,
    53: Main_Content.gpioGetPinMode,
    54: Main_Content.gpioGetPinModeResponse,
    55: Main_Content.gpioReadPin,
    56: Main_Content.gpioReadPinResponse,
    57: Main_Content.gpioWritePin,
    58: Main_Content.appStateResponse,
    59: Main_Content.storageTimestampRequest,
    60: Main_Content.storageTimestampResponse,
    61: Main_Content.propertyGetRequest,
    62: Main_Content.propertyGetResponse,
    63: Main_Content.appGetErrorRequest,
    64: Main_Content.appGetErrorResponse,
    65: Main_Content.appDataExchangeRequest,
    66: Main_Content.desktopIsLockedRequest,
    67: Main_Content.desktopUnlockRequest,
    68: Main_Content.desktopStatusSubscribeRequest,
    69: Main_Content.desktopStatusUnsubscribeRequest,
    70: Main_Content.desktopStatus,
    71: Main_Content.storageTarExtractRequest,
    72: Main_Content.gpioGetOtgMode,
    73: Main_Content.gpioGetOtgModeResponse,
    74: Main_Content.gpioSetOtgMode,
    75: Main_Content.appButtonPressReleaseRequest,
    0: Main_Content.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Main',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB'),
      createEmptyInstance: create)
    ..oo(0, [
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
      20,
      21,
      22,
      23,
      24,
      25,
      26,
      27,
      28,
      29,
      30,
      31,
      32,
      33,
      34,
      35,
      36,
      37,
      38,
      39,
      40,
      41,
      42,
      43,
      44,
      45,
      46,
      47,
      48,
      49,
      50,
      51,
      52,
      53,
      54,
      55,
      56,
      57,
      58,
      59,
      60,
      61,
      62,
      63,
      64,
      65,
      66,
      67,
      68,
      69,
      70,
      71,
      72,
      73,
      74,
      75
    ])
    ..aI(1, _omitFieldNames ? '' : 'commandId', fieldType: $pb.PbFieldType.OU3)
    ..aE<CommandStatus>(2, _omitFieldNames ? '' : 'commandStatus',
        enumValues: CommandStatus.values)
    ..aOB(3, _omitFieldNames ? '' : 'hasNext')
    ..aOM<Empty>(4, _omitFieldNames ? '' : 'empty', subBuilder: Empty.create)
    ..aOM<$0.PingRequest>(5, _omitFieldNames ? '' : 'systemPingRequest',
        subBuilder: $0.PingRequest.create)
    ..aOM<$0.PingResponse>(6, _omitFieldNames ? '' : 'systemPingResponse',
        subBuilder: $0.PingResponse.create)
    ..aOM<$1.ListRequest>(7, _omitFieldNames ? '' : 'storageListRequest',
        subBuilder: $1.ListRequest.create)
    ..aOM<$1.ListResponse>(8, _omitFieldNames ? '' : 'storageListResponse',
        subBuilder: $1.ListResponse.create)
    ..aOM<$1.ReadRequest>(9, _omitFieldNames ? '' : 'storageReadRequest',
        subBuilder: $1.ReadRequest.create)
    ..aOM<$1.ReadResponse>(10, _omitFieldNames ? '' : 'storageReadResponse',
        subBuilder: $1.ReadResponse.create)
    ..aOM<$1.WriteRequest>(11, _omitFieldNames ? '' : 'storageWriteRequest',
        subBuilder: $1.WriteRequest.create)
    ..aOM<$1.DeleteRequest>(12, _omitFieldNames ? '' : 'storageDeleteRequest',
        subBuilder: $1.DeleteRequest.create)
    ..aOM<$1.MkdirRequest>(13, _omitFieldNames ? '' : 'storageMkdirRequest',
        subBuilder: $1.MkdirRequest.create)
    ..aOM<$1.Md5sumRequest>(14, _omitFieldNames ? '' : 'storageMd5sumRequest',
        subBuilder: $1.Md5sumRequest.create)
    ..aOM<$1.Md5sumResponse>(15, _omitFieldNames ? '' : 'storageMd5sumResponse',
        subBuilder: $1.Md5sumResponse.create)
    ..aOM<$2.StartRequest>(16, _omitFieldNames ? '' : 'appStartRequest',
        subBuilder: $2.StartRequest.create)
    ..aOM<$2.LockStatusRequest>(
        17, _omitFieldNames ? '' : 'appLockStatusRequest',
        subBuilder: $2.LockStatusRequest.create)
    ..aOM<$2.LockStatusResponse>(
        18, _omitFieldNames ? '' : 'appLockStatusResponse',
        subBuilder: $2.LockStatusResponse.create)
    ..aOM<StopSession>(19, _omitFieldNames ? '' : 'stopSession',
        subBuilder: StopSession.create)
    ..aOM<$3.StartScreenStreamRequest>(
        20, _omitFieldNames ? '' : 'guiStartScreenStreamRequest',
        subBuilder: $3.StartScreenStreamRequest.create)
    ..aOM<$3.StopScreenStreamRequest>(
        21, _omitFieldNames ? '' : 'guiStopScreenStreamRequest',
        subBuilder: $3.StopScreenStreamRequest.create)
    ..aOM<$3.ScreenFrame>(22, _omitFieldNames ? '' : 'guiScreenFrame',
        subBuilder: $3.ScreenFrame.create)
    ..aOM<$3.SendInputEventRequest>(
        23, _omitFieldNames ? '' : 'guiSendInputEventRequest',
        subBuilder: $3.SendInputEventRequest.create)
    ..aOM<$1.StatRequest>(24, _omitFieldNames ? '' : 'storageStatRequest',
        subBuilder: $1.StatRequest.create)
    ..aOM<$1.StatResponse>(25, _omitFieldNames ? '' : 'storageStatResponse',
        subBuilder: $1.StatResponse.create)
    ..aOM<$3.StartVirtualDisplayRequest>(
        26, _omitFieldNames ? '' : 'guiStartVirtualDisplayRequest',
        subBuilder: $3.StartVirtualDisplayRequest.create)
    ..aOM<$3.StopVirtualDisplayRequest>(
        27, _omitFieldNames ? '' : 'guiStopVirtualDisplayRequest',
        subBuilder: $3.StopVirtualDisplayRequest.create)
    ..aOM<$1.InfoRequest>(28, _omitFieldNames ? '' : 'storageInfoRequest',
        subBuilder: $1.InfoRequest.create)
    ..aOM<$1.InfoResponse>(29, _omitFieldNames ? '' : 'storageInfoResponse',
        subBuilder: $1.InfoResponse.create)
    ..aOM<$1.RenameRequest>(30, _omitFieldNames ? '' : 'storageRenameRequest',
        subBuilder: $1.RenameRequest.create)
    ..aOM<$0.RebootRequest>(31, _omitFieldNames ? '' : 'systemRebootRequest',
        subBuilder: $0.RebootRequest.create)
    ..aOM<$0.DeviceInfoRequest>(
        32, _omitFieldNames ? '' : 'systemDeviceInfoRequest',
        subBuilder: $0.DeviceInfoRequest.create)
    ..aOM<$0.DeviceInfoResponse>(
        33, _omitFieldNames ? '' : 'systemDeviceInfoResponse',
        subBuilder: $0.DeviceInfoResponse.create)
    ..aOM<$0.FactoryResetRequest>(
        34, _omitFieldNames ? '' : 'systemFactoryResetRequest',
        subBuilder: $0.FactoryResetRequest.create)
    ..aOM<$0.GetDateTimeRequest>(
        35, _omitFieldNames ? '' : 'systemGetDatetimeRequest',
        subBuilder: $0.GetDateTimeRequest.create)
    ..aOM<$0.GetDateTimeResponse>(
        36, _omitFieldNames ? '' : 'systemGetDatetimeResponse',
        subBuilder: $0.GetDateTimeResponse.create)
    ..aOM<$0.SetDateTimeRequest>(
        37, _omitFieldNames ? '' : 'systemSetDatetimeRequest',
        subBuilder: $0.SetDateTimeRequest.create)
    ..aOM<$0.PlayAudiovisualAlertRequest>(
        38, _omitFieldNames ? '' : 'systemPlayAudiovisualAlertRequest',
        subBuilder: $0.PlayAudiovisualAlertRequest.create)
    ..aOM<$0.ProtobufVersionRequest>(
        39, _omitFieldNames ? '' : 'systemProtobufVersionRequest',
        subBuilder: $0.ProtobufVersionRequest.create)
    ..aOM<$0.ProtobufVersionResponse>(
        40, _omitFieldNames ? '' : 'systemProtobufVersionResponse',
        subBuilder: $0.ProtobufVersionResponse.create)
    ..aOM<$0.UpdateRequest>(41, _omitFieldNames ? '' : 'systemUpdateRequest',
        subBuilder: $0.UpdateRequest.create)
    ..aOM<$1.BackupCreateRequest>(
        42, _omitFieldNames ? '' : 'storageBackupCreateRequest',
        subBuilder: $1.BackupCreateRequest.create)
    ..aOM<$1.BackupRestoreRequest>(
        43, _omitFieldNames ? '' : 'storageBackupRestoreRequest',
        subBuilder: $1.BackupRestoreRequest.create)
    ..aOM<$0.PowerInfoRequest>(
        44, _omitFieldNames ? '' : 'systemPowerInfoRequest',
        subBuilder: $0.PowerInfoRequest.create)
    ..aOM<$0.PowerInfoResponse>(
        45, _omitFieldNames ? '' : 'systemPowerInfoResponse',
        subBuilder: $0.PowerInfoResponse.create)
    ..aOM<$0.UpdateResponse>(46, _omitFieldNames ? '' : 'systemUpdateResponse',
        subBuilder: $0.UpdateResponse.create)
    ..aOM<$2.AppExitRequest>(47, _omitFieldNames ? '' : 'appExitRequest',
        subBuilder: $2.AppExitRequest.create)
    ..aOM<$2.AppLoadFileRequest>(
        48, _omitFieldNames ? '' : 'appLoadFileRequest',
        subBuilder: $2.AppLoadFileRequest.create)
    ..aOM<$2.AppButtonPressRequest>(
        49, _omitFieldNames ? '' : 'appButtonPressRequest',
        subBuilder: $2.AppButtonPressRequest.create)
    ..aOM<$2.AppButtonReleaseRequest>(
        50, _omitFieldNames ? '' : 'appButtonReleaseRequest',
        subBuilder: $2.AppButtonReleaseRequest.create)
    ..aOM<$4.SetPinMode>(51, _omitFieldNames ? '' : 'gpioSetPinMode',
        subBuilder: $4.SetPinMode.create)
    ..aOM<$4.SetInputPull>(52, _omitFieldNames ? '' : 'gpioSetInputPull',
        subBuilder: $4.SetInputPull.create)
    ..aOM<$4.GetPinMode>(53, _omitFieldNames ? '' : 'gpioGetPinMode',
        subBuilder: $4.GetPinMode.create)
    ..aOM<$4.GetPinModeResponse>(
        54, _omitFieldNames ? '' : 'gpioGetPinModeResponse',
        subBuilder: $4.GetPinModeResponse.create)
    ..aOM<$4.ReadPin>(55, _omitFieldNames ? '' : 'gpioReadPin',
        subBuilder: $4.ReadPin.create)
    ..aOM<$4.ReadPinResponse>(56, _omitFieldNames ? '' : 'gpioReadPinResponse',
        subBuilder: $4.ReadPinResponse.create)
    ..aOM<$4.WritePin>(57, _omitFieldNames ? '' : 'gpioWritePin',
        subBuilder: $4.WritePin.create)
    ..aOM<$2.AppStateResponse>(58, _omitFieldNames ? '' : 'appStateResponse',
        subBuilder: $2.AppStateResponse.create)
    ..aOM<$1.TimestampRequest>(
        59, _omitFieldNames ? '' : 'storageTimestampRequest',
        subBuilder: $1.TimestampRequest.create)
    ..aOM<$1.TimestampResponse>(
        60, _omitFieldNames ? '' : 'storageTimestampResponse',
        subBuilder: $1.TimestampResponse.create)
    ..aOM<$5.GetRequest>(61, _omitFieldNames ? '' : 'propertyGetRequest',
        subBuilder: $5.GetRequest.create)
    ..aOM<$5.GetResponse>(62, _omitFieldNames ? '' : 'propertyGetResponse',
        subBuilder: $5.GetResponse.create)
    ..aOM<$2.GetErrorRequest>(63, _omitFieldNames ? '' : 'appGetErrorRequest',
        subBuilder: $2.GetErrorRequest.create)
    ..aOM<$2.GetErrorResponse>(64, _omitFieldNames ? '' : 'appGetErrorResponse',
        subBuilder: $2.GetErrorResponse.create)
    ..aOM<$2.DataExchangeRequest>(
        65, _omitFieldNames ? '' : 'appDataExchangeRequest',
        subBuilder: $2.DataExchangeRequest.create)
    ..aOM<$6.IsLockedRequest>(
        66, _omitFieldNames ? '' : 'desktopIsLockedRequest',
        subBuilder: $6.IsLockedRequest.create)
    ..aOM<$6.UnlockRequest>(67, _omitFieldNames ? '' : 'desktopUnlockRequest',
        subBuilder: $6.UnlockRequest.create)
    ..aOM<$6.StatusSubscribeRequest>(
        68, _omitFieldNames ? '' : 'desktopStatusSubscribeRequest',
        subBuilder: $6.StatusSubscribeRequest.create)
    ..aOM<$6.StatusUnsubscribeRequest>(
        69, _omitFieldNames ? '' : 'desktopStatusUnsubscribeRequest',
        subBuilder: $6.StatusUnsubscribeRequest.create)
    ..aOM<$6.Status>(70, _omitFieldNames ? '' : 'desktopStatus',
        subBuilder: $6.Status.create)
    ..aOM<$1.TarExtractRequest>(
        71, _omitFieldNames ? '' : 'storageTarExtractRequest',
        subBuilder: $1.TarExtractRequest.create)
    ..aOM<$4.GetOtgMode>(72, _omitFieldNames ? '' : 'gpioGetOtgMode',
        subBuilder: $4.GetOtgMode.create)
    ..aOM<$4.GetOtgModeResponse>(
        73, _omitFieldNames ? '' : 'gpioGetOtgModeResponse',
        subBuilder: $4.GetOtgModeResponse.create)
    ..aOM<$4.SetOtgMode>(74, _omitFieldNames ? '' : 'gpioSetOtgMode',
        subBuilder: $4.SetOtgMode.create)
    ..aOM<$2.AppButtonPressReleaseRequest>(
        75, _omitFieldNames ? '' : 'appButtonPressReleaseRequest',
        subBuilder: $2.AppButtonPressReleaseRequest.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Main clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Main copyWith(void Function(Main) updates) =>
      super.copyWith((message) => updates(message as Main)) as Main;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Main create() => Main._();
  @$core.override
  Main createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Main getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Main>(create);
  static Main? _defaultInstance;

  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  @$pb.TagNumber(19)
  @$pb.TagNumber(20)
  @$pb.TagNumber(21)
  @$pb.TagNumber(22)
  @$pb.TagNumber(23)
  @$pb.TagNumber(24)
  @$pb.TagNumber(25)
  @$pb.TagNumber(26)
  @$pb.TagNumber(27)
  @$pb.TagNumber(28)
  @$pb.TagNumber(29)
  @$pb.TagNumber(30)
  @$pb.TagNumber(31)
  @$pb.TagNumber(32)
  @$pb.TagNumber(33)
  @$pb.TagNumber(34)
  @$pb.TagNumber(35)
  @$pb.TagNumber(36)
  @$pb.TagNumber(37)
  @$pb.TagNumber(38)
  @$pb.TagNumber(39)
  @$pb.TagNumber(40)
  @$pb.TagNumber(41)
  @$pb.TagNumber(42)
  @$pb.TagNumber(43)
  @$pb.TagNumber(44)
  @$pb.TagNumber(45)
  @$pb.TagNumber(46)
  @$pb.TagNumber(47)
  @$pb.TagNumber(48)
  @$pb.TagNumber(49)
  @$pb.TagNumber(50)
  @$pb.TagNumber(51)
  @$pb.TagNumber(52)
  @$pb.TagNumber(53)
  @$pb.TagNumber(54)
  @$pb.TagNumber(55)
  @$pb.TagNumber(56)
  @$pb.TagNumber(57)
  @$pb.TagNumber(58)
  @$pb.TagNumber(59)
  @$pb.TagNumber(60)
  @$pb.TagNumber(61)
  @$pb.TagNumber(62)
  @$pb.TagNumber(63)
  @$pb.TagNumber(64)
  @$pb.TagNumber(65)
  @$pb.TagNumber(66)
  @$pb.TagNumber(67)
  @$pb.TagNumber(68)
  @$pb.TagNumber(69)
  @$pb.TagNumber(70)
  @$pb.TagNumber(71)
  @$pb.TagNumber(72)
  @$pb.TagNumber(73)
  @$pb.TagNumber(74)
  @$pb.TagNumber(75)
  Main_Content whichContent() => _Main_ContentByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  @$pb.TagNumber(19)
  @$pb.TagNumber(20)
  @$pb.TagNumber(21)
  @$pb.TagNumber(22)
  @$pb.TagNumber(23)
  @$pb.TagNumber(24)
  @$pb.TagNumber(25)
  @$pb.TagNumber(26)
  @$pb.TagNumber(27)
  @$pb.TagNumber(28)
  @$pb.TagNumber(29)
  @$pb.TagNumber(30)
  @$pb.TagNumber(31)
  @$pb.TagNumber(32)
  @$pb.TagNumber(33)
  @$pb.TagNumber(34)
  @$pb.TagNumber(35)
  @$pb.TagNumber(36)
  @$pb.TagNumber(37)
  @$pb.TagNumber(38)
  @$pb.TagNumber(39)
  @$pb.TagNumber(40)
  @$pb.TagNumber(41)
  @$pb.TagNumber(42)
  @$pb.TagNumber(43)
  @$pb.TagNumber(44)
  @$pb.TagNumber(45)
  @$pb.TagNumber(46)
  @$pb.TagNumber(47)
  @$pb.TagNumber(48)
  @$pb.TagNumber(49)
  @$pb.TagNumber(50)
  @$pb.TagNumber(51)
  @$pb.TagNumber(52)
  @$pb.TagNumber(53)
  @$pb.TagNumber(54)
  @$pb.TagNumber(55)
  @$pb.TagNumber(56)
  @$pb.TagNumber(57)
  @$pb.TagNumber(58)
  @$pb.TagNumber(59)
  @$pb.TagNumber(60)
  @$pb.TagNumber(61)
  @$pb.TagNumber(62)
  @$pb.TagNumber(63)
  @$pb.TagNumber(64)
  @$pb.TagNumber(65)
  @$pb.TagNumber(66)
  @$pb.TagNumber(67)
  @$pb.TagNumber(68)
  @$pb.TagNumber(69)
  @$pb.TagNumber(70)
  @$pb.TagNumber(71)
  @$pb.TagNumber(72)
  @$pb.TagNumber(73)
  @$pb.TagNumber(74)
  @$pb.TagNumber(75)
  void clearContent() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.int get commandId => $_getIZ(0);
  @$pb.TagNumber(1)
  set commandId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCommandId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCommandId() => $_clearField(1);

  @$pb.TagNumber(2)
  CommandStatus get commandStatus => $_getN(1);
  @$pb.TagNumber(2)
  set commandStatus(CommandStatus value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasCommandStatus() => $_has(1);
  @$pb.TagNumber(2)
  void clearCommandStatus() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get hasNext => $_getBF(2);
  @$pb.TagNumber(3)
  set hasNext($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasHasNext() => $_has(2);
  @$pb.TagNumber(3)
  void clearHasNext() => $_clearField(3);

  @$pb.TagNumber(4)
  Empty get empty => $_getN(3);
  @$pb.TagNumber(4)
  set empty(Empty value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasEmpty() => $_has(3);
  @$pb.TagNumber(4)
  void clearEmpty() => $_clearField(4);
  @$pb.TagNumber(4)
  Empty ensureEmpty() => $_ensure(3);

  @$pb.TagNumber(5)
  $0.PingRequest get systemPingRequest => $_getN(4);
  @$pb.TagNumber(5)
  set systemPingRequest($0.PingRequest value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasSystemPingRequest() => $_has(4);
  @$pb.TagNumber(5)
  void clearSystemPingRequest() => $_clearField(5);
  @$pb.TagNumber(5)
  $0.PingRequest ensureSystemPingRequest() => $_ensure(4);

  @$pb.TagNumber(6)
  $0.PingResponse get systemPingResponse => $_getN(5);
  @$pb.TagNumber(6)
  set systemPingResponse($0.PingResponse value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasSystemPingResponse() => $_has(5);
  @$pb.TagNumber(6)
  void clearSystemPingResponse() => $_clearField(6);
  @$pb.TagNumber(6)
  $0.PingResponse ensureSystemPingResponse() => $_ensure(5);

  @$pb.TagNumber(7)
  $1.ListRequest get storageListRequest => $_getN(6);
  @$pb.TagNumber(7)
  set storageListRequest($1.ListRequest value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasStorageListRequest() => $_has(6);
  @$pb.TagNumber(7)
  void clearStorageListRequest() => $_clearField(7);
  @$pb.TagNumber(7)
  $1.ListRequest ensureStorageListRequest() => $_ensure(6);

  @$pb.TagNumber(8)
  $1.ListResponse get storageListResponse => $_getN(7);
  @$pb.TagNumber(8)
  set storageListResponse($1.ListResponse value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasStorageListResponse() => $_has(7);
  @$pb.TagNumber(8)
  void clearStorageListResponse() => $_clearField(8);
  @$pb.TagNumber(8)
  $1.ListResponse ensureStorageListResponse() => $_ensure(7);

  @$pb.TagNumber(9)
  $1.ReadRequest get storageReadRequest => $_getN(8);
  @$pb.TagNumber(9)
  set storageReadRequest($1.ReadRequest value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasStorageReadRequest() => $_has(8);
  @$pb.TagNumber(9)
  void clearStorageReadRequest() => $_clearField(9);
  @$pb.TagNumber(9)
  $1.ReadRequest ensureStorageReadRequest() => $_ensure(8);

  @$pb.TagNumber(10)
  $1.ReadResponse get storageReadResponse => $_getN(9);
  @$pb.TagNumber(10)
  set storageReadResponse($1.ReadResponse value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasStorageReadResponse() => $_has(9);
  @$pb.TagNumber(10)
  void clearStorageReadResponse() => $_clearField(10);
  @$pb.TagNumber(10)
  $1.ReadResponse ensureStorageReadResponse() => $_ensure(9);

  @$pb.TagNumber(11)
  $1.WriteRequest get storageWriteRequest => $_getN(10);
  @$pb.TagNumber(11)
  set storageWriteRequest($1.WriteRequest value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasStorageWriteRequest() => $_has(10);
  @$pb.TagNumber(11)
  void clearStorageWriteRequest() => $_clearField(11);
  @$pb.TagNumber(11)
  $1.WriteRequest ensureStorageWriteRequest() => $_ensure(10);

  @$pb.TagNumber(12)
  $1.DeleteRequest get storageDeleteRequest => $_getN(11);
  @$pb.TagNumber(12)
  set storageDeleteRequest($1.DeleteRequest value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasStorageDeleteRequest() => $_has(11);
  @$pb.TagNumber(12)
  void clearStorageDeleteRequest() => $_clearField(12);
  @$pb.TagNumber(12)
  $1.DeleteRequest ensureStorageDeleteRequest() => $_ensure(11);

  @$pb.TagNumber(13)
  $1.MkdirRequest get storageMkdirRequest => $_getN(12);
  @$pb.TagNumber(13)
  set storageMkdirRequest($1.MkdirRequest value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasStorageMkdirRequest() => $_has(12);
  @$pb.TagNumber(13)
  void clearStorageMkdirRequest() => $_clearField(13);
  @$pb.TagNumber(13)
  $1.MkdirRequest ensureStorageMkdirRequest() => $_ensure(12);

  @$pb.TagNumber(14)
  $1.Md5sumRequest get storageMd5sumRequest => $_getN(13);
  @$pb.TagNumber(14)
  set storageMd5sumRequest($1.Md5sumRequest value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasStorageMd5sumRequest() => $_has(13);
  @$pb.TagNumber(14)
  void clearStorageMd5sumRequest() => $_clearField(14);
  @$pb.TagNumber(14)
  $1.Md5sumRequest ensureStorageMd5sumRequest() => $_ensure(13);

  @$pb.TagNumber(15)
  $1.Md5sumResponse get storageMd5sumResponse => $_getN(14);
  @$pb.TagNumber(15)
  set storageMd5sumResponse($1.Md5sumResponse value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasStorageMd5sumResponse() => $_has(14);
  @$pb.TagNumber(15)
  void clearStorageMd5sumResponse() => $_clearField(15);
  @$pb.TagNumber(15)
  $1.Md5sumResponse ensureStorageMd5sumResponse() => $_ensure(14);

  @$pb.TagNumber(16)
  $2.StartRequest get appStartRequest => $_getN(15);
  @$pb.TagNumber(16)
  set appStartRequest($2.StartRequest value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasAppStartRequest() => $_has(15);
  @$pb.TagNumber(16)
  void clearAppStartRequest() => $_clearField(16);
  @$pb.TagNumber(16)
  $2.StartRequest ensureAppStartRequest() => $_ensure(15);

  @$pb.TagNumber(17)
  $2.LockStatusRequest get appLockStatusRequest => $_getN(16);
  @$pb.TagNumber(17)
  set appLockStatusRequest($2.LockStatusRequest value) => $_setField(17, value);
  @$pb.TagNumber(17)
  $core.bool hasAppLockStatusRequest() => $_has(16);
  @$pb.TagNumber(17)
  void clearAppLockStatusRequest() => $_clearField(17);
  @$pb.TagNumber(17)
  $2.LockStatusRequest ensureAppLockStatusRequest() => $_ensure(16);

  @$pb.TagNumber(18)
  $2.LockStatusResponse get appLockStatusResponse => $_getN(17);
  @$pb.TagNumber(18)
  set appLockStatusResponse($2.LockStatusResponse value) =>
      $_setField(18, value);
  @$pb.TagNumber(18)
  $core.bool hasAppLockStatusResponse() => $_has(17);
  @$pb.TagNumber(18)
  void clearAppLockStatusResponse() => $_clearField(18);
  @$pb.TagNumber(18)
  $2.LockStatusResponse ensureAppLockStatusResponse() => $_ensure(17);

  @$pb.TagNumber(19)
  StopSession get stopSession => $_getN(18);
  @$pb.TagNumber(19)
  set stopSession(StopSession value) => $_setField(19, value);
  @$pb.TagNumber(19)
  $core.bool hasStopSession() => $_has(18);
  @$pb.TagNumber(19)
  void clearStopSession() => $_clearField(19);
  @$pb.TagNumber(19)
  StopSession ensureStopSession() => $_ensure(18);

  @$pb.TagNumber(20)
  $3.StartScreenStreamRequest get guiStartScreenStreamRequest => $_getN(19);
  @$pb.TagNumber(20)
  set guiStartScreenStreamRequest($3.StartScreenStreamRequest value) =>
      $_setField(20, value);
  @$pb.TagNumber(20)
  $core.bool hasGuiStartScreenStreamRequest() => $_has(19);
  @$pb.TagNumber(20)
  void clearGuiStartScreenStreamRequest() => $_clearField(20);
  @$pb.TagNumber(20)
  $3.StartScreenStreamRequest ensureGuiStartScreenStreamRequest() =>
      $_ensure(19);

  @$pb.TagNumber(21)
  $3.StopScreenStreamRequest get guiStopScreenStreamRequest => $_getN(20);
  @$pb.TagNumber(21)
  set guiStopScreenStreamRequest($3.StopScreenStreamRequest value) =>
      $_setField(21, value);
  @$pb.TagNumber(21)
  $core.bool hasGuiStopScreenStreamRequest() => $_has(20);
  @$pb.TagNumber(21)
  void clearGuiStopScreenStreamRequest() => $_clearField(21);
  @$pb.TagNumber(21)
  $3.StopScreenStreamRequest ensureGuiStopScreenStreamRequest() => $_ensure(20);

  @$pb.TagNumber(22)
  $3.ScreenFrame get guiScreenFrame => $_getN(21);
  @$pb.TagNumber(22)
  set guiScreenFrame($3.ScreenFrame value) => $_setField(22, value);
  @$pb.TagNumber(22)
  $core.bool hasGuiScreenFrame() => $_has(21);
  @$pb.TagNumber(22)
  void clearGuiScreenFrame() => $_clearField(22);
  @$pb.TagNumber(22)
  $3.ScreenFrame ensureGuiScreenFrame() => $_ensure(21);

  @$pb.TagNumber(23)
  $3.SendInputEventRequest get guiSendInputEventRequest => $_getN(22);
  @$pb.TagNumber(23)
  set guiSendInputEventRequest($3.SendInputEventRequest value) =>
      $_setField(23, value);
  @$pb.TagNumber(23)
  $core.bool hasGuiSendInputEventRequest() => $_has(22);
  @$pb.TagNumber(23)
  void clearGuiSendInputEventRequest() => $_clearField(23);
  @$pb.TagNumber(23)
  $3.SendInputEventRequest ensureGuiSendInputEventRequest() => $_ensure(22);

  @$pb.TagNumber(24)
  $1.StatRequest get storageStatRequest => $_getN(23);
  @$pb.TagNumber(24)
  set storageStatRequest($1.StatRequest value) => $_setField(24, value);
  @$pb.TagNumber(24)
  $core.bool hasStorageStatRequest() => $_has(23);
  @$pb.TagNumber(24)
  void clearStorageStatRequest() => $_clearField(24);
  @$pb.TagNumber(24)
  $1.StatRequest ensureStorageStatRequest() => $_ensure(23);

  @$pb.TagNumber(25)
  $1.StatResponse get storageStatResponse => $_getN(24);
  @$pb.TagNumber(25)
  set storageStatResponse($1.StatResponse value) => $_setField(25, value);
  @$pb.TagNumber(25)
  $core.bool hasStorageStatResponse() => $_has(24);
  @$pb.TagNumber(25)
  void clearStorageStatResponse() => $_clearField(25);
  @$pb.TagNumber(25)
  $1.StatResponse ensureStorageStatResponse() => $_ensure(24);

  @$pb.TagNumber(26)
  $3.StartVirtualDisplayRequest get guiStartVirtualDisplayRequest => $_getN(25);
  @$pb.TagNumber(26)
  set guiStartVirtualDisplayRequest($3.StartVirtualDisplayRequest value) =>
      $_setField(26, value);
  @$pb.TagNumber(26)
  $core.bool hasGuiStartVirtualDisplayRequest() => $_has(25);
  @$pb.TagNumber(26)
  void clearGuiStartVirtualDisplayRequest() => $_clearField(26);
  @$pb.TagNumber(26)
  $3.StartVirtualDisplayRequest ensureGuiStartVirtualDisplayRequest() =>
      $_ensure(25);

  @$pb.TagNumber(27)
  $3.StopVirtualDisplayRequest get guiStopVirtualDisplayRequest => $_getN(26);
  @$pb.TagNumber(27)
  set guiStopVirtualDisplayRequest($3.StopVirtualDisplayRequest value) =>
      $_setField(27, value);
  @$pb.TagNumber(27)
  $core.bool hasGuiStopVirtualDisplayRequest() => $_has(26);
  @$pb.TagNumber(27)
  void clearGuiStopVirtualDisplayRequest() => $_clearField(27);
  @$pb.TagNumber(27)
  $3.StopVirtualDisplayRequest ensureGuiStopVirtualDisplayRequest() =>
      $_ensure(26);

  @$pb.TagNumber(28)
  $1.InfoRequest get storageInfoRequest => $_getN(27);
  @$pb.TagNumber(28)
  set storageInfoRequest($1.InfoRequest value) => $_setField(28, value);
  @$pb.TagNumber(28)
  $core.bool hasStorageInfoRequest() => $_has(27);
  @$pb.TagNumber(28)
  void clearStorageInfoRequest() => $_clearField(28);
  @$pb.TagNumber(28)
  $1.InfoRequest ensureStorageInfoRequest() => $_ensure(27);

  @$pb.TagNumber(29)
  $1.InfoResponse get storageInfoResponse => $_getN(28);
  @$pb.TagNumber(29)
  set storageInfoResponse($1.InfoResponse value) => $_setField(29, value);
  @$pb.TagNumber(29)
  $core.bool hasStorageInfoResponse() => $_has(28);
  @$pb.TagNumber(29)
  void clearStorageInfoResponse() => $_clearField(29);
  @$pb.TagNumber(29)
  $1.InfoResponse ensureStorageInfoResponse() => $_ensure(28);

  @$pb.TagNumber(30)
  $1.RenameRequest get storageRenameRequest => $_getN(29);
  @$pb.TagNumber(30)
  set storageRenameRequest($1.RenameRequest value) => $_setField(30, value);
  @$pb.TagNumber(30)
  $core.bool hasStorageRenameRequest() => $_has(29);
  @$pb.TagNumber(30)
  void clearStorageRenameRequest() => $_clearField(30);
  @$pb.TagNumber(30)
  $1.RenameRequest ensureStorageRenameRequest() => $_ensure(29);

  @$pb.TagNumber(31)
  $0.RebootRequest get systemRebootRequest => $_getN(30);
  @$pb.TagNumber(31)
  set systemRebootRequest($0.RebootRequest value) => $_setField(31, value);
  @$pb.TagNumber(31)
  $core.bool hasSystemRebootRequest() => $_has(30);
  @$pb.TagNumber(31)
  void clearSystemRebootRequest() => $_clearField(31);
  @$pb.TagNumber(31)
  $0.RebootRequest ensureSystemRebootRequest() => $_ensure(30);

  @$pb.TagNumber(32)
  $0.DeviceInfoRequest get systemDeviceInfoRequest => $_getN(31);
  @$pb.TagNumber(32)
  set systemDeviceInfoRequest($0.DeviceInfoRequest value) =>
      $_setField(32, value);
  @$pb.TagNumber(32)
  $core.bool hasSystemDeviceInfoRequest() => $_has(31);
  @$pb.TagNumber(32)
  void clearSystemDeviceInfoRequest() => $_clearField(32);
  @$pb.TagNumber(32)
  $0.DeviceInfoRequest ensureSystemDeviceInfoRequest() => $_ensure(31);

  @$pb.TagNumber(33)
  $0.DeviceInfoResponse get systemDeviceInfoResponse => $_getN(32);
  @$pb.TagNumber(33)
  set systemDeviceInfoResponse($0.DeviceInfoResponse value) =>
      $_setField(33, value);
  @$pb.TagNumber(33)
  $core.bool hasSystemDeviceInfoResponse() => $_has(32);
  @$pb.TagNumber(33)
  void clearSystemDeviceInfoResponse() => $_clearField(33);
  @$pb.TagNumber(33)
  $0.DeviceInfoResponse ensureSystemDeviceInfoResponse() => $_ensure(32);

  @$pb.TagNumber(34)
  $0.FactoryResetRequest get systemFactoryResetRequest => $_getN(33);
  @$pb.TagNumber(34)
  set systemFactoryResetRequest($0.FactoryResetRequest value) =>
      $_setField(34, value);
  @$pb.TagNumber(34)
  $core.bool hasSystemFactoryResetRequest() => $_has(33);
  @$pb.TagNumber(34)
  void clearSystemFactoryResetRequest() => $_clearField(34);
  @$pb.TagNumber(34)
  $0.FactoryResetRequest ensureSystemFactoryResetRequest() => $_ensure(33);

  @$pb.TagNumber(35)
  $0.GetDateTimeRequest get systemGetDatetimeRequest => $_getN(34);
  @$pb.TagNumber(35)
  set systemGetDatetimeRequest($0.GetDateTimeRequest value) =>
      $_setField(35, value);
  @$pb.TagNumber(35)
  $core.bool hasSystemGetDatetimeRequest() => $_has(34);
  @$pb.TagNumber(35)
  void clearSystemGetDatetimeRequest() => $_clearField(35);
  @$pb.TagNumber(35)
  $0.GetDateTimeRequest ensureSystemGetDatetimeRequest() => $_ensure(34);

  @$pb.TagNumber(36)
  $0.GetDateTimeResponse get systemGetDatetimeResponse => $_getN(35);
  @$pb.TagNumber(36)
  set systemGetDatetimeResponse($0.GetDateTimeResponse value) =>
      $_setField(36, value);
  @$pb.TagNumber(36)
  $core.bool hasSystemGetDatetimeResponse() => $_has(35);
  @$pb.TagNumber(36)
  void clearSystemGetDatetimeResponse() => $_clearField(36);
  @$pb.TagNumber(36)
  $0.GetDateTimeResponse ensureSystemGetDatetimeResponse() => $_ensure(35);

  @$pb.TagNumber(37)
  $0.SetDateTimeRequest get systemSetDatetimeRequest => $_getN(36);
  @$pb.TagNumber(37)
  set systemSetDatetimeRequest($0.SetDateTimeRequest value) =>
      $_setField(37, value);
  @$pb.TagNumber(37)
  $core.bool hasSystemSetDatetimeRequest() => $_has(36);
  @$pb.TagNumber(37)
  void clearSystemSetDatetimeRequest() => $_clearField(37);
  @$pb.TagNumber(37)
  $0.SetDateTimeRequest ensureSystemSetDatetimeRequest() => $_ensure(36);

  @$pb.TagNumber(38)
  $0.PlayAudiovisualAlertRequest get systemPlayAudiovisualAlertRequest =>
      $_getN(37);
  @$pb.TagNumber(38)
  set systemPlayAudiovisualAlertRequest($0.PlayAudiovisualAlertRequest value) =>
      $_setField(38, value);
  @$pb.TagNumber(38)
  $core.bool hasSystemPlayAudiovisualAlertRequest() => $_has(37);
  @$pb.TagNumber(38)
  void clearSystemPlayAudiovisualAlertRequest() => $_clearField(38);
  @$pb.TagNumber(38)
  $0.PlayAudiovisualAlertRequest ensureSystemPlayAudiovisualAlertRequest() =>
      $_ensure(37);

  @$pb.TagNumber(39)
  $0.ProtobufVersionRequest get systemProtobufVersionRequest => $_getN(38);
  @$pb.TagNumber(39)
  set systemProtobufVersionRequest($0.ProtobufVersionRequest value) =>
      $_setField(39, value);
  @$pb.TagNumber(39)
  $core.bool hasSystemProtobufVersionRequest() => $_has(38);
  @$pb.TagNumber(39)
  void clearSystemProtobufVersionRequest() => $_clearField(39);
  @$pb.TagNumber(39)
  $0.ProtobufVersionRequest ensureSystemProtobufVersionRequest() =>
      $_ensure(38);

  @$pb.TagNumber(40)
  $0.ProtobufVersionResponse get systemProtobufVersionResponse => $_getN(39);
  @$pb.TagNumber(40)
  set systemProtobufVersionResponse($0.ProtobufVersionResponse value) =>
      $_setField(40, value);
  @$pb.TagNumber(40)
  $core.bool hasSystemProtobufVersionResponse() => $_has(39);
  @$pb.TagNumber(40)
  void clearSystemProtobufVersionResponse() => $_clearField(40);
  @$pb.TagNumber(40)
  $0.ProtobufVersionResponse ensureSystemProtobufVersionResponse() =>
      $_ensure(39);

  @$pb.TagNumber(41)
  $0.UpdateRequest get systemUpdateRequest => $_getN(40);
  @$pb.TagNumber(41)
  set systemUpdateRequest($0.UpdateRequest value) => $_setField(41, value);
  @$pb.TagNumber(41)
  $core.bool hasSystemUpdateRequest() => $_has(40);
  @$pb.TagNumber(41)
  void clearSystemUpdateRequest() => $_clearField(41);
  @$pb.TagNumber(41)
  $0.UpdateRequest ensureSystemUpdateRequest() => $_ensure(40);

  @$pb.TagNumber(42)
  $1.BackupCreateRequest get storageBackupCreateRequest => $_getN(41);
  @$pb.TagNumber(42)
  set storageBackupCreateRequest($1.BackupCreateRequest value) =>
      $_setField(42, value);
  @$pb.TagNumber(42)
  $core.bool hasStorageBackupCreateRequest() => $_has(41);
  @$pb.TagNumber(42)
  void clearStorageBackupCreateRequest() => $_clearField(42);
  @$pb.TagNumber(42)
  $1.BackupCreateRequest ensureStorageBackupCreateRequest() => $_ensure(41);

  @$pb.TagNumber(43)
  $1.BackupRestoreRequest get storageBackupRestoreRequest => $_getN(42);
  @$pb.TagNumber(43)
  set storageBackupRestoreRequest($1.BackupRestoreRequest value) =>
      $_setField(43, value);
  @$pb.TagNumber(43)
  $core.bool hasStorageBackupRestoreRequest() => $_has(42);
  @$pb.TagNumber(43)
  void clearStorageBackupRestoreRequest() => $_clearField(43);
  @$pb.TagNumber(43)
  $1.BackupRestoreRequest ensureStorageBackupRestoreRequest() => $_ensure(42);

  @$pb.TagNumber(44)
  $0.PowerInfoRequest get systemPowerInfoRequest => $_getN(43);
  @$pb.TagNumber(44)
  set systemPowerInfoRequest($0.PowerInfoRequest value) =>
      $_setField(44, value);
  @$pb.TagNumber(44)
  $core.bool hasSystemPowerInfoRequest() => $_has(43);
  @$pb.TagNumber(44)
  void clearSystemPowerInfoRequest() => $_clearField(44);
  @$pb.TagNumber(44)
  $0.PowerInfoRequest ensureSystemPowerInfoRequest() => $_ensure(43);

  @$pb.TagNumber(45)
  $0.PowerInfoResponse get systemPowerInfoResponse => $_getN(44);
  @$pb.TagNumber(45)
  set systemPowerInfoResponse($0.PowerInfoResponse value) =>
      $_setField(45, value);
  @$pb.TagNumber(45)
  $core.bool hasSystemPowerInfoResponse() => $_has(44);
  @$pb.TagNumber(45)
  void clearSystemPowerInfoResponse() => $_clearField(45);
  @$pb.TagNumber(45)
  $0.PowerInfoResponse ensureSystemPowerInfoResponse() => $_ensure(44);

  @$pb.TagNumber(46)
  $0.UpdateResponse get systemUpdateResponse => $_getN(45);
  @$pb.TagNumber(46)
  set systemUpdateResponse($0.UpdateResponse value) => $_setField(46, value);
  @$pb.TagNumber(46)
  $core.bool hasSystemUpdateResponse() => $_has(45);
  @$pb.TagNumber(46)
  void clearSystemUpdateResponse() => $_clearField(46);
  @$pb.TagNumber(46)
  $0.UpdateResponse ensureSystemUpdateResponse() => $_ensure(45);

  @$pb.TagNumber(47)
  $2.AppExitRequest get appExitRequest => $_getN(46);
  @$pb.TagNumber(47)
  set appExitRequest($2.AppExitRequest value) => $_setField(47, value);
  @$pb.TagNumber(47)
  $core.bool hasAppExitRequest() => $_has(46);
  @$pb.TagNumber(47)
  void clearAppExitRequest() => $_clearField(47);
  @$pb.TagNumber(47)
  $2.AppExitRequest ensureAppExitRequest() => $_ensure(46);

  @$pb.TagNumber(48)
  $2.AppLoadFileRequest get appLoadFileRequest => $_getN(47);
  @$pb.TagNumber(48)
  set appLoadFileRequest($2.AppLoadFileRequest value) => $_setField(48, value);
  @$pb.TagNumber(48)
  $core.bool hasAppLoadFileRequest() => $_has(47);
  @$pb.TagNumber(48)
  void clearAppLoadFileRequest() => $_clearField(48);
  @$pb.TagNumber(48)
  $2.AppLoadFileRequest ensureAppLoadFileRequest() => $_ensure(47);

  @$pb.TagNumber(49)
  $2.AppButtonPressRequest get appButtonPressRequest => $_getN(48);
  @$pb.TagNumber(49)
  set appButtonPressRequest($2.AppButtonPressRequest value) =>
      $_setField(49, value);
  @$pb.TagNumber(49)
  $core.bool hasAppButtonPressRequest() => $_has(48);
  @$pb.TagNumber(49)
  void clearAppButtonPressRequest() => $_clearField(49);
  @$pb.TagNumber(49)
  $2.AppButtonPressRequest ensureAppButtonPressRequest() => $_ensure(48);

  @$pb.TagNumber(50)
  $2.AppButtonReleaseRequest get appButtonReleaseRequest => $_getN(49);
  @$pb.TagNumber(50)
  set appButtonReleaseRequest($2.AppButtonReleaseRequest value) =>
      $_setField(50, value);
  @$pb.TagNumber(50)
  $core.bool hasAppButtonReleaseRequest() => $_has(49);
  @$pb.TagNumber(50)
  void clearAppButtonReleaseRequest() => $_clearField(50);
  @$pb.TagNumber(50)
  $2.AppButtonReleaseRequest ensureAppButtonReleaseRequest() => $_ensure(49);

  @$pb.TagNumber(51)
  $4.SetPinMode get gpioSetPinMode => $_getN(50);
  @$pb.TagNumber(51)
  set gpioSetPinMode($4.SetPinMode value) => $_setField(51, value);
  @$pb.TagNumber(51)
  $core.bool hasGpioSetPinMode() => $_has(50);
  @$pb.TagNumber(51)
  void clearGpioSetPinMode() => $_clearField(51);
  @$pb.TagNumber(51)
  $4.SetPinMode ensureGpioSetPinMode() => $_ensure(50);

  @$pb.TagNumber(52)
  $4.SetInputPull get gpioSetInputPull => $_getN(51);
  @$pb.TagNumber(52)
  set gpioSetInputPull($4.SetInputPull value) => $_setField(52, value);
  @$pb.TagNumber(52)
  $core.bool hasGpioSetInputPull() => $_has(51);
  @$pb.TagNumber(52)
  void clearGpioSetInputPull() => $_clearField(52);
  @$pb.TagNumber(52)
  $4.SetInputPull ensureGpioSetInputPull() => $_ensure(51);

  @$pb.TagNumber(53)
  $4.GetPinMode get gpioGetPinMode => $_getN(52);
  @$pb.TagNumber(53)
  set gpioGetPinMode($4.GetPinMode value) => $_setField(53, value);
  @$pb.TagNumber(53)
  $core.bool hasGpioGetPinMode() => $_has(52);
  @$pb.TagNumber(53)
  void clearGpioGetPinMode() => $_clearField(53);
  @$pb.TagNumber(53)
  $4.GetPinMode ensureGpioGetPinMode() => $_ensure(52);

  @$pb.TagNumber(54)
  $4.GetPinModeResponse get gpioGetPinModeResponse => $_getN(53);
  @$pb.TagNumber(54)
  set gpioGetPinModeResponse($4.GetPinModeResponse value) =>
      $_setField(54, value);
  @$pb.TagNumber(54)
  $core.bool hasGpioGetPinModeResponse() => $_has(53);
  @$pb.TagNumber(54)
  void clearGpioGetPinModeResponse() => $_clearField(54);
  @$pb.TagNumber(54)
  $4.GetPinModeResponse ensureGpioGetPinModeResponse() => $_ensure(53);

  @$pb.TagNumber(55)
  $4.ReadPin get gpioReadPin => $_getN(54);
  @$pb.TagNumber(55)
  set gpioReadPin($4.ReadPin value) => $_setField(55, value);
  @$pb.TagNumber(55)
  $core.bool hasGpioReadPin() => $_has(54);
  @$pb.TagNumber(55)
  void clearGpioReadPin() => $_clearField(55);
  @$pb.TagNumber(55)
  $4.ReadPin ensureGpioReadPin() => $_ensure(54);

  @$pb.TagNumber(56)
  $4.ReadPinResponse get gpioReadPinResponse => $_getN(55);
  @$pb.TagNumber(56)
  set gpioReadPinResponse($4.ReadPinResponse value) => $_setField(56, value);
  @$pb.TagNumber(56)
  $core.bool hasGpioReadPinResponse() => $_has(55);
  @$pb.TagNumber(56)
  void clearGpioReadPinResponse() => $_clearField(56);
  @$pb.TagNumber(56)
  $4.ReadPinResponse ensureGpioReadPinResponse() => $_ensure(55);

  @$pb.TagNumber(57)
  $4.WritePin get gpioWritePin => $_getN(56);
  @$pb.TagNumber(57)
  set gpioWritePin($4.WritePin value) => $_setField(57, value);
  @$pb.TagNumber(57)
  $core.bool hasGpioWritePin() => $_has(56);
  @$pb.TagNumber(57)
  void clearGpioWritePin() => $_clearField(57);
  @$pb.TagNumber(57)
  $4.WritePin ensureGpioWritePin() => $_ensure(56);

  @$pb.TagNumber(58)
  $2.AppStateResponse get appStateResponse => $_getN(57);
  @$pb.TagNumber(58)
  set appStateResponse($2.AppStateResponse value) => $_setField(58, value);
  @$pb.TagNumber(58)
  $core.bool hasAppStateResponse() => $_has(57);
  @$pb.TagNumber(58)
  void clearAppStateResponse() => $_clearField(58);
  @$pb.TagNumber(58)
  $2.AppStateResponse ensureAppStateResponse() => $_ensure(57);

  @$pb.TagNumber(59)
  $1.TimestampRequest get storageTimestampRequest => $_getN(58);
  @$pb.TagNumber(59)
  set storageTimestampRequest($1.TimestampRequest value) =>
      $_setField(59, value);
  @$pb.TagNumber(59)
  $core.bool hasStorageTimestampRequest() => $_has(58);
  @$pb.TagNumber(59)
  void clearStorageTimestampRequest() => $_clearField(59);
  @$pb.TagNumber(59)
  $1.TimestampRequest ensureStorageTimestampRequest() => $_ensure(58);

  @$pb.TagNumber(60)
  $1.TimestampResponse get storageTimestampResponse => $_getN(59);
  @$pb.TagNumber(60)
  set storageTimestampResponse($1.TimestampResponse value) =>
      $_setField(60, value);
  @$pb.TagNumber(60)
  $core.bool hasStorageTimestampResponse() => $_has(59);
  @$pb.TagNumber(60)
  void clearStorageTimestampResponse() => $_clearField(60);
  @$pb.TagNumber(60)
  $1.TimestampResponse ensureStorageTimestampResponse() => $_ensure(59);

  @$pb.TagNumber(61)
  $5.GetRequest get propertyGetRequest => $_getN(60);
  @$pb.TagNumber(61)
  set propertyGetRequest($5.GetRequest value) => $_setField(61, value);
  @$pb.TagNumber(61)
  $core.bool hasPropertyGetRequest() => $_has(60);
  @$pb.TagNumber(61)
  void clearPropertyGetRequest() => $_clearField(61);
  @$pb.TagNumber(61)
  $5.GetRequest ensurePropertyGetRequest() => $_ensure(60);

  @$pb.TagNumber(62)
  $5.GetResponse get propertyGetResponse => $_getN(61);
  @$pb.TagNumber(62)
  set propertyGetResponse($5.GetResponse value) => $_setField(62, value);
  @$pb.TagNumber(62)
  $core.bool hasPropertyGetResponse() => $_has(61);
  @$pb.TagNumber(62)
  void clearPropertyGetResponse() => $_clearField(62);
  @$pb.TagNumber(62)
  $5.GetResponse ensurePropertyGetResponse() => $_ensure(61);

  @$pb.TagNumber(63)
  $2.GetErrorRequest get appGetErrorRequest => $_getN(62);
  @$pb.TagNumber(63)
  set appGetErrorRequest($2.GetErrorRequest value) => $_setField(63, value);
  @$pb.TagNumber(63)
  $core.bool hasAppGetErrorRequest() => $_has(62);
  @$pb.TagNumber(63)
  void clearAppGetErrorRequest() => $_clearField(63);
  @$pb.TagNumber(63)
  $2.GetErrorRequest ensureAppGetErrorRequest() => $_ensure(62);

  @$pb.TagNumber(64)
  $2.GetErrorResponse get appGetErrorResponse => $_getN(63);
  @$pb.TagNumber(64)
  set appGetErrorResponse($2.GetErrorResponse value) => $_setField(64, value);
  @$pb.TagNumber(64)
  $core.bool hasAppGetErrorResponse() => $_has(63);
  @$pb.TagNumber(64)
  void clearAppGetErrorResponse() => $_clearField(64);
  @$pb.TagNumber(64)
  $2.GetErrorResponse ensureAppGetErrorResponse() => $_ensure(63);

  @$pb.TagNumber(65)
  $2.DataExchangeRequest get appDataExchangeRequest => $_getN(64);
  @$pb.TagNumber(65)
  set appDataExchangeRequest($2.DataExchangeRequest value) =>
      $_setField(65, value);
  @$pb.TagNumber(65)
  $core.bool hasAppDataExchangeRequest() => $_has(64);
  @$pb.TagNumber(65)
  void clearAppDataExchangeRequest() => $_clearField(65);
  @$pb.TagNumber(65)
  $2.DataExchangeRequest ensureAppDataExchangeRequest() => $_ensure(64);

  @$pb.TagNumber(66)
  $6.IsLockedRequest get desktopIsLockedRequest => $_getN(65);
  @$pb.TagNumber(66)
  set desktopIsLockedRequest($6.IsLockedRequest value) => $_setField(66, value);
  @$pb.TagNumber(66)
  $core.bool hasDesktopIsLockedRequest() => $_has(65);
  @$pb.TagNumber(66)
  void clearDesktopIsLockedRequest() => $_clearField(66);
  @$pb.TagNumber(66)
  $6.IsLockedRequest ensureDesktopIsLockedRequest() => $_ensure(65);

  @$pb.TagNumber(67)
  $6.UnlockRequest get desktopUnlockRequest => $_getN(66);
  @$pb.TagNumber(67)
  set desktopUnlockRequest($6.UnlockRequest value) => $_setField(67, value);
  @$pb.TagNumber(67)
  $core.bool hasDesktopUnlockRequest() => $_has(66);
  @$pb.TagNumber(67)
  void clearDesktopUnlockRequest() => $_clearField(67);
  @$pb.TagNumber(67)
  $6.UnlockRequest ensureDesktopUnlockRequest() => $_ensure(66);

  @$pb.TagNumber(68)
  $6.StatusSubscribeRequest get desktopStatusSubscribeRequest => $_getN(67);
  @$pb.TagNumber(68)
  set desktopStatusSubscribeRequest($6.StatusSubscribeRequest value) =>
      $_setField(68, value);
  @$pb.TagNumber(68)
  $core.bool hasDesktopStatusSubscribeRequest() => $_has(67);
  @$pb.TagNumber(68)
  void clearDesktopStatusSubscribeRequest() => $_clearField(68);
  @$pb.TagNumber(68)
  $6.StatusSubscribeRequest ensureDesktopStatusSubscribeRequest() =>
      $_ensure(67);

  @$pb.TagNumber(69)
  $6.StatusUnsubscribeRequest get desktopStatusUnsubscribeRequest => $_getN(68);
  @$pb.TagNumber(69)
  set desktopStatusUnsubscribeRequest($6.StatusUnsubscribeRequest value) =>
      $_setField(69, value);
  @$pb.TagNumber(69)
  $core.bool hasDesktopStatusUnsubscribeRequest() => $_has(68);
  @$pb.TagNumber(69)
  void clearDesktopStatusUnsubscribeRequest() => $_clearField(69);
  @$pb.TagNumber(69)
  $6.StatusUnsubscribeRequest ensureDesktopStatusUnsubscribeRequest() =>
      $_ensure(68);

  @$pb.TagNumber(70)
  $6.Status get desktopStatus => $_getN(69);
  @$pb.TagNumber(70)
  set desktopStatus($6.Status value) => $_setField(70, value);
  @$pb.TagNumber(70)
  $core.bool hasDesktopStatus() => $_has(69);
  @$pb.TagNumber(70)
  void clearDesktopStatus() => $_clearField(70);
  @$pb.TagNumber(70)
  $6.Status ensureDesktopStatus() => $_ensure(69);

  @$pb.TagNumber(71)
  $1.TarExtractRequest get storageTarExtractRequest => $_getN(70);
  @$pb.TagNumber(71)
  set storageTarExtractRequest($1.TarExtractRequest value) =>
      $_setField(71, value);
  @$pb.TagNumber(71)
  $core.bool hasStorageTarExtractRequest() => $_has(70);
  @$pb.TagNumber(71)
  void clearStorageTarExtractRequest() => $_clearField(71);
  @$pb.TagNumber(71)
  $1.TarExtractRequest ensureStorageTarExtractRequest() => $_ensure(70);

  @$pb.TagNumber(72)
  $4.GetOtgMode get gpioGetOtgMode => $_getN(71);
  @$pb.TagNumber(72)
  set gpioGetOtgMode($4.GetOtgMode value) => $_setField(72, value);
  @$pb.TagNumber(72)
  $core.bool hasGpioGetOtgMode() => $_has(71);
  @$pb.TagNumber(72)
  void clearGpioGetOtgMode() => $_clearField(72);
  @$pb.TagNumber(72)
  $4.GetOtgMode ensureGpioGetOtgMode() => $_ensure(71);

  @$pb.TagNumber(73)
  $4.GetOtgModeResponse get gpioGetOtgModeResponse => $_getN(72);
  @$pb.TagNumber(73)
  set gpioGetOtgModeResponse($4.GetOtgModeResponse value) =>
      $_setField(73, value);
  @$pb.TagNumber(73)
  $core.bool hasGpioGetOtgModeResponse() => $_has(72);
  @$pb.TagNumber(73)
  void clearGpioGetOtgModeResponse() => $_clearField(73);
  @$pb.TagNumber(73)
  $4.GetOtgModeResponse ensureGpioGetOtgModeResponse() => $_ensure(72);

  @$pb.TagNumber(74)
  $4.SetOtgMode get gpioSetOtgMode => $_getN(73);
  @$pb.TagNumber(74)
  set gpioSetOtgMode($4.SetOtgMode value) => $_setField(74, value);
  @$pb.TagNumber(74)
  $core.bool hasGpioSetOtgMode() => $_has(73);
  @$pb.TagNumber(74)
  void clearGpioSetOtgMode() => $_clearField(74);
  @$pb.TagNumber(74)
  $4.SetOtgMode ensureGpioSetOtgMode() => $_ensure(73);

  @$pb.TagNumber(75)
  $2.AppButtonPressReleaseRequest get appButtonPressReleaseRequest =>
      $_getN(74);
  @$pb.TagNumber(75)
  set appButtonPressReleaseRequest($2.AppButtonPressReleaseRequest value) =>
      $_setField(75, value);
  @$pb.TagNumber(75)
  $core.bool hasAppButtonPressReleaseRequest() => $_has(74);
  @$pb.TagNumber(75)
  void clearAppButtonPressReleaseRequest() => $_clearField(75);
  @$pb.TagNumber(75)
  $2.AppButtonPressReleaseRequest ensureAppButtonPressReleaseRequest() =>
      $_ensure(74);
}

class Region_Band extends $pb.GeneratedMessage {
  factory Region_Band({
    $core.int? start,
    $core.int? end,
    $core.int? powerLimit,
    $core.int? dutyCycle,
  }) {
    final result = create();
    if (start != null) result.start = start;
    if (end != null) result.end = end;
    if (powerLimit != null) result.powerLimit = powerLimit;
    if (dutyCycle != null) result.dutyCycle = dutyCycle;
    return result;
  }

  Region_Band._();

  factory Region_Band.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Region_Band.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Region.Band',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'start', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'end', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'powerLimit')
    ..aI(4, _omitFieldNames ? '' : 'dutyCycle', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Region_Band clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Region_Band copyWith(void Function(Region_Band) updates) =>
      super.copyWith((message) => updates(message as Region_Band))
          as Region_Band;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Region_Band create() => Region_Band._();
  @$core.override
  Region_Band createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Region_Band getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Region_Band>(create);
  static Region_Band? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get start => $_getIZ(0);
  @$pb.TagNumber(1)
  set start($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStart() => $_has(0);
  @$pb.TagNumber(1)
  void clearStart() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get end => $_getIZ(1);
  @$pb.TagNumber(2)
  set end($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEnd() => $_has(1);
  @$pb.TagNumber(2)
  void clearEnd() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get powerLimit => $_getIZ(2);
  @$pb.TagNumber(3)
  set powerLimit($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPowerLimit() => $_has(2);
  @$pb.TagNumber(3)
  void clearPowerLimit() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get dutyCycle => $_getIZ(3);
  @$pb.TagNumber(4)
  set dutyCycle($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDutyCycle() => $_has(3);
  @$pb.TagNumber(4)
  void clearDutyCycle() => $_clearField(4);
}

class Region extends $pb.GeneratedMessage {
  factory Region({
    $core.List<$core.int>? countryCode,
    $core.Iterable<Region_Band>? bands,
  }) {
    final result = create();
    if (countryCode != null) result.countryCode = countryCode;
    if (bands != null) result.bands.addAll(bands);
    return result;
  }

  Region._();

  factory Region.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Region.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Region',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'countryCode', $pb.PbFieldType.OY)
    ..pPM<Region_Band>(2, _omitFieldNames ? '' : 'bands',
        subBuilder: Region_Band.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Region clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Region copyWith(void Function(Region) updates) =>
      super.copyWith((message) => updates(message as Region)) as Region;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Region create() => Region._();
  @$core.override
  Region createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Region getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Region>(create);
  static Region? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get countryCode => $_getN(0);
  @$pb.TagNumber(1)
  set countryCode($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCountryCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCountryCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<Region_Band> get bands => $_getList(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
