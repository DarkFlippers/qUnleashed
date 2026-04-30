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

class RebootRequest_RebootMode extends $pb.ProtobufEnum {
  static const RebootRequest_RebootMode OS =
      RebootRequest_RebootMode._(0, _omitEnumNames ? '' : 'OS');
  static const RebootRequest_RebootMode DFU =
      RebootRequest_RebootMode._(1, _omitEnumNames ? '' : 'DFU');
  static const RebootRequest_RebootMode UPDATE =
      RebootRequest_RebootMode._(2, _omitEnumNames ? '' : 'UPDATE');

  static const $core.List<RebootRequest_RebootMode> values =
      <RebootRequest_RebootMode>[
    OS,
    DFU,
    UPDATE,
  ];

  static final $core.List<RebootRequest_RebootMode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static RebootRequest_RebootMode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const RebootRequest_RebootMode._(super.value, super.name);
}

class UpdateResponse_UpdateResultCode extends $pb.ProtobufEnum {
  static const UpdateResponse_UpdateResultCode OK =
      UpdateResponse_UpdateResultCode._(0, _omitEnumNames ? '' : 'OK');
  static const UpdateResponse_UpdateResultCode ManifestPathInvalid =
      UpdateResponse_UpdateResultCode._(
          1, _omitEnumNames ? '' : 'ManifestPathInvalid');
  static const UpdateResponse_UpdateResultCode ManifestFolderNotFound =
      UpdateResponse_UpdateResultCode._(
          2, _omitEnumNames ? '' : 'ManifestFolderNotFound');
  static const UpdateResponse_UpdateResultCode ManifestInvalid =
      UpdateResponse_UpdateResultCode._(
          3, _omitEnumNames ? '' : 'ManifestInvalid');
  static const UpdateResponse_UpdateResultCode StageMissing =
      UpdateResponse_UpdateResultCode._(
          4, _omitEnumNames ? '' : 'StageMissing');
  static const UpdateResponse_UpdateResultCode StageIntegrityError =
      UpdateResponse_UpdateResultCode._(
          5, _omitEnumNames ? '' : 'StageIntegrityError');
  static const UpdateResponse_UpdateResultCode ManifestPointerError =
      UpdateResponse_UpdateResultCode._(
          6, _omitEnumNames ? '' : 'ManifestPointerError');
  static const UpdateResponse_UpdateResultCode TargetMismatch =
      UpdateResponse_UpdateResultCode._(
          7, _omitEnumNames ? '' : 'TargetMismatch');
  static const UpdateResponse_UpdateResultCode OutdatedManifestVersion =
      UpdateResponse_UpdateResultCode._(
          8, _omitEnumNames ? '' : 'OutdatedManifestVersion');
  static const UpdateResponse_UpdateResultCode IntFull =
      UpdateResponse_UpdateResultCode._(9, _omitEnumNames ? '' : 'IntFull');
  static const UpdateResponse_UpdateResultCode UnspecifiedError =
      UpdateResponse_UpdateResultCode._(
          10, _omitEnumNames ? '' : 'UnspecifiedError');

  static const $core.List<UpdateResponse_UpdateResultCode> values =
      <UpdateResponse_UpdateResultCode>[
    OK,
    ManifestPathInvalid,
    ManifestFolderNotFound,
    ManifestInvalid,
    StageMissing,
    StageIntegrityError,
    ManifestPointerError,
    TargetMismatch,
    OutdatedManifestVersion,
    IntFull,
    UnspecifiedError,
  ];

  static final $core.List<UpdateResponse_UpdateResultCode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 10);
  static UpdateResponse_UpdateResultCode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const UpdateResponse_UpdateResultCode._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
