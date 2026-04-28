// This is a generated file - do not edit.
//
// Generated from gui.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class InputKey extends $pb.ProtobufEnum {
  static const InputKey UP = InputKey._(0, _omitEnumNames ? '' : 'UP');
  static const InputKey DOWN = InputKey._(1, _omitEnumNames ? '' : 'DOWN');
  static const InputKey RIGHT = InputKey._(2, _omitEnumNames ? '' : 'RIGHT');
  static const InputKey LEFT = InputKey._(3, _omitEnumNames ? '' : 'LEFT');
  static const InputKey OK = InputKey._(4, _omitEnumNames ? '' : 'OK');
  static const InputKey BACK = InputKey._(5, _omitEnumNames ? '' : 'BACK');

  static const $core.List<InputKey> values = <InputKey>[
    UP,
    DOWN,
    RIGHT,
    LEFT,
    OK,
    BACK,
  ];

  static final $core.List<InputKey?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static InputKey? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const InputKey._(super.value, super.name);
}

class InputType extends $pb.ProtobufEnum {
  static const InputType PRESS = InputType._(0, _omitEnumNames ? '' : 'PRESS');
  static const InputType RELEASE =
      InputType._(1, _omitEnumNames ? '' : 'RELEASE');
  static const InputType SHORT = InputType._(2, _omitEnumNames ? '' : 'SHORT');
  static const InputType LONG = InputType._(3, _omitEnumNames ? '' : 'LONG');
  static const InputType REPEAT =
      InputType._(4, _omitEnumNames ? '' : 'REPEAT');

  static const $core.List<InputType> values = <InputType>[
    PRESS,
    RELEASE,
    SHORT,
    LONG,
    REPEAT,
  ];

  static final $core.List<InputType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static InputType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const InputType._(super.value, super.name);
}

class ScreenOrientation extends $pb.ProtobufEnum {
  static const ScreenOrientation HORIZONTAL =
      ScreenOrientation._(0, _omitEnumNames ? '' : 'HORIZONTAL');
  static const ScreenOrientation HORIZONTAL_FLIP =
      ScreenOrientation._(1, _omitEnumNames ? '' : 'HORIZONTAL_FLIP');
  static const ScreenOrientation VERTICAL =
      ScreenOrientation._(2, _omitEnumNames ? '' : 'VERTICAL');
  static const ScreenOrientation VERTICAL_FLIP =
      ScreenOrientation._(3, _omitEnumNames ? '' : 'VERTICAL_FLIP');

  static const $core.List<ScreenOrientation> values = <ScreenOrientation>[
    HORIZONTAL,
    HORIZONTAL_FLIP,
    VERTICAL,
    VERTICAL_FLIP,
  ];

  static final $core.List<ScreenOrientation?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static ScreenOrientation? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ScreenOrientation._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
