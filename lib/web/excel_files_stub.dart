import 'dart:typed_data';
import 'excel_file_types.dart';

Future<ExcelUpload?> pickExcelFile() async => throw UnsupportedError(
  'Open the admin web dashboard to import Excel files.',
);
Future<void> saveExcelFile(Uint8List bytes, String name) async =>
    throw UnsupportedError(
      'Open the admin web dashboard to download Excel files.',
    );
Future<void> saveBrowserFile(
  Uint8List bytes,
  String name,
  String mimeType,
) async =>
    throw UnsupportedError('Open the admin web dashboard to download files.');
