-- Use this alternative when the old caches contain records.
-- Deploy the updated backend first, then run this whole file in a NEW query.
-- Moves only these two retired tables out of public; it does not delete rows.
-- The archive schema must remain outside Supabase's exposed API schemas.
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '30s';

CREATE SCHEMA IF NOT EXISTS geosustain_cache_archive_20261110;
REVOKE ALL ON SCHEMA geosustain_cache_archive_20261110 FROM PUBLIC;

DO $archive$
DECLARE
    archive_schema constant text := 'geosustain_cache_archive_20261110';
    cache_name text;
    cache_oid regclass;
    expected_columns text[];
    actual_columns text[];
    client_role text;
    rows_before bigint;
    rows_after bigint;
BEGIN
    -- Existing table grants otherwise survive ALTER TABLE ... SET SCHEMA.
    FOREACH client_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role']
    LOOP
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = client_role) THEN
            EXECUTE format('REVOKE ALL ON SCHEMA %I FROM %I', archive_schema, client_role);
        END IF;
    END LOOP;

    FOREACH cache_name IN ARRAY ARRAY['analysis_cache', 'climate_monthly_baselines']
    LOOP
        cache_oid := to_regclass(format('public.%I', cache_name));
        IF cache_oid IS NULL THEN
            RAISE NOTICE 'public.% already absent; nothing moved', cache_name;
            CONTINUE;
        END IF;
        IF to_regclass(format('%I.%I', archive_schema, cache_name)) IS NOT NULL THEN
            RAISE EXCEPTION 'Archive target already exists for %. Nothing overwritten.', cache_name;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = cache_oid AND relkind = 'r') THEN
            RAISE EXCEPTION 'Refusing unexpected object type: public.%', cache_name;
        END IF;
        EXECUTE format('LOCK TABLE public.%I IN ACCESS EXCLUSIVE MODE NOWAIT', cache_name);

        expected_columns := CASE cache_name
            WHEN 'analysis_cache' THEN ARRAY[
                'id', 'lat_rounded', 'lon_rounded', 'cached_result', 'cached_at', 'expires_at']
            ELSE ARRAY[
                'id', 'latitude_key', 'longitude_key', 'month_number',
                'mean_temperature_c', 'mean_rainfall_mm', 'mean_humidity_pct',
                'baseline_start_year', 'baseline_end_year', 'source_name', 'fetched_at']
        END;
        SELECT array_agg(attname::text ORDER BY attname::text) INTO actual_columns
          FROM pg_attribute
         WHERE attrelid = cache_oid AND attnum > 0 AND NOT attisdropped;
        IF actual_columns IS DISTINCT FROM ARRAY(
            SELECT c FROM unnest(expected_columns) AS columns_list(c) ORDER BY c
        ) THEN
            RAISE EXCEPTION 'Refusing changed schema for public.%', cache_name;
        END IF;

        EXECUTE format('SELECT COUNT(*) FROM public.%I', cache_name) INTO rows_before;
        EXECUTE format('ALTER TABLE public.%I SET SCHEMA %I', cache_name, archive_schema);
        IF to_regclass(format('%I.%I', archive_schema, cache_name)) IS DISTINCT FROM cache_oid THEN
            RAISE EXCEPTION 'Archive object identity check failed: %', cache_name;
        END IF;
        EXECUTE format('SELECT COUNT(*) FROM %I.%I', archive_schema, cache_name) INTO rows_after;
        IF rows_after <> rows_before THEN
            RAISE EXCEPTION 'Archive row count check failed: %', cache_name;
        END IF;

        EXECUTE format('REVOKE ALL ON TABLE %I.%I FROM PUBLIC', archive_schema, cache_name);
        FOREACH client_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role']
        LOOP
            IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = client_role) THEN
                EXECUTE format('REVOKE ALL ON TABLE %I.%I FROM %I', archive_schema, cache_name, client_role);
            END IF;
        END LOOP;
        RAISE NOTICE 'Archived % with % rows preserved', cache_name, rows_after;
    END LOOP;
END
$archive$;
COMMIT;

SELECT table_schema, table_name
  FROM information_schema.tables
 WHERE table_schema = 'geosustain_cache_archive_20261110'
   AND table_name IN ('analysis_cache', 'climate_monthly_baselines')
 ORDER BY table_name;
