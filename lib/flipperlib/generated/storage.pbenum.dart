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

import 'package:protobuf/protobuf.dart' as $pb;

class File_FileType extends $pb.ProtobufEnum {
  static const File_FileType FILE =
      File_FileType._(0, _omitEnumNames ? '' : 'FILE');
  static const File_FileType DIR =
      File_FileType._(1, _omitEnumNames ? '' : 'DIR');

  static const $core.List<File_FileType> values = <File_FileType>[
    FILE,
    DIR,
  ];

  static final $core.List<File_FileType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 1);
  static File_FileType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const File_FileType._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
