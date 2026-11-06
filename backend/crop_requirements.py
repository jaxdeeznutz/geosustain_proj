"""Published reference checks, frozen for new analyses; not trained-model validation."""
VERSION = 'panabo-annual-terrain-references-2026-11-06-v5'
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
    'coconut_elevation': {'url': 'https://ati2.da.gov.ph/ati-7/content/sites/default/files/2023-09/Coconut%20Specialist%20Course%20%28ISBN%29.pdf', 'title': 'DA Agricultural Training Institute (2022), Coconut Specialist Course Facilitators Guide', 'section': 'Table 6, printed p.80 / PDF p.93, Altitude (MASL), coconut column', 'scope': 'Published coconut growing-condition recommendation from a coconut-based farming guide, citing DA/PCA Davao Research Center. Below 600 m is a recommendation, not a universal survival limit or a complete suitability class. Cultivar, climate, soil depth, drainage and management need separate assessment.'},
    'durian_elevation': {'url': 'https://hvcdp.da.gov.ph/wp-content/uploads/2022/05/Durian-Production-Guide-koronadal-new.pdf', 'title': 'Department of Agriculture, Durian Production Guide', 'section': 'PDF p.3, introductory growing conditions', 'scope': 'Philippine production guide recommends areas below 800 m; no optimum lower altitude or S1/S2/S3 classes are supplied. This altitude check alone does not assess temperature, drainage, soil depth, water supply or cultivar.'},
    'cacao_elevation': {'url': 'https://www.bswm.da.gov.ph/wp-content/uploads/DAVAO_DEL_NORTE_SUITABILITY_CACAO.pdf', 'title': 'BSWM: Davao del Norte Land Suitability Map for Cacao', 'section': 'PDF p.3, Agronomic requirement of cacao production, Elevation (masl)', 'scope': 'Provincial BSWM altitude classes selected for Panabo; the conflicting altitude wording in the cacao roadmap is not combined with these classes. This is one factor, not a complete land suitability grade. Shade, drainage, soil depth and land-cover exclusions remain separate.'},
    'banana_slope': {'url': 'https://publikasi.agroforestri.id/sites/all/modules/publication/data/softcopy/manual/MN0037-07.pdf', 'title': 'Ritung et al. (2007), Land Suitability Evaluation', 'section': 'Annex 11, printed p.33 / PDF p.40, Erosion hazard: slope (%)', 'scope': 'Musa acuminata slope criteria from Indonesia, transferred for preliminary Panabo comparison; not locally validated or variety-specific. This slope factor does not establish soil depth, drainage, erosion rate or overall land suitability.'},
    'coconut_slope': {'url': 'https://publikasi.agroforestri.id/sites/all/modules/publication/data/softcopy/manual/MN0037-07.pdf', 'title': 'Ritung et al. (2007), Land Suitability Evaluation', 'section': 'Annex 3, printed p.25 / PDF p.32, Erosion hazard: slope (%)', 'scope': 'Coconut slope criteria from Indonesia, transferred for preliminary Panabo comparison; not locally validated. Management, erosion protection, drainage and soil depth need separate assessment.'},
    'mango_slope': {'url': 'https://doi.org/10.3390/su15032619', 'title': 'Salunkhe et al. (2023), Land Suitability Planning for Sustainable Mango Production in Vulnerable Region Using Geospatial Multi-Criteria Decision Model', 'section': 'Table 1 continued, PDF p.7, Slope (%)', 'scope': 'Published mango slope classes used in Ratnagiri, India, transferred for preliminary Panabo comparison; not locally validated for Philippine cultivars. Only the slope criterion is adopted, not the study AHP weights, climate ranges, conservation assumptions or reported accuracy.'},
    'cacao_slope': {'url': 'https://www.bswm.da.gov.ph/wp-content/uploads/DAVAO_DEL_NORTE_SUITABILITY_CACAO.pdf', 'title': 'BSWM: Davao del Norte Land Suitability Map for Cacao', 'section': 'PDF p.3, Agronomic requirement of cacao production, Slope (%)', 'scope': 'Published cacao slope classes for the province containing Panabo. Slope alone does not establish shade, soil depth, drainage, flooding or overall suitability. The source separately excludes existing forest, shrubland above 18% slope, irrigated paddy and miscellaneous land types; the slope grade does not override land-cover safeguards.'},
    'rice_terrain': {'url': 'https://www.bswm.da.gov.ph/wp-content/uploads/Davao-del-Norte_SUITABILITY-rice.pdf', 'title': 'BSWM (2016): Davao del Norte Rice Suitability Map', 'section': 'Sheet 1, Agronomic requirements, Terrain: slope (%)', 'scope': 'Published rice slope classes for the province containing Panabo. This is one factor only; drainage, flooding, stoniness and soil depth are not assessed by slope.'},
    'banana': {'url': 'https://ecocrop.apps.fao.org/ecocrop/srv/en/dataSheet?id=2483', 'title': 'FAO EcoCrop: Musa sp.', 'section': 'Ecology', 'scope': 'Species-level tropical screening; no variety distinctions. Temperature is interpreted as climate mean for screening, not daily extremes.'},
    'rice': {'url': 'https://ecocrop.apps.fao.org/ecocrop/srv/en/dataSheet?id=1574', 'title': 'FAO EcoCrop: Oryza sativa', 'section': 'Ecology / wet-rice system', 'scope': 'Wet rice. Annual rainfall does not establish irrigation availability or growing-season water balance.'},
    'coconut': {'url': 'https://www.fao.org/4/af298e/af298E01.htm', 'title': 'FAO: Pasture-Cattle-Coconut Systems', 'section': '1.2', 'scope': 'General tropical coconut climate. Rainfall distribution also matters.'},
    'durian': {'url': 'https://apps.worldagroforestry.org/downloads/publications/PDFs/mn15224.pdf', 'title': 'Ritung et al. (2007), Land Suitability Evaluation', 'section': 'Annex 9, printed p.31 / PDF p.38', 'scope': 'Indonesian criteria transferred for preliminary Panabo screening; not locally validated. Full land classes require additional drainage, soil and hazard assessments.'},
    'coconut_ph': {'url': 'https://apps.worldagroforestry.org/downloads/publications/PDFs/mn15224.pdf', 'title': 'Ritung et al. (2007), Land Suitability Evaluation', 'section': 'Annex 3, printed p.25 / PDF p.32', 'scope': 'Indonesian coconut soil criteria; only pH used alongside general FAO climate ranges.'},
    'mango': {'url': 'https://www.da.gov.ph/wp-content/uploads/2023/05/Philippine-Mango-Industry-Roadmap.pdf', 'title': 'Philippine Mango Industry Roadmap 2021–2025', 'section': 'Table 29, printed p.76 / PDF p.97', 'scope': 'Philippine mango. Distinct dry season is required but not assessed; the stated temperature interval is used only as a climate screening range.'},
    'cacao': {'url': 'https://faolex.fao.org/docs/pdf/phi229725.pdf', 'title': 'Philippine Cacao Industry Roadmap 2021–2025', 'section': 'Appendix 1, printed p.84', 'scope': 'Philippine cacao. Uses narrative maximum 32 C. Conflicting elevation recommendations on this page are not used; a separately cited provincial BSWM elevation criterion is configured. Shade, drainage and dry-season duration need field assessment.'},
    'rubber': {'url': 'https://bswm.da.gov.ph/wp-content/uploads/DAVAO_DEL_SUR_SUITABILITY_RUBBER.pdf', 'title': 'BSWM (2019): Davao del Sur Land Suitability Map for Rubber', 'section': 'Sheet 1, Agronomic requirement of rubber production', 'scope': 'Philippine rubber criteria transferred from neighbouring province. Gaps between printed decimal/integer intervals remain unassessed; not interpolated.'},
    'durian_annual': {'url': 'https://apps.worldagroforestry.org/treedb/AFTPDFS/Durio_zibethinus.PDF',
        'title': 'Orwa et al. (2009), Agroforestry Database 4.0: Durio zibethinus',
        'section': 'PDF page 2, Biophysical limits and Ecology',
        'scope': 'Published general annual rainfall interval, not a locally validated S1 class. Rainfall distribution, flowering dry spell, soil depth and drainage are not established by the annual total.'},
    'mango_annual': {'url': 'https://ecocrop.apps.fao.org/ecocrop/srv/en/dataSheet?id=1416',
        'title': 'FAO EcoCrop: Mangifera indica', 'section': 'Ecology, Rainfall (annual)',
        'scope': 'Global ecological annual rainfall ranges. The Philippine mango dry-period requirement remains separate and is not established by an annual total.'},
    'rubber_annual': {'url': 'https://apps.worldagroforestry.org/treedb/AFTPDFS/Hevea_brasiliensis.PDF',
        'title': 'Orwa et al. (2009), Agroforestry Database 4.0: Hevea brasiliensis',
        'section': 'PDF page 2, Biophysical limits and Ecology',
        'scope': 'Published general annual rainfall interval and upper maximum, not a locally validated S1 class. Drainage, rainfall distribution, soil depth and groundwater remain unassessed.'},
}

