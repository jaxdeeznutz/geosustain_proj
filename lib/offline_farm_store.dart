import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'session_token_store.dart';
import 'farm_geometry.dart';

/// Account-scoped durable farm queue. Android values are Keystore encrypted.
/// Browser values use this origin's local storage, like the existing web session.
class OfflineFarmStore {
  @visibleForTesting
  static void resetTestState() {
    _writes = null;
    _syncs.clear();
  }

  static Future<void>? _writes;
  static final Map<String, Future<void>> _syncs = {};
  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static Future<String?> owner() async =>
      (await SharedPreferences.getInstance()).getString('account_id');
  static Future<void> _check(String ownerId) async {
    if (await owner() != ownerId) {
      throw StateError('The signed-in account changed.');
    }
  }

  static Future<Map<String, dynamic>> _read(String ownerId) async {
    await _check(ownerId);
    final prefs = await SharedPreferences.getInstance();
    final raw = _android
        ? await SessionTokenStore.channel.invokeMethod<String>(
            'workspaceRead',
            {'owner': ownerId},
          )
        : prefs.getString('geosustain_workspace_$ownerId');
    await _check(ownerId);
    if (raw == null) {
      return {'version': 1, 'pending': [], 'farms': [], 'events': []};
    }
    final value = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    if (value['version'] != 1) {
      throw const FormatException('Saved farm format is not supported.');
    }
    return value;
  }

  static Future<Map<String, dynamic>> read() async {
    final id = await owner();
    if (id == null) return {'pending': [], 'farms': [], 'events': []};
    if (_writes != null) await _writes;
    return _read(id);
  }

  static Future<void> _change(
    String id,
    void Function(Map<String, dynamic>) change,
  ) async {
    final work = (_writes ?? Future<void>.value()).catchError((_) {}).then((
      _,
    ) async {
      final value = await _read(id);
      change(value);
      await _check(id);
      final encoded = jsonEncode(value);
      if (_android) {
        await SessionTokenStore.channel.invokeMethod<void>('workspaceWrite', {
          'owner': id,
          'value': encoded,
        });
      } else {
        if (!await (await SharedPreferences.getInstance()).setString(
          'geosustain_workspace_$id',
          encoded,
        )) {
          throw StateError('Device storage could not save this farm.');
        }
      }
      await _check(id);
    });
    _writes = work;
    try {
      await work;
    } finally {
      if (identical(_writes, work)) _writes = null;
    }
  }

  static Future<void> cacheIdentity(Map<String, dynamic> user) async {
    final id = '${user['id']}';
    if (await owner() != id) return;
    await _change(
      id,
      (data) => data['identity'] = {
        for (final key in ['id', 'username', 'email', 'role']) key: user[key],
      },
    );
  }

  static List<Map<String, dynamic>> rows(dynamic value) =>
      (value as List? ?? [])
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
  static Future<void> cacheFarms(List<Map<String, dynamic>> farms) async {
    final id = await owner();
    if (id != null) await _change(id, (data) => data['farms'] = farms);
  }

  static Future<Map<String, dynamic>> save({
    required String requestId,
    required String name,
    required String location,
    required List<Map<String, double>> polygon,
    required String method,
    double? gpsAccuracyM,
    List<Map<String, dynamic>>? capture,
  }) async {
    final id = await owner();
    if (id == null) {
      throw StateError('Sign in online once before saving on this device.');
    }
    final farm = <String, dynamic>{
      'id': 'local:$requestId',
      'farmer_id': int.parse(id),
      'farm_name': name,
      'location_name': location,
      'selected_polygon': polygon,
      'area_hectares':
          FarmGeometry.areaSquareMetres(FarmGeometry.fromPayload(polygon)) /
          10000,
      'mapping_method': method,
      'gps_accuracy_m': gpsAccuracyM,
      'capture': capture,
      'analysis_count': 0,
      '_local_only': true,
      'sync_state': 'Pending sync',
      'request_id': requestId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _change(id, (data) {
      final pending = rows(data['pending']);
      final existing = pending
          .where((r) => r['request_id'] == requestId)
          .firstOrNull;
      if (existing != null) {
        if (jsonEncode(existing['selected_polygon']) != jsonEncode(polygon) ||
            existing['farm_name'] != name ||
            existing['location_name'] != location) {
          throw StateError('This saved request already has different inputs.');
        }
        farm.addAll(existing);
      } else {
        data['pending'] = [farm, ...pending];
      }
    });
    return farm;
  }

  static Future<void> remove(String requestId) async {
    final id = await owner();
    if (id != null) {
      await _change(
        id,
        (data) => data['pending'] = rows(
          data['pending'],
        ).where((r) => r['request_id'] != requestId).toList(),
      );
    }
  }

  static Future<void> markLocalRead(String eventId) async {
    final id = await owner();
    if (id != null) {
      await _change(id, (data) {
        data['events'] = rows(data['events'])
            .map(
              (r) => r['id'] == eventId
                  ? {
                      ...r,
                      'read_at':
                          r['read_at'] ??
                          DateTime.now().toUtc().toIso8601String(),
                    }
                  : r,
            )
            .toList();
      });
    }
  }

  static Future<void> sync(
    Future<Map<String, dynamic>> Function(Map<String, dynamic>) upload,
    String Function(Object) safeMessage,
  ) async {
    final id = await owner();
    if (id == null) return;
    if (_syncs[id] != null) return _syncs[id]!;
    final work = _runSync(id, upload, safeMessage);
    _syncs[id] = work;
    try {
      await work;
    } finally {
      _syncs.remove(id);
    }
  }

  static Future<void> _runSync(
    String id,
    Future<Map<String, dynamic>> Function(Map<String, dynamic>) upload,
    String Function(Object) safeMessage,
  ) async {
    if (_writes != null) await _writes;
    final initial = await _read(id);
    for (final farm in rows(initial['pending'])) {
      await _check(id);
      try {
        final saved = await upload(farm);
        await _check(id);
        if ('${saved['farmer_id']}' != id) {
          throw StateError('Unexpected farm owner.');
        }
        await _change(id, (data) {
          data['pending'] = rows(
            data['pending'],
          ).where((r) => r['request_id'] != farm['request_id']).toList();
          data['farms'] = [
            saved,
            ...rows(data['farms']).where((r) => r['id'] != saved['id']),
          ];
          final events = rows(data['events']);
          final eventId = 'sync:${farm['request_id']}';
          if (!events.any((e) => e['id'] == eventId)) {
            data['events'] = [
              {
                'id': eventId,
                'farm_id': saved['id'],
                'farm_name': saved['farm_name'],
                'created_at': DateTime.now().toUtc().toIso8601String(),
                'read_at': null,
              },
              ...events,
            ].take(100).toList();
          }
        });
      } catch (error) {
        if (await owner() == id) {
          await _change(
            id,
            (data) => data['pending'] = rows(data['pending'])
                .map(
                  (r) => r['request_id'] == farm['request_id']
                      ? {
                          ...r,
                          'sync_state': 'Needs attention',
                          'sync_error': safeMessage(error),
                        }
                      : r,
                )
                .toList(),
          );
        }
        rethrow;
      }
    }
  }

  static Future<void> deleteCurrentAccountData() async {
    final id = await owner();
    if (id == null) return;
    if (_writes != null) await _writes;
    await _check(id);
    if (_android) {
      await SessionTokenStore.channel.invokeMethod<void>('workspaceDelete', {
        'owner': id,
      });
    } else {
      await (await SharedPreferences.getInstance()).remove(
        'geosustain_workspace_$id',
      );
    }
  }
}
