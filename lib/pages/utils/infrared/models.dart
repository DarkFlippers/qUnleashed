enum IrEntryType { dir, file }

class IrEntry {
  IrEntry({
    required this.name,
    required this.path,
    required this.type,
    this.size = 0,
    this.downloadUrl,
  });

  final String name;
  final String path;
  final IrEntryType type;
  final int size;
  final String? downloadUrl;

  bool get isDir => type == IrEntryType.dir;
  bool get isIrFile =>
      type == IrEntryType.file && name.toLowerCase().endsWith('.ir');
}
