part of '../main.dart';

/// Plain-language presentation of saved results. No scores or inputs change.
class FarmerAnalysisContent extends StatelessWidget {
  final AnalysisState state;
  final Map<String, dynamic> record;
  const FarmerAnalysisContent({
    super.key,
    required this.state,
    required this.record,
  });

  @override
  Widget build(BuildContext context) {
    final preliminary = WebAnalysisMetrics.preliminary(record);
    final annualCheck =
        record['reference_screening_reason'] == 'annual_model_pending';
    final crops = preliminary || record['is_crop_recommended'] == false
        ? <Map<String, dynamic>>[]
        : rankedCropRecommendations(record);
    final model = isModelRanked(record);
    final cover = analysisMapValue(record['land_cover']);
    final headline = annualCheck
        ? 'Annual land check'
        : preliminary
        ? 'More data needed'
        : crops.isNotEmpty
        ? 'Crop choices for your farm'
        : cover['status'] == 'water'
        ? 'Water area detected'
        : ['built', 'built_up', 'urban'].contains(cover['status'])
        ? 'Built-up area detected'
        : 'No crop recommendation yet';
    final scope =
        '${record['session_id']}-${record['prediction_context_id']}-${record['boundary_version']}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GeoResultCard(child: AnalysisIdentity(record: record, compact: true)),
        if (isAnnualPrototypeRecord(record))
          AnnualPrototypeNotice(record: record),
        GeoResultCard(
          key: const ValueKey('farmer-result-summary'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                headline,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                annualCheck
                    ? 'Five-year climate and terrain checks. NPK is not yet assessed.'
                    : preliminary
                    ? 'Land check only. Soil data is incomplete.'
                    : crops.isEmpty
                    ? 'Ask an analyst to check the available land data.'
                    : model
                    ? 'Model scores rank approved crops, not harvest success.'
                    : 'These choices use the saved condition checks.',
              ),
              if (_farmerUsesEstimates(record)) ...[
                const SizedBox(height: 8),
                const Text(
                  'Estimated soil data — not a field soil test.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
              if (isNoNpkModelRecord(record)) ...[
                const SizedBox(height: 8),
                const Text(
                  'NPK not used. PAGRO soil data pending.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
              for (var i = 0; i < crops.length; i++)
                _FarmerCropRow(crop: crops[i], record: record, rank: i + 1),
            ],
          ),
        ),
        _FarmerDisclosure(
          key: ValueKey('farmer-map-$scope'),
          title: 'Farm map',
          icon: Icons.map_outlined,
          builder: (_) => SpatialRasterCard(record: record, simple: true),
        ),
        _FarmerDisclosure(
          key: ValueKey('farmer-details-$scope'),
          title: 'Full analysis details',
          icon: Icons.info_outline,
          builder: (_) => ReferenceAnalysisContent(
            state: state,
            record: record,
            showActions: false,
            farmerDetails: true,
          ),
        ),
        AnalysisReviewCard(
          key: ValueKey('farmer-review-$scope'),
          state: state,
          record: record,
          simple: true,
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 2, 8, 12),
          child: FarmerLegend(
            title: 'Review color guide',
            items: [
              FarmerLegendItem(
                Icons.edit_note,
                Color(0xFF667085),
                'Gray: Not sent',
              ),
              FarmerLegendItem(
                Icons.hourglass_top,
                Color(0xFF805700),
                'Brown: Waiting',
              ),
              FarmerLegendItem(
                Icons.verified,
                Color(0xFF1FA463),
                'Green: Reviewed',
              ),
              FarmerLegendItem(
                Icons.report_gmailerrorred,
                Color(0xFFE45B5B),
                'Red: Not approved',
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Text(
            'Approved means reviewed, not guaranteed crop success.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            try {
              await generateAnalysisPdf(record, state: state);
            } catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(friendlyErrorMessage(error))),
                );
              }
            }
          },
          icon: const Icon(Icons.download_outlined),
          label: const Text('Save report (PDF)'),
        ),
      ],
    );
  }
}

bool _farmerUsesEstimates(Map<String, dynamic> record) {
  if (record['nutrient_display_basis'] == 'legacy_model_estimates') {
    return true;
  }
  final quality = analysisMapValue(record['data_quality']);
  return ['nitrogen', 'phosphorus', 'potassium'].any((key) {
    final item = analysisMapValue(quality[key]);
    return '${item['overall_quality'] ?? item['quality'] ?? ''}'
        .toLowerCase()
        .contains('estimated');
  });
}

