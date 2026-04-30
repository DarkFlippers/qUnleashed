// This is a generated file - do not edit.
//
// Generated from storage.proto.

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

@$core.Deprecated('Use fileDescriptor instead')
const File$json = {
  '1': 'File',
  '2': [
    {
      '1': 'type',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.PB_Storage.File.FileType',
      '10': 'type'
    },
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'size', '3': 3, '4': 1, '5': 13, '10': 'size'},
    {'1': 'data', '3': 4, '4': 1, '5': 12, '10': 'data'},
    {'1': 'md5sum', '3': 5, '4': 1, '5': 9, '10': 'md5sum'},
  ],
  '4': [File_FileType$json],
};

@$core.Deprecated('Use fileDescriptor instead')
const File_FileType$json = {
  '1': 'FileType',
  '2': [
    {'1': 'FILE', '2': 0},
    {'1': 'DIR', '2': 1},
  ],
};

/// Descriptor for `File`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileDescriptor = $convert.base64Decode(
    'CgRGaWxlEi0KBHR5cGUYASABKA4yGS5QQl9TdG9yYWdlLkZpbGUuRmlsZVR5cGVSBHR5cGUSEg'
    'oEbmFtZRgCIAEoCVIEbmFtZRISCgRzaXplGAMgASgNUgRzaXplEhIKBGRhdGEYBCABKAxSBGRh'
    'dGESFgoGbWQ1c3VtGAUgASgJUgZtZDVzdW0iHQoIRmlsZVR5cGUSCAoERklMRRAAEgcKA0RJUh'
    'AB');

@$core.Deprecated('Use infoRequestDescriptor instead')
const InfoRequest$json = {
  '1': 'InfoRequest',
  '2': [
    {'1': 'path', '3': 1, '4': 1, '5': 9, '10': 'path'},
  ],
};

/// Descriptor for `InfoRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List infoRequestDescriptor =
    $convert.base64Decode('CgtJbmZvUmVxdWVzdBISCgRwYXRoGAEgASgJUgRwYXRo');

@$core.Deprecated('Use infoResponseDescriptor instead')
const InfoResponse$json = {
  '1': 'InfoResponse',
  '2': [
    {'1': 'total_space', '3': 1, '4': 1, '5': 4, '10': 'totalSpace'},
    {'1': 'free_space', '3': 2, '4': 1, '5': 4, '10': 'freeSpace'},
  ],
};

/// Descriptor for `InfoResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List infoResponseDescriptor = $convert.base64Decode(
    'CgxJbmZvUmVzcG9uc2USHwoLdG90YWxfc3BhY2UYASABKARSCnRvdGFsU3BhY2USHQoKZnJlZV'
    '9zcGFjZRgCIAEoBFIJZnJlZVNwYWNl');

@$core.Deprecated('Use timestampRequestDescriptor instead')
const TimestampRequest$json = {
  '1': 'TimestampRequest',
  '2': [
    {'1': 'path', '3': 1, '4': 1, '5': 9, '10': 'path'},
  ],
};

/// Descriptor for `TimestampRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List timestampRequestDescriptor = $convert
    .base64Decode('ChBUaW1lc3RhbXBSZXF1ZXN0EhIKBHBhdGgYASABKAlSBHBhdGg=');

@$core.Deprecated('Use timestampResponseDescriptor instead')
const TimestampResponse$json = {
  '1': 'TimestampResponse',
  '2': [
    {'1': 'timestamp', '3': 1, '4': 1, '5': 13, '10': 'timestamp'},
  ],
};

/// Descriptor for `TimestampResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List timestampResponseDescriptor = $convert.base64Decode(
    'ChFUaW1lc3RhbXBSZXNwb25zZRIcCgl0aW1lc3RhbXAYASABKA1SCXRpbWVzdGFtcA==');

@$core.Deprecated('Use statRequestDescriptor instead')
const StatRequest$json = {
  '1': 'StatRequest',
  '2': [
    {'1': 'path', '3': 1, '4': 1, '5': 9, '10': 'path'},
  ],
};

/// Descriptor for `StatRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List statRequestDescriptor =
    $convert.base64Decode('CgtTdGF0UmVxdWVzdBISCgRwYXRoGAEgASgJUgRwYXRo');

