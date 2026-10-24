part of '../main.dart';

// Display the actual recorded inference inputs, never fabricated lab values.
double? recordedModelInput(Map<String, dynamic> record, String key) {
  final explanation = analysisMapValue(record['model_explanation']);
  final samples = analysisListValue(explanation['samples']);
  if (samples.isEmpty) return null;
  final values = <double>[];
  for (final sample in samples) {
    final inputs = analysisMapValue(analysisMapValue(sample)['inputs']);
    final value = analysisNumber(inputs[key]);
    if (value == null) return null;
    values.add(value);
  }
  return values.reduce((a, b) => a + b) / values.length;
}

class ReferenceAnalysisContent extends StatefulWidget {
  final AnalysisState state;
  final Map<String, dynamic> record;
  const ReferenceAnalysisContent({
    super.key,
    required this.state,
    required this.record,
  });
  @override
  State<ReferenceAnalysisContent> createState() =>
      _ReferenceAnalysisContentState();
}

class _ReferenceAnalysisContentState extends State<ReferenceAnalysisContent> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final preliminary = r['analysis_mode'] == 'preliminary_environmental';
    final crops =
        preliminary && analysisListValue(r['crop_assessments']).isNotEmpty
        ? analysisListValue(r['crop_assessments'])
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .where(
                (entry) =>
                    entry['classification'] != 'Disabled in crop settings',
              )
              .toList()
        : rankedCropRecommendations(r);
    if (r['is_crop_recommended'] == false &&
        r['land_cover'] is Map &&
        !(preliminary && crops.isNotEmpty)) {
      final cover = Map<String, dynamic>.from(r['land_cover']);
      final unverified =
          cover['status'] == 'unknown' ||
          '${r['land_status']}'.toUpperCase() == 'UNKNOWN';
      final coverage = analysisNumber(cover['observed_fraction']);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GeoResultCard(child: GeoRecordSummary(r)),
          if (r['preliminary_notice'] != null)
            GeoResultCard(
              color: const Color(0xFFFFF4D6),
              child: Text('${r['preliminary_notice']}'),
            ),
          GeoResultCard(
            color: const Color(0xFFFFF6E5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFFFFE2A8),
                      child: Icon(
                        unverified
                            ? Icons.satellite_alt
                            : cover['status'] == 'water'
                            ? Icons.water_drop
                            : Icons.location_city,
                        color: GeoDesign.orange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        unverified
                            ? 'Land cover not verified'
                            : '${r['land_status'] ?? 'Land use advisory'}',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '${cover['message'] ?? r['analysis_summary'] ?? ''}',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          GeoResultCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Land cover composition',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (unverified) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Incomplete satellite coverage. Mapped percentages do not establish that the remaining area is free of buildings or water.',
                  ),
                  GeoCoverBar(
                    label: 'Confident satellite coverage',
                    fraction: coverage,
                    color: Colors.blueGrey,
                    icon: Icons.satellite_alt,
                  ),
                ],
                GeoCoverBar(
                  label: 'Mapped buildings/roads',
                  fraction: unverified && (coverage == null || coverage == 0)
                      ? null
                      : analysisNumber(cover['built_fraction']),
                  color: GeoDesign.statusRed,
                  icon: Icons.home_rounded,
                ),
                GeoCoverBar(
                  label: 'Mapped water',
                  fraction: unverified && (coverage == null || coverage == 0)
                      ? null
                      : analysisNumber(cover['water_fraction']),
                  color: Colors.blue,
                  icon: Icons.water_drop,
                ),
              ],
            ),
          ),
          CagroSoilObservationsCard(record: r),
          const GeoResultCard(
            child: Text(
              'This is a partial assessment, not a crop recommendation. You can ask an analyst to review the available evidence or retry online when coverage is available.',
            ),
          ),
          AnalysisReviewCard(state: widget.state, record: r),
          if ('${cover['limitation'] ?? ''}'.isNotEmpty)
            GeoResultCard(
              color: const Color(0xFFE9F3FD),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notes',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${cover['limitation']}',
                    style: TextStyle(height: 1.4, color: GeoDesign.muted),
                  ),
                ],
              ),
            ),
          if ('${cover['source'] ?? ''}${cover['attribution'] ?? ''}'
              .isNotEmpty)
            GeoResultCard(
              color: const Color(0xFFEEF4EF),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Data source',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text('${cover['source'] ?? ''}'),
                  if ('${cover['attribution'] ?? ''}'.isNotEmpty) ...[
                    const Divider(height: 24),
                    Text(
                      '${cover['attribution']}',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      );
    }

    final best = crops.isEmpty ? <String, dynamic>{} : crops.first;
    final score = analysisNumber(best['compatibility_pct']);
    final modern = r['scoring_version'] != null;
    final modelRanked = isModelRanked(r);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (r['preliminary_notice'] != null)
          GeoResultCard(
            color: const Color(0xFFFFF4D6),
            child: Text('${r['preliminary_notice']}'),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BoundaryThumbnail(r, size: 100),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnalysisIdentity(record: r, compact: true),
                      const SizedBox(height: 7),
                      VerificationStatusBadge(
                        status: '${r['verification_status'] ?? 'draft'}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: geoPanelColor(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD7EBDF)),
          ),
          child: Row(
            children: [
              for (final item in [
                (Icons.bar_chart, 'Overview'),
                (
                  Icons.eco_outlined,
                  preliminary ? 'Comparisons' : 'Recommended',
                ),
                (Icons.list, 'Key Factors'),
                (Icons.map_outlined, 'Map'),
              ].indexed)
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => tab = item.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 2,
                      ),
                      decoration: BoxDecoration(
                        color: tab == item.$1 ? green : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            item.$2.$1,
                            color: tab == item.$1 ? Colors.white : darkGreen,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.$2.$2,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              color: tab == item.$1 ? Colors.white : darkGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (tab == 0)
          _AnalysisSection(
            title: modelRanked
                ? 'Top model recommendation'
                : preliminary
                ? 'Preliminary environmental screening'
                : 'Land suitability',
            icon: Icons.spa_outlined,
            children: [
              Text(
                modelRanked
                    ? 'RANDOM FOREST MODEL SCORE'
                    : modern
                    ? 'REFERENCE-BASED SCREENING'
                    : farmerLandType(r).toUpperCase(),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    preliminary
                        ? 'Preliminary only'
                        : score == null
                        ? 'Insufficient data'
                        : '${score.toStringAsFixed(1)}${modern && !modelRanked ? '/100' : '%'}',
                    style: TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.w800,
                      color: green,
                    ),
                  ),
                  Text(
                    modelRanked
                        ? '${best['crop'] ?? ''}'
                        : modern
                        ? 'Assessed-condition index'
                        : (score == null ? '' : farmerSuitability(score)),
                    style: TextStyle(fontSize: 12, color: green),
                  ),
                ],
              ),
              if (score != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: LinearProgressIndicator(
                      value: (score / 100).clamp(0, 1),
                      minHeight: 8,
                      backgroundColor: softGreen,
                    ),
                  ),
                ),
              AnalysisReadableText(
                '${best['explanation'] ?? r['analysis_summary'] ?? analysisMapValue(r['xai_explanation'])['summary'] ?? 'No summary was recorded.'}',
              ),
              if (modelRanked)
                Text(
                  'Model class score, not a harvest probability. Nutrient inputs include estimates.',
                  style: TextStyle(fontSize: 12),
                )
              else if (preliminary)
                const Text(
                  'Compare individual conditions below. Missing CAGRO NPK prevents a complete soil suitability assessment.',
                  style: TextStyle(fontSize: 12),
                )
              else if (modern)
                Text(
                  'Saved reference-based analysis. Run a new analysis to get model-ranked recommendations.',
                  style: TextStyle(fontSize: 12),
                ),
            ],
          ),
        if (tab == 0 || tab == 1)
          _AnalysisSection(
            title: preliminary
                ? 'Crop condition comparisons'
                : 'Recommended crops',
            icon: Icons.spa_outlined,
            children: [
              if (crops.isEmpty) Text('No crop assessment was saved.'),
              for (final entry in crops.indexed)
                _cropRow(entry.$2, entry.$1 + 1, r),
              if (crops.isNotEmpty)
                Text(
                  preliminary
                      ? 'Available crop comparisons; this is not a complete suitability ranking.'
                      : modelRanked
                      ? 'Top ${crops.length}, highest model score first.'
                      : 'Top ${crops.length}, highest recorded score first.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF5D6A61)),
                ),
            ],
          ),
        if (tab == 0 || tab == 2) ...[
          AnalysisCoverageCard(record: r),
          CagroSoilObservationsCard(record: r),
          _AnalysisSection(
            title: modelRanked
                ? 'Environmental & Soil Reference Assessment'
                : 'Environmental factors (10)',
            icon: Icons.bar_chart,
            children: [
              GeoEqualGrid(
                children: [
                  for (final factor in environmentalFactorViews(best, r))
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5FAF7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFEDF2EF)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _factorIcon(factor.key).$1,
                            color: green,
                            size: 21,
                          ),
                          const SizedBox(height: 5),
                          Text(factor.label, style: TextStyle(fontSize: 12)),
                          Text(
                            factor.value == null
                                ? 'Unavailable'
                                : _withUnit(
                                    _cropNum(factor.value),
                                    factor.unit,
                                  ),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: green,
                            ),
                          ),
                          if (['N', 'P', 'K'].contains(factor.key))
                            Text(
                              'Existing model estimate; not a soil test',
                              style: TextStyle(fontSize: 10),
                            ),
                          if (factor.key == 'ndvi')
                            Text(
                              'Vegetation only; not crop suitability',
                              style: TextStyle(fontSize: 10),
                            ),
                          if (factor.key == 'humidity')
                            Text(
                              'Not a climate average',
                              style: TextStyle(fontSize: 10),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
              TextButton(
                onPressed: () =>
                    _analysisDetails(context, 'Data sources and limitations', [
                      AnalysisIndicatorsCard(record: r),
                      if (modern)
                        SelectableText('${r['recommendation_scoring']}'),
                    ]),
                child: Text('See all details'),
              ),
            ],
          ),
          if (!modern || modelRanked)
            ModelExplanationCard(record: r)
          else
            _LegacyModelSummary(record: r),
        ],
        if (tab == 3) AnalysisBoundaryPreview(record: r),
        if (tab == 0) ...[
          AnalysisReviewCard(state: widget.state, record: r),
          OutlinedButton.icon(
            onPressed: () async {
              try {
                await generateAnalysisPdf(r, state: widget.state);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(friendlyErrorMessage(e))),
                  );
                }
              }
            },
            icon: const Icon(Icons.download_outlined),
            label: Text('Export analysis report'),
          ),
        ],
      ],
    );
  }

  Widget _cropRow(
    Map<String, dynamic> crop,
    int order,
    Map<String, dynamic> r,
  ) {
    final score = analysisNumber(crop['compatibility_pct']);
    return InkWell(
      onTap: () => _showCropDetails(context, crop, r, rank: order),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            CropArtwork('${crop['crop']}'),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$order. ${crop['crop']}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    r['analysis_mode'] == 'preliminary_environmental'
                        ? '${crop['assessed_count'] ?? 0} documented factors assessed'
                        : score == null
                        ? 'Insufficient data'
                        : isModelRanked(r)
                        ? '${score.toStringAsFixed(1)}% · Model score'
                        : r['scoring_version'] != null
                        ? '${score.toStringAsFixed(1)}/100 · Assessed-condition index'
                        : '${score.toStringAsFixed(1)}% · ${crop['classification'] ?? farmerSuitability(score)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (score != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: LinearProgressIndicator(
                        value: (score / 100).clamp(0, 1),
                        minHeight: 5,
                        backgroundColor: softGreen,
                      ),
                    ),
                  if (!isModelRanked(r) && crop['assessed_count'] != null)
                    Text(
                      '${crop['assessed_count']}/${crop['total_factors'] ?? 6} reference conditions assessed',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64756C)),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ReferenceCropDetails extends StatefulWidget {
  final Map<String, dynamic> crop, record;
  const _ReferenceCropDetails({required this.crop, required this.record});
  @override
  State<_ReferenceCropDetails> createState() => _ReferenceCropDetailsState();
}

