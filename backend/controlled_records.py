"""Versioned public administration records; immutable revisions, explicit activation.

No uploaded artifacts, provider URLs, credentials or NPK data are executable here.
"""
from copy import deepcopy
from datetime import date, datetime, timezone
import hashlib
import ipaddress
import json
import math
import re
from typing import Literal
from urllib.parse import urlsplit

from pydantic import BaseModel, ConfigDict, Field, StrictBool, StrictInt, model_validator
from psycopg2.extras import Json
from crop_requirements import REQUIREMENTS, FACTORS
from spatial_analysis import LAYERS

KINDS = ('crop_requirement', 'planting_calendar', 'environmental_source',
         'model_version', 'supporting_reference', 'system_setting')
PERIODS = {'ndvi': 'latest_scene', 'elevation': 'terrain', 'slope': 'terrain',
           'soil_ph': 'soil_surface', 'rainfall_30d': 'rolling_30_days',
           'rainfall_annual': 'annual_mean_total', 'temperature_annual': 'annual_mean'}
PHYSICAL = {'temperature': (-90, 65), 'rainfall': (0, 20000), 'soil_ph': (0, 14),
            'elevation': (-500, 9000), 'slope': (0, 1000), 'humidity': (0, 100)}


class Conflict(ValueError):
    pass


class RecordBody(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)
    kind: Literal['crop_requirement', 'planting_calendar', 'environmental_source',
                  'model_version', 'supporting_reference', 'system_setting']
    record_key: str = Field(pattern=r'^[a-z][a-z0-9_-]{2,79}$')
    expected_revision: StrictInt = Field(ge=0)
    title: str = Field(min_length=3, max_length=120)
    scope: Literal['Panabo City'] = 'Panabo City'
    evidence_url: str = Field(max_length=500)
    reference: str = Field(min_length=3, max_length=300)
    method: str = Field(min_length=3, max_length=500)
    valid_from: date
    valid_until: date
    review_status: Literal['draft', 'reviewed', 'rejected'] = 'draft'
    review_note: str = Field(default='', max_length=1000)
    payload: dict

    @model_validator(mode='after')
    def validate_document(self):
        public_url(self.evidence_url)
        if self.valid_until < self.valid_from:
            raise ValueError('Validity end must not precede its start.')
        if self.review_status == 'reviewed' and len(self.review_note.strip()) < 3:
            raise ValueError('Reviewed records require an explicit review note.')
        for key in ('title', 'reference', 'method'):
            if len(getattr(self, key).strip()) < 3:
                raise ValueError(f'{key} must contain meaningful text.')
        validate_payload(self.kind, self.record_key, self.payload)
        return self


class ActivationBody(BaseModel):
    model_config = ConfigDict(extra='forbid')
    record_id: StrictInt = Field(gt=0)
    expected_generation: StrictInt = Field(ge=0)
    activate: StrictBool = True


def public_url(value):
    parsed = urlsplit(value)
    if (parsed.scheme != 'https' or not parsed.hostname or '.' not in parsed.hostname
            or parsed.username or parsed.password or parsed.query or parsed.fragment
            or parsed.port not in (None, 443) or parsed.hostname.lower().endswith(('.localhost', '.local'))):
        raise ValueError('Use a public HTTPS evidence URL without credentials, query or fragment.')
    try:
        ipaddress.ip_address(parsed.hostname)
    except ValueError:
        return
    raise ValueError('Evidence URLs must use a public hostname, not a literal IP address.')


def fields(payload, expected):
    if set(payload) != set(expected):
        raise ValueError('Record fields do not match the supported contract: '+', '.join(expected))


