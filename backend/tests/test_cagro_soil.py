"""Offline provenance, spatial rejection and model isolation regressions."""
import json
from copy import deepcopy

import pytest

from cagro_soil import DATA, lookup_soil_observations


def square(lat, lon, delta=.0001):
    return [{"lat": lat-delta, "lng": lon-delta},
            {"lat": lat-delta, "lng": lon+delta},
            {"lat": lat+delta, "lng": lon+delta},
            {"lat": lat+delta, "lng": lon-delta}]


def boundary(locality, ring, holes=None, **properties):
    return {"type": "Feature", "id": "test-only-boundary",
            "properties": {"locality_id": locality, "verified": True,
                           "source": "test fixture, not production geography", **properties},
            "geometry": {"type": "Polygon", "coordinates": [ring, *(holes or [])]}}


@pytest.fixture(autouse=True)
def no_external_boundaries(monkeypatch):
    monkeypatch.delenv("CAGRO_LOCALITY_BOUNDARIES_PATH", raising=False)


def test_catalog_preserves_all_rows_precision_and_no_original_gps():
    locations = json.loads((DATA / "cagro_locations.json").read_text())
    rows = json.loads((DATA / "cagro_observations.json").read_text())
    assert len(locations) == 9 and len(rows) == 31
    assert all(l["original_cagro_gps"] is False for l in locations)
    assert all(l["confidence"] and l["coordinate_precision"] for l in locations)
    assert len({r["id"] for r in rows}) == 31
    first = next(r for r in rows if r["id"] == "cagro-workbook-5")
    assert first["location_name"] == "FARM 2, DAPCO"
    assert (first["estimated_nitrogen_pct"], first["phosphorus_ppm"], first["potassium_ppm"]) == (.09, 61.47, 1337.2)
    reported = next(r for r in rows if r["id"] == "cagro-image-2025-1")
    assert reported["estimated_nitrogen_pct"] is None
    assert reported["nitrogen_pct"] == .05


def test_mapped_farm_returns_four_separate_rows_not_mean():
    result = lookup_soil_observations(square(7.39242, 125.62293))
    assert result["status"] == "matched"
    assert len(result["observations"]) == 4
    assert {r["location_id"] for r in result["observations"]} == {"dapco_farm_3"}
    assert len({r["potassium_ppm"] for r in result["observations"]}) == 4
    assert all(r["match"]["radius_m"] == 250 and not r["original_cagro_gps"] for r in result["observations"])
    assert result["model_compatibility"]["used_for_prediction"] is False


def test_mapped_purok_returns_reported_n_without_converting():
    result = lookup_soil_observations(square(7.29811, 125.66111))
    assert result["status"] == "matched"
    assert len(result["observations"]) == 4
    assert result["observations"][0]["nitrogen_pct"] == .05


@pytest.mark.parametrize("lat,lon", [(7.39163,125.59919), (7.2743,125.625), (7.2756,125.5907), (7.29,125.62)])
def test_approximate_anchors_and_unrelated_polygons_never_match_by_distance(lat, lon):
    result = lookup_soil_observations(square(lat, lon))
    assert result["status"] == "unavailable"
    assert result["observations"] == []


def test_large_boundary_near_anchor_does_not_pass_centroid_only_match():
    assert lookup_soil_observations(square(7.39242,125.62293,.004))["status"] == "unavailable"


def test_reviewed_boundary_returns_locality_context_preserving_original_addresses():
    ring = [[125.62,7.27],[125.63,7.27],[125.63,7.28],[125.62,7.28],[125.62,7.27]]
    b = boundary("tagpore", ring)
    result = lookup_soil_observations(square(7.2743,125.625), boundaries=[b])
    assert result["status"] == "matched"
    assert {r["location_name"] for r in result["observations"]} == {"PRK 6, TAGPORE", "TAGPORE"}
    assert all(r["classification"] == "historical locality-level soil observation" for r in result["observations"])
    assert all(r["match"]["method"] == "verified_locality_boundary" for r in result["observations"])
    assert len(result["observations"]) == 4
    assert lookup_soil_observations(square(7.2743,125.625), boundaries=[boundary("tagpore", ring, verified=False)])["observations"] == []


