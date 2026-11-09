"""Synthetic XLSX software fixtures; not published crop requirements."""
import base64
from datetime import date
import io
from pathlib import Path
from uuid import uuid4
import zipfile
from xml.etree import ElementTree as xml

import pytest
import controlled_excel as excel

ROOT = Path(__file__).resolve().parents[2]
NS = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'


def workbook(rows, headers=None):
    """Patch cell data in the authored template for isolated parser tests."""
    original = ROOT / 'backend/assets/crop_requirements_template.xlsx'
    with zipfile.ZipFile(original) as archive:
        entries = {name: archive.read(name) for name in archive.namelist()}
    tree = xml.fromstring(entries['xl/worksheets/sheet1.xml'])
    data = tree.find(f'{{{NS}}}sheetData')
    for row in list(data):
        if int(row.get('r')) > 1 or headers is not None:
            data.remove(row)
    content = ([headers] if headers is not None else []) + rows
    start = 1 if headers is not None else 2
    for index, values in enumerate(content, start):
        row = xml.SubElement(data, f'{{{NS}}}row', {'r': str(index)})
        for column, value in enumerate(values, 1):
            if value is None:
                continue
            cell = xml.SubElement(row, f'{{{NS}}}c', {'r': f'{chr(64+column)}{index}'})
            if type(value) is bool:
                cell.set('t','b'); xml.SubElement(cell,f'{{{NS}}}v').text = '1' if value else '0'
            elif type(value) in (int,float):
                xml.SubElement(cell,f'{{{NS}}}v').text = str(value)
            elif str(value).startswith('='):
                xml.SubElement(cell,f'{{{NS}}}f').text = value[1:]
            else:
                cell.set('t','inlineStr')
                xml.SubElement(xml.SubElement(cell,f'{{{NS}}}is'),f'{{{NS}}}t').text = str(value)
    entries['xl/worksheets/sheet1.xml'] = xml.tostring(tree,encoding='utf-8',xml_declaration=True)
    output = io.BytesIO()
    with zipfile.ZipFile(output,'w',compression=zipfile.ZIP_DEFLATED) as archive:
        for name, value in entries.items(): archive.writestr(name,value)
    return output.getvalue()


def row(**changes):
    value = dict(crop='Rice',factor='rainfall',unit='mm/year',period='annual_mean_total',
                 preferred_min=2000,preferred_max=2500,absolute_min=1000,absolute_max=4000,
                 source='Synthetic software test only; not agronomic evidence')
    value.update(changes)
    return [value.get(name) for name in excel.HEADERS]


def test_reads_cells_without_url_and_preserves_zero_units_and_file_provenance():
    upload_id = uuid4()
    content = workbook([row(),row(crop='Mango',factor='elevation',unit='m',period='terrain',
                                preferred_min=0,preferred_max=400,absolute_min=0,absolute_max=600)])
    preview = excel.parse(content,'requirements.xlsx',upload_id,date(2026,11,9))
    assert len(preview['rows']) == 2
    assert all(not r['errors'] for r in preview['rows'])
    record = preview['rows'][1]['document']
    assert record['payload']['preferred_min'] == 0
    assert record['evidence_url'] == ''
    assert record['source_file']['upload_id'] == str(upload_id)
    assert record['source_file']['row'] == 3 and record['source_file']['sheet'] == 'Crop requirements'
    assert record['valid_from'] == '2026-11-09' and record['valid_until'] == '9999-12-31'


@pytest.mark.parametrize('change,message', [
    ({'crop':'Potato'},'seven approved'),
    ({'factor':'nitrogen'},'supported factor'),
    ({'unit':'mm/month'},'unit or period'),
    ({'period':'rolling_30_days'},'unit or period'),
    ({'preferred_min':5000},'Preferred range'),
    ({'absolute_min':True},'needs a number'),
    ({'absolute_min':None},'needs a number'),
    ({'preferred_min':'=1+1'},'formulas'),
    ({'source_url':'https://localhost/internal'},'public HTTPS'),
    ({'valid_from':'11/09/26'},'Dates must'),
])
def test_bad_rows_are_reported_instead_of_applied(change,message):
    parsed = excel.parse(workbook([row(**change)]),'fixture.xlsx',uuid4())
    assert message in parsed['rows'][0]['errors'][0]


def test_duplicate_rows_mark_both_and_missing_headers_do_not_get_guessed():
    parsed = excel.parse(workbook([row(),row()]),'fixture.xlsx',uuid4())
    assert all('Duplicate' in r['errors'][0] for r in parsed['rows'])
    with pytest.raises(ValueError,match='Unknown column'):
        excel.parse(workbook([],headers=['temperature','humidity','label']),'training.xlsx',uuid4())
    with pytest.raises(ValueError,match='No crop requirements'):
        excel.parse(workbook([]),'blank.xlsx',uuid4())


def test_invalid_formats_size_and_external_workbooks_are_rejected():
    with pytest.raises(ValueError,match='.xlsx'):
        excel.parse(b'not excel','bad.xlsm',uuid4())
    with pytest.raises(ValueError,match='readable'):
        excel.parse(b'not excel','bad.xlsx',uuid4())
    with pytest.raises(ValueError,match='2 MB'):
        excel.parse(b'x'*(excel.MAX_BYTES+1),'big.xlsx',uuid4())
    output=io.BytesIO()
    with zipfile.ZipFile(output,'w') as z: z.writestr('xl/externalLinks/externalLink1.xml','<link/>')
    with pytest.raises(ValueError,match='external workbook'):
        excel.parse(output.getvalue(),'external.xlsx',uuid4())


@pytest.mark.parametrize('role',['farmer','agricultural_planning_analyst'])
def test_excel_endpoints_are_admin_only_before_reading_the_file(client,monkeypatch,role):
    import fastapi_app as api
    api.app.dependency_overrides[api.get_api_user] = lambda: {'id':10,'role':role}
    monkeypatch.setattr(excel,'preview',lambda *args: pytest.fail('Unauthorized parse/storage'))
    assert client.get('/api/admin/controlled-records/excel/template').status_code == 403
    assert client.post('/api/admin/controlled-records/excel/preview',json={'filename':'x.xlsx','content_base64':'eA=='}).status_code == 403
    assert client.post('/api/admin/controlled-records/excel/apply',json={'upload_id':str(uuid4()),'expected':[{'record_key':'rice_rainfall','revision':0,'generation':0}]}).status_code == 403
    assert client.get('/api/admin/controlled-records/excel/files/'+str(uuid4())).status_code == 403


def test_preview_api_reads_json_and_reports_validation_without_database_on_bad_file(client):
    import fastapi_app as api
    api.app.dependency_overrides[api.get_api_user] = lambda: {'id':10,'role':'super_admin','is_active':True}
    response=client.post('/api/admin/controlled-records/excel/preview',json={'filename':'bad.xlsx','content_base64':base64.b64encode(b'not excel').decode()})
    assert response.status_code == 422 and 'readable' in response.json()['detail']
    assert client.get('/api/admin/controlled-records/excel/template').status_code == 200
