import 'dart:js_interop';
import 'package:web/web.dart' as web;

String currentLocation() =>
    web.window.location.hash.replaceFirst(RegExp('^#'), '');
void observeLocation(void Function(String) listener) {
  web.window.addEventListener(
    'hashchange',
    ((web.Event _) => listener(currentLocation())).toJS,
  );
}

void changeLocation(String path) {
  web.window.location.hash = path;
}
