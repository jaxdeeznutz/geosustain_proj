import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'route_location.dart';

String currentLocation() => portalLocation(
  web.window.location.hash,
  web.window.location.pathname,
  web.window.location.search,
);
void observeLocation(void Function(String) listener) {
  web.window.addEventListener(
    'hashchange',
    ((web.Event _) => listener(currentLocation())).toJS,
  );
  web.window.addEventListener(
    'popstate',
    ((web.Event _) => listener(currentLocation())).toJS,
  );
}

void changeLocation(String path) {
  // pushState avoids a second hash navigation event for an in-app transition.
  web.window.history.pushState(null, '', '#$path');
}