@$core.Deprecated('Use statResponseDescriptor instead')
const StatResponse$json = {
  '1': 'StatResponse',
  '2': [
    {
      '1': 'file',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.File',
      '10': 'file'
    },
  ],
};

/// Descriptor for `StatResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List statResponseDescriptor = $convert.base64Decode(
    'CgxTdGF0UmVzcG9uc2USJAoEZmlsZRgBIAEoCzIQLlBCX1N0b3JhZ2UuRmlsZVIEZmlsZQ==');

@$core.Deprecated('Use listRequestDescriptor instead')
const ListRequest$json = {
  '1': 'ListRequest',
  '2': [
    {'1': 'path', '3': 1, '4': 1, '5': 9, '10': 'path'},
    {'1': 'include_md5', '3': 2, '4': 1, '5': 8, '10': 'includeMd5'},
    {'1': 'filter_max_size', '3': 3, '4': 1, '5': 13, '10': 'filterMaxSize'},
  ],
};

/// Descriptor for `ListRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listRequestDescriptor = $convert.base64Decode(
    'CgtMaXN0UmVxdWVzdBISCgRwYXRoGAEgASgJUgRwYXRoEh8KC2luY2x1ZGVfbWQ1GAIgASgIUg'
    'ppbmNsdWRlTWQ1EiYKD2ZpbHRlcl9tYXhfc2l6ZRgDIAEoDVINZmlsdGVyTWF4U2l6ZQ==');

@$core.Deprecated('Use listResponseDescriptor instead')
const ListResponse$json = {
  '1': 'ListResponse',
  '2': [
    {
      '1': 'file',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.PB_Storage.File',
      '10': 'file'
    },
  ],
};

/// Descriptor for `ListResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listResponseDescriptor = $convert.base64Decode(
    'CgxMaXN0UmVzcG9uc2USJAoEZmlsZRgBIAMoCzIQLlBCX1N0b3JhZ2UuRmlsZVIEZmlsZQ==');

@$core.Deprecated('Use readRequestDescriptor instead')
const ReadRequest$json = {
  '1': 'ReadRequest',
  '2': [
    {'1': 'path', '3': 1, '4': 1, '5': 9, '10': 'path'},
  ],
};

/// Descriptor for `ReadRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List readRequestDescriptor =
    $convert.base64Decode('CgtSZWFkUmVxdWVzdBISCgRwYXRoGAEgASgJUgRwYXRo');

@$core.Deprecated('Use readResponseDescriptor instead')
const ReadResponse$json = {
  '1': 'ReadResponse',
  '2': [
    {
      '1': 'file',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.File',
      '10': 'file'
    },
  ],
};

/// Descriptor for `ReadResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List readResponseDescriptor = $convert.base64Decode(
    'CgxSZWFkUmVzcG9uc2USJAoEZmlsZRgBIAEoCzIQLlBCX1N0b3JhZ2UuRmlsZVIEZmlsZQ==');

@$core.Deprecated('Use writeRequestDescriptor instead')
const WriteRequest$json = {
  '1': 'WriteRequest',
  '2': [
    {'1': 'path', '3': 1, '4': 1, '5': 9, '10': 'path'},
    {
      '1': 'file',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.PB_Storage.File',
      '10': 'file'
    },
  ],
};

/// Descriptor for `WriteRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List writeRequestDescriptor = $convert.base64Decode(
    'CgxXcml0ZVJlcXVlc3QSEgoEcGF0aBgBIAEoCVIEcGF0aBIkCgRmaWxlGAIgASgLMhAuUEJfU3'
    'RvcmFnZS5GaWxlUgRmaWxl');

@$core.Deprecated('Use deleteRequestDescriptor instead')
const DeleteRequest$json = {
  '1': 'DeleteRequest',
  '2': [
    {'1': 'path', '3': 1, '4': 1, '5': 9, '10': 'path'},
    {'1': 'recursive', '3': 2, '4': 1, '5': 8, '10': 'recursive'},
  ],
};

/// Descriptor for `DeleteRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deleteRequestDescriptor = $convert.base64Decode(
    'Cg1EZWxldGVSZXF1ZXN0EhIKBHBhdGgYASABKAlSBHBhdGgSHAoJcmVjdXJzaXZlGAIgASgIUg'
    'lyZWN1cnNpdmU=');

