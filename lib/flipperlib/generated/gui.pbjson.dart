// This is a generated file - do not edit.
//
// Generated from gui.proto.

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

@$core.Deprecated('Use inputKeyDescriptor instead')
const InputKey$json = {
  '1': 'InputKey',
  '2': [
    {'1': 'UP', '2': 0},
    {'1': 'DOWN', '2': 1},
    {'1': 'RIGHT', '2': 2},
    {'1': 'LEFT', '2': 3},
    {'1': 'OK', '2': 4},
    {'1': 'BACK', '2': 5},
  ],
};

/// Descriptor for `InputKey`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List inputKeyDescriptor = $convert.base64Decode(
    'CghJbnB1dEtleRIGCgJVUBAAEggKBERPV04QARIJCgVSSUdIVBACEggKBExFRlQQAxIGCgJPSx'
    'AEEggKBEJBQ0sQBQ==');

@$core.Deprecated('Use inputTypeDescriptor instead')
const InputType$json = {
  '1': 'InputType',
  '2': [
    {'1': 'PRESS', '2': 0},
    {'1': 'RELEASE', '2': 1},
    {'1': 'SHORT', '2': 2},
    {'1': 'LONG', '2': 3},
    {'1': 'REPEAT', '2': 4},
  ],
};

/// Descriptor for `InputType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List inputTypeDescriptor = $convert.base64Decode(
    'CglJbnB1dFR5cGUSCQoFUFJFU1MQABILCgdSRUxFQVNFEAESCQoFU0hPUlQQAhIICgRMT05HEA'
    'MSCgoGUkVQRUFUEAQ=');

@$core.Deprecated('Use screenOrientationDescriptor instead')
const ScreenOrientation$json = {
  '1': 'ScreenOrientation',
  '2': [
    {'1': 'HORIZONTAL', '2': 0},
    {'1': 'HORIZONTAL_FLIP', '2': 1},
    {'1': 'VERTICAL', '2': 2},
    {'1': 'VERTICAL_FLIP', '2': 3},
  ],
};

/// Descriptor for `ScreenOrientation`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List screenOrientationDescriptor = $convert.base64Decode(
    'ChFTY3JlZW5PcmllbnRhdGlvbhIOCgpIT1JJWk9OVEFMEAASEwoPSE9SSVpPTlRBTF9GTElQEA'
    'ESDAoIVkVSVElDQUwQAhIRCg1WRVJUSUNBTF9GTElQEAM=');

@$core.Deprecated('Use screenFrameDescriptor instead')
const ScreenFrame$json = {
  '1': 'ScreenFrame',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
    {
      '1': 'orientation',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.PB_Gui.ScreenOrientation',
      '10': 'orientation'
    },
  ],
};

/// Descriptor for `ScreenFrame`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List screenFrameDescriptor = $convert.base64Decode(
    'CgtTY3JlZW5GcmFtZRISCgRkYXRhGAEgASgMUgRkYXRhEjsKC29yaWVudGF0aW9uGAIgASgOMh'
    'kuUEJfR3VpLlNjcmVlbk9yaWVudGF0aW9uUgtvcmllbnRhdGlvbg==');

@$core.Deprecated('Use startScreenStreamRequestDescriptor instead')
const StartScreenStreamRequest$json = {
  '1': 'StartScreenStreamRequest',
};

/// Descriptor for `StartScreenStreamRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startScreenStreamRequestDescriptor =
    $convert.base64Decode('ChhTdGFydFNjcmVlblN0cmVhbVJlcXVlc3Q=');

@$core.Deprecated('Use stopScreenStreamRequestDescriptor instead')
const StopScreenStreamRequest$json = {
  '1': 'StopScreenStreamRequest',
};

/// Descriptor for `StopScreenStreamRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List stopScreenStreamRequestDescriptor =
    $convert.base64Decode('ChdTdG9wU2NyZWVuU3RyZWFtUmVxdWVzdA==');

@$core.Deprecated('Use sendInputEventRequestDescriptor instead')
const SendInputEventRequest$json = {
  '1': 'SendInputEventRequest',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 14, '6': '.PB_Gui.InputKey', '10': 'key'},
    {
      '1': 'type',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.PB_Gui.InputType',
      '10': 'type'
    },
  ],
};

/// Descriptor for `SendInputEventRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sendInputEventRequestDescriptor = $convert.base64Decode(
    'ChVTZW5kSW5wdXRFdmVudFJlcXVlc3QSIgoDa2V5GAEgASgOMhAuUEJfR3VpLklucHV0S2V5Ug'
    'NrZXkSJQoEdHlwZRgCIAEoDjIRLlBCX0d1aS5JbnB1dFR5cGVSBHR5cGU=');

@$core.Deprecated('Use startVirtualDisplayRequestDescriptor instead')
const StartVirtualDisplayRequest$json = {
  '1': 'StartVirtualDisplayRequest',
  '2': [
    {
      '1': 'first_frame',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.PB_Gui.ScreenFrame',
      '10': 'firstFrame'
    },
    {'1': 'send_input', '3': 2, '4': 1, '5': 8, '10': 'sendInput'},
  ],
};

/// Descriptor for `StartVirtualDisplayRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startVirtualDisplayRequestDescriptor =
    $convert.base64Decode(
        'ChpTdGFydFZpcnR1YWxEaXNwbGF5UmVxdWVzdBI0CgtmaXJzdF9mcmFtZRgBIAEoCzITLlBCX0'
        'd1aS5TY3JlZW5GcmFtZVIKZmlyc3RGcmFtZRIdCgpzZW5kX2lucHV0GAIgASgIUglzZW5kSW5w'
        'dXQ=');

@$core.Deprecated('Use stopVirtualDisplayRequestDescriptor instead')
const StopVirtualDisplayRequest$json = {
  '1': 'StopVirtualDisplayRequest',
};

/// Descriptor for `StopVirtualDisplayRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List stopVirtualDisplayRequestDescriptor =
    $convert.base64Decode('ChlTdG9wVmlydHVhbERpc3BsYXlSZXF1ZXN0');
