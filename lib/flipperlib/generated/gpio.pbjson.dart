// This is a generated file - do not edit.
//
// Generated from gpio.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use gpioPinDescriptor instead')
const GpioPin$json = {
  '1': 'GpioPin',
  '2': [
    {'1': 'PC0', '2': 0},
    {'1': 'PC1', '2': 1},
    {'1': 'PC3', '2': 2},
    {'1': 'PB2', '2': 3},
    {'1': 'PB3', '2': 4},
    {'1': 'PA4', '2': 5},
    {'1': 'PA6', '2': 6},
    {'1': 'PA7', '2': 7},
  ],
};

/// Descriptor for `GpioPin`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List gpioPinDescriptor = $convert.base64Decode(
    'CgdHcGlvUGluEgcKA1BDMBAAEgcKA1BDMRABEgcKA1BDMxACEgcKA1BCMhADEgcKA1BCMxAEEg'
    'cKA1BBNBAFEgcKA1BBNhAGEgcKA1BBNxAH');

@$core.Deprecated('Use gpioPinModeDescriptor instead')
const GpioPinMode$json = {
  '1': 'GpioPinMode',
  '2': [
    {'1': 'OUTPUT', '2': 0},
    {'1': 'INPUT', '2': 1},
  ],
};

/// Descriptor for `GpioPinMode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List gpioPinModeDescriptor =
    $convert.base64Decode('CgtHcGlvUGluTW9kZRIKCgZPVVRQVVQQABIJCgVJTlBVVBAB');

@$core.Deprecated('Use gpioInputPullDescriptor instead')
const GpioInputPull$json = {
  '1': 'GpioInputPull',
  '2': [
    {'1': 'NO', '2': 0},
    {'1': 'UP', '2': 1},
    {'1': 'DOWN', '2': 2},
  ],
};

/// Descriptor for `GpioInputPull`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List gpioInputPullDescriptor = $convert
    .base64Decode('Cg1HcGlvSW5wdXRQdWxsEgYKAk5PEAASBgoCVVAQARIICgRET1dOEAI=');

@$core.Deprecated('Use gpioOtgModeDescriptor instead')
const GpioOtgMode$json = {
  '1': 'GpioOtgMode',
  '2': [
    {'1': 'OFF', '2': 0},
    {'1': 'ON', '2': 1},
  ],
};

/// Descriptor for `GpioOtgMode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List gpioOtgModeDescriptor =
    $convert.base64Decode('CgtHcGlvT3RnTW9kZRIHCgNPRkYQABIGCgJPThAB');

@$core.Deprecated('Use setPinModeDescriptor instead')
const SetPinMode$json = {
  '1': 'SetPinMode',
  '2': [
    {'1': 'pin', '3': 1, '4': 1, '5': 14, '6': '.PB_Gpio.GpioPin', '10': 'pin'},
    {
      '1': 'mode',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.PB_Gpio.GpioPinMode',
      '10': 'mode'
    },
  ],
};

/// Descriptor for `SetPinMode`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setPinModeDescriptor = $convert.base64Decode(
    'CgpTZXRQaW5Nb2RlEiIKA3BpbhgBIAEoDjIQLlBCX0dwaW8uR3Bpb1BpblIDcGluEigKBG1vZG'
    'UYAiABKA4yFC5QQl9HcGlvLkdwaW9QaW5Nb2RlUgRtb2Rl');

@$core.Deprecated('Use setInputPullDescriptor instead')
const SetInputPull$json = {
  '1': 'SetInputPull',
  '2': [
    {'1': 'pin', '3': 1, '4': 1, '5': 14, '6': '.PB_Gpio.GpioPin', '10': 'pin'},
    {
      '1': 'pull_mode',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.PB_Gpio.GpioInputPull',
      '10': 'pullMode'
    },
  ],
};

/// Descriptor for `SetInputPull`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setInputPullDescriptor = $convert.base64Decode(
    'CgxTZXRJbnB1dFB1bGwSIgoDcGluGAEgASgOMhAuUEJfR3Bpby5HcGlvUGluUgNwaW4SMwoJcH'
    'VsbF9tb2RlGAIgASgOMhYuUEJfR3Bpby5HcGlvSW5wdXRQdWxsUghwdWxsTW9kZQ==');

