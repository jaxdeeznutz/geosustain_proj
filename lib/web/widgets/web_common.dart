part of '../../main.dart';

class _WebCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _WebCard({
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: WebPortalColors.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Color(0xFFE4ECE6)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .035),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );
}

class _SmallBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _SmallBadge(this.text, {this.color = green});
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12),
    ),
  );
}

class _WebHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final AnalysisState state;
  final ValueChanged<String> message;
  const _WebHeader({
    required this.title,
    required this.subtitle,
    required this.state,
    required this.message,
  });
  @override
  Widget build(BuildContext context) => WebAdaptiveRow(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(header: true, child: Text(
              title,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: WebPortalColors.ink,
              ),
            )),
            SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: WebPortalColors.muted, fontSize: 15),
            ),
          ],
        ),
      ),
      OutlinedButton.icon(
        onPressed: state.weatherLoading
            ? null
            : () async {
                final err = await state.refreshLiveWeather();
                if (err != null) message(err);
              },
        icon: Icon(Icons.refresh_rounded),
        label: Text(
          state.weatherLoading ? 'Refreshing weather...' : 'Refresh Weather',
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: WebPortalColors.accent,
          side: BorderSide(color: Color(0xFFE1E8E2)),
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      SizedBox(width: 14),
      IconButton(
        tooltip: 'Open activity',
        onPressed: () => PortalRoutes.go('/operator/activity'),
        icon: Icon(Icons.notifications_none_rounded),
      ),
    ],
  );
}

class _WebKpiCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  const _WebKpiCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) => _WebCard(
    child: Row(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: WebPortalColors.tint,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, color: WebPortalColors.accent, size: 32),
        ),
        SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: WebPortalColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 6),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: WebPortalColors.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _WebMapVisual extends StatefulWidget {
  final AnalysisState state;
  final bool showPopup;
  final VoidCallback onClosePopup;
  final Future<void> Function() onAnalyze;
  const _WebMapVisual({
    required this.state,
    required this.showPopup,
    required this.onClosePopup,
    required this.onAnalyze,
  });

  @override
  State<_WebMapVisual> createState() => _WebMapVisualState();
}

class _WebMapVisualState extends State<_WebMapVisual> {
  AnalysisState get state => widget.state;

