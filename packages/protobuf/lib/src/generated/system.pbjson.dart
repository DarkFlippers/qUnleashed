// This is a generated file - do not edit.
//
// Generated from system.proto.

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

@$core.Deprecated('Use pingRequestDescriptor instead')
const PingRequest$json = {
  '1': 'PingRequest',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `PingRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pingRequestDescriptor =
    $convert.base64Decode('CgtQaW5nUmVxdWVzdBISCgRkYXRhGAEgASgMUgRkYXRh');

@$core.Deprecated('Use pingResponseDescriptor instead')
const PingResponse$json = {
  '1': 'PingResponse',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `PingResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pingResponseDescriptor =
    $convert.base64Decode('CgxQaW5nUmVzcG9uc2USEgoEZGF0YRgBIAEoDFIEZGF0YQ==');

@$core.Deprecated('Use rebootRequestDescriptor instead')
const RebootRequest$json = {
  '1': 'RebootRequest',
  '2': [
    {
      '1': 'mode',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.PB_System.RebootRequest.RebootMode',
      '10': 'mode'
    },
  ],
  '4': [RebootRequest_RebootMode$json],
};

@$core.Deprecated('Use rebootRequestDescriptor instead')
const RebootRequest_RebootMode$json = {
  '1': 'RebootMode',
  '2': [
    {'1': 'OS', '2': 0},
    {'1': 'DFU', '2': 1},
    {'1': 'UPDATE', '2': 2},
  ],
};

/// Descriptor for `RebootRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rebootRequestDescriptor = $convert.base64Decode(
    'Cg1SZWJvb3RSZXF1ZXN0EjcKBG1vZGUYASABKA4yIy5QQl9TeXN0ZW0uUmVib290UmVxdWVzdC'
    '5SZWJvb3RNb2RlUgRtb2RlIikKClJlYm9vdE1vZGUSBgoCT1MQABIHCgNERlUQARIKCgZVUERB'
    'VEUQAg==');

@$core.Deprecated('Use deviceInfoRequestDescriptor instead')
const DeviceInfoRequest$json = {
  '1': 'DeviceInfoRequest',
};

/// Descriptor for `DeviceInfoRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceInfoRequestDescriptor =
    $convert.base64Decode('ChFEZXZpY2VJbmZvUmVxdWVzdA==');

@$core.Deprecated('Use deviceInfoResponseDescriptor instead')
const DeviceInfoResponse$json = {
  '1': 'DeviceInfoResponse',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
};

/// Descriptor for `DeviceInfoResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceInfoResponseDescriptor = $convert.base64Decode(
    'ChJEZXZpY2VJbmZvUmVzcG9uc2USEAoDa2V5GAEgASgJUgNrZXkSFAoFdmFsdWUYAiABKAlSBX'
    'ZhbHVl');

@$core.Deprecated('Use factoryResetRequestDescriptor instead')
const FactoryResetRequest$json = {
  '1': 'FactoryResetRequest',
};

/// Descriptor for `FactoryResetRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List factoryResetRequestDescriptor =
    $convert.base64Decode('ChNGYWN0b3J5UmVzZXRSZXF1ZXN0');

@$core.Deprecated('Use getDateTimeRequestDescriptor instead')
const GetDateTimeRequest$json = {
  '1': 'GetDateTimeRequest',
};

/// Descriptor for `GetDateTimeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getDateTimeRequestDescriptor =
    $convert.base64Decode('ChJHZXREYXRlVGltZVJlcXVlc3Q=');

@$core.Deprecated('Use getDateTimeResponseDescriptor instead')
const GetDateTimeResponse$json = {
  '1': 'GetDateTimeResponse',
  '2': [
    {
      '1': 'datetime',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.PB_System.DateTime',
      '10': 'datetime'
    },
  ],
};

