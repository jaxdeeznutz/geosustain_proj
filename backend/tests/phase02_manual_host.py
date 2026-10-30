"""Phase 2 local UI lab: synthetic monthly context, never real provider data."""
import argparse
from contextlib import contextmanager
from pathlib import Path
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import phase01_manual_host as base
from seasonal_assessment import empty_baseline, parse_baseline, YEARS


def monthly_fixture(lat, lon, month):
    if month == 5:
        result = empty_baseline(lat, lon, month)
    else:
        payload = {
            'parameters': {'T2M': {'units': 'C'}, 'PRECTOTCORR': {'units': 'mm/day'}, 'RH2M': {'units': '%'}},
            'properties': {'parameter': {
                key: {f'{year}{month:02d}': value for year in YEARS}
                for key, value in [('T2M', 24 + month / 2), ('PRECTOTCORR', 1 + month / 2), ('RH2M', 75 + month)]
            }},
        }
        if month == 11:
            del payload['properties']['parameter']['T2M']['200511']
        result = parse_baseline(payload, lat, lon, month)
    result['source_name'] = 'Synthetic monthly workflow fixture - NOT NASA observations'
    result['fixture'] = True
    result['limitations'].insert(0, 'SYNTHETIC WORKFLOW TEST: monthly values and baseline-year coverage are fixtures, not real climate evidence.')
    return result


@contextmanager
def workspace():
    with base.workspace() as values, patch.object(base.api, 'fetch_multi_year_monthly_baseline', monthly_fixture):
        yield values


def smoke():
    with workspace() as (farmer, analyst, farm), base.TestClient(base.api.app) as client:
        headers = {'Authorization': 'Bearer '+base.api.generate_mobile_token(farmer)}
        records = []
        for month, status in [(2, 'available'), (8, 'available'), (5, 'unavailable'), (11, 'partial')]:
            response = client.post('/api/mobile/analysis', headers={**headers, 'Idempotency-Key': f'phase02-lab-{month}'},
                                   json={'farm_id': farm['id'], 'boundary_version': 1, 'intended_planting_month': month})
            assert response.status_code == 200, response.text
            result = response.json()
            assert result['seasonal_assessment']['status'] == status
            assert result['seasonal_assessment']['monthly_climate']['fixture'] is True
            records.append(result)
        assert records[0]['top_crop_recommendations'] == records[1]['top_crop_recommendations']
        print('PASS: Phase 2 lab real-model fixture inference, month changes, available/partial/unavailable climate and unchanged ranks; temporary schema removed on exit.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--smoke', action='store_true')
    if parser.parse_args().smoke:
        smoke()
        return
    import uvicorn
    with workspace():
        print('PHASE 2 LOCAL WORKFLOW TEST - SYNTHETIC MONTHLY DATA - NOT PRODUCTION', flush=True)
        print('Backend: http://127.0.0.1:18001 | Chrome: http://localhost:18002')
        print('Farmer:', base.FARMER, '| Analyst:', base.ANALYST, '| Disposable password:', base.PASSWORD)
        print('Use the seeded Phase 1 Test Farm. February/August: distinct fixtures; May: unavailable; November: partial.', flush=True)
        print('Keep this terminal open. Ctrl+C removes only its temporary records. External backend HTTP, email and push are disabled.', flush=True)
        uvicorn.run(base.api.app, host='127.0.0.1', port=18001, log_level='warning')


if __name__ == '__main__':
    main()