def validate_payload(kind, key, payload):
    crops = {name.lower() for name in REQUIREMENTS}
    if kind == 'crop_requirement':
        fields(payload, ['crop', 'factor', 'unit', 'period', 'preferred_min', 'preferred_max', 'absolute_min', 'absolute_max'])
        crop, factor = payload['crop'], payload['factor']
        if not isinstance(crop, str) or not isinstance(factor, str) or crop not in crops or factor not in FACTORS:
            raise ValueError('Choose an approved crop and supported non-nutrient factor.')
        if key != f'{crop}_{factor}' or (payload['unit'], payload['period']) != FACTORS[factor][1:]:
            raise ValueError('Requirement key, unit or period does not match the selected crop/factor.')
        numbers = [payload[name] for name in ['absolute_min', 'preferred_min', 'preferred_max', 'absolute_max']]
        if any(type(v) not in (int, float) or not math.isfinite(v) for v in numbers):
            raise ValueError('All range endpoints must be finite numbers.')
        low, high = PHYSICAL[factor]
        if numbers != sorted(numbers) or numbers[0] < low or numbers[-1] > high:
            raise ValueError('Preferred range must be inside the absolute range and physical bounds.')
    elif kind == 'planting_calendar':
        fields(payload, ['crop', 'months'])
        months = payload['months']
        if (not isinstance(payload['crop'], str) or payload['crop'] not in crops or key != payload['crop'] or not isinstance(months, list)
                or not 1 <= len(months) <= 12 or any(type(v) is not int or not 1 <= v <= 12 for v in months)
                or len(set(months)) != len(months)):
            raise ValueError('Choose one approved crop and unique calendar months 1 through 12.')
    elif kind == 'environmental_source':
        fields(payload, ['layer', 'source_id', 'unit', 'period'])
        layer = payload['layer']
        if (not isinstance(layer, str) or layer not in LAYERS or key != layer or payload['source_id'] != LAYERS[layer]['source']
                or payload['unit'] != LAYERS[layer]['unit'] or payload['period'] != PERIODS[layer]):
            raise ValueError('Source ID, unit and period must match the installed layer contract. Arbitrary providers are unsupported.')
    elif kind == 'model_version':
        fields(payload, ['sha256'])
        if key != 'installed_model' or not isinstance(payload['sha256'], str) or not re.fullmatch('[0-9a-f]{64}', payload['sha256']):
            raise ValueError('Use installed_model and a lowercase SHA-256 identity. Model uploads are unsupported.')
    elif kind == 'supporting_reference':
        fields(payload, ['applies_to', 'citation'])
        if (not isinstance(payload['applies_to'], str) or payload['applies_to'] not in crops | {'analysis'} or not isinstance(payload['citation'], str)
                or not 3 <= len(payload['citation'].strip()) <= 1000):
            raise ValueError('Choose analysis or an approved crop, and supply a public citation.')
    elif kind == 'system_setting':
        fields(payload, ['sample_count'])
        if key != 'analysis_sampling' or type(payload['sample_count']) is not int or payload['sample_count'] not in (1, 5, 9):
            raise ValueError('Only analysis_sampling with 1, 5 or 9 original parcel samples is supported.')


def document(body):
    return body.model_dump(mode='json', exclude={'expected_revision'})


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False, allow_nan=False).encode()).hexdigest()


def installed_model():
    import rainfallDatasets as env
    return {'sha256': env.MODEL_VERSION if env.MODEL is not None else None,
            'status': 'loaded_trusted_artifact' if env.MODEL is not None else 'unavailable',
            'activation': 'Metadata binding only. Files are installed through the trusted developer release procedure; no uploads or model loading from records.'}


def migrate(cur):
    cur.execute('''CREATE TABLE IF NOT EXISTS controlled_record_revisions (
        id BIGSERIAL PRIMARY KEY, kind TEXT NOT NULL, record_key TEXT NOT NULL,
        revision INTEGER NOT NULL CHECK (revision>0), document JSONB NOT NULL,
        content_sha256 TEXT NOT NULL, created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), UNIQUE(kind,record_key,revision))''')
    cur.execute('''CREATE TABLE IF NOT EXISTS controlled_record_activations (
        kind TEXT NOT NULL, record_key TEXT NOT NULL, record_id BIGINT REFERENCES controlled_record_revisions(id),
        generation INTEGER NOT NULL CHECK(generation>0), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        PRIMARY KEY(kind,record_key))''')


def rollback(cur):
    # Refuse to destroy controlled evidence. A used installation rolls back its
    # application candidate, retaining the append-only tables and saved JSON.
    cur.execute('SELECT COUNT(*) AS count FROM controlled_record_revisions')
    if cur.fetchone()['count']:
        raise Conflict('Used record tables must be retained. Restore the prior application candidate without deleting evidence.')
    cur.execute('DROP TABLE controlled_record_activations')
    cur.execute('DROP TABLE controlled_record_revisions')


