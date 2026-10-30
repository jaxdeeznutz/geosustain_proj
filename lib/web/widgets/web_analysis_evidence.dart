part of '../../main.dart';

class WebAnalysisEvidence extends StatelessWidget {
  final AnalysisState state;
  final Map<String, dynamic> record;
  const WebAnalysisEvidence({
    super.key,
    required this.state,
    required this.record,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AnalysisCoverageCard(record: record),
      CagroSoilObservationsCard(record: record),
      ReferenceAnalysisContent(
        key: ValueKey(
          'web-evidence-${record['session_id']}-${record['analysis_mode']}',
        ),
        state: state,
        record: record,
      ),
    ],
  );
}

class WebModelScoreDistribution extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  const WebModelScoreDistribution({super.key, required this.records});
  @override
  Widget build(BuildContext context) {
    final metrics = WebAnalysisMetrics(records);
    final labels = ['75–100', '50–<75', '25–<50', '0–<25'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recorded model scores',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        Text('Score bands are not agronomic suitability grades.'),
        if (metrics.scores.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No assessed model scores available.'),
          ),
        if (metrics.scores.isNotEmpty)
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${labels[i]}: ${metrics.scoreBands[i]} (${(100 * metrics.scoreBands[i] / metrics.scores.length).toStringAsFixed(1)}%)',
              ),
            ),
        Text(
          '${metrics.records.length} records; ${metrics.scores.length} scored; ${metrics.records.length - metrics.scores.length} unassessed or without a model score.',
        ),
      ],
    );
  }
}