@$core.Deprecated('Use mkdirRequestDescriptor instead')
const MkdirRequest$json = {
  '1': 'MkdirRequest',
  '2': [
    {'1': 'path', '3': 1, '4': 1, '5': 9, '10': 'path'},
  ],
};

/// Descriptor for `MkdirRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mkdirRequestDescriptor =
    $convert.base64Decode('CgxNa2RpclJlcXVlc3QSEgoEcGF0aBgBIAEoCVIEcGF0aA==');

@$core.Deprecated('Use md5sumRequestDescriptor instead')
const Md5sumRequest$json = {
  '1': 'Md5sumRequest',
  '2': [
    {'1': 'path', '3': 1, '4': 1, '5': 9, '10': 'path'},
  ],
};

/// Descriptor for `Md5sumRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List md5sumRequestDescriptor =
    $convert.base64Decode('Cg1NZDVzdW1SZXF1ZXN0EhIKBHBhdGgYASABKAlSBHBhdGg=');

@$core.Deprecated('Use md5sumResponseDescriptor instead')
const Md5sumResponse$json = {
  '1': 'Md5sumResponse',
  '2': [
    {'1': 'md5sum', '3': 1, '4': 1, '5': 9, '10': 'md5sum'},
  ],
};

/// Descriptor for `Md5sumResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List md5sumResponseDescriptor = $convert
    .base64Decode('Cg5NZDVzdW1SZXNwb25zZRIWCgZtZDVzdW0YASABKAlSBm1kNXN1bQ==');

@$core.Deprecated('Use renameRequestDescriptor instead')
const RenameRequest$json = {
  '1': 'RenameRequest',
  '2': [
    {'1': 'old_path', '3': 1, '4': 1, '5': 9, '10': 'oldPath'},
    {'1': 'new_path', '3': 2, '4': 1, '5': 9, '10': 'newPath'},
  ],
};

/// Descriptor for `RenameRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List renameRequestDescriptor = $convert.base64Decode(
    'Cg1SZW5hbWVSZXF1ZXN0EhkKCG9sZF9wYXRoGAEgASgJUgdvbGRQYXRoEhkKCG5ld19wYXRoGA'
    'IgASgJUgduZXdQYXRo');

@$core.Deprecated('Use backupCreateRequestDescriptor instead')
const BackupCreateRequest$json = {
  '1': 'BackupCreateRequest',
  '2': [
    {'1': 'archive_path', '3': 1, '4': 1, '5': 9, '10': 'archivePath'},
  ],
};

/// Descriptor for `BackupCreateRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List backupCreateRequestDescriptor = $convert.base64Decode(
    'ChNCYWNrdXBDcmVhdGVSZXF1ZXN0EiEKDGFyY2hpdmVfcGF0aBgBIAEoCVILYXJjaGl2ZVBhdG'
    'g=');

@$core.Deprecated('Use backupRestoreRequestDescriptor instead')
const BackupRestoreRequest$json = {
  '1': 'BackupRestoreRequest',
  '2': [
    {'1': 'archive_path', '3': 1, '4': 1, '5': 9, '10': 'archivePath'},
  ],
};

/// Descriptor for `BackupRestoreRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List backupRestoreRequestDescriptor = $convert.base64Decode(
    'ChRCYWNrdXBSZXN0b3JlUmVxdWVzdBIhCgxhcmNoaXZlX3BhdGgYASABKAlSC2FyY2hpdmVQYX'
    'Ro');

@$core.Deprecated('Use tarExtractRequestDescriptor instead')
const TarExtractRequest$json = {
  '1': 'TarExtractRequest',
  '2': [
    {'1': 'tar_path', '3': 1, '4': 1, '5': 9, '10': 'tarPath'},
    {'1': 'out_path', '3': 2, '4': 1, '5': 9, '10': 'outPath'},
  ],
};

/// Descriptor for `TarExtractRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tarExtractRequestDescriptor = $convert.base64Decode(
    'ChFUYXJFeHRyYWN0UmVxdWVzdBIZCgh0YXJfcGF0aBgBIAEoCVIHdGFyUGF0aBIZCghvdXRfcG'
    'F0aBgCIAEoCVIHb3V0UGF0aA==');
