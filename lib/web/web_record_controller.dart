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
  Map<String, String> parameters = {}, appliedParameters = {};
  Timer? _debounce;
  Future<void> filter(Map<String, String> values) {
    parameters = Map.of(values);
    _debounce?.cancel();
    return load(offset: 0);
  }

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
    final filters = Map<String, String>.of(parameters);
    loading = true;
    error = null;
    notifyListeners();
    try {
      final data = await api.getRecordPage(
        path,
        offset: target,
        search: search,
        parameters: {'limit': '$limit', ...filters},
      );
      if (_disposed || generation != _generation) return;
      rows = (data[key] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      this.offset = target;
      more = data['has_more'] == true;
      appliedQuery = search;
      appliedParameters = filters;
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
