part of '../../main.dart';

class _ReviewDecisionCard extends StatelessWidget {
  final Map<String, bool> checks;
  final bool disabled, ownSubmission;
  final void Function(String, bool) onCheck;
  final VoidCallback verify, requestInformation, reject;
  const _ReviewDecisionCard({
    required this.checks,
    required this.disabled,
    required this.ownSubmission,
    required this.onCheck,
    required this.verify,
    required this.requestInformation,
    required this.reject,
  });

  @override
  Widget build(BuildContext context) {
    final count = checks.values.where((value) => value).length;
    const labels = {
      'reference': 'Results, dates and sources checked',
      'geometry': 'Saved boundary and any changes checked',
      'coverage': 'Coverage and missing readings checked',
      'limitations': 'Limitations and next steps checked',
    };
    return _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AnalystSectionTitle(
            '2. Complete the review checks',
            icon: Icons.fact_check_outlined,
          ),
          const SizedBox(height: 8),
          const Text('Tick each item after checking the farm results above.'),
          const SizedBox(height: 8),
          for (final item in labels.entries)
            CheckboxListTile(
              key: ValueKey('review-check-${item.key}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: checks[item.key],
              onChanged: disabled
                  ? null
                  : (value) => onCheck(item.key, value == true),
              title: Text(item.value),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          Semantics(
            liveRegion: true,
            child: Text(
              '$count of 4 checked',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: count == 4
                    ? WebPortalColors.accent
                    : WebPortalColors.muted,
              ),
            ),
          ),
          const Divider(height: 28),
          const _AnalystSectionTitle(
            '3. Choose a decision',
            icon: Icons.task_alt,
          ),
          const SizedBox(height: 10),
          Text(
            ownSubmission
                ? 'Another analyst must review your submission.'
                : count < 4
                ? 'Complete all four checks to enable verification.'
                : 'Your checks are complete. You can now verify the assessment.',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: disabled || count < 4 ? null : verify,
                child: const Text('Verify assessment'),
              ),
              OutlinedButton(
                onPressed: disabled ? null : requestInformation,
                child: const Text('Request information'),
              ),
              OutlinedButton(
                onPressed: disabled ? null : reject,
                child: const Text('Reject submission'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Missing details? Request information. Unable to accept the submission? Reject it and explain why.',
            style: TextStyle(fontSize: 12, color: WebPortalColors.muted),
          ),
        ],
      ),
    );
  }
}

class _ReviewDecisionDialog extends StatefulWidget {
  final String status;
  final TextEditingController notes;
  final String? reason;
  final ValueChanged<String?> onReasonChanged;
  const _ReviewDecisionDialog({
    required this.status,
    required this.notes,
    required this.reason,
    required this.onReasonChanged,
  });
  @override
  State<_ReviewDecisionDialog> createState() => _ReviewDecisionDialogState();
}

class _ReviewDecisionDialogState extends State<_ReviewDecisionDialog> {
  final form = GlobalKey<FormState>();
  @override
  Widget build(BuildContext context) {
    final verifying = widget.status == 'verified';
    final asking = widget.status == 'needs_information';
    final accent = verifying
        ? green
        : asking
        ? green
        : Colors.red.shade700;
    return AlertDialog(
      backgroundColor: const Color(0xFFFBFFFB),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      title: Text(
        verifying
            ? 'Verify Assessment'
            : asking
            ? 'Request Information'
            : 'Reject Submission',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF003B2B),
          fontSize: 25,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 112,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE8F8EC), Color(0xFFBDECC8)],
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Positioned(
                        left: 20,
                        bottom: 8,
                        child: Icon(
                          Icons.spa_rounded,
                          color: Color(0xFF56BB75),
                          size: 56,
                        ),
                      ),
                      Icon(
                        verifying
                            ? Icons.fact_check_rounded
                            : asking
                            ? Icons.quiz_rounded
                            : Icons.cancel_presentation_rounded,
                        color: accent,
                        size: 70,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  verifying
                      ? 'Confirm that you reviewed the saved farm results. Verification does not guarantee crop success.'
                      : asking
                      ? 'Tell the farmer what to clarify or provide.'
                      : 'Tell the farmer why this submission cannot be accepted.',
                ),
                const SizedBox(height: 16),
                if (!verifying) ...[
                  DropdownButtonFormField<String>(
                    key: const ValueKey('review-decision-reason'),
                    initialValue: widget.reason,
                    isExpanded: true,
                    itemHeight: null,
                    decoration: const InputDecoration(
                      labelText: 'Reason',
                      hintText: 'Choose a reason',
                    ),
                    items: [
                      for (final item in const {
                        'boundary_clarification':
                            'Farm boundary needs clarification',
                        'missing_evidence': 'Missing information or evidence',
                        'coverage_limitation': 'Limited data coverage',
                        'data_inconsistency': 'Details do not match',
                        'other': 'Other',
                      }.entries)
                        DropdownMenuItem(
                          value: item.key,
                          child: Text(
                            item.value,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: widget.onReasonChanged,
                    validator: (value) => value == null || value.isEmpty
                        ? 'Choose a reason.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  key: const ValueKey('review-decision-note'),
                  controller: widget.notes,
                  maxLength: 500,
                  minLines: 3,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: verifying
                        ? 'Note to farmer (optional)'
                        : 'Message to farmer',
                    helperText: verifying
                        ? null
                        : 'Required. Explain what the farmer needs to know.',
                    helperMaxLines: 2,
                  ),
                  validator: (value) =>
                      !verifying && (value ?? '').trim().isEmpty
                      ? 'Add a message for the farmer.'
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: accent),
          onPressed: () {
            if (form.currentState!.validate()) Navigator.pop(context, true);
          },
          child: Text(verifying ? 'Verify Assessment' : 'Confirm decision'),
        ),
      ],
    );
  }
}

class _ReviewOptionalSection extends StatefulWidget {
  final String storageId, title;
  final IconData icon;
  final List<Widget> children;
  const _ReviewOptionalSection({
    required this.storageId,
    required this.title,
    required this.icon,
    required this.children,
  });
  @override
  State<_ReviewOptionalSection> createState() => _ReviewOptionalSectionState();
}

class _ReviewOptionalSectionState extends State<_ReviewOptionalSection> {
  // Text fields have numeric scroll offsets; keep them separate from the
  // ExpansionTile's saved open/closed boolean.
  final contentStorage = PageStorageBucket();
  @override
  Widget build(BuildContext context) => _WebCard(
    child: ExpansionTile(
      key: PageStorageKey<String>('review-option-${widget.storageId}'),
      tilePadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      leading: Icon(widget.icon, color: WebPortalColors.accent),
      title: Text(
        widget.title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      children: [
        PageStorage(
          bucket: contentStorage,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.children,
            ),
          ),
        ),
      ],
    ),
  );
}

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
                      'Check the farm results, then record your decision.',
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

class _ReviewDecisionSummary extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback? exportCase, exportAnalysis, saveReport;
  const _ReviewDecisionSummary({
    required this.data,
    this.exportCase,
    this.exportAnalysis,
    this.saveReport,
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
                onPressed: saveReport,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save to Reports'),
              ),
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
