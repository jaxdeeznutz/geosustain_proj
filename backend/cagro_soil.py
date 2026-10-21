"""Historical locality observations; never substitutes model features.

Coordinates are reconstructed locality anchors, not original soil-sample GPS.
The optional boundary file is a server-admin-reviewed GeoJSON FeatureCollection.
No client-provided place names or reverse-geocoder display labels are trusted.
"""
from copy import deepcopy
from pathlib import Path
import json
import math
import os
from nutrient_contract import WARNING, recorded_inputs

from geometry import normalize_polygon

DATA = Path(__file__).parent / "data"
VERSION = "cagro-locality-v1"
MAPPED_RADIUS_M = 250
MAPPED_PRECISIONS = {"mapped_farm", "mapped_purok"}
MODEL_COMPATIBILITY = {
    "compatible": False,
    "used_for_prediction": False,
    "status": "incompatible_with_current_production_model",
    "reason": (
        "The current production model training representation is not directly compatible "
        "with CAGRO N%, P ppm and K ppm. Do not rescale or substitute these observations. "
        "Direct use requires a newly trained and validated compatible model. "
        "Legacy model nutrient inputs/proxies remain unchanged."
    ),
}


def _read(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _distance(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (*a, *b))
    h = math.sin((lat2-lat1)/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin((lon2-lon1)/2)**2
    return 6371008.8 * 2 * math.asin(min(1, math.sqrt(h)))


def _cross(a, b, c):
    return (b[0]-a[0])*(c[1]-a[1]) - (b[1]-a[1])*(c[0]-a[0])


def _on(a, b, p):
    return (abs(_cross(a, b, p)) < 1e-12
            and min(a[0], b[0])-1e-12 <= p[0] <= max(a[0], b[0])+1e-12
            and min(a[1], b[1])-1e-12 <= p[1] <= max(a[1], b[1])+1e-12)


def _intersects(a, b, c, d):
    values = (_cross(a, b, c), _cross(a, b, d), _cross(c, d, a), _cross(c, d, b))
    return ((values[0]*values[1] < 0 and values[2]*values[3] < 0)
            or _on(a, b, c) or _on(a, b, d) or _on(c, d, a) or _on(c, d, b))


def _inside(point, ring):
    inside = False
    for a, b in zip(ring, ring[1:]):
        if _on(a, b, point):
            return False  # Touching an administrative edge is ambiguous.
        if (a[1] > point[1]) != (b[1] > point[1]):
            if point[0] < (b[0]-a[0])*(point[1]-a[1])/(b[1]-a[1])+a[0]:
                inside = not inside
    return inside


def _rings_valid(rings):
    return bool(rings) and all(
        len(ring) >= 4 and ring[0] == ring[-1]
        and all(len(p) == 2 and all(isinstance(v, (int, float)) and math.isfinite(v) for v in p)
                and -180 <= p[0] <= 180 and -90 <= p[1] <= 90 for p in ring)
        for ring in rings
    )


def _contained(parcel, rings):
    if not _rings_valid(rings):
        return False
    outer, *holes = rings
    if not all(_inside(p, outer) and not any(_inside(p, h) for h in holes) for p in parcel):
        return False
    # Vertex-only tests miss edges crossing a concavity and enclosed holes.
    if any(_intersects(a, b, c, d)
           for a, b in zip(parcel, parcel[1:])
           for ring in rings for c, d in zip(ring, ring[1:])):
        return False
    if any(_inside(h[0], parcel) for h in holes):
        return False
    return True


def _boundary_evidence(parcel, features):
    matches = {}
    for feature in features:
        properties = feature.get("properties", {})
        if properties.get("verified") is not True or not properties.get("source"):
            continue
        locality = properties.get("locality_id")
        geometry = feature.get("geometry") or {}
        polygons = ([geometry.get("coordinates", [])] if geometry.get("type") == "Polygon"
                    else geometry.get("coordinates", []) if geometry.get("type") == "MultiPolygon" else [])
        if locality and any(_contained(parcel, rings) for rings in polygons):
            matches[locality] = {"source": properties["source"],
                                 "boundary_id": feature.get("id"),
                                 "verified_on": properties.get("verified_on")}
    # Overlapping incompatible administrative claims are not a reliable match.
    return None if len(matches) > 1 else matches


def lookup_soil_observations(polygon, *, boundaries=None):
    """Return all matched historical rows, without averaging or selecting a sample.

    Mapped-locality proximity requires every polygon vertex within 250 m.
    Other anchors require full containment in a reviewed locality boundary.
    """
    result = {
        "version": VERSION, "source": "CAGRO local soil analysis",
        "status": "unavailable", "observations": [],
        "model_compatibility": deepcopy(MODEL_COMPATIBILITY),
        "message": "No reliable locality match. CAGRO soil NPK is unavailable for this polygon.",
        "matching_policy": (
            "Mapped farm/purok: entire boundary within 250 m of reconstructed anchor; "
            "other anchors: full containment in a reviewed locality boundary. "
            "Historical locality context only; never an exact polygon soil measurement."
        ),
    }
    if not polygon:
        result["message"] = "A farm polygon is required to match historical CAGRO observations."
        return result
    try:
        ring = normalize_polygon(polygon)
        parcel = [[p["lng"], p["lat"]] for p in ring]
        locations = _read(DATA / "cagro_locations.json")
        observations = _read(DATA / "cagro_observations.json")
        if boundaries is None:
            path = os.getenv("CAGRO_LOCALITY_BOUNDARIES_PATH")
            boundaries = _read(path).get("features", []) if path else []
        evidence = _boundary_evidence(parcel, boundaries)
        if evidence is None:
            result["message"] = "Conflicting locality boundaries; CAGRO observations cannot be assigned reliably."
            return result
        found = {}
        for location in locations:
            if (not all(isinstance(location[k], (int, float)) and math.isfinite(location[k]) for k in ("latitude", "longitude"))
                    or not -90 <= location["latitude"] <= 90 or not -180 <= location["longitude"] <= 180):
                raise ValueError("Invalid locality coordinate")
            mapped = location["coordinate_precision"] in MAPPED_PRECISIONS
            if mapped:
                distance = max(_distance((p["lat"], p["lng"]),
                                        (location["latitude"], location["longitude"])) for p in ring)
                if distance > MAPPED_RADIUS_M:
                    continue
                # A verified conflicting locality always overrides proximity.
                if evidence and location["locality_id"] not in evidence:
                    continue
                match = {"method": "mapped_locality_proximity", "radius_m": MAPPED_RADIUS_M,
                         "maximum_vertex_distance_m": round(distance, 1)}
            else:
                if location["locality_id"] not in evidence:
                    continue
                match = {"method": "verified_locality_boundary",
                         "boundary": evidence[location["locality_id"]]}
            found[location["id"]] = (location, match)
        for row in observations:
            if row["location_id"] not in found:
                continue
            location, match = found[row["location_id"]]
            observation = deepcopy(row)
            # Preserve the original source address separately from the normalized catalog label.
            observation.update({k: v for k, v in location.items() if k not in ("id", "location_name")})
            observation["catalog_location_name"] = location["location_name"]
            observation["match"] = match
            observation["classification"] = "historical locality-level soil observation"
            observation["data_note"] = (
                f"This historical record is associated with {row['location_name']}. "
                "Coordinates are reconstructed locality references, not original CAGRO sample GPS. "
                "It is not an exact soil measurement for the selected polygon."
            )
            result["observations"].append(observation)
        if result["observations"]:
            result.update(status="matched", message=(
                "Historical locality observations are shown separately. Rows are not averaged, "
                "interpolated or used to replace the model's NPK inputs."
            ))
    except (OSError, ValueError, TypeError, KeyError, AttributeError, IndexError):
        result.update(status="unavailable", observations=[],
                      message="CAGRO locality data could not be verified. Soil observations are unavailable.")
    return result


MODEL_WARNING = WARNING


def nutrient_layers(soil, analysis):
    """Versioned observation interface, never a production feature-vector adapter.

    Each historical row remains distinct. No automatic representative selection,
    conversion, imputation or averaging is permitted here.
    """
    records = []
    matches = []
    for row in soil.get("observations", []):
        estimated = row.get("estimated_nitrogen_pct") is not None
        nutrients = {}
        for name, key, unit in (
            ("nitrogen", "estimated_nitrogen_pct" if estimated else "nitrogen_pct", "%"),
            ("phosphorus", "phosphorus_ppm", "ppm"),
            ("potassium", "potassium_ppm", "ppm"),
        ):
            nutrients[name] = {
                "value": row.get(key), "unit": unit, "source": row.get("source"),
                "quality": ("unavailable" if row.get(key) is None else
                            "estimated_from_organic_matter" if name == "nitrogen" and estimated else
                            "local_soil_observation"),
                "method": "OM / 20" if name == "nitrogen" and estimated else None,
                "date": row.get("sample_date"), "sample_year": row.get("sample_year"),
                "compatible": False, "used_for_prediction": False,
            }
        records.append({"record_id": row["id"], **nutrients,
                        "source_file": row.get("source_file"), "source_row": row.get("source_row"),
                        "sample_date": row.get("sample_date"), "sample_year": row.get("sample_year")})
        matches.append({"record_id": row["id"], **{key: row.get(key) for key in (
            "location_name", "latitude", "longitude", "coordinate_precision", "confidence", "original_cagro_gps")},
            "match_type": row.get("match", {}).get("method"), "note": row.get("data_note")})
    explanation = analysis.get("model_explanation") or {}
    explanation = explanation if isinstance(explanation, dict) else {}
    samples = explanation.get("samples", [])
    return {
        "soil_nutrients_observed": {"schema_version": 1, "status": soil.get("status", "unavailable"),
                                    "records": records, "used_for_prediction": False},
        "soil_location_match": {"status": soil.get("status", "unavailable"), "records": matches},
        "model_nutrient_inputs": recorded_inputs(samples, explanation.get('model_version')),
        "legacy_model_nutrient_inputs": {
            "representation": "legacy_training_scale", "compatible_with_cagro": False,
            "samples": [{"sample_index": i, **{"model_" + k: sample.get("inputs", {}).get(k)
                         for k in ("N", "P", "K")}}
                        for i, sample in enumerate(samples)],
            "note": "Recorded inference inputs only; empty samples mean no recorded model inputs."
        },
        "soil_model_warning": MODEL_WARNING,
    }