class FarmerLegendItem {
  final IconData icon;
  final Color color;
  final String label;
  const FarmerLegendItem(this.icon, this.color, this.label);
}

/// Text and distinct symbols always accompany colors, including missing data.
class FarmerLegend extends StatelessWidget {
  final String title;
  final List<FarmerLegendItem> items;
  const FarmerLegend({super.key, required this.title, required this.items});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 7),
      Wrap(
        spacing: 14,
        runSpacing: 8,
        children: [
          for (final item in items)
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  item.icon,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Color.lerp(item.color, Colors.white, .5)
                      : item.color,
                  size: 17,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    item.label,
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

class FarmerLiveMapGuide extends StatelessWidget {
  final AnalysisState state;
  const FarmerLiveMapGuide({super.key, required this.state});
  @override
  Widget build(BuildContext context) {
    final record = state.result;
    final points = List<LatLng>.from(state.polygonPoints);
    final saved = record == null
        ? <LatLng>[]
        : FarmGeometry.fromPayload(record['selected_polygon']);
    final layerId = {
      'NDVI': 'ndvi',
      'Soil pH': 'soil_ph',
      'Rainfall': rainfallLayerForRecord(record ?? {}),
      'Elevation': 'elevation',
      'Slope': 'slope',
    }[state.heatmapLayer];
    final sameBoundary =
        !state.drawing &&
        points.length >= 3 &&
        saved.length >= 3 &&
        jsonEncode(FarmGeometry.payload(points)) ==
            jsonEncode(FarmGeometry.payload(saved));
    final layer =
        !sameBoundary ||
            record == null ||
            layerId == null ||
            spatialCellPolygons(record, layerId).isEmpty
        ? <String, dynamic>{}
        : spatialLayers(record).firstWhere((item) => item['id'] == layerId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const FarmerLegend(
          title: 'Symbols',
          items: [
            FarmerLegendItem(
              Icons.location_on,
              Colors.red,
              'Pin: Selected place',
            ),
            FarmerLegendItem(Icons.crop_free, green, 'Outline: Farm boundary'),
            FarmerLegendItem(
              Icons.filter_1,
              green,
              'Numbered dots: Boundary corners',
            ),
          ],
        ),
        if (layer.isNotEmpty) ...[
          const SizedBox(height: 16),
          FarmerLegend(
            title: '${layer['label']} (${layer['unit']}) colors',
            items: [
              for (final row in spatialRows(
                spatialObject(layer['legend'])['classes'],
              ))
                FarmerLegendItem(
                  Icons.square,
                  spatialColor('${row['color']}'),
                  '${row['label']}: ${spatialValue(row['minimum'])}–${spatialValue(row['maximum'])}',
                ),
              FarmerLegendItem(
                Icons.help_outline,
                spatialColor(spatialCellColor(layer, null)),
                'Gray: No usable reading',
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text('Colors show the reading level, not crop suitability.'),
        ],
      ],
    );
  }
}

class _FarmerDisclosure extends StatelessWidget {
  final String title;
  final IconData icon;
  final WidgetBuilder builder;
  const _FarmerDisclosure({
    super.key,
    required this.title,
    required this.icon,
    required this.builder,
  });
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      key: PageStorageKey<String>('farmer-disclosure-${key ?? title}'),
      leading: Icon(icon),
      title: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      children: [Builder(builder: builder)],
    ),
  );
}

class _FarmerCropRow extends StatelessWidget {
  final Map<String, dynamic> crop, record;
  final int rank;
  const _FarmerCropRow({
    required this.crop,
    required this.record,
    required this.rank,
  });
  @override
  Widget build(BuildContext context) {
    final name = '${crop['crop'] ?? crop['name'] ?? 'Unnamed crop'}';
    final score = analysisNumber(crop['compatibility_pct'] ?? crop['score']);
    final label = score == null
        ? 'Score unavailable'
        : isModelRanked(record)
        ? 'Model score: ${score.toStringAsFixed(1)}%'
        : record['scoring_version'] != null
        ? 'Condition score: ${score.toStringAsFixed(1)}/100'
        : 'Recorded score: ${score.toStringAsFixed(1)}%';
    return ListTile(
      key: ValueKey('farmer-crop-$rank-$name'),
      contentPadding: const EdgeInsets.symmetric(vertical: 5),
      leading: CropArtwork(name, size: 40),
      title: Text(
        '$rank. $name',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          if (score != null) ...[
            const SizedBox(height: 5),
            LinearProgressIndicator(
              value: (score / 100).clamp(0, 1),
              minHeight: 5,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
            ),
          ],
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) =>
            _FarmerCropSheet(crop: crop, record: record, rank: rank),
      ),
    );
  }
}

class _FarmerCropSheet extends StatelessWidget {
  final Map<String, dynamic> crop, record;
  final int rank;
  const _FarmerCropSheet({
    required this.crop,
    required this.record,
    required this.rank,
  });
  @override
  Widget build(BuildContext context) {
    final name = '${crop['crop'] ?? crop['name'] ?? 'Unnamed crop'}';
    final factors = environmentalFactorViews(crop, record);
    final screening = factors.any((f) => f.applicationScreening);
    final explanation = verifiedLocalExplanation(record);
    final view = explanation.isEmpty
        ? <String, dynamic>{}
        : localCropView(explanation, name);
    final features = localRows(view['features'])
      ..sort(
        (a, b) => (b['contribution_pp'] as num).abs().compareTo(
          (a['contribution_pp'] as num).abs(),
        ),
      );
    final raises = features
        .where((f) => (f['contribution_pp'] as num) > 0)
        .take(2)
        .toList();
    final lowers = features
        .where((f) => (f['contribution_pp'] as num) < 0)
        .take(2)
        .toList();
    return CropSheetFrame(
      header: Row(
        children: [
          CropArtwork(name),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                color: CropSheetStyle.ink,
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
      children: [
        SeasonalPlantingAdvice(record: record, crop: name),
        CropVarietyReference(crop: name),
        Text(
          screening ? 'Land checks' : 'Growing conditions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          screening
              ? 'General land checks, not crop-specific requirements.'
              : 'Checks use the saved crop reference ranges.',
        ),
        const SizedBox(height: 14),
        const FarmerLegend(
          title: 'Condition color guide',
          items: [
            FarmerLegendItem(
              Icons.check_circle,
              Color(0xFF14833B),
              'Green: Fits range',
            ),
            FarmerLegendItem(
              Icons.error_outline,
              CropSheetStyle.amber,
              'Amber: Partial fit',
            ),
            FarmerLegendItem(
              Icons.error,
              CropSheetStyle.red,
              'Red: Outside range',
            ),
            FarmerLegendItem(
              Icons.help_outline,
              CropSheetStyle.grey,
              'Gray: Not assessed',
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (factors.isEmpty)
          const Text('No saved condition checks. Ask an analyst for help.'),
        for (final factor in factors) _FarmerFactorRow(factor),
        const SizedBox(height: 6),
        const Text(
          'Not assessed means a check is missing, not that the land is poor.',
          style: TextStyle(fontSize: 12),
        ),
        if (raises.isNotEmpty || lowers.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text(
            'Why this crop?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (raises.isNotEmpty)
            Text(
              'Raises its model score: ${raises.map((f) => f['label'] ?? f['feature']).join(', ')}.',
            ),
          if (lowers.isNotEmpty)
            Text(
              'Lowers its model score: ${lowers.map((f) => f['label'] ?? f['feature']).join(', ')}.',
            ),
          const SizedBox(height: 8),
          const Text(
            'These model patterns do not prove crop success.',
            style: TextStyle(fontSize: 12),
          ),
        ],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () =>
              showCropDetailsSheet(context, crop, record, rank: rank),
          icon: const Icon(Icons.menu_book_outlined),
          label: const Text('Full explanation and sources'),
        ),
      ],
    );
  }
}

class _FarmerFactorRow extends StatelessWidget {
  final CropFactorView factor;
  const _FarmerFactorRow(this.factor);
  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (factor.state) {
      CropFactorState.suitable => (Icons.check_circle, 'Fits range'),
      CropFactorState.near => (Icons.error_outline, 'Partial fit'),
      CropFactorState.outside => (Icons.error, 'Outside range'),
      CropFactorState.unassessed => (Icons.help_outline, 'Not assessed'),
    };
    final nutrient = [
      'nitrogen',
      'phosphorus',
      'potassium',
      'n',
      'p',
      'k',
    ].contains(factor.key.toLowerCase());
    final value = nutrient
        ? (factor.value == null
              ? 'No soil reading'
              : 'Input details in the full explanation')
        : factor.valueText ??
              (factor.value == null
                  ? 'No reading'
                  : _withUnit(_cropNum(factor.value), factor.unit));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            factor.label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              Text(value),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: MatchStatusBadge.colorFor(factor.state),
                  ),
                  const SizedBox(width: 5),
                  Flexible(child: Text(factor.statusLabel ?? label)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
