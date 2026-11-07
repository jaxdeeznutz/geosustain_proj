"""Seasonal reference decisions, complete-year evidence and score separation."""
from copy import deepcopy

import pytest

import seasonal_assessment as seasonal
from seasonal_planting import CROPS, SOURCES, assess_crop, eto_month, longest_dry_run


def climate_payload():
    values = {'T2M': 27, 'T2M_MIN_AVG': 22, 'T2M_MAX_AVG': 32, 'PRECTOTCORR': 10, 'RH2M': 80}
    return {
        'header': {'fill_value': -999},
        'parameters': {key: {'units': 'mm/day' if key == 'PRECTOTCORR' else '%' if key == 'RH2M' else 'C'} for key in values},
        'properties': {'parameter': {key: {f'{year}{month:02d}': value for year in seasonal.YEARS for month in range(1, 13)} for key, value in values.items()}},
    }


def cycle(status='humid', rainfall=300):
    return [{'month': m, 'rainfall_status': 'available', 'rainfall_mm': rainfall, 'moisture_status': status} for m in range(1, 13)]


def test_eto_radiation_water_equivalent_and_polar_and_invalid_inputs():
    # Equatorial March Ra is ~37-38 MJ/m2/day. Equation 52 with a 10 C
    # temperature range yields ~4.8 mm/day, not ~12 mm/day (MJ/mm mixup).
    assert 140 < eto_month(0, 2024, 3, 25, 20, 30) < 155
    assert eto_month(7.3, 2024, 2, 27, 22, 32) > eto_month(7.3, 2023, 2, 27, 22, 32)
    assert eto_month(90, 2024, 12, -20, -25, -15) is None
    for inputs in [(7, 27, None, 32), (7, 27, 32, 22), (7, 27, 22, 22), (7, True, 22, 32), (91, 27, 22, 32)]:
        assert eto_month(inputs[0], 2024, 2, *inputs[1:]) is None


def test_twelve_months_and_paired_years_and_incompatible_temperature_units():
    raw = climate_payload()
    baseline = seasonal.parse_baseline(raw, 7.3, 125.62, 2)
    assert len(baseline['monthly_cycle']) == 12
    feb = baseline['monthly_cycle'][1]
    assert feb['rainfall_mm'] == pytest.approx(282.5)
    assert feb['paired_valid_years'] == seasonal.YEARS
    assert feb['moisture_status'] == 'humid'
    raw['properties']['parameter']['T2M_MAX_AVG']['202402'] = -999
    incomplete = seasonal.parse_baseline(raw, 7.3, 125.62, 2)['monthly_cycle'][1]
    assert incomplete['rainfall_status'] == 'available'
    assert len(incomplete['paired_valid_years']) == 19
    assert incomplete['rainfall_eto_ratio'] is None
    assert incomplete['moisture_status'] == 'unavailable'
    raw['parameters']['T2M_MIN_AVG']['units'] = 'F'
    assert all(row['moisture_status'] == 'unavailable' for row in seasonal.parse_baseline(raw, 7.3, 125.62, 2)['monthly_cycle'])


def test_monthly_extremes_cannot_substitute_for_average_daily_extremes():
    raw = climate_payload()
    for average, extreme in [('T2M_MIN_AVG', 'T2M_MIN'), ('T2M_MAX_AVG', 'T2M_MAX')]:
        raw['parameters'][extreme] = raw['parameters'].pop(average)
        raw['properties']['parameter'][extreme] = raw['properties']['parameter'].pop(average)
    assert all(row['moisture_status'] == 'unavailable' for row in seasonal.parse_baseline(raw, 7.3, 125.62, 6)['monthly_cycle'])


