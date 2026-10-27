/// Relative position within recorded measurements, never an agronomic grade.
double? observedPosition(double? value, Iterable<double> observations) {
  if (value == null || !value.isFinite) return null;
  final finite = observations.where((v) => v.isFinite).toList();
  if (finite.isEmpty) return null;
  final low = finite.reduce((a, b) => a < b ? a : b),
      high = finite.reduce((a, b) => a > b ? a : b);
  return high == low ? .5 : ((value - low) / (high - low)).clamp(0, 1);
}
