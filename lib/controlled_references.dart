import 'dart:convert';

Map<String, dynamic> _recordObject(dynamic value) {
  if (value is String) {
    try {
      value = jsonDecode(value);
    } catch (_) {
      return {};
    }
  }
  return value is Map ? Map<String, dynamic>.from(value) : {};
}

List<Map<String, dynamic>> savedControlledRecords(Map<String, dynamic> record) {
  final snapshot = _recordObject(record['configuration_snapshot']);
  final rows = snapshot['records'];
  return rows is List
      ? rows.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList()
      : [];
}

List<String> controlledReferenceLines(Map<String, dynamic> record) {
  final rows = savedControlledRecords(record);
  if (rows.isEmpty) return [];
  final snapshot = _recordObject(record['configuration_snapshot']);
  return [
    'Saved reference configuration: ${snapshot['content_sha256']}',
    'Parcel sample limit: ${snapshot['parcel_sample_limit']}. These versions apply to this analysis; later edits do not replace them.',
    for (final row in rows) ...[
      '${_recordObject(row['document'])['title']} - ${row['kind']}, revision ${row['revision']} (record ${row['id']})',
      'Reference: ${_recordObject(row['document'])['reference']}; ${_recordObject(row['document'])['evidence_url']}',
      'Scope: ${_recordObject(row['document'])['scope']}; validity: ${_recordObject(row['document'])['valid_from']} to ${_recordObject(row['document'])['valid_until']}; review: ${_recordObject(row['document'])['review_status']}',
      'Method: ${_recordObject(row['document'])['method']}',
      if (row['kind'] == 'supporting_reference')
        'Citation: ${_recordObject(_recordObject(row['document'])['payload'])['citation']}',
      'Content checksum: ${row['content_sha256']}',
    ],
  ];
}
