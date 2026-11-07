"""Record reviewed published facts without fabricating complete training rows."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SOURCE_URL = 'https://www.musalit.org/viewPdf.php?file=IN000103_eng.pdf&id=5704'
SABA_URL = 'https://cagayandeoro.da.gov.ph/wp-content/uploads/2013/04/SABA-BANANA-PRODUCTION-GUIDE.pdf'
LAKATAN_URL = 'https://www.yumpu.com/en/document/view/45523019/practical-lakatan-production-management-for-the-local-market'
PROVINCE_URL = 'https://davaodelnorte.gov.ph/images/jf/docs/plans_programs/pdpfp_2008-2022/davnor_pdpfp2008-2022.pdf'


def write(path, value):
    path.write_bytes((json.dumps(value, indent=2, ensure_ascii=False) + '\n').encode('utf-8'))


def build():
    sources = {
        'bpi_imtp_2000': {
            'title': 'BPI trial reports in Evaluating bananas: a global partnership. Results of IMTP Phase II',
            'publisher': 'INIBAP', 'compiler': 'G. Orjeda', 'year': 2000, 'url': SOURCE_URL,
            'catalogue_url': 'https://www.musalit.org/seeMore.php?id=5704',
            'reviewed_printed_pages': [109, 110, 134], 'reviewed_pdf_pages': [109, 110, 132],
            'evidence_kind': 'published_trial_site_conditions_and_genotype_means',
            'source_sha256': '2ac556da6fdfaaf0cea36bacf85b0273e5a241e2f05d8d79590f2caeb31df4b9'},
        'saba_da_guide': {'title': 'DA/BPI Saba Banana Production Guide', 'url': SABA_URL,
                          'evidence_kind': 'published_growing_guidance', 'geography': 'Philippines; not a Panabo trial',
                          'retrieval': 'Official document indexed text; direct download timed out'},
        'lakatan_smiarc_2007': {'title': 'DA RFU XI / SMIARC: Practical Lakatan Production and Management for the Local Market',
            'year': 2007, 'url': LAKATAN_URL, 'publisher': 'Department of Agriculture RFU XI, Bago Oshiro, Davao City',
            'source_location': 'Third-party mirror of the government technoguide; indexed pages 1-2 reviewed',
            'evidence_kind': 'published_growing_guidance'},
        'davnor_plan': {'title': 'Davao del Norte Provincial Development and Physical Framework Plan, 2008-2022',
            'url': PROVINCE_URL, 'evidence_kind': 'historical_provincial_crop_presence',
            'limitation': 'Provincial presence does not establish present Panabo farm locations or crop success.'},
        'tadeco': {'title': 'ANFLOCOR: TADECO', 'url': 'https://www.anflocor.com/tadeco',
                   'evidence_kind': 'Panabo_Cavendish_production_presence'},
    }
    requirements = {
        'cavendish': [],
        'lakatan': [
            {'factor': 'ph', 'min': 4.5, 'max': 7.5, 'preferred_value': 6.5, 'unit': 'pH', 'period': 'soil_method_and_depth_not_specified', 'source_id': 'lakatan_smiarc_2007'},
            {'factor': 'temperature', 'min': 15, 'max': 35, 'unit': 'C', 'period': 'growing_conditions_not_five_year_mean', 'source_id': 'lakatan_smiarc_2007'},
            {'factor': 'elevation', 'min': 1.5, 'max': 1000, 'unit': 'm', 'period': 'terrain', 'source_id': 'lakatan_smiarc_2007'},
            {'factor': 'rainfall', 'value': 100, 'unit': 'mm/month', 'period': 'monthly_guidance',
             'original_value': 10, 'original_unit': 'cm/month', 'annual_conversion_performed': False, 'source_id': 'lakatan_smiarc_2007'}],
        'saba': [
            {'factor': 'ph', 'min': 4.5, 'max': 7.5, 'unit': 'pH', 'period': 'soil_method_and_depth_not_specified', 'source_id': 'saba_da_guide'},
            {'factor': 'temperature', 'min': 27, 'max': 30, 'unit': 'C', 'period': 'favourable_growing_conditions_not_five_year_mean', 'source_id': 'saba_da_guide'},
            {'factor': 'rainfall', 'min': 1524, 'unit': 'mm/year', 'period': 'annual',
             'original_value': 60, 'original_unit': 'inches/year', 'conversion': '60 * 25.4',
             'condition': 'Even rainfall distribution; dry periods may require viable irrigation.', 'source_id': 'saba_da_guide'}],
    }
    published = {'schema_version': 1, 'sources': sources, 'requirements_by_variety': requirements,
        'numeric_slope_limits_established': False, 'numeric_ndvi_limits_established': False,
        'automatic_model_score_adjustment': False, 'used_as_training_rows': False,
        'limitation': 'Requirement ranges are not statistical training observations. Source periods/methods must be checked before comparison. Monthly Lakatan rainfall is not converted to an annual requirement; trial conditions are not optimum ranges.'}
    write(HERE / 'published_requirements.json', published)
    bago = {'site_id': 'bpi-bago-oshiro', 'location': 'Bago Oshiro, Davao City', 'latitude': 7+5/60,
            'trial_purpose': 'IMTP Sigatoka disease evaluation',
            'longitude': 125+36/60, 'planted_at': '1996-06-20', 'temperature_c': 26,
            'humidity_pct': None, 'humidity_range_pct': [83,86], 'soil_ph': 5.4,
            'rainfall_mm_year': None, 'rainfall_description': 'Evenly distributed; numeric annual total not stated on this page',
            'ndvi': None, 'elevation_m': 100, 'slope_pct': None, 'terrain_description': 'Plain',
            'soil_texture': 'clay loam', 'irrigation': 'available', 'drainage': 'moderate',
            'source_id': 'bpi_imtp_2000', 'printed_page': 109, 'pdf_page': 109}
    santo = {'site_id': 'bpi-santo-tomas', 'location': 'Santo Tomas, Davao del Norte', 'latitude': 7+30/60,
             'trial_purpose': 'IMTP Fusarium wilt evaluation',
             'longitude': 125+39/60, 'planted_at': None, 'temperature_c': 27,
             'humidity_pct': 84, 'humidity_range_pct': None, 'soil_ph': 6.7, 'rainfall_mm_year': 3416,
             'rainfall_description': 'Evenly distributed, with a small April peak', 'ndvi': None,
             'elevation_m': 39, 'slope_pct': None, 'terrain_description': 'Plain', 'soil_texture': 'clay loam',
             'irrigation': 'irrigated', 'drainage': 'good', 'source_id': 'bpi_imtp_2000', 'printed_page': 134, 'pdf_page': 132}
    records = []
    for variety, site, bunch in [('lakatan',bago,10.4),('saba',bago,20.5),('saba',santo,27.6)]:
        records.append({'record_id': site['site_id']+'-'+variety, 'observed_variety': variety,
                        'site_context': deepcopy(site), 'reported_mean_bunch_weight_kg': bunch,
                        'observation_level': 'published_genotype_mean_with_shared_trial_site_context',
                        'individual_plant_records_available': False, 'sample_count': None,
                        'observed_at': None, 'model_training_ready': False})
    trials = {'schema_version': 1, 'records': records, 'record_count': 3, 'independent_sites': 2,
              'complete_model_training_rows': 0, 'used_for_fitting': False,
              'limitation': 'These are published aggregate disease-trial results, not individual Panabo farm measurements or best-variety labels. Disease pressure, irrigation and cultivar material affect the reported means. NDVI and numeric slope are missing. Climate averaging periods, soil methods/depths and exact observation dates are not documented here; do not present these as the app seven-input contract. Humidity ranges remain ranges, with no midpoint imputation.'}
    write(HERE / 'published_trial_observations_partial.json', trials)
    asset = ROOT / 'assets/data/banana_varieties.json'
    data = json.loads(asset.read_text(encoding='utf-8'))
    data['version'] = 'banana-variety-reference-v2-published-evidence'
    data['local_scope_note'] = 'Cavendish production is documented in Panabo. A historical Davao del Norte plan also identifies Lakatan and Saba in the province. BPI trial sites are in Davao City and Santo Tomas; current Panabo variety shares were not established.'
    data['guidance_scope_note'] = 'Published guide values and trial context are reference information. They do not create separate variety model scores or verified Panabo suitability limits.'
    lines = {
        'cavendish': ['Documented production: A.O. Floirendo, Panabo.'],
        'lakatan': ['Guide: soil pH 4.5-7.5; growing temperature 15-35 C.', 'Guide: elevation 1.5-1,000 m. Avoid standing water.'],
        'saba': ['Guide: soil pH 4.5-7.5; favourable growing temperature 27-30 C.', 'Guide: at least 1,524 mm/year, with rainfall distribution and irrigation considered.'],
    }
    for profile in data['profiles']:
        key = profile['variety_key']
        if key == 'cavendish':
            profile['description'] = 'Fresh fruit and export banana.'
        profile['guidance_lines'] = lines[key]
        profile['environmental_references'] = requirements[key]
        profile['published_trial_record_ids'] = [r['record_id'] for r in records if r['observed_variety'] == key]
        ids = ['tadeco'] if key == 'cavendish' else ['davnor_plan', 'bpi_imtp_2000', 'lakatan_smiarc_2007' if key == 'lakatan' else 'saba_da_guide']
        urls = {s['url'] for s in profile['sources']}
        profile['sources'].extend({'title':sources[k]['title'],'url':sources[k]['url']} for k in ids if sources[k]['url'] not in urls)
    write(asset, data)
    write(HERE / 'evidence_manifest.json', {'schema_version':1,'source_retrieval':'Official/indexed source text plus a downloaded BPI PDF, relevant full pages read and visually reviewed.',
        'sources': sources, 'files_sha256': {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [HERE/'published_requirements.json',HERE/'published_trial_observations_partial.json']},
        'real_aggregate_trial_records':3,'complete_compatible_training_rows':0,'production_model_changed':False})
    print(json.dumps({'reference_profiles':3,'published_aggregate_records':3,'complete_compatible_training_rows':0,'production_model_changed':False}))


if __name__ == '__main__':
    build()
