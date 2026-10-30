import 'dart:convert';
import 'dart:collection';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;

const localAttributionMethod = 'random_forest_tree_path_probability';
const localAttributionVersion = 'rf-path-probability-v1';
const localAttributionTolerance = 1e-9;

Map<String, dynamic> localObject(dynamic raw) {
  if (raw is String) {
    try {
      raw = jsonDecode(raw);
    } catch (_) {
      return {};
    }
  }
  return raw is Map ? Map<String, dynamic>.from(raw) : {};
}

List<Map<String, dynamic>> localRows(dynamic raw) => raw is List
    ? raw.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
    : [];

dynamic _localSorted(dynamic value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _localSorted(value[key])};
  }
  if (value is List) {
    return value.map(_localSorted).toList();
  }
  return value;
}

String localNumericHash(
  String domain,
  Map<String, dynamic> metadata,
  List<double> values,
) {
  if (values.any((v) => !v.isFinite)) {
    throw const FormatException('Nonfinite attribution values');
  }
  final numbers = ByteData(values.length * 8);
  for (var i = 0; i < values.length; i++) {
    numbers.setFloat64(i * 8, values[i], Endian.big);
  }
  final bytes = BytesBuilder(copy: false)
    ..add(utf8.encode(domain))
    ..addByte(0)
    ..add(utf8.encode(jsonEncode(_localSorted(metadata))))
    ..addByte(0)
    ..add(numbers.buffer.asUint8List());
  return crypto.sha256.convert(bytes.toBytes()).toString();
}

String localInputHash(
  String version,
  List<String> order,
  Map<String, dynamic> inputs,
) {
  if (inputs.length != order.length ||
      order.any((key) => inputs[key] is! num)) {
    throw const FormatException('Input feature mismatch');
  }
  return localNumericHash(
    'geosustain-local-input-v1',
    {'feature_order': order, 'model_version': version},
    [for (final key in order) (inputs[key] as num).toDouble()],
  );
}

List<double> _localNumbers(dynamic value, int length) {
  if (value is! List ||
      value.length != length ||
      value.any((v) => v is! num || !v.isFinite)) {
    throw const FormatException('Attribution vector shape mismatch');
  }
  return value.map((v) => (v as num).toDouble()).toList();
}

List<String> _localStrings(dynamic value, int maximum) {
  if (value is! List ||
      value.isEmpty ||
      value.length > maximum ||
      value.any((v) => v is! String || v.isEmpty)) {
    throw const FormatException('Attribution label shape mismatch');
  }
  final strings = value.cast<String>();
  if (strings.toSet().length != strings.length) {
    throw const FormatException('Duplicate attribution labels');
  }
  return strings;
}

List<List<double>> _localMatrix(dynamic value, int rows, int columns) {
  if (value is! List || value.length != rows) {
    throw const FormatException('Attribution matrix shape mismatch');
  }
  return value.map((row) => _localNumbers(row, columns)).toList();
}

bool _localSame(dynamic a, dynamic b) =>
    jsonEncode(_localSorted(a)) == jsonEncode(_localSorted(b));
bool _localClose(num a, num b) => (a - b).abs() <= localAttributionTolerance;
double _localSum(Iterable<double> values) => values.fold(0.0, (a, b) => a + b);

Map<String, dynamic> _coreMetadata(Map<String, dynamic> core) => {
  for (final key in [
    'class_order',
    'feature_order',
    'input_hash',
    'method_version',
    'model_version',
  ])
    key: core[key],
};

List<double> _coreValues(
  Map<String, dynamic> core,
  int classes,
  int features,
) => [
  ..._localNumbers(core['base_values'], classes),
  for (final row in _localMatrix(core['contributions'], classes, features))
    ...row,
  ..._localNumbers(core['model_scores'], classes),
];

Map<String, dynamic> _aggregateMetadata(Map<String, dynamic> body) => {
  for (final key in [
    'class_order',
    'crop_classes',
    'feature_definitions',
    'feature_order',
    'input_snapshot_hash',
    'method_version',
    'model_version',
    'prediction_context_id',
    'sample_attribution_hashes',
    'sample_count',
    'sample_input_hashes',
  ])
    key: body[key],
};

