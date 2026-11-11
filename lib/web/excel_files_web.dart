import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'excel_file_types.dart';

Future<ExcelUpload?> pickExcelFile() {
  final selected = Completer<ExcelUpload?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.xlsx';
  input.style.display = 'none';
  web.document.body?.appendChild(input);
  void finish(ExcelUpload? value, [Object? error]) {
    input.remove();
    if (selected.isCompleted) return;
    if (error == null) {
      selected.complete(value);
    } else {
      selected.completeError(error);
    }
  }

  input.addEventListener('cancel', ((web.Event _) => finish(null)).toJS);
  input.addEventListener(
    'change',
    ((web.Event _) {
      unawaited(() async {
        try {
          final file = input.files?.item(0);
          if (file == null) {
            finish(null);
            return;
          }
          if (file.size > 2 * 1024 * 1024 ||
              !file.name.toLowerCase().endsWith('.xlsx')) {
            throw const FormatException(
              'Choose an .xlsx file no larger than 2 MB.',
            );
          }
          final buffer = (await file.arrayBuffer().toDart).toDart;
          finish(ExcelUpload(file.name, buffer.asUint8List()));
        } catch (error) {
          finish(null, error);
        }
      }());
    }).toJS,
  );
  input.click();
  return selected.future;
}

Future<void> saveExcelFile(Uint8List bytes, String name) => saveBrowserFile(
  bytes,
  name,
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
);

Future<void> saveBrowserFile(
  Uint8List bytes,
  String name,
  String mimeType,
) async {
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body?.appendChild(link);
  link.click();
  link.remove();
  Timer(const Duration(seconds: 1), () => web.URL.revokeObjectURL(url));
}
