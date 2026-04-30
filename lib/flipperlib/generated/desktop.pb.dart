// This is a generated file - do not edit.
//
// Generated from desktop.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class IsLockedRequest extends $pb.GeneratedMessage {
  factory IsLockedRequest() => create();

  IsLockedRequest._();

  factory IsLockedRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory IsLockedRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'IsLockedRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Desktop'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  IsLockedRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  IsLockedRequest copyWith(void Function(IsLockedRequest) updates) =>
      super.copyWith((message) => updates(message as IsLockedRequest))
          as IsLockedRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static IsLockedRequest create() => IsLockedRequest._();
  @$core.override
  IsLockedRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static IsLockedRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<IsLockedRequest>(create);
  static IsLockedRequest? _defaultInstance;
}

class UnlockRequest extends $pb.GeneratedMessage {
  factory UnlockRequest() => create();

  UnlockRequest._();

  factory UnlockRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UnlockRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UnlockRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Desktop'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UnlockRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UnlockRequest copyWith(void Function(UnlockRequest) updates) =>
      super.copyWith((message) => updates(message as UnlockRequest))
          as UnlockRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UnlockRequest create() => UnlockRequest._();
  @$core.override
  UnlockRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UnlockRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UnlockRequest>(create);
  static UnlockRequest? _defaultInstance;
}

class StatusSubscribeRequest extends $pb.GeneratedMessage {
  factory StatusSubscribeRequest() => create();

  StatusSubscribeRequest._();

  factory StatusSubscribeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StatusSubscribeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StatusSubscribeRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Desktop'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StatusSubscribeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StatusSubscribeRequest copyWith(
          void Function(StatusSubscribeRequest) updates) =>
      super.copyWith((message) => updates(message as StatusSubscribeRequest))
          as StatusSubscribeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StatusSubscribeRequest create() => StatusSubscribeRequest._();
  @$core.override
  StatusSubscribeRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StatusSubscribeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StatusSubscribeRequest>(create);
  static StatusSubscribeRequest? _defaultInstance;
}

class StatusUnsubscribeRequest extends $pb.GeneratedMessage {
  factory StatusUnsubscribeRequest() => create();

  StatusUnsubscribeRequest._();

  factory StatusUnsubscribeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StatusUnsubscribeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StatusUnsubscribeRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Desktop'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StatusUnsubscribeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StatusUnsubscribeRequest copyWith(
          void Function(StatusUnsubscribeRequest) updates) =>
      super.copyWith((message) => updates(message as StatusUnsubscribeRequest))
          as StatusUnsubscribeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StatusUnsubscribeRequest create() => StatusUnsubscribeRequest._();
  @$core.override
  StatusUnsubscribeRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StatusUnsubscribeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StatusUnsubscribeRequest>(create);
  static StatusUnsubscribeRequest? _defaultInstance;
}

class Status extends $pb.GeneratedMessage {
  factory Status({
    $core.bool? locked,
  }) {
    final result = create();
    if (locked != null) result.locked = locked;
    return result;
  }

  Status._();

  factory Status.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Status.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Status',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Desktop'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'locked')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Status clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Status copyWith(void Function(Status) updates) =>
      super.copyWith((message) => updates(message as Status)) as Status;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Status create() => Status._();
  @$core.override
  Status createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Status getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Status>(create);
  static Status? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get locked => $_getBF(0);
  @$pb.TagNumber(1)
  set locked($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLocked() => $_has(0);
  @$pb.TagNumber(1)
  void clearLocked() => $_clearField(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
