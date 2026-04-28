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

class GpioPin extends $pb.ProtobufEnum {
  static const GpioPin PC0 = GpioPin._(0, _omitEnumNames ? '' : 'PC0');
  static const GpioPin PC1 = GpioPin._(1, _omitEnumNames ? '' : 'PC1');
  static const GpioPin PC3 = GpioPin._(2, _omitEnumNames ? '' : 'PC3');
  static const GpioPin PB2 = GpioPin._(3, _omitEnumNames ? '' : 'PB2');
  static const GpioPin PB3 = GpioPin._(4, _omitEnumNames ? '' : 'PB3');
  static const GpioPin PA4 = GpioPin._(5, _omitEnumNames ? '' : 'PA4');
  static const GpioPin PA6 = GpioPin._(6, _omitEnumNames ? '' : 'PA6');
  static const GpioPin PA7 = GpioPin._(7, _omitEnumNames ? '' : 'PA7');

  static const $core.List<GpioPin> values = <GpioPin>[
    PC0,
    PC1,
    PC3,
    PB2,
    PB3,
    PA4,
    PA6,
    PA7,
  ];

  static final $core.List<GpioPin?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 7);
  static GpioPin? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const GpioPin._(super.value, super.name);
}

class GpioPinMode extends $pb.ProtobufEnum {
  static const GpioPinMode OUTPUT =
      GpioPinMode._(0, _omitEnumNames ? '' : 'OUTPUT');
  static const GpioPinMode INPUT =
      GpioPinMode._(1, _omitEnumNames ? '' : 'INPUT');

  static const $core.List<GpioPinMode> values = <GpioPinMode>[
    OUTPUT,
    INPUT,
  ];

  static final $core.List<GpioPinMode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 1);
  static GpioPinMode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const GpioPinMode._(super.value, super.name);
}

class GpioInputPull extends $pb.ProtobufEnum {
  static const GpioInputPull NO =
      GpioInputPull._(0, _omitEnumNames ? '' : 'NO');
  static const GpioInputPull UP =
      GpioInputPull._(1, _omitEnumNames ? '' : 'UP');
  static const GpioInputPull DOWN =
      GpioInputPull._(2, _omitEnumNames ? '' : 'DOWN');

  static const $core.List<GpioInputPull> values = <GpioInputPull>[
    NO,
    UP,
    DOWN,
  ];

  static final $core.List<GpioInputPull?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static GpioInputPull? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const GpioInputPull._(super.value, super.name);
}

class GpioOtgMode extends $pb.ProtobufEnum {
  static const GpioOtgMode OFF = GpioOtgMode._(0, _omitEnumNames ? '' : 'OFF');
  static const GpioOtgMode ON = GpioOtgMode._(1, _omitEnumNames ? '' : 'ON');

  static const $core.List<GpioOtgMode> values = <GpioOtgMode>[
    OFF,
    ON,
  ];

  static final $core.List<GpioOtgMode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 1);
  static GpioOtgMode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const GpioOtgMode._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
