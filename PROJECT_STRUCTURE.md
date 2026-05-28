# Clean GeoSustain Project Structure

Keep these folders/files visible:

- `lib/` - Flutter app source code
- `android/` - Android build files
- `web/` - Flutter web files
- `backend/` - Python/FastAPI backend, model files, datasets, templates, and static files
- `pubspec.yaml` - Flutter dependencies
- `start_backend.bat` - starts the backend on Windows
- `run_flutter.bat` - runs the Flutter app

Removed from this clean copy:

- generated build folders: `build/`, `.dart_tool/`
- desktop folders not needed for Android/web testing: `linux/`, `macos/`, `windows/`
- old helper scripts and extra docs that clutter the root
- `test/`, `docs/`, and `scripts/` folders

If Flutter needs generated folders again, it will recreate them automatically when you run `flutter pub get` or `flutter run`.
