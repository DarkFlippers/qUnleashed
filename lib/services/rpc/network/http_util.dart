import 'dart:typed_data';

Map<String, String> parseHeaderBlock(String raw) {
  final headers = <String, String>{};
  if (raw.isEmpty) return headers;
  for (final line in raw.split(RegExp(r'\r\n|\n'))) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final separator = trimmed.indexOf(':');
    if (separator <= 0) continue;
    final name = trimmed.substring(0, separator).trim();
    final value = trimmed.substring(separator + 1).trim();
    if (name.isEmpty) continue;
    headers[name] = value;
  }
  return headers;
}

String formatHeaderBlock(Map<String, String> headers) {
  final buffer = StringBuffer();
  headers.forEach((name, value) {
    buffer.write(name);
    buffer.write(': ');
    buffer.write(value);
    buffer.write('\r\n');
  });
  return buffer.toString();
}

Uint8List asBytes(List<int> data) =>
    data is Uint8List ? data : Uint8List.fromList(data);

Iterable<Uint8List> chunkByteViews(Uint8List data, int chunkSize) sync* {
  if (data.isEmpty) return;
  if (chunkSize <= 0 || data.length <= chunkSize) {
    yield data;
    return;
  }
  for (var offset = 0; offset < data.length; offset += chunkSize) {
    final end = offset + chunkSize;
    yield Uint8List.sublistView(
      data,
      offset,
      end < data.length ? end : data.length,
    );
  }
}