def requirement(source, optimal, absolute=None, classes=None):
    return {'source': SOURCES[source], 'optimal': optimal, 'absolute': absolute,
            'classes': classes, 'limitations': SOURCES[source]['scope']}

# Ranges are inclusive unless optimal_upper_exclusive is explicitly set.
# For adjacent published classes, the more limiting class
# owns a shared endpoint; explicit < boundaries are represented in the evaluator.
REQUIREMENTS = {
    'Banana': {
        'elevation': {**requirement('banana', [None,2400]), 'range_label': 'Published altitude limit', 'range_basis': 'absolute_limit', 'limitations': SOURCES['banana']['scope'] + ' EcoCrop gives only an absolute upper altitude of 2400 m, not an optimum. This checks that limit alone; a coconut-banana intercropping altitude is not substituted as a universal banana limit.'},
        'temperature': requirement('banana', [22, 32], [13, 38]),
        'rainfall': requirement('banana', [2400, 2700], [2000, 3500]),
        'soil_ph': requirement('banana', [5, 7], [4.5, 7.5]),
        'slope': {**requirement('banana_slope', [0,8], classes={'S1': [[0,8]], 'S2': [[8,16]], 'S3': [[16,30]], 'N': [[30,None]]}), 'range_label': 'S1 slope range (below 8%)'},
    },
    'Coconut': {
        'elevation': {**requirement('coconut_elevation', [None,600]), 'range_label': 'Published altitude recommendation', 'range_basis': 'published_altitude_limit', 'optimal_upper_exclusive': True},
        'temperature': requirement('coconut', [27, 32]),
        'rainfall': requirement('coconut', [1250, 2250]),
        'soil_ph': requirement('coconut_ph', [5.2, 7.5], classes={'S1': [[5.2,7.5]], 'S2': [[4.8,5.2],[7.5,8]], 'S3': [[None,4.8],[8,None]]}),
        'slope': {**requirement('coconut_slope', [0,8], classes={'S1': [[0,8]], 'S2': [[8,16]], 'S3': [[16,30]], 'N': [[30,None]]}), 'range_label': 'S1 slope range (below 8%)'},
    },
    'Rice': {
        'temperature': requirement('rice', [20, 30], [10,36]),
        'rainfall': requirement('rice', [1500,2000], [1000,4000]),
        'soil_ph': requirement('rice', [5.5,7], [4.5,9]),
        'slope': requirement('rice_terrain', [0,3], classes={'S1': [[0,3]], 'S2': [[3,8]], 'S3': [[8,18]], 'N': [[18,None]]}),
        'elevation': {**requirement('rice', [None,2500]), 'range_label': 'Published altitude limit', 'range_basis': 'absolute_limit', 'limitations': SOURCES['rice']['scope'] + ' EcoCrop gives only an absolute upper altitude of 2500 m, not an optimum. This checks that limit alone.'},
    },
    'Durian': {
        'elevation': {**requirement('durian_elevation', [None,800]), 'range_label': 'Published altitude recommendation', 'range_basis': 'published_altitude_limit', 'optimal_upper_exclusive': True},
        'temperature': requirement('durian', [25,28], classes={'S1': [[25,28]], 'S2': [[22,25],[28,32]], 'S3': [[20,22],[32,35]], 'N': [[None,20],[35,None]]}),
        'rainfall': {**requirement('durian_annual', [1500,2000]),
            'range_label': 'Published annual range', 'range_basis': 'general_biophysical_interval'},
        'soil_ph': requirement('durian', [5.5,7.8], classes={'S1': [[5.5,7.8]], 'S2': [[5,5.5],[7.8,8]], 'S3': [[None,5],[8,None]]}),
        'slope': requirement('durian', [0,8], classes={'S1': [[0,8]], 'S2': [[8,16]], 'S3': [[16,30]], 'N': [[30,None]]}),
    },
    'Mango': {
        'temperature': requirement('mango', [22,34]),
        'rainfall': requirement('mango_annual', [600,1500], [300,2600]),
        'soil_ph': requirement('mango', [5.5,7.5]),
        'elevation': {**requirement('mango', [None,600]), 'range_label': 'Published altitude recommendation', 'range_basis': 'published_altitude_limit'},
        'slope': {**requirement('mango_slope', [0,8], classes={'S1': [[0,8]], 'S2': [[8,16]], 'S3': [[16,30]], 'N': [[30,None]]}), 'range_label': 'S1 slope range (below 8%)'},
    },
    'Rubber': {
        'slope': requirement('rubber', [0,8], classes={'S1': [[0,8]], 'S2': [[8,30]], 'S3': [[30,None]]}),
        'elevation': {**requirement('rubber', [None,500], classes={'S1': [[None,500]], 'S2': [[500,1000]], 'S3': [[1000,None]]}), 'range_label': 'S1 altitude range (below 500 m)', 'optimal_upper_exclusive': True},
        'rainfall': {**requirement('rubber_annual', [1500,3000]),
            'range_label': 'Published annual range', 'range_basis': 'general_biophysical_interval',
            'published_upper_extension': 4000},
        'soil_ph': requirement('rubber', [5.6,7.2], classes={'S1': [[5.6,7.2]], 'S2': [[4.5,5.5],[7.3,7.8]], 'S3': [[None,4.5],[7.9,None]]}),
    },
    'Cacao': {
        'elevation': {**requirement('cacao_elevation', [None,1000], classes={'S1': [[None,1000]], 'S2': [[1000,1500]], 'S3': [[1500,None]]}), 'range_label': 'S1 altitude range (below 1000 m)', 'optimal_upper_exclusive': True},
        'temperature': requirement('cacao', [18,32]),
        'rainfall': requirement('cacao', [1250,3000]),
        'soil_ph': requirement('cacao', [5,7.5]),
        'humidity': requirement('cacao', [75,90]),
        'slope': {**requirement('cacao_slope', [0,8], classes={'S1': [[0,8]], 'S2': [[8,30]], 'S3': [[30,None]]}), 'range_label': 'S1 slope range (below 8%)'},
    },
}

