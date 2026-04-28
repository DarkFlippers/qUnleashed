// This is a generated file - do not edit.
//
// Generated from gpio.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'gpio.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'gpio.pbenum.dart';

class SetPinMode extends $pb.GeneratedMessage {
  factory SetPinMode({
    GpioPin? pin,
    GpioPinMode? mode,
  }) {
    final result = create();
    if (pin != null) result.pin = pin;
    if (mode != null) result.mode = mode;
    return result;
  }

  SetPinMode._();

  factory SetPinMode.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetPinMode.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetPinMode',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Gpio'),
      createEmptyInstance: create)
    ..aE<GpioPin>(1, _omitFieldNames ? '' : 'pin', enumValues: GpioPin.values)
    ..aE<GpioPinMode>(2, _omitFieldNames ? '' : 'mode',
        enumValues: GpioPinMode.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetPinMode clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetPinMode copyWith(void Function(SetPinMode) updates) =>
      super.copyWith((message) => updates(message as SetPinMode)) as SetPinMode;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetPinMode create() => SetPinMode._();
  @$core.override
  SetPinMode createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetPinMode getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetPinMode>(create);
  static SetPinMode? _defaultInstance;

  @$pb.TagNumber(1)
  GpioPin get pin => $_getN(0);
  @$pb.TagNumber(1)
  set pin(GpioPin value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPin() => $_has(0);
  @$pb.TagNumber(1)
  void clearPin() => $_clearField(1);

  @$pb.TagNumber(2)
  GpioPinMode get mode => $_getN(1);
  @$pb.TagNumber(2)
  set mode(GpioPinMode value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasMode() => $_has(1);
  @$pb.TagNumber(2)
  void clearMode() => $_clearField(2);
}

class SetInputPull extends $pb.GeneratedMessage {
  factory SetInputPull({
    GpioPin? pin,
    GpioInputPull? pullMode,
  }) {
    final result = create();
    if (pin != null) result.pin = pin;
    if (pullMode != null) result.pullMode = pullMode;
    return result;
  }

  SetInputPull._();

  factory SetInputPull.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetInputPull.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetInputPull',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Gpio'),
      createEmptyInstance: create)
    ..aE<GpioPin>(1, _omitFieldNames ? '' : 'pin', enumValues: GpioPin.values)
    ..aE<GpioInputPull>(2, _omitFieldNames ? '' : 'pullMode',
        enumValues: GpioInputPull.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetInputPull clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetInputPull copyWith(void Function(SetInputPull) updates) =>
      super.copyWith((message) => updates(message as SetInputPull))
          as SetInputPull;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetInputPull create() => SetInputPull._();
  @$core.override
  SetInputPull createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetInputPull getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetInputPull>(create);
  static SetInputPull? _defaultInstance;

  @$pb.TagNumber(1)
  GpioPin get pin => $_getN(0);
  @$pb.TagNumber(1)
  set pin(GpioPin value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPin() => $_has(0);
  @$pb.TagNumber(1)
  void clearPin() => $_clearField(1);

  @$pb.TagNumber(2)
  GpioInputPull get pullMode => $_getN(1);
  @$pb.TagNumber(2)
  set pullMode(GpioInputPull value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPullMode() => $_has(1);
  @$pb.TagNumber(2)
  void clearPullMode() => $_clearField(2);
}

class GetPinMode extends $pb.GeneratedMessage {
  factory GetPinMode({
    GpioPin? pin,
  }) {
    final result = create();
    if (pin != null) result.pin = pin;
    return result;
  }

  GetPinMode._();

  factory GetPinMode.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetPinMode.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetPinMode',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Gpio'),
      createEmptyInstance: create)
    ..aE<GpioPin>(1, _omitFieldNames ? '' : 'pin', enumValues: GpioPin.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPinMode clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPinMode copyWith(void Function(GetPinMode) updates) =>
      super.copyWith((message) => updates(message as GetPinMode)) as GetPinMode;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetPinMode create() => GetPinMode._();
  @$core.override
  GetPinMode createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetPinMode getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetPinMode>(create);
  static GetPinMode? _defaultInstance;

  @$pb.TagNumber(1)
  GpioPin get pin => $_getN(0);
  @$pb.TagNumber(1)
  set pin(GpioPin value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPin() => $_has(0);
  @$pb.TagNumber(1)
  void clearPin() => $_clearField(1);
}

class GetPinModeResponse extends $pb.GeneratedMessage {
  factory GetPinModeResponse({
    GpioPinMode? mode,
  }) {
    final result = create();
    if (mode != null) result.mode = mode;
    return result;
  }

  GetPinModeResponse._();

  factory GetPinModeResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetPinModeResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetPinModeResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Gpio'),
      createEmptyInstance: create)
    ..aE<GpioPinMode>(1, _omitFieldNames ? '' : 'mode',
        enumValues: GpioPinMode.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPinModeResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPinModeResponse copyWith(void Function(GetPinModeResponse) updates) =>
      super.copyWith((message) => updates(message as GetPinModeResponse))
          as GetPinModeResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetPinModeResponse create() => GetPinModeResponse._();
  @$core.override
  GetPinModeResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetPinModeResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetPinModeResponse>(create);
  static GetPinModeResponse? _defaultInstance;

  @$pb.TagNumber(1)
  GpioPinMode get mode => $_getN(0);
  @$pb.TagNumber(1)
  set mode(GpioPinMode value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasMode() => $_has(0);
  @$pb.TagNumber(1)
  void clearMode() => $_clearField(1);
}

class ReadPin extends $pb.GeneratedMessage {
  factory ReadPin({
    GpioPin? pin,
  }) {
    final result = create();
    if (pin != null) result.pin = pin;
    return result;
  }

  ReadPin._();

  factory ReadPin.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ReadPin.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReadPin',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Gpio'),
      createEmptyInstance: create)
    ..aE<GpioPin>(1, _omitFieldNames ? '' : 'pin', enumValues: GpioPin.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadPin clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadPin copyWith(void Function(ReadPin) updates) =>
      super.copyWith((message) => updates(message as ReadPin)) as ReadPin;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ReadPin create() => ReadPin._();
  @$core.override
  ReadPin createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ReadPin getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ReadPin>(create);
  static ReadPin? _defaultInstance;

  @$pb.TagNumber(1)
  GpioPin get pin => $_getN(0);
  @$pb.TagNumber(1)
  set pin(GpioPin value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPin() => $_has(0);
  @$pb.TagNumber(1)
  void clearPin() => $_clearField(1);
}

class ReadPinResponse extends $pb.GeneratedMessage {
  factory ReadPinResponse({
    $core.int? value,
  }) {
    final result = create();
    if (value != null) result.value = value;
    return result;
  }

  ReadPinResponse._();

  factory ReadPinResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ReadPinResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReadPinResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Gpio'),
      createEmptyInstance: create)
    ..aI(2, _omitFieldNames ? '' : 'value', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadPinResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadPinResponse copyWith(void Function(ReadPinResponse) updates) =>
      super.copyWith((message) => updates(message as ReadPinResponse))
          as ReadPinResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ReadPinResponse create() => ReadPinResponse._();
  @$core.override
  ReadPinResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ReadPinResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReadPinResponse>(create);
  static ReadPinResponse? _defaultInstance;

  @$pb.TagNumber(2)
  $core.int get value => $_getIZ(0);
  @$pb.TagNumber(2)
  set value($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(2)
  $core.bool hasValue() => $_has(0);
  @$pb.TagNumber(2)
  void clearValue() => $_clearField(2);
}

class WritePin extends $pb.GeneratedMessage {
  factory WritePin({
    GpioPin? pin,
    $core.int? value,
  }) {
    final result = create();
    if (pin != null) result.pin = pin;
    if (value != null) result.value = value;
    return result;
  }

  WritePin._();

  factory WritePin.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory WritePin.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WritePin',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Gpio'),
      createEmptyInstance: create)
    ..aE<GpioPin>(1, _omitFieldNames ? '' : 'pin', enumValues: GpioPin.values)
    ..aI(2, _omitFieldNames ? '' : 'value', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WritePin clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WritePin copyWith(void Function(WritePin) updates) =>
      super.copyWith((message) => updates(message as WritePin)) as WritePin;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static WritePin create() => WritePin._();
  @$core.override
  WritePin createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static WritePin getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WritePin>(create);
  static WritePin? _defaultInstance;

  @$pb.TagNumber(1)
  GpioPin get pin => $_getN(0);
  @$pb.TagNumber(1)
  set pin(GpioPin value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPin() => $_has(0);
  @$pb.TagNumber(1)
  void clearPin() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get value => $_getIZ(1);
  @$pb.TagNumber(2)
  set value($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasValue() => $_has(1);
  @$pb.TagNumber(2)
  void clearValue() => $_clearField(2);
}

class GetOtgMode extends $pb.GeneratedMessage {
  factory GetOtgMode() => create();

  GetOtgMode._();

  factory GetOtgMode.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetOtgMode.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetOtgMode',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Gpio'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetOtgMode clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetOtgMode copyWith(void Function(GetOtgMode) updates) =>
      super.copyWith((message) => updates(message as GetOtgMode)) as GetOtgMode;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetOtgMode create() => GetOtgMode._();
  @$core.override
  GetOtgMode createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetOtgMode getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetOtgMode>(create);
  static GetOtgMode? _defaultInstance;
}

class GetOtgModeResponse extends $pb.GeneratedMessage {
  factory GetOtgModeResponse({
    GpioOtgMode? mode,
  }) {
    final result = create();
    if (mode != null) result.mode = mode;
    return result;
  }

  GetOtgModeResponse._();

  factory GetOtgModeResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetOtgModeResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetOtgModeResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Gpio'),
      createEmptyInstance: create)
    ..aE<GpioOtgMode>(1, _omitFieldNames ? '' : 'mode',
        enumValues: GpioOtgMode.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetOtgModeResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetOtgModeResponse copyWith(void Function(GetOtgModeResponse) updates) =>
      super.copyWith((message) => updates(message as GetOtgModeResponse))
          as GetOtgModeResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetOtgModeResponse create() => GetOtgModeResponse._();
  @$core.override
  GetOtgModeResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetOtgModeResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetOtgModeResponse>(create);
  static GetOtgModeResponse? _defaultInstance;

  @$pb.TagNumber(1)
  GpioOtgMode get mode => $_getN(0);
  @$pb.TagNumber(1)
  set mode(GpioOtgMode value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasMode() => $_has(0);
  @$pb.TagNumber(1)
  void clearMode() => $_clearField(1);
}

class SetOtgMode extends $pb.GeneratedMessage {
  factory SetOtgMode({
    GpioOtgMode? mode,
  }) {
    final result = create();
    if (mode != null) result.mode = mode;
    return result;
  }

  SetOtgMode._();

  factory SetOtgMode.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetOtgMode.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetOtgMode',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Gpio'),
      createEmptyInstance: create)
    ..aE<GpioOtgMode>(1, _omitFieldNames ? '' : 'mode',
        enumValues: GpioOtgMode.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetOtgMode clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetOtgMode copyWith(void Function(SetOtgMode) updates) =>
      super.copyWith((message) => updates(message as SetOtgMode)) as SetOtgMode;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetOtgMode create() => SetOtgMode._();
  @$core.override
  SetOtgMode createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetOtgMode getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetOtgMode>(create);
  static SetOtgMode? _defaultInstance;

  @$pb.TagNumber(1)
  GpioOtgMode get mode => $_getN(0);
  @$pb.TagNumber(1)
  set mode(GpioOtgMode value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasMode() => $_has(0);
  @$pb.TagNumber(1)
  void clearMode() => $_clearField(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
