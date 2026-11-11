import 'dart:typed_data';
import 'excel_file_types.dart';
import 'excel_files_stub.dart'
    if (dart.library.js_interop) 'excel_files_web.dart'
    as platform;
export 'excel_file_types.dart';

Future<ExcelUpload?> pickExcelFile() => platform.pickExcelFile();
Future<void> saveExcelFile(Uint8List bytes, String name) =>
    platform.saveExcelFile(bytes, name);
Future<void> saveBrowserFile(Uint8List bytes, String name, String mimeType) =>
    platform.saveBrowserFile(bytes, name, mimeType);