/// Validate saved data only. Never retrieve the current model or fill old results.
Map<String, dynamic> verifiedLocalExplanation(Map<String, dynamic> record) {
  try {
    final body = localObject(record['local_model_explanation']);
    final snapshot = localObject(record['model_explanation']);
    final version = body['model_version'];
    if (body['schema_version'] != 1 ||
        body['status'] != 'available' ||
        body['scope'] != 'sample_mean_class_probability' ||
        body['method'] != localAttributionMethod ||
        body['method_version'] != localAttributionVersion ||
        record['recommendation_basis'] != 'model_probability' ||
        version is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(version) ||
        version != record['model_version'] ||
        version != snapshot['model_version'] ||
        record['prediction_context_id'] == null ||
        body['prediction_context_id'] != record['prediction_context_id'] ||
        body['prediction_context_id'] != snapshot['prediction_context_id'] ||
        body['input_snapshot_hash'] != snapshot['input_snapshot_hash'] ||
        body['selected_output'] != record['predicted_crop'] ||
        body['selected_score'] != record['crop_compatibility_pct']) {
      return {};
    }
    final features = _localStrings(body['feature_order'], 32);
    final classes = _localStrings(body['class_order'], 64);
    final f = features.length, c = classes.length;
    final base = _localNumbers(body['base_values'], c);
    final matrix = _localMatrix(body['contributions'], c, f);
    final scores = _localNumbers(body['model_scores'], c);
    final samples = localRows(snapshot['samples']);
    if (samples.isEmpty ||
        samples.length > 64 ||
        samples.length != body['sample_count'] ||
        samples.length != (snapshot['samples'] as List).length) {
      return {};
    }
    final inputHashes = <String>[], attributionHashes = <String>[];
    final means = List.generate(c, (_) => List.filled(f, 0.0));
    final baseMeans = List.filled(c, 0.0), scoreMeans = List.filled(c, 0.0);
    for (final sample in samples) {
      final core = localObject(sample['local_attribution']);
      if (core['schema_version'] != 1 ||
          core['status'] != 'available' ||
          core['method'] != localAttributionMethod ||
          core['method_version'] != localAttributionVersion ||
          core['model_version'] != version ||
          sample['model_version'] != version ||
          !_localSame(core['feature_order'], features) ||
          !_localSame(core['class_order'], classes) ||
          localInputHash(version, features, localObject(sample['inputs'])) !=
              core['input_hash']) {
        return {};
      }
      final values = _coreValues(core, c, f);
      final hash = localNumericHash(
        'geosustain-rf-path-attribution-v1',
        _coreMetadata(core),
        values,
      );
      if (hash != core['attribution_hash']) {
        return {};
      }
      inputHashes.add(core['input_hash'] as String);
      attributionHashes.add(hash);
      final sampleBase = _localNumbers(core['base_values'], c);
      final sampleMatrix = _localMatrix(core['contributions'], c, f);
      final sampleScores = _localNumbers(core['model_scores'], c);
      final probabilities = localObject(sample['class_probabilities']);
      if (probabilities.length != c ||
          classes.any((name) => probabilities[name] is! num) ||
          !_localClose(
            _localSum([
              for (final name in classes)
                (probabilities[name] as num).toDouble(),
            ]),
            1,
          )) {
        return {};
      }
      for (var k = 0; k < c; k++) {
        final probability = (probabilities[classes[k]] as num).toDouble();
        if (!probability.isFinite ||
            probability < 0 ||
            probability > 1 ||
            !_localClose(sampleScores[k], probability) ||
            !_localClose(
              sampleBase[k] + _localSum(sampleMatrix[k]),
              sampleScores[k],
            )) {
          return {};
        }
        baseMeans[k] += sampleBase[k] / samples.length;
        scoreMeans[k] += sampleScores[k] / samples.length;
        for (var j = 0; j < f; j++) {
          means[k][j] += sampleMatrix[k][j] / samples.length;
        }
      }
    }
    if (!_localSame(inputHashes, body['sample_input_hashes']) ||
        !_localSame(attributionHashes, body['sample_attribution_hashes'])) {
      return {};
    }
    for (var k = 0; k < c; k++) {
      if (!_localClose(baseMeans[k], base[k]) ||
          !_localClose(scoreMeans[k], scores[k]) ||
          !_localClose(base[k] + _localSum(matrix[k]), scores[k])) {
        return {};
      }
      for (var j = 0; j < f; j++) {
        if (!_localClose(means[k][j], matrix[k][j])) {
          return {};
        }
      }
    }
    final inputs = localRows(body['feature_inputs']);
    final definitions = localRows(body['feature_definitions']);
    if (inputs.length != f || definitions.length != f) {
      return {};
    }
    for (var j = 0; j < f; j++) {
      if (inputs[j]['feature'] != features[j] ||
          definitions[j]['feature'] != features[j] ||
          definitions[j]['label'] is! String ||
          definitions[j]['unit'] is! String) {
        return {};
      }
      final values = [
        for (final sample in samples)
          (localObject(sample['inputs'])[features[j]] as num).toDouble(),
      ];
      final expected = {
        'mean': _localSum(values) / values.length,
        'minimum': values.reduce((a, b) => a < b ? a : b),
        'maximum': values.reduce((a, b) => a > b ? a : b),
      };
      for (final key in expected.keys) {
        if (inputs[j][key] is! num ||
            !_localClose(inputs[j][key] as num, expected[key]!)) {
          return {};
        }
      }
    }
    final bindings = localRows(body['crop_classes']);
    final crops = localRows(record['crop_assessments']);
    if (bindings.isEmpty ||
        bindings.length != crops.length ||
        bindings.length > c ||
        bindings.map((v) => v['crop']).toSet().length != bindings.length) {
      return {};
    }
    for (final binding in bindings) {
      final index = binding['class_index'];
      final crop = crops.where((v) => v['crop'] == binding['crop']).firstOrNull;
      if (index is! int ||
          index < 0 ||
          index >= c ||
          classes[index] != binding['class_label'] ||
          '${binding['crop']}'.toLowerCase() != classes[index] ||
          crop == null ||
          crop['compatibility_pct'] is! num ||
          !_localClose(
            (crop['compatibility_pct'] as num) / 100,
            scores[index],
          )) {
        return {};
      }
    }
    final selected = bindings
        .where((v) => v['crop'] == record['predicted_crop'])
        .firstOrNull;
    if (selected == null ||
        record['crop_compatibility_pct'] is! num ||
        !_localClose(
          (record['crop_compatibility_pct'] as num) / 100,
          scores[selected['class_index'] as int],
        )) {
      return {};
    }
    final signedValues = [
      ...base,
      for (final row in matrix) ...row,
      ...scores,
      for (final item in inputs)
        for (final key in ['mean', 'minimum', 'maximum'])
          (item[key] as num).toDouble(),
    ];
    if (localNumericHash(
          'geosustain-rf-path-aggregate-v1',
          _aggregateMetadata(body),
          signedValues,
        ) !=
        body['snapshot_hash']) {
      return {};
    }
    return body;
  } catch (_) {
    return {};
  }
}

