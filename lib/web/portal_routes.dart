import 'package:flutter/foundation.dart';
import 'browser_location_stub.dart'
    if (dart.library.js_interop) 'browser_location_web.dart'
    as location;

class PortalRoutes {
  static final current = ValueNotifier<Uri>(
    Uri.tryParse(location.currentLocation()) ?? Uri(path: '/'),
  );
  static bool _started = false;
  static void start() {
    if (_started) return;
    _started = true;
    location.observeLocation((value) {
      current.value = Uri.tryParse(value) ?? Uri(path: '/');
    });
  }

  static void go(String path) {
    current.value = Uri.parse(path);
    if (kIsWeb) location.changeLocation(path);
  }

  static int pageFor(List<String> pages, String role) {
    final uri = current.value;
    if (!uri.path.startsWith('/$role/')) return 0;
    final index = pages.indexOf(uri.path.split('/').last);
    return index < 0 ? 0 : index;
  }
}
