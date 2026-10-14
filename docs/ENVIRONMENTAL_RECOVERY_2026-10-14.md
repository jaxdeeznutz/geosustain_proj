# Model input recovery

The supplied deployment log shows all nine samples failing before prediction,
with ModelRankingUnavailable. The previous code suppressed the missing feature
names and replaced the cause with a generic polygon error. CHIRPS also lacked
precipitation for the requested window; that alone does not identify every missing
model input. Successful provider function returns were incorrectly easy to read
as successful data availability.

Changes:
- Use Open-Meteo current relative humidity when OpenWeather humidity is unavailable.
  Preserve provider provenance and label this weather-model data, not field data.
- Require all 30 completed dates for rainfall; exclude today's forecast and reject
  partial/null series. Reject incomplete CHIRPS windows before reading their sum.
- Log missing feature names and preserve the model-input error through polygon/API
  handling. No constant or rule-based crop fallback and no dropped parcel samples.
- Preserve CAGRO images as manually transcribed, unverified reference CSV files in
  data/cagro_pending. Do not infer units, convert Organic to N, or assign these rows
  to farm coordinates. They are not runtime inputs or training data.

Public backup calls at a Panabo coordinate succeeded locally. Full authenticated
production analysis still requires deployment and a user retry. API documentation:
https://open-meteo.com/en/docs