Map<String, dynamic> localCropView(Map<String, dynamic> body, String crop) {
  final binding = localRows(
    body['crop_classes'],
  ).where((v) => v['crop'] == crop).firstOrNull;
  if (binding == null) {
    return {};
  }
  final index = binding['class_index'] as int;
  final definitions = localRows(body['feature_definitions']);
  final inputs = localRows(body['feature_inputs']);
  final contribution = (body['contributions'] as List)[index] as List;
  return {
    ...binding,
    'score_pct': ((body['model_scores'] as List)[index] as num) * 100,
    'base_pct': ((body['base_values'] as List)[index] as num) * 100,
    'net_pp':
        _localSum(contribution.cast<num>().map((v) => v.toDouble())) * 100,
    'features': [
      for (var j = 0; j < definitions.length; j++)
        {
          ...definitions[j],
          ...inputs[j],
          'contribution_pp': (contribution[j] as num) * 100,
        },
    ],
  };
}

Map<String, dynamic> localCropComparison(
  Map<String, dynamic> body,
  String crop,
  String alternative,
) {
  final a = localCropView(body, crop), b = localCropView(body, alternative);
  if (a.isEmpty || b.isEmpty || crop == alternative) {
    return {};
  }
  final af = localRows(a['features']), bf = localRows(b['features']);
  return {
    'crop': crop,
    'alternative': alternative,
    'score_gap_pp': (a['score_pct'] as num) - (b['score_pct'] as num),
    'baseline_gap_pp': (a['base_pct'] as num) - (b['base_pct'] as num),
    'features': [
      for (var j = 0; j < af.length; j++)
        {
          'feature': af[j]['feature'],
          'label': af[j]['label'],
          'contribution_pp':
              (af[j]['contribution_pp'] as num) -
              (bf[j]['contribution_pp'] as num),
        },
    ],
  };
}

