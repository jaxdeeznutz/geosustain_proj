# GeoSustain mobile design system

Implemented the attached UI request in the existing Flutter app. Backend files, GPS acceptance rules, permission handling, storage, map providers, and analysis requests were not changed.

## Shared components

`lib/screens/design_system.dart` centralizes the palette, 22 px card radius, 16 px small-card radius, 17 px button radius, 54 px action height, 48 px circular header actions, 80 px header content height, and 16 px page gutters.

- `GeoSustainHeader` is used for the five tabs and nested mapping, farm details, history/result details, saved analyses, reports, account editing, password, location, settings, and notification screens. Other existing mobile map/dashboard/report/admin entry points also reuse it. Authentication and desktop web shells retain their separate layouts.
- Main headers have a leaf, app name, page subtitle, and notification action. My Farms retains Search; its former plus action is replaced by the bell. Creating farms remains available through the two action cards. Nested routes retain back navigation. No unread count is invented.
- `GeoButton`, `GeoStatusChip`, `GeoInfoCard`, `GeoFarmCard`, `GeoSectionHeader`, and `GeoEqualGrid` provide reusable sizing and alignment. `ReferenceAction` reserves shared measured text heights so its paired cards stay aligned without truncating enlarged text.
- Main navigation retains Home, My Farms, Analysis, History, Profile, with a shared 76 px navigation height and 24 px icons.

## GPS and farms

The GPS screen has the three-step guide, responsive field illustration, satellite/map selector, four equally sized circular map controls, equal-height status cards, a full-width Start/Pause/Resume button, equal-width Finish/Undo buttons, and a visible Tip card. The area estimate still appears once a valid area can be computed. Existing recording, accuracy, pause/background, recenter, finish, review, and save behavior remains connected to the original handlers.

Farm cards have matching thumbnails and metadata chips. Edit opens the existing edit flow; View Results selects the latest completed analysis through the existing farm-detail flow. The existing removal operation is still labelled **Archive**, rather than implying permanent deletion. Its confirmation and preservation of historical analyses remain intact.

## Validation

- Full Flutter suite: **74 tests passed** (`build/redesign-verified-tests.log`).
- Flutter analyzer: **no issues found** (`build/redesign-verified-analyze.log`).
- Alignment tests cover 320, 360, and 402 px widths at normal and 1.5x text scaling, including equal action-card sizes, equal GPS status-card heights, equal button dimensions, and 48 px header actions.
- Render checks cover the five tabs, GPS ready/recording, polygon mapping, farm details, crop details, settings, saved analyses, report lists/details, profile editing, security, notifications, and saved/history result details at 360 and 402 px. Images are under `build/mobile-qa/october/`.
- Screenshots use fixture data and neutral offline map tiles. They validate layout; they are not evidence of a physical GPS field test or authenticated production analysis.

APK build command: `flutter build apk --release --dart-define=API_BASE_URL=https://geosustain.onrender.com`. The output is `build/app/outputs/flutter-apk/app-release.apk`, using the existing Android signing configuration. No backend deployment is part of this update.