  Future<void> _analyze() async {
    await widget.onAnalyze();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final data = state.result;
    final crop =
        '${data?['crop_recommendation'] ?? data?['recommended_crop'] ?? '--'}';
    final pct = data?['crop_compatibility_pct'] ?? data?['compatibility_pct'];

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: double.infinity,
        height: 440,
        child: Stack(
          children: [
            Positioned.fill(
              child: LiveFieldMap(
                analysisState: state,
                onError: (msg) => ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(msg))),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: .04),
                        Colors.transparent,
                        Colors.black.withValues(alpha: .22),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 18,
              left: 18,
              child: _SmallBadge(
                state.satellite ? 'Satellite' : 'Street',
                color: WebPortalColors.accent,
              ),
            ),
            if (state.result?['heatmap_grid'] is List &&
                (state.result?['heatmap_grid'] as List).isNotEmpty)
              Positioned(
                top: 70,
                right: 18,
                child: Container(
                  padding: EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: WebPortalColors.surface.withValues(alpha: .96),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .10),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Wrap(
                    spacing: 5,
                    children:
                        [
                              'NDVI',
                              'Suitability',
                              'Soil pH',
                              'Rainfall',
                              'Elevation',
                              'Slope',
                            ]
                            .map(
                              (layer) => ChoiceChip(
                                label: Text(layer),
                                selected: state.heatmapLayer == layer,
                                selectedColor: softGreen,
                                labelStyle: TextStyle(
                                  color: state.heatmapLayer == layer
                                      ? green
                                      : WebPortalColors.muted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                                onSelected: (_) => state.setHeatmapLayer(layer),
                              ),
                            )
                            .toList(),
                  ),
                ),
              ),
            Positioned(
              top: 18,
              right: 18,
              child: Row(
                children: [
                  _MapToolButton(
                    icon: Icons.layers_rounded,
                    onTap: state.toggleSatellite,
                  ),
                  SizedBox(width: 8),
                  _MapToolButton(
                    icon: state.drawing
                        ? Icons.edit_off_rounded
                        : Icons.polyline_rounded,
                    onTap: state.toggleDrawing,
                  ),
                  SizedBox(width: 8),
                  _MapToolButton(
                    icon: Icons.clear_rounded,
                    onTap: state.clearSelection,
                  ),
                ],
              ),
            ),
            Positioned(
              right: 18,
              bottom: 18,
              child: FilledButton.icon(
                onPressed: state.loading ? null : _analyze,
                icon: Icon(Icons.analytics_rounded),
                label: Text(
                  state.polygonPoints.length >= 3
                      ? 'Analyze Polygon'
                      : 'Analyze Point',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: Size(0, 44),
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            if (state.heatmapLayer == 'Suitability' &&
                analysisListValue(state.result?['heatmap_grid']).isNotEmpty)
              Positioned(left: 18, bottom: 72, child: _SuitabilityLegend()),
            if (widget.showPopup)
              Positioned(
                left: 18,
                right: 18,
                top: 82,
                child: _WebMapPopup(
                  state: state,
                  crop: crop,
                  pct: pct,
                  onClose: widget.onClosePopup,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WebMapPopup extends StatelessWidget {
  final AnalysisState state;
  final String crop;
  final dynamic pct;
  final VoidCallback onClose;

  const _WebMapPopup({
    required this.state,
    required this.crop,
    required this.pct,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final hasResult = state.result != null;
    final displayCrop = WebAnalysisMetrics.preliminary(state.result ?? {})
        ? 'Preliminary screening'
        : hasResult && crop.trim().isNotEmpty && crop != '--'
        ? crop
        : 'Select or draw an area';
    final pctText = pct == null
        ? (state.result == null
              ? 'Ready for analysis'
              : 'No complete model score')
        : '${double.tryParse('$pct')?.toStringAsFixed(1) ?? pct}% model score';

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 300,
        padding: EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: WebPortalColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Color(0xFFE2ECE6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .10),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: WebPortalColors.accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.eco_rounded, color: WebPortalColors.accent),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    displayCrop,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: WebPortalColors.ink,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: Icon(Icons.close_rounded),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              pctText,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: hasResult ? green : WebPortalColors.muted,
              ),
            ),
            SizedBox(height: 10),
            Text(
              state.polygonPoints.length >= 3
                  ? 'Polygon area: ${state.polygonPoints.length} points selected'
                  : 'Point: ${state.selectedPoint.latitude.toStringAsFixed(5)}, ${state.selectedPoint.longitude.toStringAsFixed(5)}',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: WebPortalColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              state.selectedPlaceName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: WebPortalColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapToolButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MapToolButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    tooltip: icon == Icons.layers_rounded
        ? 'Change map layer'
        : icon == Icons.clear_rounded
        ? 'Clear map selection'
        : 'Toggle boundary drawing',
    onPressed: onTap,
    icon: Icon(icon),
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
  );
}

class _SuitabilityLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 180,
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: WebPortalColors.surface.withValues(alpha: .92),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Map score bands', style: TextStyle(fontWeight: FontWeight.w900)),
        SizedBox(height: 8),
        _LegendDot(color: Color(0xFF1FA463), label: '75% - 100%'),
        _LegendDot(color: Color(0xFF8BDD75), label: '50% - 75%'),
        _LegendDot(color: Color(0xFFE9A829), label: '25% - 50%'),
        _LegendDot(color: Color(0xFFE45B5B), label: '0% - 25%'),
      ],
    ),
  );
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
