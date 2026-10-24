import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Serialized, account-scoped drafts. A new sign-in cannot read another owner's
/// draft, and sign-out queues cleanup after all pending writes.
class BoundaryDraftStore {
  static Future<void>? _writes;

  static Future<Map<String, dynamic>?> read(String kind) async {
    if (_writes != null) await _writes;
    final prefs = await SharedPreferences.getInstance();
    final owner = prefs.getString('account_id');
    if (owner == null) return null;
    try {
      final raw = prefs.getString('geosustain_draft_${owner}_$kind');
      return raw == null
          ? null
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } on FormatException {
      return null;
    }
  }

  static Future<void> write(String kind, Map<String, dynamic>? draft) async {
    final prefs = await SharedPreferences.getInstance();
    final owner = prefs.getString('account_id');
    if (owner == null) return;
    final encoded = draft == null ? null : jsonEncode(draft);
    final work = (_writes ?? Future<void>.value()).catchError((_) {}).then((
      _,
    ) async {
      if (prefs.getString('account_id') != owner) return;
      final key = 'geosustain_draft_${owner}_$kind';
      if (encoded == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, encoded);
      }
    });
    _writes = work;
    try {
      await work;
    } finally {
      if (identical(_writes, work)) _writes = null;
    }
  }

  static Future<void> clearForSignOut() async {
    final work = (_writes ?? Future<void>.value()).catchError((_) {}).then((
      _,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('account_id');
      for (final key
          in prefs
              .getKeys()
              .where((key) => key.startsWith('geosustain_draft_'))
              .toList()) {
        await prefs.remove(key);
      }
    });
    _writes = work;
    try {
      await work;
    } finally {
      if (identical(_writes, work)) _writes = null;
    }
  }
}
