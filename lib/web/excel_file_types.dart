import 'dart:typed_data';

class ExcelUpload {
  final String name;
  final Uint8List bytes;
  const ExcelUpload(this.name, this.bytes);
}