/// Descriptor for `GetDateTimeResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getDateTimeResponseDescriptor = $convert.base64Decode(
    'ChNHZXREYXRlVGltZVJlc3BvbnNlEi8KCGRhdGV0aW1lGAEgASgLMhMuUEJfU3lzdGVtLkRhdG'
    'VUaW1lUghkYXRldGltZQ==');

@$core.Deprecated('Use setDateTimeRequestDescriptor instead')
const SetDateTimeRequest$json = {
  '1': 'SetDateTimeRequest',
  '2': [
    {
      '1': 'datetime',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.PB_System.DateTime',
      '10': 'datetime'
    },
  ],
};

/// Descriptor for `SetDateTimeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setDateTimeRequestDescriptor = $convert.base64Decode(
    'ChJTZXREYXRlVGltZVJlcXVlc3QSLwoIZGF0ZXRpbWUYASABKAsyEy5QQl9TeXN0ZW0uRGF0ZV'
    'RpbWVSCGRhdGV0aW1l');

@$core.Deprecated('Use dateTimeDescriptor instead')
const DateTime$json = {
  '1': 'DateTime',
  '2': [
    {'1': 'hour', '3': 1, '4': 1, '5': 13, '10': 'hour'},
    {'1': 'minute', '3': 2, '4': 1, '5': 13, '10': 'minute'},
    {'1': 'second', '3': 3, '4': 1, '5': 13, '10': 'second'},
    {'1': 'day', '3': 4, '4': 1, '5': 13, '10': 'day'},
    {'1': 'month', '3': 5, '4': 1, '5': 13, '10': 'month'},
    {'1': 'year', '3': 6, '4': 1, '5': 13, '10': 'year'},
    {'1': 'weekday', '3': 7, '4': 1, '5': 13, '10': 'weekday'},
  ],
};

/// Descriptor for `DateTime`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dateTimeDescriptor = $convert.base64Decode(
    'CghEYXRlVGltZRISCgRob3VyGAEgASgNUgRob3VyEhYKBm1pbnV0ZRgCIAEoDVIGbWludXRlEh'
    'YKBnNlY29uZBgDIAEoDVIGc2Vjb25kEhAKA2RheRgEIAEoDVIDZGF5EhQKBW1vbnRoGAUgASgN'
    'UgVtb250aBISCgR5ZWFyGAYgASgNUgR5ZWFyEhgKB3dlZWtkYXkYByABKA1SB3dlZWtkYXk=');

@$core.Deprecated('Use playAudiovisualAlertRequestDescriptor instead')
const PlayAudiovisualAlertRequest$json = {
  '1': 'PlayAudiovisualAlertRequest',
};

/// Descriptor for `PlayAudiovisualAlertRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List playAudiovisualAlertRequestDescriptor =
    $convert.base64Decode('ChtQbGF5QXVkaW92aXN1YWxBbGVydFJlcXVlc3Q=');

@$core.Deprecated('Use protobufVersionRequestDescriptor instead')
const ProtobufVersionRequest$json = {
  '1': 'ProtobufVersionRequest',
};

/// Descriptor for `ProtobufVersionRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List protobufVersionRequestDescriptor =
    $convert.base64Decode('ChZQcm90b2J1ZlZlcnNpb25SZXF1ZXN0');

@$core.Deprecated('Use protobufVersionResponseDescriptor instead')
const ProtobufVersionResponse$json = {
  '1': 'ProtobufVersionResponse',
  '2': [
    {'1': 'major', '3': 1, '4': 1, '5': 13, '10': 'major'},
    {'1': 'minor', '3': 2, '4': 1, '5': 13, '10': 'minor'},
  ],
};

/// Descriptor for `ProtobufVersionResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List protobufVersionResponseDescriptor =
    $convert.base64Decode(
        'ChdQcm90b2J1ZlZlcnNpb25SZXNwb25zZRIUCgVtYWpvchgBIAEoDVIFbWFqb3ISFAoFbWlub3'
        'IYAiABKA1SBW1pbm9y');