class _ReferenceCropDetailsState extends State<_ReferenceCropDetails> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final crop = widget.crop,
        score = analysisNumber(widget.crop['compatibility_pct']);
    final factors = analysisListValue(crop['factors']).whereType<Map>();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .83,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
              child: Row(
                children: [
                  CropArtwork('${crop['crop']}', size: 60),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${crop['crop']} details',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  for (final label in [
                    'Overview',
                    'Growing Requirements',
                    'Why Recommended',
                  ].indexed)
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: tab == label.$1 ? green : softGreen,
                          foregroundColor: tab == label.$1
                              ? Colors.white
                              : darkGreen,
                        ),
                        onPressed: () => setState(() => tab = label.$1),
                        child: Text(
                          label.$2,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (tab == 0)
                      _AnalysisSection(
                        title: 'Crop overview',
                        children: [
                          Text(cropReason(crop, widget.record)),
                          const SizedBox(height: 14),
                          Text(
                            score == null
                                ? 'Insufficient data'
                                : isModelRanked(widget.record)
                                ? 'Model score: ${score.toStringAsFixed(1)}%'
                                : 'Screening index: ${score.toStringAsFixed(1)}/100',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isModelRanked(widget.record)
                                ? 'The Random Forest class probability determines this ranking. The environmental comparisons do not adjust it. This is not a harvest probability.'
                                : 'This index compares documented requirements with the available observations. It is not a harvest probability, yield forecast, or model prediction.',
                          ),
                        ],
                      ),
                    if (tab == 1)
                      for (final factor in factors)
                        _AnalysisSection(
                          title: '${factor['label']}',
                          children: [
                            if (factor['requirement'] is Map) ...[
                              Text(
                                'Preferred range: ${analysisListValue(factor['requirement']['optimal']).map((v) => v ?? 'unbounded').join(' – ')} ${factor['unit']}',
                              ),
                              if (factor['requirement']['absolute'] != null)
                                Text(
                                  'Absolute range: ${factor['requirement']['absolute']}',
                                ),
                              if (factor['requirement']['classes'] != null)
                                Text(
                                  'Published factor classes: ${factor['requirement']['classes']}',
                                ),
                              Text('Period: ${factor['period']}'),
                              SelectableText(
                                '${factor['requirement']['source']['title']}\n${factor['requirement']['source']['section']}\n${factor['requirement']['source']['url']}',
                                style: TextStyle(fontSize: 12, color: green),
                              ),
                              Text(
                                '${factor['requirement']['limitations']}',
                                style: TextStyle(fontSize: 12),
                              ),
                            ] else
                              Text(
                                'No verified numerical criterion configured. This factor is unassessed.',
                              ),
                          ],
                        ),
                    if (tab == 2) ...[
                      _AnalysisSection(
                        title: isModelRanked(widget.record)
                            ? 'Model ranking method'
                            : 'Suitability calculation',
                        children: [
                          Text('${crop['explanation']}'),
                          const SizedBox(height: 10),
                          Text('${crop['method']}'),
                          Text(
                            'Configuration: ${crop['scoring_version']}',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      for (final factor in factors)
                        _AnalysisSection(
                          title: '${factor['label']}',
                          children: [
                            Text(
                              '${factor['value'] ?? 'Unavailable'} ${factor['unit']} · ${factor['result']}',
                            ),
                            Text(
                              '${analysisMapValue(factor['measurement'])['source'] ?? 'Source unavailable'}',
                              style: TextStyle(fontSize: 12),
                            ),
                            if (analysisMapValue(
                                  factor['measurement'],
                                )['start'] !=
                                null)
                              Text(
                                '${factor['measurement']['start']} to ${factor['measurement']['end_exclusive']} (end excluded)',
                                style: TextStyle(fontSize: 12),
                              ),
                          ],
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegacyModelSummary extends StatelessWidget {
  final Map<String, dynamic> record;
  const _LegacyModelSummary({required this.record});
  @override
  Widget build(BuildContext context) {
    final snapshots = [
      if (record['legacy_model_explanation'] is Map)
        record['legacy_model_explanation'],
      ...analysisListValue(record['legacy_model_samples']),
    ].whereType<Map>().toList();
    final snapshot = snapshots.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(snapshots.first);
    return _AnalysisSection(
      title: 'Actual model · research output',
      icon: Icons.insights_outlined,
      children: [
        Text(
          snapshots.isEmpty
              ? 'The legacy model could not run with the available inputs. It does not determine these crop scores.'
              : 'The retained forest ran on ${snapshots.length} sampled location(s). Its outputs are separate from these suitability calculations.',
        ),
        Text(
          'Training includes synthetic local rows and GIS features. Panabo field validation has not been established.',
          style: TextStyle(fontSize: 12),
        ),
        if (snapshots.isNotEmpty) ...[
          Text(
            'Raw model outputs: ${snapshots.expand((s) => analysisListValue(s['samples'])).whereType<Map>().map((s) => s['raw_prediction']).toSet().join(', ')}',
          ),
          for (final f in analysisListValue(
            snapshot['features'],
          ).whereType<Map>().take(3))
            _ModelImportanceBar(feature: Map<String, dynamic>.from(f)),
          Text(
            'Global, unsigned feature importance; not an explanation of a particular prediction or crop ranking.',
            style: TextStyle(fontSize: 12),
          ),
          TextButton(
            onPressed: () => _analysisDetails(context, 'Actual model details', [
              for (final s in snapshots) ...[
                SelectableText('Model SHA-256: ${s['model_version']}'),
                for (final f in analysisListValue(
                  s['features'],
                ).whereType<Map>())
                  _ModelImportanceBar(feature: Map<String, dynamic>.from(f)),
                SelectableText(
                  const JsonEncoder.withIndent('  ').convert(s['samples']),
                ),
              ],
            ]),
            child: Text('View detailed explanation'),
          ),
        ],
      ],
    );
  }
}
