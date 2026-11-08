"""One bounded, cloud-masked NDVI definition for inference and parcel maps."""
from datetime import timedelta


def recent_ndvi(ee, geometry, today):
    start, end = (today - timedelta(days=90)).isoformat(), today.isoformat()
    collection = (ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED')
                  .filterBounds(geometry).filterDate(start, end)
                  .filter(ee.Filter.lt('CLOUDY_PIXEL_PERCENTAGE', 80))
                  .sort('system:time_start', False).limit(12))
    scene = ee.Image(collection.first())

    def usable(image):
        scl = image.select('SCL')
        mask = scl.neq(0)
        for code in (1, 2, 3, 8, 9, 10, 11):
            mask = mask.And(scl.neq(code))
        return (image.normalizedDifference(['B8', 'B4']).updateMask(mask)
                .copyProperties(image, ['system:time_start']))

    image = collection.map(usable).sort('system:time_start').mosaic()
    return image, scene.select('B8').projection(), {
        'start': start, 'end_exclusive': end,
        'period': 'Latest usable pixels across at most 12 scenes in completed 90-day window',
        'newest_scene_date': scene.date().format('YYYY-MM-dd'),
        'scene_count': collection.size(),
        'observation_date': 'Mixed dates within the recorded window; not one acquisition date',
        'method': '(B8-B4)/(B8+B4); newest-valid-pixel mosaic; scene clouds <80%; per-pixel SCL dark/cloud/shadow/snow/nodata mask (20 m mask, nearest resampling)',
    }
