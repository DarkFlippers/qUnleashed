// This is a generated file - do not edit.
//
// Generated from application.proto.

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

@$core.Deprecated('Use appStateDescriptor instead')
const AppState$json = {
  '1': 'AppState',
  '2': [
    {'1': 'APP_CLOSED', '2': 0},
    {'1': 'APP_STARTED', '2': 1},
  ],
};

/// Descriptor for `AppState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List appStateDescriptor = $convert.base64Decode(
    'CghBcHBTdGF0ZRIOCgpBUFBfQ0xPU0VEEAASDwoLQVBQX1NUQVJURUQQAQ==');

@$core.Deprecated('Use startRequestDescriptor instead')
const StartRequest$json = {
  '1': 'StartRequest',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'args', '3': 2, '4': 1, '5': 9, '10': 'args'},
  ],
};

/// Descriptor for `StartRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startRequestDescriptor = $convert.base64Decode(
    'CgxTdGFydFJlcXVlc3QSEgoEbmFtZRgBIAEoCVIEbmFtZRISCgRhcmdzGAIgASgJUgRhcmdz');

@$core.Deprecated('Use lockStatusRequestDescriptor instead')
const LockStatusRequest$json = {
  '1': 'LockStatusRequest',
};

/// Descriptor for `LockStatusRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lockStatusRequestDescriptor =
    $convert.base64Decode('ChFMb2NrU3RhdHVzUmVxdWVzdA==');

@$core.Deprecated('Use lockStatusResponseDescriptor instead')
const LockStatusResponse$json = {
  '1': 'LockStatusResponse',
  '2': [
    {'1': 'locked', '3': 1, '4': 1, '5': 8, '10': 'locked'},
  ],
};

/// Descriptor for `LockStatusResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lockStatusResponseDescriptor =
    $convert.base64Decode(
        'ChJMb2NrU3RhdHVzUmVzcG9uc2USFgoGbG9ja2VkGAEgASgIUgZsb2NrZWQ=');

@$core.Deprecated('Use appExitRequestDescriptor instead')
const AppExitRequest$json = {
  '1': 'AppExitRequest',
};

/// Descriptor for `AppExitRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List appExitRequestDescriptor =
    $convert.base64Decode('Cg5BcHBFeGl0UmVxdWVzdA==');

@$core.Deprecated('Use appLoadFileRequestDescriptor instead')
const AppLoadFileRequest$json = {
  '1': 'AppLoadFileRequest',
  '2': [
    {'1': 'path', '3': 1, '4': 1, '5': 9, '10': 'path'},
  ],
};

/// Descriptor for `AppLoadFileRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List appLoadFileRequestDescriptor = $convert
    .base64Decode('ChJBcHBMb2FkRmlsZVJlcXVlc3QSEgoEcGF0aBgBIAEoCVIEcGF0aA==');

@$core.Deprecated('Use appButtonPressRequestDescriptor instead')
const AppButtonPressRequest$json = {
  '1': 'AppButtonPressRequest',
  '2': [
    {'1': 'args', '3': 1, '4': 1, '5': 9, '10': 'args'},
    {'1': 'index', '3': 2, '4': 1, '5': 5, '10': 'index'},
  ],
};

/// Descriptor for `AppButtonPressRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List appButtonPressRequestDescriptor = $convert.base64Decode(
    'ChVBcHBCdXR0b25QcmVzc1JlcXVlc3QSEgoEYXJncxgBIAEoCVIEYXJncxIUCgVpbmRleBgCIA'
    'EoBVIFaW5kZXg=');

@$core.Deprecated('Use appButtonReleaseRequestDescriptor instead')
const AppButtonReleaseRequest$json = {
  '1': 'AppButtonReleaseRequest',
};

/// Descriptor for `AppButtonReleaseRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List appButtonReleaseRequestDescriptor =
    $convert.base64Decode('ChdBcHBCdXR0b25SZWxlYXNlUmVxdWVzdA==');

@$core.Deprecated('Use appButtonPressReleaseRequestDescriptor instead')
const AppButtonPressReleaseRequest$json = {
  '1': 'AppButtonPressReleaseRequest',
  '2': [
    {'1': 'args', '3': 1, '4': 1, '5': 9, '10': 'args'},
    {'1': 'index', '3': 2, '4': 1, '5': 5, '10': 'index'},
  ],
};

/// Descriptor for `AppButtonPressReleaseRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List appButtonPressReleaseRequestDescriptor =
    $convert.base64Decode(
        'ChxBcHBCdXR0b25QcmVzc1JlbGVhc2VSZXF1ZXN0EhIKBGFyZ3MYASABKAlSBGFyZ3MSFAoFaW'
        '5kZXgYAiABKAVSBWluZGV4');

@$core.Deprecated('Use appStateResponseDescriptor instead')
const AppStateResponse$json = {
  '1': 'AppStateResponse',
  '2': [
    {
      '1': 'state',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.PB_App.AppState',
      '10': 'state'
    },
  ],
};

/// Descriptor for `AppStateResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List appStateResponseDescriptor = $convert.base64Decode(
    'ChBBcHBTdGF0ZVJlc3BvbnNlEiYKBXN0YXRlGAEgASgOMhAuUEJfQXBwLkFwcFN0YXRlUgVzdG'
    'F0ZQ==');

@$core.Deprecated('Use getErrorRequestDescriptor instead')
const GetErrorRequest$json = {
  '1': 'GetErrorRequest',
};

/// Descriptor for `GetErrorRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getErrorRequestDescriptor =
    $convert.base64Decode('Cg9HZXRFcnJvclJlcXVlc3Q=');

@$core.Deprecated('Use getErrorResponseDescriptor instead')
const GetErrorResponse$json = {
  '1': 'GetErrorResponse',
  '2': [
    {'1': 'code', '3': 1, '4': 1, '5': 13, '10': 'code'},
    {'1': 'text', '3': 2, '4': 1, '5': 9, '10': 'text'},
  ],
};

/// Descriptor for `GetErrorResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getErrorResponseDescriptor = $convert.base64Decode(
    'ChBHZXRFcnJvclJlc3BvbnNlEhIKBGNvZGUYASABKA1SBGNvZGUSEgoEdGV4dBgCIAEoCVIEdG'
    'V4dA==');

@$core.Deprecated('Use dataExchangeRequestDescriptor instead')
const DataExchangeRequest$json = {
  '1': 'DataExchangeRequest',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `DataExchangeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dataExchangeRequestDescriptor = $convert
    .base64Decode('ChNEYXRhRXhjaGFuZ2VSZXF1ZXN0EhIKBGRhdGEYASABKAxSBGRhdGE=');