def catalog():
    return {'version': VERSION, 'crops': [{'key': name.lower(), 'name': name,
        'local_relevance': {'verified': True, 'source': LOCAL_SOURCE, 'date': '2023-02-03'},
        'requirements': rules} for name, rules in REQUIREMENTS.items()]}


def annual_rainfall_references():
    """Public metadata for reference checks, not learned estimator parameters."""
    from copy import deepcopy
    return {'version': VERSION, 'scope': 'annual_rainfall_reference_checks',
            'affects_fitted_model': False, 'model_accuracy_validation': 'not_established',
            'crops': {name.lower(): deepcopy(rules['rainfall']) for name, rules in REQUIREMENTS.items()}}


def slope_references():
    """Frozen crop-specific slope evidence; no fitted-model weights or labels."""
    from copy import deepcopy
    return {'version': VERSION, 'scope': 'crop_specific_slope_reference_checks',
            'unit': '%', 'period': 'terrain', 'affects_fitted_model': False,
            'crops': {name.lower(): deepcopy(rules['slope']) for name, rules in REQUIREMENTS.items()}}


def elevation_references():
    """Saved altitude evidence, independent of learned model parameters."""
    from copy import deepcopy
    return {'version': VERSION, 'scope': 'crop_specific_elevation_reference_checks',
            'unit': 'm', 'period': 'terrain', 'affects_fitted_model': False,
            'crops': {name.lower(): deepcopy(rules['elevation']) for name, rules in REQUIREMENTS.items()}}


# Reference-only soil chemistry criteria. No compatible N/P/K criteria have
# been established for the stored CAGRO definitions/methods. Never populate this
# from model training ranges or fertilizer application/removal rates.
# Future entries require source {title, url/citation, section}, unit,
# nutrient_definition, method, limitations, optimal and optional absolute.
NUTRIENT_REQUIREMENTS = {crop: {} for crop in REQUIREMENTS}
