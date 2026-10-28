from copy import deepcopy

import pytest

from analysis_coverage import check_coverage, require_analysis_coverage
from city_boundary import contains_point, contains_polygon, reference
from geometry import normalize_polygon


def square(lat,lon,d=.0001):
    return [{'lat':lat-d,'lng':lon-d},{'lat':lat-d,'lng':lon+d},
            {'lat':lat+d,'lng':lon+d},{'lat':lat+d,'lng':lon-d}]


def test_city_boundary_covers_north_beyond_old_rectangle():
    candidates=[(lat,lon) for lat in (7.42,7.43,7.44) for lon in (125.60,125.62,125.64)]
    point=next(p for p in candidates if contains_polygon(square(*p)))
    assert point[0]>7.41
    ring=normalize_polygon(square(*point))
    coverage,soil=require_analysis_coverage(ring)
    assert coverage['preliminary_supported'] and coverage['can_analyze']
    assert not coverage['supported'] and not soil.get('observations')
    assert coverage['analysis_mode']=='legacy_model_estimates'
    assert coverage['nutrient_source'] is None


def test_outside_city_and_administrative_edge_are_not_admitted():
    assert not contains_point(7.29,125.53)
    x,y=reference()['geometry']['coordinates'][0][0]
    assert not contains_point(y,x)
    with pytest.raises(ValueError):normalize_polygon(square(7.29,125.53))


def test_preliminary_admission_does_not_fabricate_cagro_matches():
    coverage,soil=check_coverage(square(7.29,125.62))
    assert coverage['can_analyze'] and not coverage['supported']
    assert coverage['matches']==[] and soil.get('observations',[])==[]


def test_preliminary_inference_uses_reference_measurements_without_forest_or_npk(monkeypatch):
    import environmental_pipeline as pipeline
    import rainfallDatasets as env
    def measurement(value,unit,period):
        return {'value':value,'unit':unit,'period':period,'quality':'modelled','source':'Explicit unit-test observation'}
    data={'soil_ph':(5.7,'measured','Test'),'elevation':(30,'measured','Test'),
          'ndvi':(.7,'measured','Test'),'rainfall_recent':(100,'measured','Test'),
          'slope':3,'weather':(80,28,1,1,'measured'),
          'climate':{'temperature':measurement(27,'C','annual_mean'),
                     'rainfall':measurement(2600,'mm/year','annual_mean_total')}}
    seen=[]
    def retrieve(key,*args):
        seen.append(key)
        return deepcopy(data[key])
    monkeypatch.setattr(pipeline,'retrieve',retrieve)
    monkeypatch.setattr(env,'MODEL',None)
    result=pipeline.analyze_location(7.29,125.62,['rice'],preliminary=True)
    assert result['analysis_mode']=='preliminary_environmental'
    assert result['recommendation_basis']=='environmental_reference_screening'
    assert result['model_explanation'] is None
    assert 'nitrogen' not in seen
    assert not any(k in result for k in ('nitrogen','phosphorus','potassium'))
    rice=next(c for c in result['crop_assessments'] if c['crop']=='Rice')
    factors={f['factor']:f for f in rice['factors']}
    assert factors['temperature']['score']==100
    assert factors['rainfall']['score']==50
    assert factors['humidity']['score'] is None
    merged=pipeline.merge_results([result,deepcopy(result)],['rice'])
    assert merged['analysis_mode']=='preliminary_environmental'
    assert merged['model_explanation'] is None
