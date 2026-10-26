import 'dart:async';
import 'package:flutter/foundation.dart';
import '../api_service.dart';

/// Bounded owner-checked page requests. Older query responses cannot overwrite newer ones.
class WebRecordController extends ChangeNotifier {
  final ApiService api;
  final String path, key;
  final int limit;
  WebRecordController(this.api, this.path, this.key, {this.limit = 20});
  List<Map<String, dynamic>> rows = [];
  int offset = 0, _generation = 0;
  bool loading = false, more = false, _disposed = false, loaded = false;
  String query = '', appliedQuery = '';
  String? error;
  Timer? _debounce;
  void search(String value) {
    query = value.trim();
    _generation++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => load(offset: 0));
  }

  Future<void> load({int? offset}) async {
    if (_disposed) return;
    final generation = ++_generation, target = offset ?? this.offset;
    final search = query;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final data = await api.getRecordPage(
        path,
        offset: target,
        search: search,
        parameters: {'limit': '$limit'},
      );
      if (_disposed || generation != _generation) return;
      rows = (data[key] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      this.offset = target;
      more = data['has_more'] == true;
      appliedQuery = search;
      loaded = true;
    } catch (failure) {
      if (!_disposed && generation == _generation) {
        error = failure is ApiException
            ? failure.message
            : 'Could not load records. Check your connection and retry.';
      }
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _debounce?.cancel();
    super.dispose();
  }
}
