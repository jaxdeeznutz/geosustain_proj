"""Offline SDK graph/REST/NPY contract checks; no Earth Engine evaluation."""
from datetime import date
import io
import json
from types import SimpleNamespace
from unittest.mock import patch

import ee
from ee.apitestcase import ApiTestCase
import numpy as np
import pytest

import spatial_provider as provider
from spatial_analysis import LAYERS


class Response:
    def __init__(self, body):
        self.body = body
        self.closed = False
    def raise_for_status(self):
        pass
    def iter_content(self, size):
        for offset in range(0, len(self.body), size):
            yield self.body[offset:offset+size]
    def close(self):
        self.closed = True


def test_oversized_response_is_rejected_and_closed():
    response = Response(b'12345')
    with pytest.raises(ValueError, match='byte limit'):
        provider.limited_body(response, 4)
    assert response.closed


class TestEarthEngineWireContract(ApiTestCase):
    def setUp(self):
        self.original_install = ee.data._install_cloud_api_resource
        super().setUp()

    def tearDown(self):
        super().tearDown()
        ee.data._install_cloud_api_resource = self.original_install

    def test_all_layer_graphs_serialize_with_real_sdk_algorithms(self):
        polygon = [{'lat': 7.29, 'lng': 125.62}, {'lat': 7.291, 'lng': 125.62},
                   {'lat': 7.291, 'lng': 125.621}, {'lat': 7.29, 'lng': 125.62}]
        for layer_id in LAYERS:
            image, native, period = provider.image_for_layer(ee, layer_id, polygon, date(2026, 10, 29))
            expression = ee.serializer.encode(image)
            assert expression['result'] and expression['values']
            metadata = ee.serializer.encode(ee.Dictionary({'crs': native.crs(), 'transform': native.transform(), 'period': ee.Dictionary(period)}))
            assert metadata['result']

    def test_bounded_rest_pixel_grid_and_mask_roundtrip(self):
        import rainfallDatasets as env
        polygon = [{'lat': 7.29, 'lng': 125.62}, {'lat': 7.291, 'lng': 125.62},
                   {'lat': 7.291, 'lng': 125.621}, {'lat': 7.29, 'lng': 125.62}]
        calls = []

        class Session:
            def __init__(self, *args, **kwargs):
                pass
            def __enter__(self):
                return self
            def __exit__(self, *args):
                pass
            def post(self, url, **kwargs):
                assert kwargs['timeout'] == (3, 8) and kwargs['stream']
                body = kwargs['json']
                calls.append(url)
                if url.endswith('/value:compute'):
                    return Response(json.dumps({'result': {
                        'native_projection': {'crs': 'EPSG:3857', 'transform': [30, 0, 0, 0, -30, 0], 'nominal_scale_m': 30},
                        'source_period': {'period': 'wire fixture', 'start': '2020-01-01', 'end_exclusive': '2025-01-01'},
                    }}).encode())
                assert url.endswith('/image:computePixels')
                assert body['fileFormat'] == 'NPY' and body['grid']['crsCode'] == 'EPSG:3857'
                assert body['grid']['affineTransform']['scaleY'] < 0
                assert body['grid']['dimensions']['width']*body['grid']['dimensions']['height'] <= 1024
                array = np.zeros((body['grid']['dimensions']['height'], body['grid']['dimensions']['width']),
                                 dtype=[('value', 'f4'), ('valid', 'f4')])
                array['value'] = .5; array['valid'] = 1; array['valid'][0, 0] = 0
                stream = io.BytesIO(); np.save(stream, array, allow_pickle=False)
                return Response(stream.getvalue())

        with (patch.object(env, '_EE_INITIALIZED', True),
              patch.object(env, 'GEE_SERVICE_ACCOUNT_JSON', None),
              patch.object(env, 'GEE_PROJECT', 'spatial-test-project'),
              patch.object(ee.data, 'get_persistent_credentials', lambda: SimpleNamespace(valid=True)),
              patch('google.auth.transport.requests.AuthorizedSession', Session)):
            rasters = provider.fetch_rasters(polygon)
        assert set(rasters) == set(LAYERS)
        assert len(calls) == len(LAYERS)*2
        for raster in rasters.values():
            assert raster['values'][0][0] is None
            assert raster['native_projection']['nominal_scale_m'] == 30
            assert raster['resampling'].startswith('Nearest')
