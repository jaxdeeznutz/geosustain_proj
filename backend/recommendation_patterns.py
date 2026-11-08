"""Version-scoped aggregates of saved results; never rerun or rewrite predictions."""
import hashlib
import json
from pathlib import Path
import database


def model_identity():
    folder = Path(__file__).resolve().parent
    metadata = json.loads((folder / 'crop_model_metadata.json').read_text(encoding='utf-8'))
    version = hashlib.sha256((folder / 'crop_model.pkl').read_bytes()).hexdigest()
    if version != metadata['model_version']:
        raise ValueError('Installed model identity does not match its metadata.')
    return version, metadata['classes']


def patterns(owner_id, *, submitted=False, model_scope='current'):
    if model_scope not in ('current', 'all'):
        raise ValueError('Unknown model scope.')
    version, classes = model_identity()
    # Analyst access is checked by require_planner on the operator endpoint.
    # Count the current revision of each submitted case, not superseded revisions.
    source = ('JOIN review_cases rc ON rc.current_session_id=s.id' if submitted else '')
    owner_filter = '' if submitted else 'WHERE s.user_id=%s'
    params = (() if submitted else (owner_id,)) + (model_scope, version, model_scope, classes)
    cte = f"""WITH records AS (
      SELECT s.id AS session_id,s.analyzed_at,s.area_hectares,s.place_name,
        {"rc.id" if submitted else "NULL::bigint"} AS case_id,
        COALESCE(s.result_snapshot->'model_explanation'->>'model_version',
                 s.result_snapshot->>'model_version','') AS model_version,
        crop.predicted_crop,crop.compatibility_pct,
        (crop.is_crop_recommended IS TRUE AND NULLIF(btrim(crop.predicted_crop),'') IS NOT NULL
         -- Current environmental rankings use "Vegetation observation only"
         -- as a descriptive label, not the legacy arable/non-arable classifier.
         -- Use their saved recommendation decision and explicit land-cover gate.
         AND (s.result_snapshot->>'recommendation_basis'='model_probability'
              OR COALESCE(crop.land_type,'arable')='arable')
         AND COALESCE(s.result_snapshot->'land_cover'->>'allow_crops','true')<>'false'
         AND COALESCE(s.result_snapshot->>'analysis_mode','')<>'preliminary_environmental') AS eligible
      FROM analysis_sessions s {source}
      LEFT JOIN LATERAL (SELECT predicted_crop,compatibility_pct,is_crop_recommended,land_type
        FROM crop_recommendations WHERE session_id=s.id ORDER BY id DESC LIMIT 1) crop ON TRUE
      {owner_filter}
    ), selected AS (SELECT * FROM records WHERE %s='all' OR model_version=%s),
    eligible AS (SELECT * FROM selected WHERE eligible AND (%s='all' OR lower(btrim(predicted_crop))=ANY(%s))),
    scored AS (SELECT * FROM eligible WHERE compatibility_pct BETWEEN 0 AND 100),
    frequency AS (SELECT predicted_crop AS crop,COUNT(*) AS count FROM eligible GROUP BY predicted_crop),
    month_counts AS (SELECT date_trunc('month',analyzed_at) AS month,COUNT(*) AS count
                    FROM eligible WHERE analyzed_at IS NOT NULL GROUP BY 1),
    months AS (SELECT series.month,COALESCE(mc.count,0) AS count FROM
      generate_series((SELECT MAX(month) FROM month_counts)-interval '5 months',
                      (SELECT MAX(month) FROM month_counts), interval '1 month') series(month)
      LEFT JOIN month_counts mc USING(month)) """
    conn = database.get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(cte + """SELECT COUNT(*) AS analysis_count,
              (SELECT COUNT(*) FROM records) AS overall_count,
              (SELECT COUNT(*) FROM records WHERE model_version<>%s) AS archived_count,
              COALESCE(SUM(GREATEST(0,area_hectares)),0) AS cumulative_area_ha,
              (SELECT AVG(compatibility_pct) FROM scored) AS average_model_score,
              (SELECT COUNT(*) FROM scored) AS scored_count,
              (SELECT COUNT(*) FROM scored WHERE compatibility_pct>=75) AS high_count,
              (SELECT COUNT(*) FROM scored WHERE compatibility_pct>=50 AND compatibility_pct<75) AS medium_count,
              (SELECT COUNT(*) FROM scored WHERE compatibility_pct>=25 AND compatibility_pct<50) AS low_count,
              (SELECT COUNT(*) FROM scored WHERE compatibility_pct<25) AS very_low_count,
              COALESCE((SELECT jsonb_agg(jsonb_build_object('crop',crop,'count',count)
                ORDER BY count DESC,crop) FROM frequency),'[]'::jsonb) AS frequencies,
              COALESCE((SELECT jsonb_agg(jsonb_build_object('month',to_char(month,'YYYY-MM'),'count',count)
                ORDER BY month) FROM months),'[]'::jsonb) AS monthly
              FROM selected""", params + (version,))
            result = dict(cur.fetchone())
            cur.execute(cte + '''SELECT session_id,case_id,place_name,analyzed_at,area_hectares,
              predicted_crop,compatibility_pct,model_version,eligible AS is_crop_recommended
              FROM selected ORDER BY analyzed_at DESC,session_id DESC LIMIT 3''', params)
            result['recent_records'] = [dict(row) for row in cur.fetchall()]
        result.update(model_scope=model_scope, current_model_version=version, classes=classes,
                      scope='Submitted cases, latest revision' if submitted else 'Your saved analyses')
        return result
    finally:
        conn.close()
