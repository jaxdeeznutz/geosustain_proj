"""Isolated Phase 3 lab: concave farm, real forest, synthetic clipped rasters."""
import argparse
from contextlib import contextmanager
from pathlib import Path
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import phase02_manual_host as base
from phase03_fixtures import RING, fixture_spatial


@contextmanager
def workspace():
    with patch.object(base.base.api, 'build_spatial_assessment', fixture_spatial), base.workspace() as (farmer, analyst, _):
        farm = base.base.db.create_farm_parcel(farmer['id'], 'Phase 3 Test Farm', RING,
                                               location_name='Synthetic concave test parcel, Panabo')
        yield farmer, analyst, farm


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--smoke', action='store_true')
    if parser.parse_args().smoke:
        from phase03_spatial_integration import run
        run()
        return
    import uvicorn
    with workspace():
        print('PHASE 3 LOCAL WORKFLOW TEST - SYNTHETIC RASTERS - NOT PRODUCTION', flush=True)
        print('Backend: http://127.0.0.1:18001 | Chrome: http://localhost:18002')
        print('Farmer:', base.base.FARMER, '| Analyst:', base.base.ANALYST, '| Disposable password:', base.base.PASSWORD)
        print('Open Phase 3 Test Farm. NDVI has explicit missing cells; soil pH/coarse climate are uniform; 30-day rainfall raster is unavailable.', flush=True)
        print('External backend HTTP, email and push remain disabled. Ctrl+C removes only temporary lab records.', flush=True)
        uvicorn.run(base.base.api.app, host='127.0.0.1', port=18001, log_level='warning')


if __name__ == '__main__':
    main()