@$core.Deprecated('Use updateRequestDescriptor instead')
const UpdateRequest$json = {
  '1': 'UpdateRequest',
  '2': [
    {'1': 'update_manifest', '3': 1, '4': 1, '5': 9, '10': 'updateManifest'},
  ],
};

/// Descriptor for `UpdateRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateRequestDescriptor = $convert.base64Decode(
    'Cg1VcGRhdGVSZXF1ZXN0EicKD3VwZGF0ZV9tYW5pZmVzdBgBIAEoCVIOdXBkYXRlTWFuaWZlc3'
    'Q=');

@$core.Deprecated('Use updateResponseDescriptor instead')
const UpdateResponse$json = {
  '1': 'UpdateResponse',
  '2': [
    {
      '1': 'code',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.PB_System.UpdateResponse.UpdateResultCode',
      '10': 'code'
    },
  ],
  '4': [UpdateResponse_UpdateResultCode$json],
};

@$core.Deprecated('Use updateResponseDescriptor instead')
const UpdateResponse_UpdateResultCode$json = {
  '1': 'UpdateResultCode',
  '2': [
    {'1': 'OK', '2': 0},
    {'1': 'ManifestPathInvalid', '2': 1},
    {'1': 'ManifestFolderNotFound', '2': 2},
    {'1': 'ManifestInvalid', '2': 3},
    {'1': 'StageMissing', '2': 4},
    {'1': 'StageIntegrityError', '2': 5},
    {'1': 'ManifestPointerError', '2': 6},
    {'1': 'TargetMismatch', '2': 7},
    {'1': 'OutdatedManifestVersion', '2': 8},
    {'1': 'IntFull', '2': 9},
    {'1': 'UnspecifiedError', '2': 10},
  ],
};

/// Descriptor for `UpdateResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateResponseDescriptor = $convert.base64Decode(
    'Cg5VcGRhdGVSZXNwb25zZRI+CgRjb2RlGAEgASgOMiouUEJfU3lzdGVtLlVwZGF0ZVJlc3Bvbn'
    'NlLlVwZGF0ZVJlc3VsdENvZGVSBGNvZGUi/QEKEFVwZGF0ZVJlc3VsdENvZGUSBgoCT0sQABIX'
    'ChNNYW5pZmVzdFBhdGhJbnZhbGlkEAESGgoWTWFuaWZlc3RGb2xkZXJOb3RGb3VuZBACEhMKD0'
    '1hbmlmZXN0SW52YWxpZBADEhAKDFN0YWdlTWlzc2luZxAEEhcKE1N0YWdlSW50ZWdyaXR5RXJy'
    'b3IQBRIYChRNYW5pZmVzdFBvaW50ZXJFcnJvchAGEhIKDlRhcmdldE1pc21hdGNoEAcSGwoXT3'
    'V0ZGF0ZWRNYW5pZmVzdFZlcnNpb24QCBILCgdJbnRGdWxsEAkSFAoQVW5zcGVjaWZpZWRFcnJv'
    'chAK');

@$core.Deprecated('Use powerInfoRequestDescriptor instead')
const PowerInfoRequest$json = {
  '1': 'PowerInfoRequest',
};

/// Descriptor for `PowerInfoRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List powerInfoRequestDescriptor =
    $convert.base64Decode('ChBQb3dlckluZm9SZXF1ZXN0');

@$core.Deprecated('Use powerInfoResponseDescriptor instead')
const PowerInfoResponse$json = {
  '1': 'PowerInfoResponse',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
};

/// Descriptor for `PowerInfoResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List powerInfoResponseDescriptor = $convert.base64Decode(
    'ChFQb3dlckluZm9SZXNwb25zZRIQCgNrZXkYASABKAlSA2tleRIUCgV2YWx1ZRgCIAEoCVIFdm'
    'FsdWU=');
