"""Shared parcel geometry contract: closed lat/lng rings in the study area."""

import math

EARTH_RADIUS_M = 6378137.0
MAX_BOUNDARY_POINTS = 2000


def polygon_centroid(polygon):
    """Area-weighted centroid in the local planar lon/lat projection, not sample GPS."""
    points = [(float(p['lng']), float(p['lat'])) for p in polygon]
    if points and points[0] == points[-1]:
        points.pop()
    if len(points) < 3:
        return None, None
    x0, y0 = points[0]
    points = [(x-x0, y-y0) for x, y in points]
    edges = list(zip(points, points[1:] + points[:1]))
    cross = [x*y2-x2*y for (x, y), (x2, y2) in edges]
    area2 = sum(cross)
    if abs(area2) < 1e-20:
        return None, None
    x = sum((a[0]+b[0])*c for (a, b), c in zip(edges, cross))/(3*area2)
    y = sum((a[1]+b[1])*c for (a, b), c in zip(edges, cross))/(3*area2)
    return y+y0, x+x0


def in_study_area(lat, lng):
    from city_boundary import contains_point
    return contains_point(lat, lng)


def polygon_area_m2(polygon):
    points = [(float(p["lat"]), float(p["lng"])) for p in polygon]
    if points and points[0] == points[-1]:
        points.pop()
    if len(points) < 3:
        return 0.0
    lat0 = math.radians(sum(p[0] for p in points) / len(points))
    origin_lat, origin_lng = points[0]
    xy = [
        (
            EARTH_RADIUS_M * math.radians(lng - origin_lng) * math.cos(lat0),
            EARTH_RADIUS_M * math.radians(lat - origin_lat),
        )
        for lat, lng in points
    ]
    return (
        abs(sum(x * y2 - x2 * y for (x, y), (x2, y2) in zip(xy, xy[1:] + xy[:1]))) / 2
    )


def self_intersects(points):
    def cross(a, b, c):
        return (b[1] - a[1]) * (c[0] - a[0]) - (b[0] - a[0]) * (c[1] - a[1])

    def on_segment(a, b, c):
        return (
            min(a[0], b[0]) - 1e-12 <= c[0] <= max(a[0], b[0]) + 1e-12
            and min(a[1], b[1]) - 1e-12 <= c[1] <= max(a[1], b[1]) + 1e-12
        )

    def intersects(a, b, c, d):
        v1, v2, v3, v4 = cross(a, b, c), cross(a, b, d), cross(c, d, a), cross(c, d, b)
        if v1 * v2 < 0 and v3 * v4 < 0:
            return True
        return any(
            abs(v) <= 1e-12 and on_segment(p, q, r)
            for v, p, q, r in [
                (v1, a, b, c),
                (v2, a, b, d),
                (v3, c, d, a),
                (v4, c, d, b),
            ]
        )

    n = len(points)
    for i in range(n):
        for j in range(i + 1, n):
            if j == i + 1 or (i == 0 and j == n - 1):
                continue
            if intersects(
                points[i], points[(i + 1) % n], points[j], points[(j + 1) % n]
            ):
                return True
    # Adjacent edges that double back overlap even without a nonadjacent crossing.
    for i in range(n):
        a, b, c = points[i - 1], points[i], points[(i + 1) % n]
        if (
            abs(cross(a, b, c)) <= 1e-12
            and ((a[0] - b[0]) * (c[0] - b[0]) + (a[1] - b[1]) * (c[1] - b[1])) > 0
        ):
            return True
    return False


def normalize_polygon(polygon):
    if not isinstance(polygon, (list, tuple)) or len(polygon) > MAX_BOUNDARY_POINTS + 1:
        raise ValueError(f"Boundary must contain at most {MAX_BOUNDARY_POINTS} points.")
    points = []
    for point in polygon:
        if not isinstance(point, dict):
            raise ValueError("Use boundary points with lat and lng coordinates.")
        try:
            lat = float(point.get("lat", point.get("latitude")))
            lng = float(point.get("lng", point.get("lon", point.get("longitude"))))
        except (TypeError, ValueError):
            raise ValueError("Each boundary point needs valid latitude and longitude.")
        if not math.isfinite(lat) or not math.isfinite(lng):
            raise ValueError("Boundary coordinates must be finite numbers.")
        if not in_study_area(lat, lng):
            raise ValueError(
                "The entire boundary must be within the supported Panabo study area."
            )
        pair = (lat, lng)
        if not points or pair != points[-1]:
            points.append(pair)
    if points and points[0] == points[-1]:
        points.pop()
    if len(points) < 3 or len(set(points)) < 3:
        raise ValueError("A boundary requires at least three distinct points.")
    if len(set(points)) != len(points) or self_intersects(points):
        raise ValueError(
            "The boundary crosses or touches itself. Correct the boundary before continuing."
        )
    ring = [{"lat": lat, "lng": lng} for lat, lng in points + points[:1]]
    from city_boundary import contains_polygon
    if not contains_polygon(ring):
        raise ValueError('The entire boundary must be inside the Panabo City reference boundary.')
    if polygon_area_m2(ring) < 4:
        raise ValueError("The boundary must enclose at least 4 square metres of land.")
    return ring
