"""Conservative limiting-factor screening; this is NOT an ML prediction."""
import math
from copy import deepcopy
from crop_requirements import REQUIREMENTS, FACTORS, VERSION

CLASS_SCORE = {'S1': 100.0, 'S2': 67.0, 'S3': 33.0, 'N': 0.0}
METHOD = ('Minimum assessed factor score; no additive weights. Published factor classes '
          'map to project display indices S1=100, S2=67, S3=33, N=0. For range-only '
          'sources: inside preferred=100, inside absolute only=50, outside documented '
          'range=0 (a screening mismatch, not a published N class). At least three '
          'factors including soil pH and a climate factor are required. Rank by number '
          'of assessed factors first, then index; ties share rank. Unmeasured drainage, '
          'irrigation, hazards, soil depth and seasonal timing can change the outcome.')

def number(value):
    if isinstance(value, bool): return None
    try:
        value = float(value)
        return value if math.isfinite(value) else None
    except (ValueError, TypeError): return None

def within(value, interval):
    lo, hi = interval
    return (lo is None or value >= lo) and (hi is None or value <= hi)

def factor_result(value, rule, factor):
    classes = rule.get('classes')
    if classes:
        for label in reversed(list(classes)):
            for interval in classes[label]:
                if within(value, interval):
                    # N extremes in the source are strictly outside finite limits.
                    if None in interval and value in interval: continue
                    return CLASS_SCORE[label], label
        return None, 'Unassessed: no published class for this value'
    if within(value, rule['optimal']): return 100.0, 'Within documented range'
    if rule.get('absolute') and within(value, rule['absolute']):
        return 50.0, 'Within absolute range only'
    return 0.0, 'Outside documented range'

def assess(measurements, active_crops=None, requirements=None):
    assessments = []
    for crop, rules in (REQUIREMENTS if requirements is None else requirements).items():
        factors = []
        for key, (label, unit, period) in FACTORS.items():
            rule = rules.get(key)
            observation = deepcopy(measurements.get(key) or {})
            value = number(observation.get('value'))
            reason = None
            if not rule: reason = 'No verified criterion configured'
            elif value is None: reason = 'Measurement unavailable'
            elif observation.get('quality') not in ('measured', 'modelled'): reason = 'Fallback or unsupported measurement quality'
            elif observation.get('unit') != unit or observation.get('period') != period: reason = 'Incompatible unit or time period'
            score, result = (None, reason) if reason else factor_result(value, rule, key)
            factors.append({'factor': key, 'label': label, 'unit': unit, 'period': period,
                'measurement': observation, 'value': value, 'requirement': deepcopy(rule),
                'score': score, 'result': result, 'weight': None,
                'contribution': 'limiting-factor minimum' if score is not None else None})
        assessed = [f for f in factors if f['score'] is not None]
        keys = {f['factor'] for f in assessed}
        sufficient = len(assessed) >= 3 and 'soil_ph' in keys and bool(keys & {'temperature','rainfall'})
        enabled = active_crops is None or crop.lower() in active_crops
        score = min(f['score'] for f in assessed) if sufficient and enabled else None
        limiting = [f['label'] for f in assessed if f['score'] < 100]
        supporting = [f['label'] for f in assessed if f['score'] == 100]
        absent = [f['label'] for f in factors if f['score'] is None]
        status = 'Insufficient data' if score is None else ('Within assessed ranges' if score == 100 else 'Limitations identified')
        if not enabled: status = 'Disabled in crop settings'
        explanation = (f'{len(assessed)}/6 environmental factors assessed. '
                       + (f'Supporting conditions: {", ".join(supporting)}. ' if supporting else '')
                       + (f'Limitations: {", ".join(limiting)}. ' if limiting else '')
                       + (f'Not assessed: {", ".join(absent)}. ' if absent else '')
                       + 'This is preliminary reference-based screening, not a yield forecast or model prediction.')
        assessments.append({'crop': crop, 'compatibility_pct': score, 'classification': status,
            'rank': None, 'factors': factors, 'assessed_count': len(assessed), 'total_factors': 6,
            'limiting_factors': limiting, 'supporting_factors': supporting, 'not_assessed': absent,
            'explanation': explanation, 'scoring_version': VERSION, 'method': METHOD})
    assessments.sort(key=lambda c: (c['compatibility_pct'] is None, -c['assessed_count'], -(c['compatibility_pct'] or 0)))
    previous, rank = None, 0
    for i, crop in enumerate(assessments):
        if crop['compatibility_pct'] is None: continue
        group = (crop['assessed_count'], crop['compatibility_pct'])
        if group != previous: rank = i + 1
        crop['rank'], previous = rank, group
    return assessments

def attach_assessment(result, measurements, active_crops=None):
    crops = assess(measurements, active_crops)
    ranked = [c for c in crops if c['rank'] is not None]
    best = ranked[0] if ranked else None
    result.update(scoring_version=VERSION, crop_config_version=VERSION,
        environmental_measurements=measurements, crop_assessments=crops,
        top_crop_recommendations=ranked, alternative_crops=ranked[1:], best_crop=best,
        predicted_crop=best['crop'] if best else 'Insufficient data',
        crop=best['crop'] if best else None,
        crop_compatibility_pct=best['compatibility_pct'] if best else None,
        suitability_level=best['classification'] if best else 'Insufficient data',
        is_crop_recommended=bool(best and best['compatibility_pct'] > 0),
        recommendation_scoring=METHOD, analysis_summary=best['explanation'] if best else
        'Insufficient measured evidence to rank crops. All seven crops remain available with their missing factors.',
        xai_explanation={'scope': 'suitability_calculation', 'method': METHOD},
        recommendation='Verify drainage, water supply, soil depth and seasonal conditions before planting.')
    return result


def mark_preliminary(result):
    """Keep factor evidence without exporting a complete recommendation/rank."""
    for crop in result.get('crop_assessments', []):
        crop.update(reference_condition_index=crop.get('compatibility_pct'),
            compatibility_pct=None, rank=None, assessment_mode='preliminary_environmental')
        if crop.get('classification') != 'Disabled in crop settings':
            crop['classification'] = 'Preliminary environmental comparison'
    result.update(analysis_mode='preliminary_environmental',
        recommendation_basis='environmental_reference_screening',
        top_crop_recommendations=[], alternative_crops=[], best_crop=None,
        predicted_crop=None, crop=None, crop_compatibility_pct=None,
        is_crop_recommended=False, suitability_level='Not fully assessed',
        recommendation_title='Preliminary environmental screening',
        analysis_summary='Preliminary environmental comparisons only. CAGRO NPK is unavailable; inspect individual factors and obtain a reviewed soil assessment before a complete crop recommendation.',
        preliminary_notice='Preliminary environmental comparison. CAGRO NPK unavailable; not a complete soil suitability assessment.')
    return result