def test_boundary_crossing_holes_and_conflicting_localities_fail_closed():
    ring = [[125.62,7.27],[125.63,7.27],[125.63,7.28],[125.62,7.28],[125.62,7.27]]
    b = boundary("tagpore", ring)
    assert lookup_soil_observations(square(7.27,125.625), boundaries=[b])["status"] == "unavailable"
    hole = [[125.62499,7.27429],[125.62501,7.27429],[125.62501,7.27431],[125.62499,7.27431],[125.62499,7.27429]]
    assert lookup_soil_observations(square(7.2743,125.625), boundaries=[boundary("tagpore", ring, [hole])])["status"] == "unavailable"
    assert lookup_soil_observations(square(7.2743,125.625), boundaries=[b, boundary("buenavista", ring)])["status"] == "unavailable"


def test_missing_or_invalid_geometry_does_not_produce_soil_data():
    assert lookup_soil_observations([])["observations"] == []
    assert lookup_soil_observations([{"lat": float("nan"), "lng": 125.6}])["observations"] == []


def test_missing_boundary_file_is_unavailable(monkeypatch):
    monkeypatch.setenv("CAGRO_LOCALITY_BOUNDARIES_PATH", "not-a-real-boundary-file.geojson")
    assert lookup_soil_observations(square(7.39242,125.62293))["status"] == "unavailable"


def test_history_restores_provenance_without_rematching():
    from database import enrich_history_rows
    soil = lookup_soil_observations(square(7.39242,125.62293))
    rows = enrich_history_rows([{"result_snapshot": {"cagro_soil": deepcopy(soil)}}])
    assert rows[0]["cagro_soil"] == soil


def test_api_attaches_soil_without_overwriting_inference(monkeypatch):
    import fastapi_app as api
    polygon = square(7.39242,125.62293)
    model = {"scoring_version": "test", "nitrogen": 80, "phosphorus": 47, "potassium": 50,
             "soil_ph": 6.2, "model_explanation": {"samples": [{"inputs": {"N": 80, "P": 47, "K": 50}}]},
             "top_crop_recommendations": [{"crop": "Rice", "compatibility_pct": 55}]}
    monkeypatch.setattr(api, "get_active_crop_keys", lambda: None)
    monkeypatch.setattr(api, "screen_land_cover", lambda *a: {"allow_crops": True})
    monkeypatch.setattr(api, "analyze_location", lambda *a: deepcopy(model))
    import environmental_pipeline
    monkeypatch.setattr(environmental_pipeline, "merge_results", lambda *a: deepcopy(model))
    result, _ = api.build_analysis_result({"polygon": polygon, "place_name": "Untrusted label"})
    assert result["cagro_soil"]["status"] == "matched"
    assert result['analysis_schema_version'] == 'panabo-preliminary-cagro-v2'
    assert result['analysis_coverage']['supported'] is True
    assert result['analysis_coverage']['used_for_model_prediction'] is False
    assert len(result['soil_nutrients_observed']['records']) == 4
    for key in model:
        assert result[key] == model[key]


def test_structured_layers_preserve_each_row_units_and_legacy_inputs():
    from cagro_soil import nutrient_layers, MODEL_WARNING
    soil = lookup_soil_observations(square(7.39242,125.62293))
    analysis = {"model_explanation": {"samples": [{"inputs": {"N": 80, "P": 47, "K": 50}}]}}
    original = deepcopy(analysis)
    layers = nutrient_layers(soil, analysis)
    assert analysis == original
    records = layers["soil_nutrients_observed"]["records"]
    assert len(records) == 4
    for observed, source in zip(records, soil["observations"]):
        assert observed["nitrogen"]["value"] == source["estimated_nitrogen_pct"]
        assert observed["nitrogen"]["unit"] == "%"
        assert observed["nitrogen"]["method"] == "OM / 20"
        assert observed["potassium"]["value"] == source["potassium_ppm"]
        assert observed["potassium"]["method"] is None
        assert observed["phosphorus"]["value"] == source["phosphorus_ppm"]
    assert layers["legacy_model_nutrient_inputs"]["samples"] == [{"sample_index": 0, "model_N": 80, "model_P": 47, "model_K": 50}]
    assert layers["soil_model_warning"] == MODEL_WARNING
    assert len(layers["soil_location_match"]["records"]) == 4


def test_structured_unavailable_and_reported_n_do_not_invent_values():
    from cagro_soil import nutrient_layers
    empty = nutrient_layers(lookup_soil_observations([]), {})
    assert empty["soil_nutrients_observed"]["records"] == []
    assert empty["legacy_model_nutrient_inputs"]["samples"] == []
    soil = lookup_soil_observations(square(7.29811,125.66111))
    rows = nutrient_layers(soil, {})["soil_nutrients_observed"]["records"]
    assert rows
    assert all(r["nitrogen"]["method"] is None for r in rows)
    assert all(r["nitrogen"]["quality"] == "local_soil_observation" for r in rows)