def list_records(kind=None, limit=50, offset=0):
    import database as db
    with db.get_conn() as conn, conn.cursor() as cur:
        cur.execute('''SELECT r.*, COALESCE(a.generation,0) AS generation,
            a.record_id AS active_record_id FROM controlled_record_revisions r
            LEFT JOIN controlled_record_activations a USING(kind,record_key)
            WHERE (%s IS NULL OR r.kind=%s) ORDER BY r.created_at DESC,r.id DESC LIMIT %s OFFSET %s''',
            (kind, kind, limit, offset))
        return [dict(row) for row in cur.fetchall()]


def create_revision(body, actor):
    import database as db
    doc = document(body)
    with db.get_conn() as conn, conn.cursor() as cur:
        cur.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s,0))', ('control:'+body.kind+':'+body.record_key,))
        cur.execute('SELECT COALESCE(MAX(revision),0) AS revision FROM controlled_record_revisions WHERE kind=%s AND record_key=%s', (body.kind, body.record_key))
        latest = cur.fetchone()['revision']
        if latest != body.expected_revision:
            raise Conflict('This record changed. Reload its latest revision before saving.')
        cur.execute('''INSERT INTO controlled_record_revisions(kind,record_key,revision,document,content_sha256,created_by)
            VALUES (%s,%s,%s,%s,%s,%s) RETURNING *''', (body.kind, body.record_key, latest+1, Json(doc), digest(doc), actor['id']))
        row = dict(cur.fetchone())
        db.audit_in_transaction(cur, actor['id'], actor.get('role'), 'controlled_record_revision', 'controlled_record', row['id'],
            {'kind': body.kind, 'record_key': body.record_key, 'revision': latest+1, 'content_sha256': row['content_sha256']})
        conn.commit()
        return row


def set_activation(body, actor):
    import database as db
    with db.get_conn() as conn, conn.cursor() as cur:
        cur.execute('SELECT * FROM controlled_record_revisions WHERE id=%s', (body.record_id,))
        row = cur.fetchone()
        if not row:
            raise ValueError('Record revision not found.')
        row = dict(row)
        cur.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s,0))', ('control:'+row['kind']+':'+row['record_key'],))
        cur.execute('SELECT * FROM controlled_record_activations WHERE kind=%s AND record_key=%s', (row['kind'], row['record_key']))
        before = cur.fetchone() or {}
        if before.get('generation', 0) != body.expected_generation:
            raise Conflict('Activation changed. Reload before changing the active revision.')
        if not body.activate and before.get('record_id') != body.record_id:
            raise Conflict('This revision is not currently active.')
        checked = RecordBody(**row['document'], expected_revision=row['revision'])
        if row['content_sha256'] != digest(row['document']):
            raise ValueError('Record integrity check failed.')
        if body.activate:
            if checked.review_status != 'reviewed' or not checked.valid_from <= date.today() <= checked.valid_until:
                raise ValueError('Only reviewed records within their validity dates may be activated.')
            if checked.kind == 'model_version' and checked.payload['sha256'] != installed_model()['sha256']:
                raise ValueError('This record does not match the trusted artifact loaded by this process. Metadata cannot deploy a model.')
        target = body.record_id if body.activate else None
        generation = body.expected_generation+1
        cur.execute('''INSERT INTO controlled_record_activations(kind,record_key,record_id,generation)
            VALUES (%s,%s,%s,%s) ON CONFLICT(kind,record_key) DO UPDATE
            SET record_id=EXCLUDED.record_id,generation=EXCLUDED.generation,updated_at=NOW()''',
            (row['kind'], row['record_key'], target, generation))
        db.audit_in_transaction(cur, actor['id'], actor.get('role'), 'controlled_record_activation', 'controlled_record', row['id'],
            {'kind': row['kind'], 'record_key': row['record_key'], 'before_record_id': before.get('record_id'),
             'after_record_id': target, 'generation': generation})
        conn.commit()
        return {'active_record_id': target, 'generation': generation}


