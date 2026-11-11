-- Run manually in Supabase SQL Editor AFTER deploying the updated backend.
-- Only the two obsolete caches are eligible. This never drops nonempty tables.
-- A row, unexpected schema, lock conflict or external dependency aborts the
-- whole transaction. Review/export populated tables separately; do not CASCADE.
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '30s';

DO $cleanup$
DECLARE
    cache_name text;
    cache_oid regclass;
    expected_columns text[];
    actual_columns text[];
    contains_rows boolean;
BEGIN
    FOREACH cache_name IN ARRAY ARRAY['analysis_cache', 'climate_monthly_baselines']
    LOOP
        cache_oid := to_regclass(format('public.%I', cache_name));
        IF cache_oid IS NULL THEN
            RAISE NOTICE 'public.% already absent; skipped', cache_name;
            CONTINUE;
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM pg_class WHERE oid = cache_oid AND relkind = 'r'
        ) THEN
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

        EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I)', cache_name)
            INTO contains_rows;
        IF contains_rows THEN
            RAISE EXCEPTION 'public.% contains rows. Nothing committed; retain and review/export it first.', cache_name;
        END IF;

        EXECUTE format('DROP TABLE public.%I RESTRICT', cache_name);
        RAISE NOTICE 'Removed empty, obsolete public.%', cache_name;
    END LOOP;
END
$cleanup$;
COMMIT;
