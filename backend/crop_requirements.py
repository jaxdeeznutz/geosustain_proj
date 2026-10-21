"""Reviewed requirements, frozen for new analyses. Never reinterpret old snapshots."""
VERSION = 'panabo-2026-10-13-v1'
LOCAL_SOURCE = 'https://panabocity.gov.ph/local-products-gibida-atol-sa-panagpulong-tali-sa-malaysia-consulate-general-ug-lokal-nga-panggamhanan/'
FACTORS = {
    'temperature': ('Climate temperature', 'C', 'annual_mean'),
    'rainfall': ('Annual rainfall', 'mm/year', 'annual_mean_total'),
    'soil_ph': ('Soil pH in water', 'pH', 'soil_surface'),
    'elevation': ('Elevation', 'm', 'terrain'),
    'slope': ('Slope', '%', 'terrain'),
    'humidity': ('Climate humidity', '%', 'annual_mean'),
}
SOURCES = {
    'banana': {'url': 'https://ecocrop.apps.fao.org/ecocrop/srv/en/dataSheet?id=2483', 'title': 'FAO EcoCrop: Musa sp.', 'section': 'Ecology', 'scope': 'Species-level tropical screening; no variety distinctions. Temperature is interpreted as climate mean for screening, not daily extremes.'},
    'rice': {'url': 'https://ecocrop.apps.fao.org/ecocrop/srv/en/dataSheet?id=1574', 'title': 'FAO EcoCrop: Oryza sativa', 'section': 'Ecology / wet-rice system', 'scope': 'Wet rice. Annual rainfall does not establish irrigation availability or growing-season water balance.'},
    'coconut': {'url': 'https://www.fao.org/4/af298e/af298E01.htm', 'title': 'FAO: Pasture-Cattle-Coconut Systems', 'section': '1.2', 'scope': 'General tropical coconut climate. Rainfall distribution also matters.'},
    'durian': {'url': 'https://apps.worldagroforestry.org/downloads/publications/PDFs/mn15224.pdf', 'title': 'Ritung et al. (2007), Land Suitability Evaluation', 'section': 'Annex 9, printed p.31 / PDF p.38', 'scope': 'Indonesian criteria transferred for preliminary Panabo screening; not locally validated. Full land classes require additional drainage, soil and hazard assessments.'},
    'coconut_ph': {'url': 'https://apps.worldagroforestry.org/downloads/publications/PDFs/mn15224.pdf', 'title': 'Ritung et al. (2007), Land Suitability Evaluation', 'section': 'Annex 3, printed p.25 / PDF p.32', 'scope': 'Indonesian coconut soil criteria; only pH used alongside general FAO climate ranges.'},
    'mango': {'url': 'https://www.da.gov.ph/wp-content/uploads/2023/05/Philippine-Mango-Industry-Roadmap.pdf', 'title': 'Philippine Mango Industry Roadmap 2021–2025', 'section': 'Table 29, printed p.76 / PDF p.97', 'scope': 'Philippine mango. Distinct dry season is required but not assessed; the stated temperature interval is used only as a climate screening range.'},
    'cacao': {'url': 'https://faolex.fao.org/docs/pdf/phi229725.pdf', 'title': 'Philippine Cacao Industry Roadmap 2021–2025', 'section': 'Appendix 1, printed p.84', 'scope': 'Philippine cacao. Uses narrative maximum 32 C. Elevation recommendation conflicts with the same page’s up-to-700m note, so elevation remains unassessed. Shade, drainage and dry-season duration need field assessment.'},
    'rubber': {'url': 'https://bswm.da.gov.ph/wp-content/uploads/DAVAO_DEL_SUR_SUITABILITY_RUBBER.pdf', 'title': 'BSWM (2019): Davao del Sur Land Suitability Map for Rubber', 'section': 'Sheet 1, Agronomic requirement of rubber production', 'scope': 'Philippine rubber criteria transferred from neighbouring province. Gaps between printed decimal/integer intervals remain unassessed; not interpolated.'},
}

