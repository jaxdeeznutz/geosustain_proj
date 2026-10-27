import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show WidgetsBinding, WidgetsBindingObserver, RouteInformation;
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
    if (kIsWeb) {
      WidgetsBinding.instance.addObserver(
        PortalBrowserHistory(location.currentLocation),
      );
    }
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

/// The portal handles its own URL history; acknowledge browser route messages
/// so the imperative authentication Navigator does not undo Back/Forward.
class PortalBrowserHistory extends WidgetsBindingObserver {
  final String Function() readLocation;
  PortalBrowserHistory(this.readLocation);
  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    PortalRoutes.current.value =
        Uri.tryParse(readLocation()) ?? routeInformation.uri;
    return true;
  }
}
