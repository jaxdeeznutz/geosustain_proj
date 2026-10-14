"""Rank approved crops using recorded forest probabilities, without rule boosts."""
from copy import deepcopy
import math

from crop_requirements import REQUIREMENTS
from model_explainability import finalize_explanation

VERSION = 'random-forest-probability-2026-10-14-v1'
METHOD = ('Arithmetic mean of Random Forest predict_proba outputs across all parcel '
          'samples, multiplied by 100. Top five enabled catalog crops in descending '
          'score order. No renormalization after filtering, rule adjustment or '
          'seasonal bonus. These are uncalibrated model class scores, not harvest '
          'probabilities or measured land suitability.')


class ModelRankingUnavailable(RuntimeError):
    pass


def attach_model_ranking(result, snapshots, active_crops=None):
    if not snapshots or any(not isinstance(s, dict) for s in snapshots):
        raise ModelRankingUnavailable('The trained model could not evaluate all farm samples. Please retry when the required inputs are available.')
    versions = {s.get('model_version') for s in snapshots}
    samples = [sample for snapshot in snapshots for sample in snapshot.get('samples', [])]
    if len(versions) != 1 or None in versions or len(samples) != len(snapshots):
        raise ModelRankingUnavailable('Model provenance is incomplete. Please retry the analysis.')
    labels = set(samples[0].get('class_probabilities', {}))
    for sample in samples:
        probabilities = sample.get('class_probabilities', {})
        if set(probabilities) != labels or not probabilities:
            raise ModelRankingUnavailable('The model returned inconsistent crop classes.')
        values = list(probabilities.values())
        if (not all(isinstance(p, (int, float)) and math.isfinite(p) and 0 <= p <= 1 for p in values)
                or not math.isclose(sum(values), 1, abs_tol=1e-6)):
            raise ModelRankingUnavailable('The model returned invalid class probabilities.')
    means = {label: sum(s['class_probabilities'][label] for s in samples) / len(samples) for label in labels}
    comparisons = {c['crop']: c for c in result.get('crop_assessments', [])}
    crops = []
    for name in REQUIREMENTS:
        label = name.lower()
        # Exact trained classes only: never substitute another crop's probability.
        if label not in means or (active_crops is not None and label not in active_crops):
            continue
        crop = deepcopy(comparisons.get(name, {}))
        crop.update(crop=name, reference_score=crop.get('compatibility_pct'),
                    compatibility_pct=means[label] * 100,
                    model_probability_pct=means[label] * 100,
                    model_labels=[label], classification='Model score',
                    scoring_version=VERSION, method=METHOD)
        crop['explanation'] = (f"{name} has a {means[label] * 100:.2f}% mean model class score across "
                               f"{len(samples)} sample(s). Environmental comparisons are shown separately "
                               'and do not change the model ranking. This is not a harvest probability.')
        crops.append(crop)
    crops.sort(key=lambda crop: (-crop['compatibility_pct'], crop['crop']))
    if not crops:
        raise ModelRankingUnavailable('No enabled catalog crops are supported by the trained model.')
    for index, crop in enumerate(crops):
        crop['rank'] = index + 1
    top = crops[:5]
    best = top[0]
    snapshot = deepcopy(snapshots[0])
    snapshot.update(samples=deepcopy(samples), aggregation=METHOD, role='crop_ranking')
    result.update(
        scoring_version=VERSION, recommendation_basis='model_probability',
        model_explanation=snapshot, crop_assessments=crops,
        top_crop_recommendations=top, alternative_crops=top[1:], best_crop=best,
        predicted_crop=best['crop'], crop=best['crop'],
        crop_compatibility_pct=best['compatibility_pct'], suitability_level='Model score',
        is_crop_recommended=best['compatibility_pct'] > 0,
        recommendation_scoring=METHOD, analysis_summary=best['explanation'],
        model_score_note='Model class scores are not harvest probabilities. Training includes synthetic GIS features; phosphorus and potassium inputs are estimated proxies.',
        xai_explanation={'scope': 'model_probability', 'method': METHOD},
    )
    result.pop('legacy_model_explanation', None)
    result.pop('legacy_model_samples', None)
    return finalize_explanation(result)
