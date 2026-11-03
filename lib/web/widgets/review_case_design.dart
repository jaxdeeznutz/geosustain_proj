part of '../../main.dart';

class _ReviewCaseHeading extends StatelessWidget {
  final Map<String, dynamic> data;
  final AnalysisState state;
  const _ReviewCaseHeading({required this.data, required this.state});
  @override
  Widget build(BuildContext context) {
    final review = analysisMapValue(data['case']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: WebPortalColors.tint,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.assignment_outlined,
                  size: 32,
                  color: WebPortalColors.accent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Case #${review['id']} – ${reviewLabel(review['status'])}',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: WebPortalColors.ink,
                          ),
                        ),
                        VerificationStatusBadge(status: '${review['status']}'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Analysis #${review['current_session_id']} · Review the saved boundary, measurements and context.',
                      style: TextStyle(color: WebPortalColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _WebCard(
          child: LayoutBuilder(
            builder: (_, box) {
              final fields = [
                (
                  Icons.person_outline,
                  'Current analyst',
                  '${state.currentUser?['username'] ?? state.currentUser?['name'] ?? 'Not recorded'}',
                ),
                (
                  Icons.calendar_today_outlined,
                  'Date submitted',
                  analysisDateText(review['submitted_at']),
                ),
                (
                  Icons.layers_outlined,
                  'Case version',
                  '${review['version'] ?? 'Not recorded'}',
                ),
                (
                  Icons.fact_check_outlined,
                  'Review status',
                  reviewLabel(review['status']),
                ),
              ];
              final columns = box.maxWidth >= 850
                  ? 4
                  : box.maxWidth >= 460
                  ? 2
                  : 1;
              return Wrap(
                spacing: 12,
                runSpacing: 16,
                children: [
                  for (final field in fields)
                    SizedBox(
                      width: (box.maxWidth - 12 * (columns - 1)) / columns,
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: WebPortalColors.tint,
                            child: Icon(
                              field.$1,
                              color: WebPortalColors.accent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  field.$2,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: WebPortalColors.muted,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  field.$3,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ReviewEvidenceLayout extends StatefulWidget {
  final Map<String, dynamic> data;
  const _ReviewEvidenceLayout({super.key, required this.data});
  @override
  State<_ReviewEvidenceLayout> createState() => _ReviewEvidenceLayoutState();
}

class _ReviewEvidenceLayoutState extends State<_ReviewEvidenceLayout> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final record = analysisMapValue(widget.data['analysis']);
    final geometry = widget.data['geometry_matches_current'];
    final tabs = [
      (Icons.layers_outlined, 'Boundary & Measurements'),
      (Icons.spa_outlined, 'Farm Details'),
      (Icons.calendar_month_outlined, 'Seasonal Context'),
      (Icons.attach_file, 'Attachments'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WebCard(
          padding: const EdgeInsets.all(5),
          child: Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final item in tabs.indexed)
                Semantics(
                  selected: tab == item.$1,
                  child: TextButton.icon(
                    key: ValueKey('review-evidence-tab-${item.$1}'),
                    style: TextButton.styleFrom(
                      backgroundColor: tab == item.$1
                          ? green
                          : Colors.transparent,
                      foregroundColor: tab == item.$1
                          ? Colors.white
                          : WebPortalColors.ink,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    onPressed: () => setState(() => tab = item.$1),
                    icon: Icon(item.$2.$1, size: 19),
                    label: Text(item.$2.$2),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _AnalystColumns(
          mainFlex: 7,
          sideFlex: 3,
          breakpoint: 950,
          main: switch (tab) {
            0 => OperatorEvidenceMap(record: record),
            1 => _WebCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _AnalystSectionTitle(
                    'Saved farm details',
                    icon: Icons.spa_outlined,
                  ),
                  const SizedBox(height: 12),
                  AnalysisIdentity(record: record, compact: true),
                  const Divider(height: 24),
                  Text(
                    'Recorded boundary vs current farm: ${geometry == true
                        ? 'same coordinates; farm metadata may have changed'
                        : geometry == false
                        ? 'CHANGED — this review uses the recorded boundary'
                        : 'current farm unavailable'}. Current farm version ${widget.data['current_farm_version'] ?? 'unavailable'}.',
                  ),
                  const SizedBox(height: 12),
                  AnalysisCoverageCard(record: record),
                  CagroSoilObservationsCard(record: record),
                ],
              ),
            ),
            2 => SeasonalContextCard(record: record),
            _ => const _WebCard(
              child: _WebEmptyState(
                title: 'No attachment records available',
                message:
                    'This case response does not include attachment records.',
                icon: Icons.attach_file,
              ),
            ),
          },
          side: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReviewLocationCard(record: record),
              const SizedBox(height: 12),
              _WebCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _AnalystSectionTitle(
                      'Seasonal Context',
                      icon: Icons.calendar_month_outlined,
                    ),
                    const SizedBox(height: 12),
                    for (final line in seasonalAssessmentLines(record).take(2))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          line,
                          style: TextStyle(
                            fontSize: 12,
                            color: WebPortalColors.muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _WebCard(
                child: LayoutBuilder(
                  builder: (_, box) => Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (box.maxWidth > 240) ...[
                        BoundaryThumbnail(record, size: 74),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AnalysisIdentity(record: record, compact: true),
                            const SizedBox(height: 6),
                            VerificationStatusBadge(
                              status:
                                  '${analysisMapValue(widget.data['case'])['status']}',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewLocationCard extends StatelessWidget {
  final Map<String, dynamic> record;
  const _ReviewLocationCard({required this.record});
  @override
  Widget build(BuildContext context) {
    final lines = analysisCoverageLines(record);
    final coverage = lines
        .where(
          (line) =>
              line.startsWith('CAGRO coverage:') ||
              line.startsWith('Analysis coverage:'),
        )
        .firstOrNull;
    final rows = [
      (
        'Farm center latitude',
        '${record['center_lat'] ?? record['lat'] ?? 'Not recorded'}',
      ),
      (
        'Farm center longitude',
        '${record['center_lon'] ?? record['lon'] ?? 'Not recorded'}',
      ),
      ('Approximate area', analysisAreaText(record)),
      ('Sample coordinates', 'Farm center is not a soil sample coordinate.'),
      if (coverage != null) ('Coverage', coverage),
    ];
    return _WebCard(
      key: const ValueKey('review-location-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AnalystSectionTitle(
            'Analyzed Farm Location',
            icon: Icons.location_on_outlined,
          ),
          const SizedBox(height: 12),
          for (final row in rows)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: WebPortalColors.muted.withValues(alpha: .12),
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      row.$1,
                      style: TextStyle(
                        fontSize: 11,
                        color: WebPortalColors.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(row.$2, style: const TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ReviewDecisionSummary extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback? exportCase, exportAnalysis;
  const _ReviewDecisionSummary({
    required this.data,
    this.exportCase,
    this.exportAnalysis,
  });
  @override
  Widget build(BuildContext context) {
    final review = analysisMapValue(data['case']);
    final record = analysisMapValue(data['analysis']);
    final status = '${review['status']}';
    final accepted = status == 'verified';
    final color = accepted
        ? green
        : status == 'rejected'
        ? Colors.red.shade700
        : Colors.orange.shade800;
    return _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AnalystSectionTitle(
            'Analyst Review',
            icon: Icons.verified_outlined,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  accepted ? Icons.check_circle : Icons.info_outline,
                  color: color,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    reviewLabel(status),
                    style: TextStyle(color: color, fontWeight: FontWeight.w800),
                  ),
                ),
                Icon(
                  Icons.spa_outlined,
                  color: color.withValues(alpha: .5),
                  size: 30,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            accepted
                ? 'An analyst approved this analysis. This decision applies to this analysis and its recorded boundary.'
                : status == 'pending'
                ? 'This submission is awaiting an analyst’s decision.'
                : status == 'needs_information'
                ? 'More information was requested. Read the recorded notes and timeline.'
                : 'Review the recorded feedback and timeline for this submission.',
          ),
          const SizedBox(height: 6),
          const Text(
            'Acceptance does not guarantee crop success or replace field and laboratory evidence.',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              if (record['verified_at'] != null)
                Text('Reviewed: ${analysisDateText(record['verified_at'])}'),
              if ('${record['planner_notes'] ?? ''}'.trim().isNotEmpty)
                Text('Analyst feedback: ${record['planner_notes']}'),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: exportAnalysis,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Export analysis report'),
              ),
              OutlinedButton.icon(
                onPressed: exportCase,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Export case report'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewEventTile extends StatelessWidget {
  final Map<String, dynamic> event;
  const _ReviewEventTile({required this.event});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WebPortalColors.tint.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: WebPortalColors.accent.withValues(alpha: .22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.history, size: 20, color: WebPortalColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reviewLabel(event['kind']),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${event['actor_name'] ?? 'Recorded system event'} · analysis #${event['session_id']}',
                  style: TextStyle(fontSize: 12, color: WebPortalColors.muted),
                ),
                Text(
                  analysisDateText(event['created_at']),
                  style: TextStyle(fontSize: 11, color: WebPortalColors.muted),
                ),
                if ('${event['notes'] ?? ''}'.isNotEmpty)
                  Text('${event['notes']}'),
                if (event['reason'] != null)
                  Text('Reason: ${reviewLabel(event['reason'])}'),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
