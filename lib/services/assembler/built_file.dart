import 'dart:typed_data';

import '../../components/codec/fap/info.dart';

/// A built `.fap` or `.fal` and the API of the firmware it was built in,
/// major and minor: what an installed app's `.fim` records as Version Build
/// API.
class BuiltFile {
  const BuiltFile(this.bytes, {required this.buildApi});

  /// One built on this machine: its own `.fapmeta` says what it was built
  /// against.
  factory BuiltFile.local(List<int> bytes) {
    final info = FapInfo.parse(Uint8List.fromList(bytes));
    return BuiltFile(
      bytes,
      buildApi: info != null && info.isValid ? info.manifest!.api : null,
    );
  }

  /// What our servers send that API in, with every built file they hand
  /// out. Archivarius does not.
  static const apiHeader = 'x-qu-build-api';

  /// The API the headers of a response name, or null when they name none.
  static String? apiIn(Map<String, String> headers) {
    final api = headers[apiHeader]?.trim();
    return api == null || api.isEmpty ? null : api;
  }

  final List<int> bytes;

  /// Null for a file from Archivarius, which does not say, and for one built
  /// here whose `.fapmeta` cannot be read.
  final String? buildApi;
}
