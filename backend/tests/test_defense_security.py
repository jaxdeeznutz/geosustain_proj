import base64
import io
from unittest.mock import Mock

import pytest
from PIL import Image
from fastapi.testclient import TestClient
import fastapi_app as api
from defense_security import validate_profile_photo


def photo(width=4, height=4):
    stream = io.BytesIO()
    Image.new('RGB',(width,height),'green').save(stream,format='PNG')
    return 'data:image/png;base64,'+base64.b64encode(stream.getvalue()).decode()


def test_photo_decoded_limit_dimensions_type_and_clear():
    assert validate_profile_photo(photo()).startswith('data:image/png;')
    assert validate_profile_photo('') == ''
    assert validate_profile_photo(None) is None
    for image in [photo(4097,1),photo().replace('image/png','image/jpeg'),
                  'data:image/png;base64,'+'A'*2_800_001]:
        with pytest.raises(ValueError):
            validate_profile_photo(image)


def test_polygon_nonfinite_input_never_reaches_inference(client, monkeypatch):
    build=Mock()
    monkeypatch.setattr(api,'build_analysis_result',build)
    for value in ['NaN','Infinity','-Infinity','91']:
        response=client.post('/api/mobile/analysis',content='{"polygon":[{"lat":'+value+',"lng":125.6}]}',
                             headers={'Content-Type':'application/json'})
        assert response.status_code==422
    build.assert_not_called()


def test_liveness_and_readiness_have_distinct_database_failure_semantics(monkeypatch):
    monkeypatch.setattr(api,'init_db',lambda:None)
    connect=Mock(side_effect=RuntimeError('private database failure'))
    monkeypatch.setattr(api.defense_db.psycopg2,'connect',connect)
    with TestClient(api.app) as client:
        assert client.get('/health').status_code==200
        response=client.get('/ready')
        assert response.status_code==503
        assert response.json()['checks']['database']=='unavailable'
        assert 'private database' not in response.text
    assert connect.call_args.kwargs['connect_timeout']==3
    assert 'statement_timeout=2000' in connect.call_args.kwargs['options']