@$core.Deprecated('Use getPinModeDescriptor instead')
const GetPinMode$json = {
  '1': 'GetPinMode',
  '2': [
    {'1': 'pin', '3': 1, '4': 1, '5': 14, '6': '.PB_Gpio.GpioPin', '10': 'pin'},
  ],
};

/// Descriptor for `GetPinMode`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getPinModeDescriptor = $convert.base64Decode(
    'CgpHZXRQaW5Nb2RlEiIKA3BpbhgBIAEoDjIQLlBCX0dwaW8uR3Bpb1BpblIDcGlu');

@$core.Deprecated('Use getPinModeResponseDescriptor instead')
const GetPinModeResponse$json = {
  '1': 'GetPinModeResponse',
  '2': [
    {
      '1': 'mode',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.PB_Gpio.GpioPinMode',
      '10': 'mode'
    },
  ],
};

/// Descriptor for `GetPinModeResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getPinModeResponseDescriptor = $convert.base64Decode(
    'ChJHZXRQaW5Nb2RlUmVzcG9uc2USKAoEbW9kZRgBIAEoDjIULlBCX0dwaW8uR3Bpb1Bpbk1vZG'
    'VSBG1vZGU=');

@$core.Deprecated('Use readPinDescriptor instead')
const ReadPin$json = {
  '1': 'ReadPin',
  '2': [
    {'1': 'pin', '3': 1, '4': 1, '5': 14, '6': '.PB_Gpio.GpioPin', '10': 'pin'},
  ],
};

/// Descriptor for `ReadPin`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List readPinDescriptor = $convert.base64Decode(
    'CgdSZWFkUGluEiIKA3BpbhgBIAEoDjIQLlBCX0dwaW8uR3Bpb1BpblIDcGlu');

@$core.Deprecated('Use readPinResponseDescriptor instead')
const ReadPinResponse$json = {
  '1': 'ReadPinResponse',
  '2': [
    {'1': 'value', '3': 2, '4': 1, '5': 13, '10': 'value'},
  ],
};

/// Descriptor for `ReadPinResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List readPinResponseDescriptor = $convert
    .base64Decode('Cg9SZWFkUGluUmVzcG9uc2USFAoFdmFsdWUYAiABKA1SBXZhbHVl');

@$core.Deprecated('Use writePinDescriptor instead')
const WritePin$json = {
  '1': 'WritePin',
  '2': [
    {'1': 'pin', '3': 1, '4': 1, '5': 14, '6': '.PB_Gpio.GpioPin', '10': 'pin'},
    {'1': 'value', '3': 2, '4': 1, '5': 13, '10': 'value'},
  ],
};

/// Descriptor for `WritePin`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List writePinDescriptor = $convert.base64Decode(
    'CghXcml0ZVBpbhIiCgNwaW4YASABKA4yEC5QQl9HcGlvLkdwaW9QaW5SA3BpbhIUCgV2YWx1ZR'
    'gCIAEoDVIFdmFsdWU=');

@$core.Deprecated('Use getOtgModeDescriptor instead')
const GetOtgMode$json = {
  '1': 'GetOtgMode',
};

/// Descriptor for `GetOtgMode`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getOtgModeDescriptor =
    $convert.base64Decode('CgpHZXRPdGdNb2Rl');

@$core.Deprecated('Use getOtgModeResponseDescriptor instead')
const GetOtgModeResponse$json = {
  '1': 'GetOtgModeResponse',
  '2': [
    {
      '1': 'mode',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.PB_Gpio.GpioOtgMode',
      '10': 'mode'
    },
  ],
};

/// Descriptor for `GetOtgModeResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getOtgModeResponseDescriptor = $convert.base64Decode(
    'ChJHZXRPdGdNb2RlUmVzcG9uc2USKAoEbW9kZRgBIAEoDjIULlBCX0dwaW8uR3Bpb090Z01vZG'
    'VSBG1vZGU=');

@$core.Deprecated('Use setOtgModeDescriptor instead')
const SetOtgMode$json = {
  '1': 'SetOtgMode',
  '2': [
    {
      '1': 'mode',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.PB_Gpio.GpioOtgMode',
      '10': 'mode'
    },
  ],
};

/// Descriptor for `SetOtgMode`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setOtgModeDescriptor = $convert.base64Decode(
    'CgpTZXRPdGdNb2RlEigKBG1vZGUYASABKA4yFC5QQl9HcGlvLkdwaW9PdGdNb2RlUgRtb2Rl');
