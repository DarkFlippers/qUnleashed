// This is a generated file - do not edit.
//
// Generated from application.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'application.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'application.pbenum.dart';

class StartRequest extends $pb.GeneratedMessage {
  factory StartRequest({
    $core.String? name,
    $core.String? args,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (args != null) result.args = args;
    return result;
  }

  StartRequest._();

  factory StartRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StartRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_App'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'args')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartRequest copyWith(void Function(StartRequest) updates) =>
      super.copyWith((message) => updates(message as StartRequest))
          as StartRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StartRequest create() => StartRequest._();
  @$core.override
  StartRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StartRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartRequest>(create);
  static StartRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get args => $_getSZ(1);
  @$pb.TagNumber(2)
  set args($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasArgs() => $_has(1);
  @$pb.TagNumber(2)
  void clearArgs() => $_clearField(2);
}

class LockStatusRequest extends $pb.GeneratedMessage {
  factory LockStatusRequest() => create();

  LockStatusRequest._();

  factory LockStatusRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LockStatusRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LockStatusRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_App'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LockStatusRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LockStatusRequest copyWith(void Function(LockStatusRequest) updates) =>
      super.copyWith((message) => updates(message as LockStatusRequest))
          as LockStatusRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LockStatusRequest create() => LockStatusRequest._();
  @$core.override
  LockStatusRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LockStatusRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LockStatusRequest>(create);
  static LockStatusRequest? _defaultInstance;
}

class LockStatusResponse extends $pb.GeneratedMessage {
  factory LockStatusResponse({
    $core.bool? locked,
  }) {
    final result = create();
    if (locked != null) result.locked = locked;
    return result;
  }

  LockStatusResponse._();

  factory LockStatusResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LockStatusResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LockStatusResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_App'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'locked')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LockStatusResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LockStatusResponse copyWith(void Function(LockStatusResponse) updates) =>
      super.copyWith((message) => updates(message as LockStatusResponse))
          as LockStatusResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LockStatusResponse create() => LockStatusResponse._();
  @$core.override
  LockStatusResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LockStatusResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LockStatusResponse>(create);
  static LockStatusResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get locked => $_getBF(0);
  @$pb.TagNumber(1)
  set locked($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLocked() => $_has(0);
  @$pb.TagNumber(1)
  void clearLocked() => $_clearField(1);
}

class AppExitRequest extends $pb.GeneratedMessage {
  factory AppExitRequest() => create();

  AppExitRequest._();

  factory AppExitRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AppExitRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AppExitRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_App'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AppExitRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AppExitRequest copyWith(void Function(AppExitRequest) updates) =>
      super.copyWith((message) => updates(message as AppExitRequest))
          as AppExitRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AppExitRequest create() => AppExitRequest._();
  @$core.override
  AppExitRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AppExitRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AppExitRequest>(create);
  static AppExitRequest? _defaultInstance;
}

class AppLoadFileRequest extends $pb.GeneratedMessage {
  factory AppLoadFileRequest({
    $core.String? path,
  }) {
    final result = create();
    if (path != null) result.path = path;
    return result;
  }

  AppLoadFileRequest._();

  factory AppLoadFileRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AppLoadFileRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AppLoadFileRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_App'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AppLoadFileRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AppLoadFileRequest copyWith(void Function(AppLoadFileRequest) updates) =>
      super.copyWith((message) => updates(message as AppLoadFileRequest))
          as AppLoadFileRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AppLoadFileRequest create() => AppLoadFileRequest._();
  @$core.override
  AppLoadFileRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AppLoadFileRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AppLoadFileRequest>(create);
  static AppLoadFileRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);
}

class AppButtonPressRequest extends $pb.GeneratedMessage {
  factory AppButtonPressRequest({
    $core.String? args,
    $core.int? index,
  }) {
    final result = create();
    if (args != null) result.args = args;
    if (index != null) result.index = index;
    return result;
  }

  AppButtonPressRequest._();

  factory AppButtonPressRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AppButtonPressRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AppButtonPressRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_App'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'args')
    ..aI(2, _omitFieldNames ? '' : 'index')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AppButtonPressRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AppButtonPressRequest copyWith(
          void Function(AppButtonPressRequest) updates) =>
      super.copyWith((message) => updates(message as AppButtonPressRequest))
          as AppButtonPressRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AppButtonPressRequest create() => AppButtonPressRequest._();
  @$core.override
  AppButtonPressRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AppButtonPressRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AppButtonPressRequest>(create);
  static AppButtonPressRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get args => $_getSZ(0);
  @$pb.TagNumber(1)
  set args($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasArgs() => $_has(0);
  @$pb.TagNumber(1)
  void clearArgs() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get index => $_getIZ(1);
  @$pb.TagNumber(2)
  set index($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIndex() => $_has(1);
  @$pb.TagNumber(2)
  void clearIndex() => $_clearField(2);
}

class AppButtonReleaseRequest extends $pb.GeneratedMessage {
  factory AppButtonReleaseRequest() => create();

  AppButtonReleaseRequest._();

  factory AppButtonReleaseRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AppButtonReleaseRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AppButtonReleaseRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_App'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AppButtonReleaseRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AppButtonReleaseRequest copyWith(
          void Function(AppButtonReleaseRequest) updates) =>
      super.copyWith((message) => updates(message as AppButtonReleaseRequest))
          as AppButtonReleaseRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AppButtonReleaseRequest create() => AppButtonReleaseRequest._();
  @$core.override
  AppButtonReleaseRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AppButtonReleaseRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AppButtonReleaseRequest>(create);
  static AppButtonReleaseRequest? _defaultInstance;
}

class AppButtonPressReleaseRequest extends $pb.GeneratedMessage {
  factory AppButtonPressReleaseRequest({
    $core.String? args,
    $core.int? index,
  }) {
    final result = create();
    if (args != null) result.args = args;
    if (index != null) result.index = index;
    return result;
  }

  AppButtonPressReleaseRequest._();

  factory AppButtonPressReleaseRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AppButtonPressReleaseRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AppButtonPressReleaseRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_App'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'args')
    ..aI(2, _omitFieldNames ? '' : 'index')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AppButtonPressReleaseRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AppButtonPressReleaseRequest copyWith(
          void Function(AppButtonPressReleaseRequest) updates) =>
      super.copyWith(
              (message) => updates(message as AppButtonPressReleaseRequest))
          as AppButtonPressReleaseRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AppButtonPressReleaseRequest create() =>
      AppButtonPressReleaseRequest._();
  @$core.override
  AppButtonPressReleaseRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AppButtonPressReleaseRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AppButtonPressReleaseRequest>(create);
  static AppButtonPressReleaseRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get args => $_getSZ(0);
  @$pb.TagNumber(1)
  set args($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasArgs() => $_has(0);
  @$pb.TagNumber(1)
  void clearArgs() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get index => $_getIZ(1);
  @$pb.TagNumber(2)
  set index($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIndex() => $_has(1);
  @$pb.TagNumber(2)
  void clearIndex() => $_clearField(2);
}

class AppStateResponse extends $pb.GeneratedMessage {
  factory AppStateResponse({
    AppState? state,
  }) {
    final result = create();
    if (state != null) result.state = state;
    return result;
  }

  AppStateResponse._();

  factory AppStateResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AppStateResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AppStateResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_App'),
      createEmptyInstance: create)
    ..aE<AppState>(1, _omitFieldNames ? '' : 'state',
        enumValues: AppState.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AppStateResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AppStateResponse copyWith(void Function(AppStateResponse) updates) =>
      super.copyWith((message) => updates(message as AppStateResponse))
          as AppStateResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AppStateResponse create() => AppStateResponse._();
  @$core.override
  AppStateResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AppStateResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AppStateResponse>(create);
  static AppStateResponse? _defaultInstance;

  @$pb.TagNumber(1)
  AppState get state => $_getN(0);
  @$pb.TagNumber(1)
  set state(AppState value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasState() => $_has(0);
  @$pb.TagNumber(1)
  void clearState() => $_clearField(1);
}

class GetErrorRequest extends $pb.GeneratedMessage {
  factory GetErrorRequest() => create();

  GetErrorRequest._();

  factory GetErrorRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetErrorRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetErrorRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_App'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetErrorRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetErrorRequest copyWith(void Function(GetErrorRequest) updates) =>
      super.copyWith((message) => updates(message as GetErrorRequest))
          as GetErrorRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetErrorRequest create() => GetErrorRequest._();
  @$core.override
  GetErrorRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetErrorRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetErrorRequest>(create);
  static GetErrorRequest? _defaultInstance;
}

class GetErrorResponse extends $pb.GeneratedMessage {
  factory GetErrorResponse({
    $core.int? code,
    $core.String? text,
  }) {
    final result = create();
    if (code != null) result.code = code;
    if (text != null) result.text = text;
    return result;
  }

  GetErrorResponse._();

  factory GetErrorResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetErrorResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetErrorResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_App'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'code', fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'text')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetErrorResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetErrorResponse copyWith(void Function(GetErrorResponse) updates) =>
      super.copyWith((message) => updates(message as GetErrorResponse))
          as GetErrorResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetErrorResponse create() => GetErrorResponse._();
  @$core.override
  GetErrorResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetErrorResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetErrorResponse>(create);
  static GetErrorResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get code => $_getIZ(0);
  @$pb.TagNumber(1)
  set code($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => $_clearField(2);
}

class DataExchangeRequest extends $pb.GeneratedMessage {
  factory DataExchangeRequest({
    $core.List<$core.int>? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  DataExchangeRequest._();

  factory DataExchangeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DataExchangeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DataExchangeRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_App'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataExchangeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataExchangeRequest copyWith(void Function(DataExchangeRequest) updates) =>
      super.copyWith((message) => updates(message as DataExchangeRequest))
          as DataExchangeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DataExchangeRequest create() => DataExchangeRequest._();
  @$core.override
  DataExchangeRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DataExchangeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DataExchangeRequest>(create);
  static DataExchangeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