String localSigned(num value, {int decimals = 3}) =>
    '${value > 0 ? '+' : ''}${value.toStringAsFixed(decimals)}';

String localCropSummary(Map<String, dynamic> body, String crop) {
  final features = localRows(localCropView(body, crop)['features']);
  final positive =
      features.where((v) => (v['contribution_pp'] as num) > 0).toList()..sort(
        (a, b) => (b['contribution_pp'] as num).compareTo(
          a['contribution_pp'] as num,
        ),
      );
  final negative =
      features.where((v) => (v['contribution_pp'] as num) < 0).toList()..sort(
        (a, b) => (a['contribution_pp'] as num).compareTo(
          b['contribution_pp'] as num,
        ),
      );
  return [
    if (positive.isNotEmpty)
      '${positive.first['label']} raises $crop\'s model score most.',
    if (negative.isNotEmpty)
      '${negative.first['label']} lowers $crop\'s model score most.',
    if (positive.isEmpty && negative.isEmpty)
      'The saved inputs leave the model score at its baseline.',
  ].join(' ');
}

List<String> localExplanationLines(Map<String, dynamic> record) {
  final body = verifiedLocalExplanation(record);
  if (body.isEmpty) {
    return [
      'A matching local Explainable AI snapshot was not saved or could not be verified. Signed contributions are unavailable; saved model scores are unchanged.',
    ];
  }
  return [
    'Explainable AI: ${body['method_label']}',
    'Method/version: ${body['method']} / ${body['method_version']}',
    'Model SHA-256: ${body['model_version']}',
    'Analysis context: ${body['prediction_context_id']}',
    'Input snapshot hash: ${body['input_snapshot_hash']}',
    'Attribution snapshot hash: ${body['snapshot_hash']}',
    '${body['baseline_definition']}',
    '${body['aggregation']}',
    'Contributions are signed percentage points. Model scores remain uncalibrated class scores. Display values are rounded; base plus all contributions is verified within 0.0000001 percentage points.',
    for (final binding in localRows(body['crop_classes'])) ...[
      '${binding['crop']}: baseline ${(localCropView(body, '${binding['crop']}')['base_pct'] as num).toStringAsFixed(6)}%; model score ${(localCropView(body, '${binding['crop']}')['score_pct'] as num).toStringAsFixed(6)}%.',
      for (final feature in localRows(
        localCropView(body, '${binding['crop']}')['features'],
      ))
        '${feature['label']}: ${localSigned(feature['contribution_pp'] as num, decimals: 6)} pp; recorded sample input mean ${(feature['mean'] as num).toStringAsFixed(6)}, range ${(feature['minimum'] as num).toStringAsFixed(6)} to ${(feature['maximum'] as num).toStringAsFixed(6)} ${feature['unit']}.',
    ],
    for (final limitation in body['limitations'] as List) '$limitation',
  ];
}
