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

class CommandStatus extends $pb.ProtobufEnum {
  static const CommandStatus OK =
      CommandStatus._(0, _omitEnumNames ? '' : 'OK');

  /// *< Common Errors
  static const CommandStatus ERROR =
      CommandStatus._(1, _omitEnumNames ? '' : 'ERROR');
  static const CommandStatus ERROR_DECODE =
      CommandStatus._(2, _omitEnumNames ? '' : 'ERROR_DECODE');
  static const CommandStatus ERROR_NOT_IMPLEMENTED =
      CommandStatus._(3, _omitEnumNames ? '' : 'ERROR_NOT_IMPLEMENTED');
  static const CommandStatus ERROR_BUSY =
      CommandStatus._(4, _omitEnumNames ? '' : 'ERROR_BUSY');
  static const CommandStatus ERROR_CONTINUOUS_COMMAND_INTERRUPTED =
      CommandStatus._(
          14, _omitEnumNames ? '' : 'ERROR_CONTINUOUS_COMMAND_INTERRUPTED');
  static const CommandStatus ERROR_INVALID_PARAMETERS =
      CommandStatus._(15, _omitEnumNames ? '' : 'ERROR_INVALID_PARAMETERS');

  /// *< Storage Errors
  static const CommandStatus ERROR_STORAGE_NOT_READY =
      CommandStatus._(5, _omitEnumNames ? '' : 'ERROR_STORAGE_NOT_READY');
  static const CommandStatus ERROR_STORAGE_EXIST =
      CommandStatus._(6, _omitEnumNames ? '' : 'ERROR_STORAGE_EXIST');
  static const CommandStatus ERROR_STORAGE_NOT_EXIST =
      CommandStatus._(7, _omitEnumNames ? '' : 'ERROR_STORAGE_NOT_EXIST');
  static const CommandStatus ERROR_STORAGE_INVALID_PARAMETER = CommandStatus._(
      8, _omitEnumNames ? '' : 'ERROR_STORAGE_INVALID_PARAMETER');
  static const CommandStatus ERROR_STORAGE_DENIED =
      CommandStatus._(9, _omitEnumNames ? '' : 'ERROR_STORAGE_DENIED');
  static const CommandStatus ERROR_STORAGE_INVALID_NAME =
      CommandStatus._(10, _omitEnumNames ? '' : 'ERROR_STORAGE_INVALID_NAME');
  static const CommandStatus ERROR_STORAGE_INTERNAL =
      CommandStatus._(11, _omitEnumNames ? '' : 'ERROR_STORAGE_INTERNAL');
  static const CommandStatus ERROR_STORAGE_NOT_IMPLEMENTED = CommandStatus._(
      12, _omitEnumNames ? '' : 'ERROR_STORAGE_NOT_IMPLEMENTED');
  static const CommandStatus ERROR_STORAGE_ALREADY_OPEN =
      CommandStatus._(13, _omitEnumNames ? '' : 'ERROR_STORAGE_ALREADY_OPEN');
  static const CommandStatus ERROR_STORAGE_DIR_NOT_EMPTY =
      CommandStatus._(18, _omitEnumNames ? '' : 'ERROR_STORAGE_DIR_NOT_EMPTY');

  /// *< Application Errors
  static const CommandStatus ERROR_APP_CANT_START =
      CommandStatus._(16, _omitEnumNames ? '' : 'ERROR_APP_CANT_START');
  static const CommandStatus ERROR_APP_SYSTEM_LOCKED =
      CommandStatus._(17, _omitEnumNames ? '' : 'ERROR_APP_SYSTEM_LOCKED');
  static const CommandStatus ERROR_APP_NOT_RUNNING =
      CommandStatus._(21, _omitEnumNames ? '' : 'ERROR_APP_NOT_RUNNING');
  static const CommandStatus ERROR_APP_CMD_ERROR =
      CommandStatus._(22, _omitEnumNames ? '' : 'ERROR_APP_CMD_ERROR');

  /// *< Virtual Display Errors
  static const CommandStatus ERROR_VIRTUAL_DISPLAY_ALREADY_STARTED =
      CommandStatus._(
          19, _omitEnumNames ? '' : 'ERROR_VIRTUAL_DISPLAY_ALREADY_STARTED');
  static const CommandStatus ERROR_VIRTUAL_DISPLAY_NOT_STARTED =
      CommandStatus._(
          20, _omitEnumNames ? '' : 'ERROR_VIRTUAL_DISPLAY_NOT_STARTED');

  /// *< GPIO Errors
  static const CommandStatus ERROR_GPIO_MODE_INCORRECT =
      CommandStatus._(58, _omitEnumNames ? '' : 'ERROR_GPIO_MODE_INCORRECT');
  static const CommandStatus ERROR_GPIO_UNKNOWN_PIN_MODE =
      CommandStatus._(59, _omitEnumNames ? '' : 'ERROR_GPIO_UNKNOWN_PIN_MODE');

  static const $core.List<CommandStatus> values = <CommandStatus>[
    OK,
    ERROR,
    ERROR_DECODE,
    ERROR_NOT_IMPLEMENTED,
    ERROR_BUSY,
    ERROR_CONTINUOUS_COMMAND_INTERRUPTED,
    ERROR_INVALID_PARAMETERS,
    ERROR_STORAGE_NOT_READY,
    ERROR_STORAGE_EXIST,
    ERROR_STORAGE_NOT_EXIST,
    ERROR_STORAGE_INVALID_PARAMETER,
    ERROR_STORAGE_DENIED,
    ERROR_STORAGE_INVALID_NAME,
    ERROR_STORAGE_INTERNAL,
    ERROR_STORAGE_NOT_IMPLEMENTED,
    ERROR_STORAGE_ALREADY_OPEN,
    ERROR_STORAGE_DIR_NOT_EMPTY,
    ERROR_APP_CANT_START,
    ERROR_APP_SYSTEM_LOCKED,
    ERROR_APP_NOT_RUNNING,
    ERROR_APP_CMD_ERROR,
    ERROR_VIRTUAL_DISPLAY_ALREADY_STARTED,
    ERROR_VIRTUAL_DISPLAY_NOT_STARTED,
    ERROR_GPIO_MODE_INCORRECT,
    ERROR_GPIO_UNKNOWN_PIN_MODE,
  ];

  static final $core.Map<$core.int, CommandStatus> _byValue =
      $pb.ProtobufEnum.initByValue(values);
  static CommandStatus? valueOf($core.int value) => _byValue[value];

  const CommandStatus._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
