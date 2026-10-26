"""Owned whole-history aggregates without shipping every analysis to the browser."""
import database

def summary(owner_id):
    conn=database.get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("""
              WITH records AS (
                SELECT s.id,s.area_hectares,s.analyzed_at,
                  c.predicted_crop,c.compatibility_pct,
                  (c.is_crop_recommended IS TRUE AND c.predicted_crop IS NOT NULL
                   AND btrim(c.predicted_crop)<>'' AND COALESCE(c.land_type,'arable')='arable'
                   AND COALESCE(s.result_snapshot->>'analysis_mode','') <> 'preliminary_environmental') AS eligible
                FROM analysis_sessions s LEFT JOIN LATERAL (
                  SELECT predicted_crop,compatibility_pct,is_crop_recommended,land_type
                  FROM crop_recommendations WHERE session_id=s.id ORDER BY id DESC LIMIT 1
                ) c ON TRUE WHERE s.user_id=%s
              ), scored AS (SELECT * FROM records WHERE eligible AND compatibility_pct BETWEEN 0 AND 100),
              frequency AS (SELECT predicted_crop AS crop,COUNT(*) AS count FROM records
                            WHERE eligible GROUP BY predicted_crop),
              months AS (SELECT date_trunc('month',analyzed_at) AS month,COUNT(*) AS count
                         FROM records GROUP BY 1 ORDER BY 1 DESC LIMIT 6)
              SELECT COUNT(*) AS analysis_count,
                COALESCE(SUM(GREATEST(0,area_hectares)),0) AS cumulative_area_ha,
                (SELECT AVG(compatibility_pct) FROM scored) AS average_model_score,
                (SELECT COUNT(*) FROM scored) AS scored_count,
                (SELECT COUNT(*) FROM scored WHERE compatibility_pct>=75) AS high_count,
                (SELECT COUNT(*) FROM scored WHERE compatibility_pct>=50 AND compatibility_pct<75) AS medium_count,
                (SELECT COUNT(*) FROM scored WHERE compatibility_pct>=25 AND compatibility_pct<50) AS low_count,
                (SELECT COUNT(*) FROM scored WHERE compatibility_pct<25) AS very_low_count,
                COALESCE((SELECT jsonb_agg(jsonb_build_object('crop',crop,'count',count) ORDER BY count DESC,crop) FROM frequency),'[]'::jsonb) AS frequencies,
                COALESCE((SELECT jsonb_agg(jsonb_build_object('month',to_char(month,'YYYY-MM'),'count',count) ORDER BY month) FROM months),'[]'::jsonb) AS monthly
              FROM records
            """,(owner_id,))
            return dict(cur.fetchone(),scope='All analyses owned by this account; cumulative area counts repeat analyses separately')
    finally:
        conn.close()