def load_active_records():
    import database as db
    # One SQL statement provides one consistent pointer/revision view per analysis.
    with db.get_conn() as conn, conn.cursor() as cur:
        cur.execute('''SELECT r.*, a.generation FROM controlled_record_activations a
            JOIN controlled_record_revisions r ON r.id=a.record_id ORDER BY r.kind,r.record_key''')
        rows = [dict(row) for row in cur.fetchall()]
    active = []
    for row in rows:
        body = RecordBody(**row['document'], expected_revision=row['revision'])
        if digest(row['document']) != row['content_sha256'] or body.review_status != 'reviewed':
            raise RuntimeError('Active reference integrity is invalid; analysis cannot use unverified configuration.')
        if body.valid_from <= date.today() <= body.valid_until:
            active.append({key: deepcopy(row[key]) for key in ('id', 'kind', 'record_key', 'revision', 'document', 'content_sha256', 'generation')})
    return active


def sampling_count(records):
    return next((r['document']['payload']['sample_count'] for r in records if r['kind']=='system_setting'), 9)


def attach_controlled_records(result, records):
    """Apply public references to new result evidence without touching model scores."""
    from suitability import assess
    snapshot = {'version': 'controlled-references-v1', 'captured_at': datetime.now(timezone.utc).isoformat(),
                'records': deepcopy(records), 'default_requirement_version': result.get('crop_config_version'),
                'parcel_sample_limit': sampling_count(records)}
    snapshot['content_sha256'] = digest(records)
    result['configuration_snapshot'] = snapshot
    requirements = [r for r in records if r['kind']=='crop_requirement']
    if requirements and result.get('crop_assessments'):
        rules = deepcopy(REQUIREMENTS)
        for row in requirements:
            doc, p = row['document'], row['document']['payload']
            crop = next(c for c in rules if c.lower()==p['crop'])
            rules[crop][p['factor']] = {'optimal': [p['preferred_min'],p['preferred_max']],
                'absolute': [p['absolute_min'],p['absolute_max']], 'classes': None,
                'source': {'title': doc['title'], 'url': doc['evidence_url'], 'section': doc['reference'], 'scope': doc['scope']},
                'limitations': doc['method'], 'controlled_record_id': row['id'], 'controlled_revision': row['revision']}
        comparisons = {c['crop']: c for c in assess(result.get('environmental_measurements') or {}, requirements=rules)}
        for crop in result['crop_assessments']:
            reference = comparisons[crop['crop']]
            crop['factors'] = reference['factors']
            crop['reference_score'] = reference['compatibility_pct']
            crop['reference_summary'] = reference['explanation']
        # Preserve exact model ranking objects/values, refreshing only factor evidence.
        for crop in result.get('top_crop_recommendations', []):
            crop['factors'] = deepcopy(comparisons[crop['crop']]['factors'])
        result['crop_config_version'] = 'controlled:'+snapshot['content_sha256']
    calendars = [r for r in records if r['kind']=='planting_calendar']
    if calendars and result.get('seasonal_assessment'):
        month = result['seasonal_assessment']['selected_month']
        crops = [{'crop': r['document']['payload']['crop'].title(),
                  'selected_month_listed': month in r['document']['payload']['months'],
                  'record_id': r['id'], 'revision': r['revision']} for r in calendars]
        result['seasonal_assessment']['calendar'] = {'status': 'available', 'crops': crops,
            'reason': '; '.join(f"{c['crop']}: selected month {'listed' if c['selected_month_listed'] else 'not listed'}" for c in crops)+'. Reviewed calendar reference only; no model ranking change or planting-safety guarantee.'}
    for row in records:
        if row['kind']=='environmental_source':
            for layer in (result.get('spatial_assessment') or {}).get('layers', []):
                if layer['id']==row['document']['payload']['layer']:
                    layer['controlled_source_reference'] = deepcopy(row)
        elif row['kind']=='model_version':
            if row['document']['payload']['sha256']==result.get('model_version'):
                result['installed_model_reference'] = deepcopy(row)
        elif row['kind']=='supporting_reference':
            result.setdefault('supporting_references', []).append(deepcopy(row))
    return result


def catalog():
    return {'kinds': list(KINDS), 'crops': [c.lower() for c in REQUIREMENTS],
            'factors': {k: {'label': v[0], 'unit': v[1], 'period': v[2]} for k,v in FACTORS.items()},
            'layers': {k: {'label': v['label'], 'source_id': v['source'], 'unit': v['unit'], 'period': PERIODS[k]} for k,v in LAYERS.items()},
            'installed_model': installed_model(), 'scope': 'Panabo City',
            'settings': {'analysis_sampling': [1,5,9]},
            'limits': 'Public references only. NPK records, provider URL changes and model uploads are unsupported.'}
