"""Phase 5 local UI lab: actual unchanged forest, synthetic varied samples."""
import argparse
from contextlib import contextmanager
from pathlib import Path
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import phase03_manual_host as previous

base = previous.base.base
api, db, TestClient = base.api, base.db, base.TestClient


@contextmanager
def workspace():
    with previous.workspace() as (farmer, analyst, _):
        farm = db.create_farm_parcel(farmer['id'], 'Phase 5 Explainable AI Test Farm', previous.RING,
            location_name='Synthetic varied-sample workflow parcel, Panabo')
        # Variation is a controlled test input, not a soil measurement.
        def nitrogen(lat, lon):
            return (65 + (lat - 7.29) * 16000 + (lon - 125.62) * 8000,
                    'estimated_proxy', base.NOTICE)
        def ndvi(lat, lon):
            return (.4 + (lat - 7.29) * 130, 'measured', base.NOTICE)
        with patch.object(base.environment, 'get_soil_nitrogen', nitrogen), \
             patch.object(base.environment, 'get_ndvi', ndvi):
            yield farmer, analyst, farm


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--smoke', action='store_true')
    if parser.parse_args().smoke:
        from phase05_explanation_integration import run
        run()
        return
    import uvicorn
    with workspace():
        print('PHASE 5 LOCAL WORKFLOW TEST - SYNTHETIC INPUTS - NOT PRODUCTION', flush=True)
        print('Backend: http://127.0.0.1:18001 | Chrome: http://localhost:18002')
        print('Farmer:', base.FARMER, '| Analyst:', base.ANALYST, '| Disposable password:', base.PASSWORD)
        print('Analyze Phase 5 Explainable AI Test Farm. Check Explainable AI on Overview and crop details, history, submitted analyst case and both exports.', flush=True)
        print('External backend HTTP, email and push remain disabled. Ctrl+C removes only temporary lab records.', flush=True)
        uvicorn.run(api.app, host='127.0.0.1', port=18001, log_level='warning')


if __name__ == '__main__':
    main()
