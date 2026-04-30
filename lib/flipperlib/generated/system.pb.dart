// This is a generated file - do not edit.
//
// Generated from system.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'system.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'system.pbenum.dart';

class PingRequest extends $pb.GeneratedMessage {
  factory PingRequest({
    $core.List<$core.int>? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  PingRequest._();

  factory PingRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PingRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PingRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_System'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PingRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PingRequest copyWith(void Function(PingRequest) updates) =>
      super.copyWith((message) => updates(message as PingRequest))
          as PingRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PingRequest create() => PingRequest._();
  @$core.override
  PingRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PingRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PingRequest>(create);
  static PingRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
}

class PingResponse extends $pb.GeneratedMessage {
  factory PingResponse({
    $core.List<$core.int>? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  PingResponse._();

  factory PingResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PingResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PingResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_System'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PingResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PingResponse copyWith(void Function(PingResponse) updates) =>
      super.copyWith((message) => updates(message as PingResponse))
          as PingResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PingResponse create() => PingResponse._();
  @$core.override
  PingResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PingResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PingResponse>(create);
  static PingResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
}

class RebootRequest extends $pb.GeneratedMessage {
  factory RebootRequest({
    RebootRequest_RebootMode? mode,
  }) {
    final result = create();
    if (mode != null) result.mode = mode;
    return result;
  }

  RebootRequest._();

  factory RebootRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RebootRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RebootRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_System'),
      createEmptyInstance: create)
    ..aE<RebootRequest_RebootMode>(1, _omitFieldNames ? '' : 'mode',
        enumValues: RebootRequest_RebootMode.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RebootRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RebootRequest copyWith(void Function(RebootRequest) updates) =>
      super.copyWith((message) => updates(message as RebootRequest))
          as RebootRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RebootRequest create() => RebootRequest._();
  @$core.override
  RebootRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RebootRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RebootRequest>(create);
  static RebootRequest? _defaultInstance;

  @$pb.TagNumber(1)
  RebootRequest_RebootMode get mode => $_getN(0);
  @$pb.TagNumber(1)
  set mode(RebootRequest_RebootMode value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasMode() => $_has(0);
  @$pb.TagNumber(1)
  void clearMode() => $_clearField(1);
}

class DeviceInfoRequest extends $pb.GeneratedMessage {
  factory DeviceInfoRequest() => create();

  DeviceInfoRequest._();

  factory DeviceInfoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DeviceInfoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeviceInfoRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_System'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceInfoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceInfoRequest copyWith(void Function(DeviceInfoRequest) updates) =>
      super.copyWith((message) => updates(message as DeviceInfoRequest))
          as DeviceInfoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeviceInfoRequest create() => DeviceInfoRequest._();
  @$core.override
  DeviceInfoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DeviceInfoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeviceInfoRequest>(create);
  static DeviceInfoRequest? _defaultInstance;
}

class DeviceInfoResponse extends $pb.GeneratedMessage {
  factory DeviceInfoResponse({
    $core.String? key,
    $core.String? value,
  }) {
    final result = create();
    if (key != null) result.key = key;
    if (value != null) result.value = value;
    return result;
  }

  DeviceInfoResponse._();

  factory DeviceInfoResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DeviceInfoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeviceInfoResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_System'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'key')
    ..aOS(2, _omitFieldNames ? '' : 'value')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceInfoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceInfoResponse copyWith(void Function(DeviceInfoResponse) updates) =>
      super.copyWith((message) => updates(message as DeviceInfoResponse))
          as DeviceInfoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeviceInfoResponse create() => DeviceInfoResponse._();
  @$core.override
  DeviceInfoResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DeviceInfoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeviceInfoResponse>(create);
  static DeviceInfoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get key => $_getSZ(0);
  @$pb.TagNumber(1)
  set key($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get value => $_getSZ(1);
  @$pb.TagNumber(2)
  set value($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasValue() => $_has(1);
  @$pb.TagNumber(2)
  void clearValue() => $_clearField(2);
}

class FactoryResetRequest extends $pb.GeneratedMessage {
  factory FactoryResetRequest() => create();

  FactoryResetRequest._();

  factory FactoryResetRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FactoryResetRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FactoryResetRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_System'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FactoryResetRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FactoryResetRequest copyWith(void Function(FactoryResetRequest) updates) =>
      super.copyWith((message) => updates(message as FactoryResetRequest))
          as FactoryResetRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FactoryResetRequest create() => FactoryResetRequest._();
  @$core.override
  FactoryResetRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FactoryResetRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FactoryResetRequest>(create);
  static FactoryResetRequest? _defaultInstance;
}

class GetDateTimeRequest extends $pb.GeneratedMessage {
  factory GetDateTimeRequest() => create();

  GetDateTimeRequest._();

  factory GetDateTimeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetDateTimeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetDateTimeRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_System'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetDateTimeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetDateTimeRequest copyWith(void Function(GetDateTimeRequest) updates) =>
      super.copyWith((message) => updates(message as GetDateTimeRequest))
          as GetDateTimeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetDateTimeRequest create() => GetDateTimeRequest._();
  @$core.override
  GetDateTimeRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetDateTimeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetDateTimeRequest>(create);
  static GetDateTimeRequest? _defaultInstance;
}

class GetDateTimeResponse extends $pb.GeneratedMessage {
  factory GetDateTimeResponse({
    DateTime? datetime,
  }) {
    final result = create();
    if (datetime != null) result.datetime = datetime;
    return result;
  }

  GetDateTimeResponse._();

  factory GetDateTimeResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetDateTimeResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetDateTimeResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_System'),
      createEmptyInstance: create)
    ..aOM<DateTime>(1, _omitFieldNames ? '' : 'datetime',
        subBuilder: DateTime.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetDateTimeResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetDateTimeResponse copyWith(void Function(GetDateTimeResponse) updates) =>
      super.copyWith((message) => updates(message as GetDateTimeResponse))
          as GetDateTimeResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetDateTimeResponse create() => GetDateTimeResponse._();
  @$core.override
  GetDateTimeResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetDateTimeResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetDateTimeResponse>(create);
  static GetDateTimeResponse? _defaultInstance;

  @$pb.TagNumber(1)
  DateTime get datetime => $_getN(0);
  @$pb.TagNumber(1)
  set datetime(DateTime value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasDatetime() => $_has(0);
  @$pb.TagNumber(1)
  void clearDatetime() => $_clearField(1);
  @$pb.TagNumber(1)
  DateTime ensureDatetime() => $_ensure(0);
}

class SetDateTimeRequest extends $pb.GeneratedMessage {
  factory SetDateTimeRequest({
    DateTime? datetime,
  }) {
    final result = create();
    if (datetime != null) result.datetime = datetime;
    return result;
  }

  SetDateTimeRequest._();

  factory SetDateTimeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetDateTimeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetDateTimeRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_System'),
      createEmptyInstance: create)
    ..aOM<DateTime>(1, _omitFieldNames ? '' : 'datetime',
        subBuilder: DateTime.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetDateTimeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetDateTimeRequest copyWith(void Function(SetDateTimeRequest) updates) =>
      super.copyWith((message) => updates(message as SetDateTimeRequest))
          as SetDateTimeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetDateTimeRequest create() => SetDateTimeRequest._();
  @$core.override
  SetDateTimeRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetDateTimeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetDateTimeRequest>(create);
  static SetDateTimeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  DateTime get datetime => $_getN(0);
  @$pb.TagNumber(1)
  set datetime(DateTime value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasDatetime() => $_has(0);
  @$pb.TagNumber(1)
  void clearDatetime() => $_clearField(1);
  @$pb.TagNumber(1)
  DateTime ensureDatetime() => $_ensure(0);
}

class DateTime extends $pb.GeneratedMessage {
  factory DateTime({
    $core.int? hour,
    $core.int? minute,
    $core.int? second,
    $core.int? day,
    $core.int? month,
    $core.int? year,
    $core.int? weekday,
  }) {
    final result = create();
    if (hour != null) result.hour = hour;
    if (minute != null) result.minute = minute;
    if (second != null) result.second = second;
    if (day != null) result.day = day;
    if (month != null) result.month = month;
    if (year != null) result.year = year;
    if (weekday != null) result.weekday = weekday;
    return result;
  }

  DateTime._();

  factory DateTime.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DateTime.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DateTime',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_System'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'hour', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'minute', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'second', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'day', fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'month', fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'year', fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'weekday', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DateTime clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DateTime copyWith(void Function(DateTime) updates) =>
      super.copyWith((message) => updates(message as DateTime)) as DateTime;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DateTime create() => DateTime._();
  @$core.override
  DateTime createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DateTime getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DateTime>(create);
  static DateTime? _defaultInstance;

  /// Time
  @$pb.TagNumber(1)
  $core.int get hour => $_getIZ(0);
  @$pb.TagNumber(1)
  set hour($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHour() => $_has(0);
  @$pb.TagNumber(1)
  void clearHour() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get minute => $_getIZ(1);
  @$pb.TagNumber(2)
  set minute($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMinute() => $_has(1);
  @$pb.TagNumber(2)
  void clearMinute() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get second => $_getIZ(2);
  @$pb.TagNumber(3)
  set second($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSecond() => $_has(2);
  @$pb.TagNumber(3)
  void clearSecond() => $_clearField(3);

  /// Date
  @$pb.TagNumber(4)
  $core.int get day => $_getIZ(3);
  @$pb.TagNumber(4)
  set day($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDay() => $_has(3);
  @$pb.TagNumber(4)
  void clearDay() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get month => $_getIZ(4);
  @$pb.TagNumber(5)
  set month($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMonth() => $_has(4);
  @$pb.TagNumber(5)
  void clearMonth() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get year => $_getIZ(5);
  @$pb.TagNumber(6)
  set year($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasYear() => $_has(5);
  @$pb.TagNumber(6)
  void clearYear() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get weekday => $_getIZ(6);
  @$pb.TagNumber(7)
  set weekday($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasWeekday() => $_has(6);
  @$pb.TagNumber(7)
  void clearWeekday() => $_clearField(7);
}

class PlayAudiovisualAlertRequest extends $pb.GeneratedMessage {
  factory PlayAudiovisualAlertRequest() => create();

  PlayAudiovisualAlertRequest._();

  factory PlayAudiovisualAlertRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PlayAudiovisualAlertRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PlayAudiovisualAlertRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_System'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlayAudiovisualAlertRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlayAudiovisualAlertRequest copyWith(
          void Function(PlayAudiovisualAlertRequest) updates) =>
      super.copyWith(
              (message) => updates(message as PlayAudiovisualAlertRequest))
          as PlayAudiovisualAlertRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PlayAudiovisualAlertRequest create() =>
      PlayAudiovisualAlertRequest._();
  @$core.override
  PlayAudiovisualAlertRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PlayAudiovisualAlertRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PlayAudiovisualAlertRequest>(create);
  static PlayAudiovisualAlertRequest? _defaultInstance;
}

class ProtobufVersionRequest extends $pb.GeneratedMessage {
  factory ProtobufVersionRequest() => create();

  ProtobufVersionRequest._();

  factory ProtobufVersionRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProtobufVersionRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProtobufVersionRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_System'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProtobufVersionRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProtobufVersionRequest copyWith(
          void Function(ProtobufVersionRequest) updates) =>
      super.copyWith((message) => updates(message as ProtobufVersionRequest))
          as ProtobufVersionRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProtobufVersionRequest create() => ProtobufVersionRequest._();
  @$core.override
  ProtobufVersionRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProtobufVersionRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProtobufVersionRequest>(create);
  static ProtobufVersionRequest? _defaultInstance;
}

class ProtobufVersionResponse extends $pb.GeneratedMessage {
  factory ProtobufVersionResponse({
    $core.int? major,
    $core.int? minor,
  }) {
    final result = create();
    if (major != null) result.major = major;
    if (minor != null) result.minor = minor;
    return result;
  }

  ProtobufVersionResponse._();

  factory ProtobufVersionResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProtobufVersionResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProtobufVersionResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_System'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'major', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'minor', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProtobufVersionResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProtobufVersionResponse copyWith(
          void Function(ProtobufVersionResponse) updates) =>
      super.copyWith((message) => updates(message as ProtobufVersionResponse))
          as ProtobufVersionResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProtobufVersionResponse create() => ProtobufVersionResponse._();
  @$core.override
  ProtobufVersionResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProtobufVersionResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProtobufVersionResponse>(create);
  static ProtobufVersionResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get major => $_getIZ(0);
  @$pb.TagNumber(1)
  set major($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMajor() => $_has(0);
  @$pb.TagNumber(1)
  void clearMajor() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get minor => $_getIZ(1);
  @$pb.TagNumber(2)
  set minor($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMinor() => $_has(1);
  @$pb.TagNumber(2)
  void clearMinor() => $_clearField(2);
}

class UpdateRequest extends $pb.GeneratedMessage {
  factory UpdateRequest({
    $core.String? updateManifest,
  }) {
    final result = create();
    if (updateManifest != null) result.updateManifest = updateManifest;
    return result;
  }

  UpdateRequest._();

  factory UpdateRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_System'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'updateManifest')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateRequest copyWith(void Function(UpdateRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateRequest))
          as UpdateRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateRequest create() => UpdateRequest._();
  @$core.override
  UpdateRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateRequest>(create);
  static UpdateRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get updateManifest => $_getSZ(0);
  @$pb.TagNumber(1)
  set updateManifest($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUpdateManifest() => $_has(0);
  @$pb.TagNumber(1)
  void clearUpdateManifest() => $_clearField(1);
}

class UpdateResponse extends $pb.GeneratedMessage {
  factory UpdateResponse({
    UpdateResponse_UpdateResultCode? code,
  }) {
    final result = create();
    if (code != null) result.code = code;
    return result;
  }

  UpdateResponse._();

  factory UpdateResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_System'),
      createEmptyInstance: create)
    ..aE<UpdateResponse_UpdateResultCode>(1, _omitFieldNames ? '' : 'code',
        enumValues: UpdateResponse_UpdateResultCode.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateResponse copyWith(void Function(UpdateResponse) updates) =>
      super.copyWith((message) => updates(message as UpdateResponse))
          as UpdateResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateResponse create() => UpdateResponse._();
  @$core.override
  UpdateResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateResponse>(create);
  static UpdateResponse? _defaultInstance;

  @$pb.TagNumber(1)
  UpdateResponse_UpdateResultCode get code => $_getN(0);
  @$pb.TagNumber(1)
  set code(UpdateResponse_UpdateResultCode value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => $_clearField(1);
}

class PowerInfoRequest extends $pb.GeneratedMessage {
  factory PowerInfoRequest() => create();

  PowerInfoRequest._();

  factory PowerInfoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PowerInfoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PowerInfoRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_System'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PowerInfoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PowerInfoRequest copyWith(void Function(PowerInfoRequest) updates) =>
      super.copyWith((message) => updates(message as PowerInfoRequest))
          as PowerInfoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PowerInfoRequest create() => PowerInfoRequest._();
  @$core.override
  PowerInfoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PowerInfoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PowerInfoRequest>(create);
  static PowerInfoRequest? _defaultInstance;
}

class PowerInfoResponse extends $pb.GeneratedMessage {
  factory PowerInfoResponse({
    $core.String? key,
    $core.String? value,
  }) {
    final result = create();
    if (key != null) result.key = key;
    if (value != null) result.value = value;
    return result;
  }

  PowerInfoResponse._();

  factory PowerInfoResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PowerInfoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PowerInfoResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_System'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'key')
    ..aOS(2, _omitFieldNames ? '' : 'value')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PowerInfoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PowerInfoResponse copyWith(void Function(PowerInfoResponse) updates) =>
      super.copyWith((message) => updates(message as PowerInfoResponse))
          as PowerInfoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PowerInfoResponse create() => PowerInfoResponse._();
  @$core.override
  PowerInfoResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PowerInfoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PowerInfoResponse>(create);
  static PowerInfoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get key => $_getSZ(0);
  @$pb.TagNumber(1)
  set key($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get value => $_getSZ(1);
  @$pb.TagNumber(2)
  set value($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasValue() => $_has(1);
  @$pb.TagNumber(2)
  void clearValue() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
