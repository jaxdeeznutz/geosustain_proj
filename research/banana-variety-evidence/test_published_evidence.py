"""Checks that published references do not silently become fabricated input rows."""
import hashlib
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def read(name):
    return json.loads((HERE/name).read_text(encoding='utf-8'))


def test_guide_periods_and_conversions_remain_distinct():
    data=read('published_requirements.json')
    assert data['requirements_by_variety']['cavendish']==[]
    saba=next(r for r in data['requirements_by_variety']['saba'] if r['factor']=='rainfall')
    lakatan=next(r for r in data['requirements_by_variety']['lakatan'] if r['factor']=='rainfall')
    assert math.isclose(saba['min'],60*25.4) and saba['unit']=='mm/year'
    assert lakatan['value']==100 and lakatan['unit']=='mm/month'
    assert lakatan['annual_conversion_performed'] is False
    assert data['numeric_slope_limits_established'] is False
    assert not data['used_as_training_rows'] and not data['automatic_model_score_adjustment']
    assert all(r['source_id'] in data['sources'] for refs in data['requirements_by_variety'].values() for r in refs)


def test_trial_aggregates_preserve_missing_inputs_ranges_and_sites():
    data=read('published_trial_observations_partial.json')
    assert len(data['records'])==data['record_count']==3
    assert len({r['site_context']['site_id'] for r in data['records']})==data['independent_sites']==2
    assert data['complete_model_training_rows']==0 and not data['used_for_fitting']
    for record in data['records']:
        assert 'IMTP' in record['site_context']['trial_purpose']
        assert record['site_context']['ndvi'] is None and record['site_context']['slope_pct'] is None
        assert record['sample_count'] is None and record['observed_at'] is None
        assert not record['individual_plant_records_available'] and not record['model_training_ready']
    bago=[r for r in data['records'] if r['site_context']['site_id']=='bpi-bago-oshiro']
    assert {r['observed_variety'] for r in bago}=={'lakatan','saba'}
    assert all(r['site_context']['humidity_pct'] is None and r['site_context']['humidity_range_pct']==[83,86] for r in bago)
    assert all(r['site_context']['rainfall_mm_year'] is None for r in bago)
    assert {r['site_context']['printed_page'] for r in data['records']}=={109,134}


def test_asset_profiles_and_hash_manifest_preserve_reference_scope():
    asset=json.loads((ROOT/'assets/data/banana_varieties.json').read_text(encoding='utf-8'))
    assert asset['prediction_scope']=='crop_group_only'
    assert {p['variety_key'] for p in asset['profiles']}=={'cavendish','lakatan','saba'}
    for p in asset['profiles']:
        assert p['guidance_lines'] and p['sources']
        assert 'model_probability_pct' not in p and 'compatibility_pct' not in p
    manifest=read('evidence_manifest.json')
    for name,digest in manifest['files_sha256'].items():
        assert hashlib.sha256((HERE/name).read_bytes()).hexdigest()==digest
