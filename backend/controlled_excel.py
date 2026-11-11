"""Bounded XLSX requirement import. Workbook cells are data, never executable code."""
import base64
from contextlib import closing
from datetime import date, datetime
import hashlib
import io
from pathlib import PurePosixPath
import re
from uuid import uuid4, UUID
import zipfile

from openpyxl import load_workbook
from defusedxml import ElementTree as safe_xml
from pydantic import BaseModel, ConfigDict, Field, StrictBool, StrictInt, ValidationError
from psycopg2.extras import Json

import controlled_records as records
import database as db

MAX_BYTES = 2 * 1024 * 1024
MAX_ROWS = 200
HEADERS = ['crop', 'factor', 'unit', 'period', 'preferred_min', 'preferred_max',
           'absolute_min', 'absolute_max', 'source', 'source_url', 'notes', 'valid_from', 'valid_until']
REQUIRED = set(HEADERS[:8])


class PreviewBody(BaseModel):
    model_config = ConfigDict(extra='forbid')
    filename: str = Field(min_length=1, max_length=255)
    content_base64: str = Field(max_length=4 * MAX_BYTES // 3 + 8)


class ExpectedRow(BaseModel):
    model_config = ConfigDict(extra='forbid')
    record_key: str = Field(max_length=80)
    revision: StrictInt = Field(ge=0)
    generation: StrictInt = Field(ge=0)


class ApplyBody(BaseModel):
    model_config = ConfigDict(extra='forbid')
    upload_id: UUID
    expected: list[ExpectedRow] = Field(min_length=1, max_length=MAX_ROWS)
    activate: StrictBool = False
    review_note: str = Field(default='', max_length=1000)


def token(value):
    return re.sub(r'[^a-z0-9]', '', str(value or '').strip().lower())


ALIASES = {token(name): name for name in HEADERS}
ALIASES.update({'preferredminimum': 'preferred_min', 'preferredmaximum': 'preferred_max',
                'absoluteminimum': 'absolute_min', 'absolutemaximum': 'absolute_max',
                'evidenceurl': 'source_url', 'reference': 'source', 'method': 'notes'})
FACTORS = {token(name): name for name in records.FACTORS}
FACTORS.update({token(spec[0]): name for name, spec in records.FACTORS.items()})
FACTORS.update({'ph': 'soil_ph', 'soilph': 'soil_ph', 'temperature': 'temperature',
                'rainfall': 'rainfall', 'humidity': 'humidity'})


def filename(value):
    name = PurePosixPath(value.replace('\\', '/')).name
    if not name.lower().endswith('.xlsx') or len(name) > 120 or any(ord(c) < 32 for c in name):
        raise ValueError('Choose an Excel Workbook (.xlsx) with a filename under 120 characters.')
    return name


def number(value, label):
    if type(value) is bool or value is None or str(value).strip() == '':
        raise ValueError(f'{label} needs a number. Do not guess a missing source limit.')
    if isinstance(value, str) and ',' in value:
        if not re.fullmatch(r'[-+]?\d{1,3}(,\d{3})+(\.\d+)?', value.strip()):
            raise ValueError(f'{label} has an ambiguous number. Use a decimal point and no unit in the cell.')
        value = value.replace(',', '')
    try:
        result = float(value)
    except (ValueError, TypeError):
        raise ValueError(f'{label} needs a number without units.') from None
    return result


def day(value, fallback):
    if value is None or str(value).strip() == '':
        return fallback
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    try:
        return date.fromisoformat(str(value).strip())
    except ValueError:
        raise ValueError('Dates must be Excel date cells or YYYY-MM-DD.') from None


def parse(content, name, upload_id, as_of=None):
    """Read one requirements sheet; preserve zeros, reject formulas and unknown units."""
    name = filename(name)
    as_of = as_of or date.today()
    if not content or len(content) > MAX_BYTES:
        raise ValueError('The Excel file must be nonempty and no larger than 2 MB.')
    try:
        with zipfile.ZipFile(io.BytesIO(content)) as archive:
            items = archive.infolist()
            if len(items) > 2000 or sum(item.file_size for item in items) > 8 * MAX_BYTES or any(item.file_size > 2 * MAX_BYTES for item in items):
                raise ValueError('The workbook is too large after decompression.')
            if any('vbaProject' in item.filename or item.filename.startswith(('xl/embeddings/', 'xl/externalLinks/')) for item in items):
                raise ValueError('Remove macros, embedded objects and external workbook links before importing.')
            for item in items:
                if item.filename.startswith('xl/worksheets/') and item.filename.endswith('.xml'):
                    for _, element in safe_xml.iterparse(io.BytesIO(archive.read(item)), events=('start',)):
                        if element.tag.endswith('}row') and int(element.get('r', '0')) > MAX_ROWS + 1:
                            raise ValueError('Use up to 200 rows; remove extra data or formatted rows.')
        book = load_workbook(io.BytesIO(content), read_only=True, data_only=False, keep_links=False)
    except ValueError:
        raise
    except Exception:
        raise ValueError('This is not a readable .xlsx workbook. Save it as Excel Workbook and try again.') from None
    try:
        candidates = [sheet for sheet in book.worksheets if sheet.title.lower() not in ('guide', 'instructions')]
        if len(candidates) != 1:
            raise ValueError('Use one crop requirements sheet. A separate Guide or Instructions sheet is allowed.')
        sheet = candidates[0]
        # Some valid exporters omit dimensions; recalculate from actual cells
        # rather than trusting a missing or misleading declared used range.
        sheet.reset_dimensions()
        sheet.calculate_dimension(force=True)
        if sheet.max_row > MAX_ROWS + 1 or sheet.max_column > 32:
            raise ValueError('Use up to 200 data rows and 32 columns; remove extra formatted rows or columns.')
        cells = list(sheet.iter_rows())
        if not cells:
            raise ValueError('The workbook is empty.')
        columns = {}
        for index, cell in enumerate(cells[0]):
            if cell.value is None:
                continue
            key = ALIASES.get(token(cell.value))
            if not key:
                raise ValueError(f'Unknown column: {str(cell.value)[:60]}. Use the downloadable template.')
            if key in columns:
                raise ValueError(f'Duplicate column: {key}.')
            columns[key] = index
        if REQUIRED - columns.keys():
            raise ValueError('Missing columns: ' + ', '.join(sorted(REQUIRED - columns.keys())))
        result = []
        seen = {}
        sha = hashlib.sha256(content).hexdigest()
        for row_number, row in enumerate(cells[1:], 2):
            if not any(cell.value is not None and str(cell.value).strip() for cell in row):
                continue
            info = {'row': row_number, 'sheet': sheet.title, 'errors': [], 'document': None}
            try:
                if any(cell.data_type in ('f', 'e') for cell in row):
                    raise ValueError('Paste calculated values instead of formulas or Excel errors.')
                if any(index not in columns.values() and cell.value is not None and str(cell.value).strip()
                       for index, cell in enumerate(row)):
                    raise ValueError('A value appears below a blank column header. Add a supported header or remove that column.')
                values = {key: row[index].value for key, index in columns.items()}
                crop = str(values['crop'] or '').strip().lower()
                factor = FACTORS.get(token(values['factor']))
                info.update(crop=crop[:50], factor=factor or str(values['factor'] or '')[:50])
                if crop not in {name.lower() for name in records.REQUIREMENTS}:
                    raise ValueError('Crop must be one of the seven approved crop groups.')
                if factor is None:
                    raise ValueError('Choose a supported factor. NPK, NDVI and training-data columns are not imported here.')
                unit = str(values['unit'] or '').strip()
                if unit in ('°C', '℃'):
                    unit = 'C'
                payload = {'crop': crop, 'factor': factor, 'unit': unit,
                           'period': str(values['period'] or '').strip(),
                           **{key: number(values[key], key.replace('_', ' ')) for key in HEADERS[4:8]}}
                key = f'{crop}_{factor}'
                doc = records.RecordBody(kind='crop_requirement', record_key=key, expected_revision=0,
                    title=f'{crop.title()}: {records.FACTORS[factor][0]}',
                    evidence_url=str(values.get('source_url') or '').strip(),
                    source_file={'upload_id': str(upload_id), 'filename': name, 'sha256': sha,
                                 'sheet': sheet.title, 'row': row_number},
                    reference=str(values.get('source') or f'{name}, {sheet.title}, row {row_number}').strip(),
                    method=str(values.get('notes') or f'Imported from {name}; supplied units, periods and ranges retained.').strip(),
                    valid_from=day(values.get('valid_from'), as_of), valid_until=day(values.get('valid_until'), date.max),
                    payload=payload)
                info.update(record_key=key, crop=crop, factor=factor, payload=payload,
                            valid_from=str(doc.valid_from), valid_until=str(doc.valid_until),
                            source=doc.reference, document=records.document(doc))
                if key in seen:
                    info['errors'].append('Duplicate crop/factor; keep one row per requirement.')
                    seen[key]['errors'].append('Duplicate crop/factor; keep one row per requirement.')
                else:
                    seen[key] = info
            except ValidationError as exc:
                info['errors'].append(exc.errors()[0]['msg'].removeprefix('Value error, '))
            except (ValueError, TypeError) as exc:
                info['errors'].append(str(exc))
            result.append(info)
        if not result:
            raise ValueError('No crop requirements found. Fill in at least one row below the headers.')
        return {'rows': result, 'as_of': as_of.isoformat(), 'filename': name, 'sha256': sha}
    finally:
        book.close()


def preview(body, actor):
    try:
        content = base64.b64decode(body.content_base64, validate=True)
    except ValueError:
        raise ValueError('The uploaded file encoding is invalid.') from None
    upload_id = uuid4()
    parsed = parse(content, body.filename, upload_id)
    with closing(db.get_conn()) as conn, conn, conn.cursor() as cur:
        keys = [row['record_key'] for row in parsed['rows'] if row.get('record_key')]
        cur.execute('''SELECT r.record_key, MAX(r.revision) AS revision, COALESCE(MAX(a.generation),0) AS generation
            FROM controlled_record_revisions r LEFT JOIN controlled_record_activations a USING(kind,record_key)
            WHERE r.kind='crop_requirement' AND r.record_key=ANY(%s) GROUP BY r.record_key''', (keys,))
        expected = {row['record_key']: dict(row) for row in cur.fetchall()}
        for row in parsed['rows']:
            if row.get('record_key'):
                row['expected'] = expected.get(row['record_key'], {'record_key': row['record_key'], 'revision': 0, 'generation': 0})
        cur.execute('''INSERT INTO controlled_excel_uploads(id,uploaded_by,filename,sha256,content,preview)
            VALUES(%s,%s,%s,%s,%s,%s)''',
            (str(upload_id), actor['id'], parsed['filename'], parsed['sha256'], content, Json(parsed)))
    return public_preview(upload_id, parsed)


def public_preview(upload_id, parsed):
    return {'upload_id': str(upload_id), 'filename': parsed['filename'], 'sha256': parsed['sha256'],
            'total_rows': len(parsed['rows']), 'valid_rows': sum(not row['errors'] for row in parsed['rows']),
            'rows': [{key: value for key, value in row.items() if key != 'document'} for row in parsed['rows']]}


def apply(body, actor):
    signature = records.digest(body.model_dump(mode='json'))
    with closing(db.get_conn()) as conn, conn, conn.cursor() as cur:
        cur.execute('SELECT * FROM controlled_excel_uploads WHERE id=%s AND uploaded_by=%s FOR UPDATE', (str(body.upload_id), actor['id']))
        upload = cur.fetchone()
        if not upload:
            raise ValueError('Uploaded spreadsheet not found for this administrator. Upload it again.')
        if upload['import_result']:
            if signature != upload['import_signature']:
                raise records.Conflict('This file was already imported. Use its saved revisions or upload it again.')
            return upload['import_result']
        content = bytes(upload['content'])
        if hashlib.sha256(content).hexdigest() != upload['sha256']:
            raise ValueError('The uploaded spreadsheet failed its integrity check.')
        parsed = parse(content, upload['filename'], body.upload_id, date.fromisoformat(upload['preview']['as_of']))
        rows = parsed['rows']
        if any(row['errors'] for row in rows):
            raise ValueError('Fix all spreadsheet row errors before importing.')
        expected = {item.record_key: item for item in body.expected}
        baseline = {row['record_key']: row['expected'] for row in upload['preview']['rows']}
        if len(expected) != len(body.expected) or set(expected) != {row['record_key'] for row in rows}:
            raise ValueError('The preview rows do not match this spreadsheet.')
        if any(item.model_dump() != baseline[key] for key, item in expected.items()):
            raise records.Conflict('The preview changed. Upload the file again.')
        if body.activate and len(body.review_note.strip()) < 3:
            raise ValueError('Confirm that you reviewed the imported ranges before activation.')
        saved = []
        for row in sorted(rows, key=lambda item: item['record_key']):
            key = row['record_key']; prior = expected[key]
            cur.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s,0))', ('control:crop_requirement:' + key,))
            cur.execute("SELECT COALESCE(MAX(revision),0) AS revision FROM controlled_record_revisions WHERE kind='crop_requirement' AND record_key=%s", (key,))
            latest = cur.fetchone()['revision']
            cur.execute("SELECT * FROM controlled_record_activations WHERE kind='crop_requirement' AND record_key=%s", (key,))
            pointer = cur.fetchone() or {}
            if latest != prior.revision or pointer.get('generation', 0) != prior.generation:
                raise records.Conflict('A reference changed after preview. Upload again to check the latest version.')
            doc = records.RecordBody(**row['document'], expected_revision=latest)
            if body.activate:
                doc.review_status = 'reviewed'; doc.review_note = body.review_note.strip()
            document = records.document(doc)
            cur.execute('''INSERT INTO controlled_record_revisions(kind,record_key,revision,document,content_sha256,created_by)
                VALUES('crop_requirement',%s,%s,%s,%s,%s) RETURNING id''',
                (key, latest + 1, Json(document), records.digest(document), actor['id']))
            rid = cur.fetchone()['id']
            db.audit_in_transaction(cur, actor['id'], actor['role'], 'controlled_record_revision', 'controlled_record', rid,
                {'kind': 'crop_requirement', 'record_key': key, 'revision': latest + 1, 'upload_id': str(body.upload_id)})
            if body.activate:
                cur.execute('''INSERT INTO controlled_record_activations(kind,record_key,record_id,generation)
                    VALUES('crop_requirement',%s,%s,%s) ON CONFLICT(kind,record_key) DO UPDATE
                    SET record_id=EXCLUDED.record_id,generation=EXCLUDED.generation,updated_at=NOW()''',
                    (key, rid, prior.generation + 1))
                db.audit_in_transaction(cur, actor['id'], actor['role'], 'controlled_record_activation', 'controlled_record', rid,
                    {'kind': 'crop_requirement', 'record_key': key, 'before_record_id': pointer.get('record_id'),
                     'after_record_id': rid, 'generation': prior.generation + 1})
            saved.append({'record_key': key, 'record_id': rid, 'revision': latest + 1})
        result = {'imported': len(saved), 'activated': body.activate, 'records': saved, 'upload_id': str(body.upload_id)}
        cur.execute('UPDATE controlled_excel_uploads SET import_signature=%s,import_result=%s WHERE id=%s',
                    (signature, Json(result), str(body.upload_id)))
        return result


def download(upload_id):
    with closing(db.get_conn()) as conn, conn.cursor() as cur:
        cur.execute('SELECT filename,content FROM controlled_excel_uploads WHERE id=%s', (str(upload_id),))
        row = cur.fetchone()
    return row
