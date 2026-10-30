"""Formal review eligibility; nutrient evidence and model scores are separate."""
import json

from geometry import normalize_polygon


def polygon_identity(value):
    if isinstance(value, str):
        value = json.loads(value)
    ring = normalize_polygon(value)
    vertices = tuple((p['lat'], p['lng']) for p in ring[:-1])
    # Equivalent starting vertex / walking direction do not change a boundary.
    forward = min(vertices[i:] + vertices[:i] for i in range(len(vertices)))
    reverse = vertices[::-1]
    backward = min(reverse[i:] + reverse[:i] for i in range(len(reverse)))
    return min(forward, backward)


def require_formal_polygon(session, farm, owner):
    if session.get('user_id') != owner:
        raise ValueError('Only the farmer who owns this analysis can submit it.')
    if not farm or farm.get('farmer_id') != owner or farm.get('is_archived'):
        raise ValueError('Open an owned, saved, active farm and analyze its boundary before submitting.')
    if not session.get('farm_id') or session['farm_id'] != farm.get('id'):
        raise ValueError('Only an analysis linked to this saved farm can be submitted.')
    snapshot = session.get('result_snapshot') or {}
    if isinstance(snapshot, str):
        snapshot = json.loads(snapshot)
    if not isinstance(snapshot, dict):
        raise ValueError('The saved analysis is incomplete. Run a new farm analysis.')
    if (snapshot.get('formal_submission_eligible') is False
            or snapshot.get('analysis_scope') in ('preliminary_point_inspection', 'unsaved_polygon_inspection')):
        raise ValueError('This is a preliminary inspection. Analyze a saved farm boundary for formal review.')
    version = session.get('boundary_version')
    if not version or version != farm.get('boundary_version'):
        raise ValueError('The farm boundary changed. Analyze the current saved boundary before submitting.')
    try:
        boundary = polygon_identity(session.get('selected_polygon'))
        if boundary != polygon_identity(farm.get('polygon')):
            raise ValueError('Boundary mismatch')
        if snapshot.get('selected_polygon') is not None and boundary != polygon_identity(snapshot['selected_polygon']):
            raise ValueError('Snapshot boundary mismatch')
    except (ValueError, TypeError, KeyError, AttributeError):
        raise ValueError('The saved analysis boundary is missing or differs from the farm. Run a new farm analysis.') from None
    if snapshot.get('boundary_version', version) != version:
        raise ValueError('The saved analysis boundary version is inconsistent. Run a new farm analysis.')


def attach_analysis_scope(result, farm=None):
    if farm:
        result.update(analysis_scope='formal_farm_polygon', formal_submission_eligible=True,
                      analysis_scope_notice='Saved farm boundary assessment. Analyst review does not verify field conditions or fill missing observations.')
    else:
        point = not result.get('selected_polygon')
        result.update(analysis_scope='preliminary_point_inspection' if point else 'unsaved_polygon_inspection',
                      formal_submission_eligible=False,
                      analysis_scope_notice='Preliminary inspection only. Open a saved farm and analyze its boundary before submitting for analyst review.')
    return result
