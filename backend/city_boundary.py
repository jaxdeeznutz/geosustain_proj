"""Panabo administrative reference; never a soil observation or survey guarantee."""
from functools import lru_cache
import json
import math
from pathlib import Path

VERSION = 'panabo-geoboundaries-adm3-2020-v1'


@lru_cache(maxsize=1)
def reference():
    path = Path(__file__).resolve().parent/'data/panabo_boundary.geojson'
    feature = json.loads(path.read_text(encoding='utf-8'))['features'][0]
    assert feature['properties']['shapeName'] == 'City of Panabo'
    assert feature['geometry']['type'] == 'Polygon'
    return feature


def inside(point, ring):
    hit = False
    for a,b in zip(ring,ring[1:]):
        cross=(b[0]-a[0])*(point[1]-a[1])-(b[1]-a[1])*(point[0]-a[0])
        if abs(cross)<1e-12 and min(a[0],b[0])-1e-12<=point[0]<=max(a[0],b[0])+1e-12 and min(a[1],b[1])-1e-12<=point[1]<=max(a[1],b[1])+1e-12:
            return False
        if (a[1]>point[1]) != (b[1]>point[1]) and point[0]<(b[0]-a[0])*(point[1]-a[1])/(b[1]-a[1])+a[0]:
            hit=not hit
    return hit


def contains_point(lat, lon):
    if not all(isinstance(v,(int,float)) and math.isfinite(v) for v in (lat,lon)):
        return False
    try:
        outer,*holes=reference()['geometry']['coordinates']
        return inside((lon,lat),outer) and not any(inside((lon,lat),h) for h in holes)
    except (OSError,ValueError,KeyError,AssertionError):
        return False


def contains_polygon(polygon):
    if not polygon:
        return False
    try:
        # Existing checked containment also rejects edge crossings, touching
        # administrative edges and parcels that enclose a boundary hole.
        from cagro_soil import _contained
        ring=[(float(p['lng'] if 'lng' in p else p['lon']),float(p['lat'])) for p in polygon]
        if ring[0]!=ring[-1]:
            ring.append(ring[0])
        return _contained(ring,reference()['geometry']['coordinates'])
    except (OSError,ValueError,TypeError,KeyError,AssertionError):
        return False