def test_selected_month_changes_advice_for_all_seven_without_changing_model():
    raw = climate_payload()
    for year in seasonal.YEARS:
        raw['properties']['parameter']['PRECTOTCORR'][f'{year}01'] = .2
    original = {'top_crop_recommendations': [{'crop': 'Banana', 'compatibility_pct': 31.771234}],
                'crop_compatibility_pct': 31.771234, 'model_explanation': {'immutable': ['fixture']},
                'rainfall_annual_mean_5y_mm': 2600, 'temperature_mean_5y_c': 27}
    snapshots = []
    for month in (1, 6):
        record = deepcopy(original)
        seasonal.attach_seasonal_assessment(record, seasonal.parse_baseline(raw, 7.3, 125.62, month), month)
        assert {key: record[key] for key in original} == original
        planting = record['seasonal_assessment']['planting_assessment']
        assert [row['crop'] for row in planting['crops']] == list(CROPS)
        assert planting['model_ranking_effect'] == 'none' and planting['forecast'] is False
        assert 'not been field-validated' in planting['local_validation']
        snapshots.append(planting)
    assert all(row['status'] == 'water_support_needed' for row in snapshots[0]['crops'])
    assert all(row['status'] == 'favorable_moisture' for row in snapshots[1]['crops'] if row['crop'] != 'Rice')
    assert next(row for row in snapshots[1]['crops'] if row['crop'] == 'Rice')['status'] == 'conditional'


def test_december_window_crosses_year_and_incomplete_data_never_gives_favorable():
    months = cycle()
    months[0]['moisture_status'] = 'dry'
    assert assess_crop('Mango', months, 12)['window_months'] == [12, 1, 2, 3]
    assert assess_crop('Mango', months, 12)['status'] == 'water_support_needed'
    months[0]['moisture_status'] = 'unavailable'
    for crop in CROPS:
        assert assess_crop(crop, months, 12)['status'] == 'unavailable'
        assert all(key in SOURCES for key in assess_crop(crop, months, 12)['source_ids'])


def test_crop_specific_reference_boundaries_and_circular_dry_spell():
    assert longest_dry_run([50, 50] + [200] * 8 + [50, 50]) == 4
    assert longest_dry_run([50] * 12) == 12
    assert longest_dry_run([None] + [200] * 11) is None
    months = cycle(rainfall=100)
    assert assess_crop('Cacao', months, 1)['status'] == 'favorable_moisture'
    assert assess_crop('Durian', months, 1)['status'] == 'conditional'
    assert assess_crop('Coconut', months, 1)['status'] == 'conditional'
    months[0]['rainfall_mm'] = 150
    assert assess_crop('Coconut', months, 1)['status'] == 'favorable_moisture'
    months = cycle(rainfall=90)
    cacao = assess_crop('Cacao', months, 1)
    assert cacao['status'] == 'conditional'
    assert cacao['reference_checks'][0]['value'] == 12


def test_no_data_legacy_snapshots_and_disabled_crops_are_not_invented():
    record = {}
    seasonal.attach_seasonal_assessment(record, seasonal.empty_baseline(7.3, 125.62, 1), 1)
    planting = record['seasonal_assessment']['planting_assessment']
    assert planting['status'] == 'unavailable'
    assert all(row['status'] == 'unavailable' and row['moisture_supported_months'] == [] for row in planting['crops'])
    seasonal.attach_seasonal_assessment(record, seasonal.parse_baseline(climate_payload(), 7.3, 125.62, 1), 1, {'banana', 'rice'})
    assert [row['crop'] for row in record['seasonal_assessment']['planting_assessment']['crops']] == ['Banana', 'Rice']
    legacy = seasonal.parse_baseline(climate_payload(), 7.3, 125.62, 1)
    legacy['version'] = 'seasonal-context-v1'
    seasonal.attach_seasonal_assessment(record, legacy, 1)
    assert record['seasonal_assessment']['planting_assessment']['status'] == 'unavailable'


def test_seasonal_moisture_cannot_override_a_blocked_land_assessment():
    record = {'land_cover': {'allow_crops': False, 'status': 'built_up'}, 'is_crop_recommended': False}
    seasonal.attach_seasonal_assessment(record, seasonal.parse_baseline(climate_payload(), 7.3, 125.62, 6), 6)
    assert record['is_crop_recommended'] is False
    planting = record['seasonal_assessment']['planting_assessment']
    assert planting['status'] == 'unavailable'
    assert all(row['status'] == 'unavailable' and row['moisture_supported_months'] == [] for row in planting['crops'])
