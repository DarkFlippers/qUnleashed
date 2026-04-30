// This is a generated file - do not edit.
//
// Generated from storage.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'storage.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'storage.pbenum.dart';

class File extends $pb.GeneratedMessage {
  factory File({
    File_FileType? type,
    $core.String? name,
    $core.int? size,
    $core.List<$core.int>? data,
    $core.String? md5sum,
  }) {
    final result = create();
    if (type != null) result.type = type;
    if (name != null) result.name = name;
    if (size != null) result.size = size;
    if (data != null) result.data = data;
    if (md5sum != null) result.md5sum = md5sum;
    return result;
  }

  File._();

  factory File.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory File.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'File',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Storage'),
      createEmptyInstance: create)
    ..aE<File_FileType>(1, _omitFieldNames ? '' : 'type',
        enumValues: File_FileType.values)
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aI(3, _omitFieldNames ? '' : 'size', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..aOS(5, _omitFieldNames ? '' : 'md5sum')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  File clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  File copyWith(void Function(File) updates) =>
      super.copyWith((message) => updates(message as File)) as File;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static File create() => File._();
  @$core.override
  File createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static File getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<File>(create);
  static File? _defaultInstance;

  @$pb.TagNumber(1)
  File_FileType get type => $_getN(0);
  @$pb.TagNumber(1)
  set type(File_FileType value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get size => $_getIZ(2);
  @$pb.TagNumber(3)
  set size($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSize() => $_has(2);
  @$pb.TagNumber(3)
  void clearSize() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get data => $_getN(3);
  @$pb.TagNumber(4)
  set data($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasData() => $_has(3);
  @$pb.TagNumber(4)
  void clearData() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get md5sum => $_getSZ(4);
  @$pb.TagNumber(5)
  set md5sum($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMd5sum() => $_has(4);
  @$pb.TagNumber(5)
  void clearMd5sum() => $_clearField(5);
}

class InfoRequest extends $pb.GeneratedMessage {
  factory InfoRequest({
    $core.String? path,
  }) {
    final result = create();
    if (path != null) result.path = path;
    return result;
  }

  InfoRequest._();

  factory InfoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory InfoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'InfoRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Storage'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InfoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InfoRequest copyWith(void Function(InfoRequest) updates) =>
      super.copyWith((message) => updates(message as InfoRequest))
          as InfoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static InfoRequest create() => InfoRequest._();
  @$core.override
  InfoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static InfoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<InfoRequest>(create);
  static InfoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);
}

class InfoResponse extends $pb.GeneratedMessage {
  factory InfoResponse({
    $fixnum.Int64? totalSpace,
    $fixnum.Int64? freeSpace,
  }) {
    final result = create();
    if (totalSpace != null) result.totalSpace = totalSpace;
    if (freeSpace != null) result.freeSpace = freeSpace;
    return result;
  }

  InfoResponse._();

  factory InfoResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory InfoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'InfoResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Storage'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'totalSpace', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'freeSpace', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InfoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InfoResponse copyWith(void Function(InfoResponse) updates) =>
      super.copyWith((message) => updates(message as InfoResponse))
          as InfoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static InfoResponse create() => InfoResponse._();
  @$core.override
  InfoResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static InfoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<InfoResponse>(create);
  static InfoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get totalSpace => $_getI64(0);
  @$pb.TagNumber(1)
  set totalSpace($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTotalSpace() => $_has(0);
  @$pb.TagNumber(1)
  void clearTotalSpace() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get freeSpace => $_getI64(1);
  @$pb.TagNumber(2)
  set freeSpace($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFreeSpace() => $_has(1);
  @$pb.TagNumber(2)
  void clearFreeSpace() => $_clearField(2);
}

class TimestampRequest extends $pb.GeneratedMessage {
  factory TimestampRequest({
    $core.String? path,
  }) {
    final result = create();
    if (path != null) result.path = path;
    return result;
  }

  TimestampRequest._();

  factory TimestampRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TimestampRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TimestampRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Storage'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TimestampRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TimestampRequest copyWith(void Function(TimestampRequest) updates) =>
      super.copyWith((message) => updates(message as TimestampRequest))
          as TimestampRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TimestampRequest create() => TimestampRequest._();
  @$core.override
  TimestampRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TimestampRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TimestampRequest>(create);
  static TimestampRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);
}

class TimestampResponse extends $pb.GeneratedMessage {
  factory TimestampResponse({
    $core.int? timestamp,
  }) {
    final result = create();
    if (timestamp != null) result.timestamp = timestamp;
    return result;
  }

  TimestampResponse._();

  factory TimestampResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TimestampResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TimestampResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Storage'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'timestamp', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TimestampResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TimestampResponse copyWith(void Function(TimestampResponse) updates) =>
      super.copyWith((message) => updates(message as TimestampResponse))
          as TimestampResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TimestampResponse create() => TimestampResponse._();
  @$core.override
  TimestampResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TimestampResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TimestampResponse>(create);
  static TimestampResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get timestamp => $_getIZ(0);
  @$pb.TagNumber(1)
  set timestamp($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTimestamp() => $_has(0);
  @$pb.TagNumber(1)
  void clearTimestamp() => $_clearField(1);
}

class StatRequest extends $pb.GeneratedMessage {
  factory StatRequest({
    $core.String? path,
  }) {
    final result = create();
    if (path != null) result.path = path;
    return result;
  }

  StatRequest._();

  factory StatRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StatRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StatRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Storage'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StatRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StatRequest copyWith(void Function(StatRequest) updates) =>
      super.copyWith((message) => updates(message as StatRequest))
          as StatRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StatRequest create() => StatRequest._();
  @$core.override
  StatRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StatRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StatRequest>(create);
  static StatRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);
}

class StatResponse extends $pb.GeneratedMessage {
  factory StatResponse({
    File? file,
  }) {
    final result = create();
    if (file != null) result.file = file;
    return result;
  }

  StatResponse._();

  factory StatResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StatResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StatResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Storage'),
      createEmptyInstance: create)
    ..aOM<File>(1, _omitFieldNames ? '' : 'file', subBuilder: File.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StatResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StatResponse copyWith(void Function(StatResponse) updates) =>
      super.copyWith((message) => updates(message as StatResponse))
          as StatResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StatResponse create() => StatResponse._();
  @$core.override
  StatResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StatResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StatResponse>(create);
  static StatResponse? _defaultInstance;

  @$pb.TagNumber(1)
  File get file => $_getN(0);
  @$pb.TagNumber(1)
  set file(File value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasFile() => $_has(0);
  @$pb.TagNumber(1)
  void clearFile() => $_clearField(1);
  @$pb.TagNumber(1)
  File ensureFile() => $_ensure(0);
}

class ListRequest extends $pb.GeneratedMessage {
  factory ListRequest({
    $core.String? path,
    $core.bool? includeMd5,
    $core.int? filterMaxSize,
  }) {
    final result = create();
    if (path != null) result.path = path;
    if (includeMd5 != null) result.includeMd5 = includeMd5;
    if (filterMaxSize != null) result.filterMaxSize = filterMaxSize;
    return result;
  }

  ListRequest._();

  factory ListRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Storage'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..aOB(2, _omitFieldNames ? '' : 'includeMd5')
    ..aI(3, _omitFieldNames ? '' : 'filterMaxSize',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListRequest copyWith(void Function(ListRequest) updates) =>
      super.copyWith((message) => updates(message as ListRequest))
          as ListRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListRequest create() => ListRequest._();
  @$core.override
  ListRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListRequest>(create);
  static ListRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get includeMd5 => $_getBF(1);
  @$pb.TagNumber(2)
  set includeMd5($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIncludeMd5() => $_has(1);
  @$pb.TagNumber(2)
  void clearIncludeMd5() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get filterMaxSize => $_getIZ(2);
  @$pb.TagNumber(3)
  set filterMaxSize($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFilterMaxSize() => $_has(2);
  @$pb.TagNumber(3)
  void clearFilterMaxSize() => $_clearField(3);
}

class ListResponse extends $pb.GeneratedMessage {
  factory ListResponse({
    $core.Iterable<File>? file,
  }) {
    final result = create();
    if (file != null) result.file.addAll(file);
    return result;
  }

  ListResponse._();

  factory ListResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Storage'),
      createEmptyInstance: create)
    ..pPM<File>(1, _omitFieldNames ? '' : 'file', subBuilder: File.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListResponse copyWith(void Function(ListResponse) updates) =>
      super.copyWith((message) => updates(message as ListResponse))
          as ListResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListResponse create() => ListResponse._();
  @$core.override
  ListResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListResponse>(create);
  static ListResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<File> get file => $_getList(0);
}

class ReadRequest extends $pb.GeneratedMessage {
  factory ReadRequest({
    $core.String? path,
  }) {
    final result = create();
    if (path != null) result.path = path;
    return result;
  }

  ReadRequest._();

  factory ReadRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ReadRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReadRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Storage'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadRequest copyWith(void Function(ReadRequest) updates) =>
      super.copyWith((message) => updates(message as ReadRequest))
          as ReadRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ReadRequest create() => ReadRequest._();
  @$core.override
  ReadRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ReadRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReadRequest>(create);
  static ReadRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);
}

class ReadResponse extends $pb.GeneratedMessage {
  factory ReadResponse({
    File? file,
  }) {
    final result = create();
    if (file != null) result.file = file;
    return result;
  }

  ReadResponse._();

  factory ReadResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ReadResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReadResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Storage'),
      createEmptyInstance: create)
    ..aOM<File>(1, _omitFieldNames ? '' : 'file', subBuilder: File.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadResponse copyWith(void Function(ReadResponse) updates) =>
      super.copyWith((message) => updates(message as ReadResponse))
          as ReadResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ReadResponse create() => ReadResponse._();
  @$core.override
  ReadResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ReadResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReadResponse>(create);
  static ReadResponse? _defaultInstance;

  @$pb.TagNumber(1)
  File get file => $_getN(0);
  @$pb.TagNumber(1)
  set file(File value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasFile() => $_has(0);
  @$pb.TagNumber(1)
  void clearFile() => $_clearField(1);
  @$pb.TagNumber(1)
  File ensureFile() => $_ensure(0);
}

class WriteRequest extends $pb.GeneratedMessage {
  factory WriteRequest({
    $core.String? path,
    File? file,
  }) {
    final result = create();
    if (path != null) result.path = path;
    if (file != null) result.file = file;
    return result;
  }

  WriteRequest._();

  factory WriteRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory WriteRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WriteRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Storage'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..aOM<File>(2, _omitFieldNames ? '' : 'file', subBuilder: File.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WriteRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WriteRequest copyWith(void Function(WriteRequest) updates) =>
      super.copyWith((message) => updates(message as WriteRequest))
          as WriteRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static WriteRequest create() => WriteRequest._();
  @$core.override
  WriteRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static WriteRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WriteRequest>(create);
  static WriteRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);

  @$pb.TagNumber(2)
  File get file => $_getN(1);
  @$pb.TagNumber(2)
  set file(File value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasFile() => $_has(1);
  @$pb.TagNumber(2)
  void clearFile() => $_clearField(2);
  @$pb.TagNumber(2)
  File ensureFile() => $_ensure(1);
}

class DeleteRequest extends $pb.GeneratedMessage {
  factory DeleteRequest({
    $core.String? path,
    $core.bool? recursive,
  }) {
    final result = create();
    if (path != null) result.path = path;
    if (recursive != null) result.recursive = recursive;
    return result;
  }

  DeleteRequest._();

  factory DeleteRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DeleteRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeleteRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Storage'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..aOB(2, _omitFieldNames ? '' : 'recursive')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteRequest copyWith(void Function(DeleteRequest) updates) =>
      super.copyWith((message) => updates(message as DeleteRequest))
          as DeleteRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeleteRequest create() => DeleteRequest._();
  @$core.override
  DeleteRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DeleteRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeleteRequest>(create);
  static DeleteRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get recursive => $_getBF(1);
  @$pb.TagNumber(2)
  set recursive($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRecursive() => $_has(1);
  @$pb.TagNumber(2)
  void clearRecursive() => $_clearField(2);
}

class MkdirRequest extends $pb.GeneratedMessage {
  factory MkdirRequest({
    $core.String? path,
  }) {
    final result = create();
    if (path != null) result.path = path;
    return result;
  }

  MkdirRequest._();

  factory MkdirRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MkdirRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MkdirRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Storage'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MkdirRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MkdirRequest copyWith(void Function(MkdirRequest) updates) =>
      super.copyWith((message) => updates(message as MkdirRequest))
          as MkdirRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MkdirRequest create() => MkdirRequest._();
  @$core.override
  MkdirRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MkdirRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MkdirRequest>(create);
  static MkdirRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);
}

class Md5sumRequest extends $pb.GeneratedMessage {
  factory Md5sumRequest({
    $core.String? path,
  }) {
    final result = create();
    if (path != null) result.path = path;
    return result;
  }

  Md5sumRequest._();

  factory Md5sumRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Md5sumRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Md5sumRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Storage'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Md5sumRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Md5sumRequest copyWith(void Function(Md5sumRequest) updates) =>
      super.copyWith((message) => updates(message as Md5sumRequest))
          as Md5sumRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Md5sumRequest create() => Md5sumRequest._();
  @$core.override
  Md5sumRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Md5sumRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Md5sumRequest>(create);
  static Md5sumRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);
}

class Md5sumResponse extends $pb.GeneratedMessage {
  factory Md5sumResponse({
    $core.String? md5sum,
  }) {
    final result = create();
    if (md5sum != null) result.md5sum = md5sum;
    return result;
  }

  Md5sumResponse._();

  factory Md5sumResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Md5sumResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Md5sumResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Storage'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'md5sum')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Md5sumResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Md5sumResponse copyWith(void Function(Md5sumResponse) updates) =>
      super.copyWith((message) => updates(message as Md5sumResponse))
          as Md5sumResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Md5sumResponse create() => Md5sumResponse._();
  @$core.override
  Md5sumResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Md5sumResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Md5sumResponse>(create);
  static Md5sumResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get md5sum => $_getSZ(0);
  @$pb.TagNumber(1)
  set md5sum($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMd5sum() => $_has(0);
  @$pb.TagNumber(1)
  void clearMd5sum() => $_clearField(1);
}

class RenameRequest extends $pb.GeneratedMessage {
  factory RenameRequest({
    $core.String? oldPath,
    $core.String? newPath,
  }) {
    final result = create();
    if (oldPath != null) result.oldPath = oldPath;
    if (newPath != null) result.newPath = newPath;
    return result;
  }

  RenameRequest._();

  factory RenameRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RenameRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RenameRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Storage'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'oldPath')
    ..aOS(2, _omitFieldNames ? '' : 'newPath')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RenameRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RenameRequest copyWith(void Function(RenameRequest) updates) =>
      super.copyWith((message) => updates(message as RenameRequest))
          as RenameRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RenameRequest create() => RenameRequest._();
  @$core.override
  RenameRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RenameRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RenameRequest>(create);
  static RenameRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get oldPath => $_getSZ(0);
  @$pb.TagNumber(1)
  set oldPath($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOldPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearOldPath() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get newPath => $_getSZ(1);
  @$pb.TagNumber(2)
  set newPath($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNewPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearNewPath() => $_clearField(2);
}

class BackupCreateRequest extends $pb.GeneratedMessage {
  factory BackupCreateRequest({
    $core.String? archivePath,
  }) {
    final result = create();
    if (archivePath != null) result.archivePath = archivePath;
    return result;
  }

  BackupCreateRequest._();

  factory BackupCreateRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory BackupCreateRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BackupCreateRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Storage'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'archivePath')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BackupCreateRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BackupCreateRequest copyWith(void Function(BackupCreateRequest) updates) =>
      super.copyWith((message) => updates(message as BackupCreateRequest))
          as BackupCreateRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BackupCreateRequest create() => BackupCreateRequest._();
  @$core.override
  BackupCreateRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static BackupCreateRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<BackupCreateRequest>(create);
  static BackupCreateRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get archivePath => $_getSZ(0);
  @$pb.TagNumber(1)
  set archivePath($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasArchivePath() => $_has(0);
  @$pb.TagNumber(1)
  void clearArchivePath() => $_clearField(1);
}

class BackupRestoreRequest extends $pb.GeneratedMessage {
  factory BackupRestoreRequest({
    $core.String? archivePath,
  }) {
    final result = create();
    if (archivePath != null) result.archivePath = archivePath;
    return result;
  }

  BackupRestoreRequest._();

  factory BackupRestoreRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory BackupRestoreRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BackupRestoreRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Storage'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'archivePath')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BackupRestoreRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BackupRestoreRequest copyWith(void Function(BackupRestoreRequest) updates) =>
      super.copyWith((message) => updates(message as BackupRestoreRequest))
          as BackupRestoreRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BackupRestoreRequest create() => BackupRestoreRequest._();
  @$core.override
  BackupRestoreRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static BackupRestoreRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<BackupRestoreRequest>(create);
  static BackupRestoreRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get archivePath => $_getSZ(0);
  @$pb.TagNumber(1)
  set archivePath($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasArchivePath() => $_has(0);
  @$pb.TagNumber(1)
  void clearArchivePath() => $_clearField(1);
}

class TarExtractRequest extends $pb.GeneratedMessage {
  factory TarExtractRequest({
    $core.String? tarPath,
    $core.String? outPath,
  }) {
    final result = create();
    if (tarPath != null) result.tarPath = tarPath;
    if (outPath != null) result.outPath = outPath;
    return result;
  }

  TarExtractRequest._();

  factory TarExtractRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TarExtractRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TarExtractRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Storage'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'tarPath')
    ..aOS(2, _omitFieldNames ? '' : 'outPath')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TarExtractRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TarExtractRequest copyWith(void Function(TarExtractRequest) updates) =>
      super.copyWith((message) => updates(message as TarExtractRequest))
          as TarExtractRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TarExtractRequest create() => TarExtractRequest._();
  @$core.override
  TarExtractRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TarExtractRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TarExtractRequest>(create);
  static TarExtractRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get tarPath => $_getSZ(0);
  @$pb.TagNumber(1)
  set tarPath($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTarPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearTarPath() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get outPath => $_getSZ(1);
  @$pb.TagNumber(2)
  set outPath($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOutPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearOutPath() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