def requirement(source, optimal, absolute=None, classes=None):
    return {'source': SOURCES[source], 'optimal': optimal, 'absolute': absolute,
            'classes': classes, 'limitations': SOURCES[source]['scope']}

# Ranges are inclusive. For adjacent published classes, the more limiting class
# owns a shared endpoint; explicit < boundaries are represented in the evaluator.
REQUIREMENTS = {
    'Banana': {
        'temperature': requirement('banana', [22, 32], [13, 38]),
        'rainfall': requirement('banana', [2400, 2700], [2000, 3500]),
        'soil_ph': requirement('banana', [5, 7], [4.5, 7.5]),
    },
    'Coconut': {
        'temperature': requirement('coconut', [27, 32]),
        'rainfall': requirement('coconut', [1250, 2250]),
        'soil_ph': requirement('coconut_ph', [5.2, 7.5], classes={'S1': [[5.2,7.5]], 'S2': [[4.8,5.2],[7.5,8]], 'S3': [[None,4.8],[8,None]]}),
    },
    'Rice': {
        'temperature': requirement('rice', [20, 30], [10,36]),
        'rainfall': requirement('rice', [1500,2000], [1000,4000]),
        'soil_ph': requirement('rice', [5.5,7], [4.5,9]),
    },
    'Durian': {
        'temperature': requirement('durian', [25,28], classes={'S1': [[25,28]], 'S2': [[22,25],[28,32]], 'S3': [[20,22],[32,35]], 'N': [[None,20],[35,None]]}),
        'rainfall': requirement('durian', [2000,3000], classes={'S1': [[2000,3000]], 'S2': [[1750,2000],[3000,3500]], 'S3': [[1250,1750],[3500,4000]], 'N': [[None,1250],[4000,None]]}),
        'soil_ph': requirement('durian', [5.5,7.8], classes={'S1': [[5.5,7.8]], 'S2': [[5,5.5],[7.8,8]], 'S3': [[None,5],[8,None]]}),
        'slope': requirement('durian', [0,8], classes={'S1': [[0,8]], 'S2': [[8,16]], 'S3': [[16,30]], 'N': [[30,None]]}),
    },
    'Mango': {
        'temperature': requirement('mango', [22,34]),
        'soil_ph': requirement('mango', [5.5,7.5]),
        'elevation': requirement('mango', [None,600]),
    },
    'Rubber': {
        'slope': requirement('rubber', [0,8], classes={'S1': [[0,8]], 'S2': [[8,30]], 'S3': [[30,None]]}),
        'elevation': requirement('rubber', [None,500], classes={'S1': [[None,500]], 'S2': [[500,1000]], 'S3': [[1000,None]]}),
        'rainfall': requirement('rubber', [1000,2000], classes={'S1': [[1000,2000]], 'S2': [[2001,4500]], 'S3': [[None,1000],[4500,None]]}),
        'soil_ph': requirement('rubber', [5.6,7.2], classes={'S1': [[5.6,7.2]], 'S2': [[4.5,5.5],[7.3,7.8]], 'S3': [[None,4.5],[7.9,None]]}),
    },
    'Cacao': {
        'temperature': requirement('cacao', [18,32]),
        'rainfall': requirement('cacao', [1250,3000]),
        'soil_ph': requirement('cacao', [5,7.5]),
        'humidity': requirement('cacao', [75,90]),
    },
}

def catalog():
    return {'version': VERSION, 'crops': [{'key': name.lower(), 'name': name,
        'local_relevance': {'verified': True, 'source': LOCAL_SOURCE, 'date': '2023-02-03'},
        'requirements': rules} for name, rules in REQUIREMENTS.items()]}


# Reference-only soil chemistry criteria. No compatible N/P/K criteria have
# been established for the stored CAGRO definitions/methods. Never populate this
# from model training ranges or fertilizer application/removal rates.
# Future entries require source {title, url/citation, section}, unit,
# nutrient_definition, method, limitations, optimal and optional absolute.
NUTRIENT_REQUIREMENTS = {crop: {} for crop in REQUIREMENTS}
