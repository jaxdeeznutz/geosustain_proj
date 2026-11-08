"""Reference-based seasonal moisture screening, independent of trained scores.

Monthly P/ETo is a reconnaissance proxy, not the complete FAO growing-period
water balance: effective rainfall, soil storage, irrigation and local calibration
are not available. Crop growth references are not seedling survival thresholds.
"""
from calendar import month_name, monthrange
from datetime import date
from math import acos, cos, isfinite, pi, radians, sin, sqrt, tan

VERSION = 'seasonal-planting-v1'
WINDOW_MONTHS = 4  # Application preview horizon, not a crop maturity duration.
SOURCES = {
    'fao_moisture': {
        'title': 'FAO: Land evaluation for rainfed agriculture, A.1.1',
        'url': 'https://www.fao.org/4/x5648e/x5648e0e.htm',
        'criterion': 'Reconnaissance moisture comparison: precipitation versus 0.5 and 1.0 potential evapotranspiration.',
    },
    'fao_eto': {
        'title': 'FAO Irrigation and Drainage Paper 56, Chapter 3, equation 52',
        'url': 'https://www.fao.org/4/X0490E/x0490e07.htm',
        'criterion': 'Hargreaves reference evapotranspiration estimate; Ra must be expressed as equivalent mm/day. Local checking/calibration is advised.',
    },
    'nasa_processing': {
        'title': 'NASA POWER: Temporal Processing, extreme-value parameters',
        'url': 'https://power.larc.nasa.gov/docs/methodology/data/processing/',
        'criterion': 'T2M_MAX_AVG and T2M_MIN_AVG are averages of daily extremes. Monthly T2M_MAX/T2M_MIN extremes are not substituted in the ETo calculation.',
    },
    'banana': {
        'title': 'DA-ATI SOCCSKSARGEN: Banana production guide, Planting Time',
        'url': 'https://ati2.da.gov.ph/ati-12/content/sites/default/files/2023-02/banana-iec-pdf.pdf',
        'criterion': 'Prefer rainy-season onset; planting at other times requires adequate moisture.',
    },
    'cacao': {
        'title': 'DA-HVCDP: Cacao Production Guide, Planting',
        'url': 'https://hvcdp.da.gov.ph/wp-content/uploads/2022/05/Cacao-Production-Guide.pdf',
        'criterion': 'Field planting at rainy-season onset.',
    },
    'cacao_dry': {
        'title': 'International Cocoa Organization: Growing Cocoa, Rainfall',
        'url': 'https://www.icco.org/growing-cocoa/',
        'criterion': 'Dry spells with less than 100 mm/month should not exceed three months; general growing-climate guidance.',
    },
    'coconut': {
        'title': 'PNS/BAFS 238:2018: Good Agricultural Practices for Coconut, section 4.4.3',
        'url': 'https://www.pca.gov.ph/images/cocotech/PNS_BAFS_238_2018_Code_of_Good_Agricultural_Practices_for_Coconut.pdf',
        'criterion': 'Plant seedlings at rainy-season onset.',
    },
    'coconut_rain': {
        'title': 'COLEAD: Coconut production guide, section 1.2.1',
        'url': 'https://eservices.colead.link/en/system/files/file_fields/2025/05/26/production-guide-coconutseng-light.pdf',
        'criterion': 'Around 150 mm/month is an optimum rainfall reference, not a minimum seedling establishment threshold.',
    },
    'durian': {
        'title': 'DA SOCCSKSARGEN: Durian Production Guide, Planting',
        'url': 'https://hvcdp.da.gov.ph/wp-content/uploads/2022/05/Durian-Production-Guide-koronadal-new.pdf',
        'criterion': 'Start planting at rainy-season onset.',
    },
    'durian_rain': {
        'title': 'Indonesia Ministry of Agriculture: Buku Lapang Budidaya Durian (2021), page 2',
        'url': 'https://ppid.pertanian.go.id/pemberitahuan_attachment/15/14811/Buku%20Lapang%20Durian%202021.pdf',
        'criterion': 'Growing-climate profile: wet months >100 mm, dry months <50 mm; 7-10 wet and 2-4 dry months. Indonesian guidance, not a reviewed Panabo calendar.',
    },
    'mango': {
        'title': 'DA CARAGA: Giya sa Pagpananum ug Manga, Transplanting and Pagpatubig',
        'url': 'https://hvcdp.da.gov.ph/wp-content/uploads/2022/05/Giya-sa-Pagpananum-ug-Manga-with-cover.pdf',
        'criterion': 'Transplant at the start of rains and water young trees during establishment/dry conditions; flowering management is a different stage.',
    },
    'rice': {
        'title': 'DA-PhilRice: PalayCheck System (2020), Key Check 3',
        'url': 'https://www.philrice.gov.ph/wp-content/uploads/2020/07/Palaycheck-system-2020-revised-edition-for-trainers-and-extensionist.pdf',
        'criterion': 'Follow the local planting calendar and water availability; coordinate planting with the community.',
    },
    'rubber': {
        'title': 'DA-HVCDP: Rubber Plantation Establishment, printed page 5',
        'url': 'https://hvcdp.da.gov.ph/wp-content/uploads/2022/05/Rubber-Production-Guide.pdf',
        'criterion': 'Prefer planting when rainy weather is expected.',
    },
}
CROPS = ('Banana', 'Cacao', 'Coconut', 'Durian', 'Mango', 'Rice', 'Rubber')


def eto_month(lat, year, month, mean, minimum, maximum):
    """FAO-56 eqs 21-25,52, using monthly means of daily temperatures.

    Average extraterrestrial radiation over every actual day of the month;
    convert MJ/m2/day to mm/day with 0.408 before using equation 52.
    """
    values = (lat, mean, minimum, maximum)
    if any(isinstance(v, bool) or not isinstance(v, (int, float)) or not isfinite(v) for v in values):
        return None
    if not (-90 <= lat <= 90 and -90 <= minimum < maximum <= 65 and minimum <= mean <= maximum):
        return None
    phi = radians(lat)
    total = 0.0
    for day in range(1, monthrange(year, month)[1] + 1):
        j = date(year, month, day).timetuple().tm_yday
        dr = 1 + .033 * cos(2 * pi * j / 365)
        delta = .409 * sin(2 * pi * j / 365 - 1.39)
        angle = max(-1.0, min(1.0, -tan(phi) * tan(delta)))
        ws = acos(angle)
        ra_mj = 24 * 60 / pi * .0820 * dr * (ws * sin(phi) * sin(delta) + cos(phi) * cos(delta) * sin(ws))
        total += max(0.0, .0023 * (mean + 17.8) * sqrt(maximum - minimum) * ra_mj * .408)
    return total if total > 0 and isfinite(total) else None


def longest_dry_run(values):
    if any(value is None for value in values):
        return None
    longest = run = 0
    for value in values * 2:  # December -> January is a consecutive sequence.
        run = run + 1 if value < 100 else 0
        longest = min(12, max(longest, run))
    return longest


def assess_crop(crop, cycle, month):
    rows = {row.get('month'): row for row in cycle}
    window = [rows.get((month - 1 + offset) % 12 + 1, {}) for offset in range(WINDOW_MONTHS)]
    selected = window[0]
    adequate = all(row.get('moisture_status') in ('humid', 'intermediate', 'dry') for row in window)
    rain = selected.get('rainfall_mm') if selected.get('rainfall_status') == 'available' else None
    status = 'unavailable'
    reasons, checks = [], []
    if adequate:
        dry = [month_name[row['month']] for row in window if row['moisture_status'] == 'dry']
        intermediate = [month_name[row['month']] for row in window if row['moisture_status'] == 'intermediate']
        status = 'water_support_needed' if dry else 'conditional' if intermediate else 'favorable_moisture'
        if dry:
            reasons.append('Rainfall is below half the estimated reference evapotranspiration in ' + ', '.join(dry) + '; confirm a dependable water supply before planting.')
        elif intermediate:
            reasons.append('Rainfall is below estimated reference evapotranspiration in ' + ', '.join(intermediate) + '; supplemental water may be needed.')
        else:
            reasons.append('Historical monthly rainfall equals or exceeds estimated reference evapotranspiration in the selected month and the next three months; actual root-zone water is not measured.')
    else:
        reasons.append('Complete monthly rainfall and temperature evidence for the selected month and the next three months is needed for moisture screening.')
    source_keys = [crop.lower(), 'fao_moisture', 'fao_eto', 'nasa_processing']
    if crop == 'Cacao':
        source_keys.append('cacao_dry')
        dry_run = longest_dry_run([rows.get(m, {}).get('rainfall_mm') if rows.get(m, {}).get('rainfall_status') == 'available' else None for m in range(1, 13)])
        checks.append({'name': 'Longest typical dry spell (<100 mm/month)', 'value': dry_run, 'unit': 'consecutive months', 'source_id': 'cacao_dry'})
        if dry_run is not None and dry_run > 3:
            reasons.append(f'The typical yearly pattern has {dry_run} consecutive months below 100 mm, exceeding the cacao reference; review irrigation for long-term establishment.')
            if status == 'favorable_moisture':
                status = 'conditional'
        if rain is not None and rain < 100:
            reasons.append('The selected month is dry under the cacao reference (<100 mm); young plants need moisture protection.')
            if status == 'favorable_moisture':
                status = 'conditional'
    elif crop == 'Coconut':
        source_keys.append('coconut_rain')
        checks.append({'name': 'Selected-month rain versus ~150 mm/month growing-climate reference', 'value': rain, 'unit': 'mm/month', 'source_id': 'coconut_rain'})
        if rain is not None and rain < 150:
            reasons.append('Selected-month rainfall is below the approximately 150 mm/month coconut reference; check stored soil moisture and watering.')
            if status == 'favorable_moisture':
                status = 'conditional'
    elif crop == 'Durian':
        source_keys.append('durian_rain')
        wet_count = sum(row.get('rainfall_status') == 'available' and row['rainfall_mm'] > 100 for row in rows.values())
        complete = len(rows) == 12 and all(row.get('rainfall_status') == 'available' for row in rows.values())
        checks.append({'name': 'Typical wet months (>100 mm/month)', 'value': wet_count if complete else None, 'unit': 'months/year', 'source_id': 'durian_rain'})
        if rain is not None and rain <= 100:
            reasons.append('This is not a wet month under the cited durian climate profile (>100 mm); confirm watering for new seedlings.')
            if status == 'favorable_moisture':
                status = 'conditional'
        if complete and not 7 <= wet_count <= 10:
            reasons.append('The number of wet months differs from the Indonesian 7-10-month profile; this is a regional reference difference, not proof the farm is unsuitable.')
    elif crop == 'Rice':
        reasons.append('Rice planting also depends on variety duration, field water and the local irrigation/community calendar; these are not established by monthly rain alone.')
        if status == 'favorable_moisture':
            status = 'conditional'
    elif crop == 'Mango':
        reasons.append('This advice is for establishing young trees. Dry-weather flowering requirements of mature mango trees are a separate assessment.')
    reasons.append(SOURCES[crop.lower()]['criterion'])
    labels = {'favorable_moisture': 'Moisture supports planting', 'conditional': 'Check water and planting conditions',
              'water_support_needed': 'Seasonal water support needed', 'unavailable': 'Seasonal assessment unavailable'}
    if crop == 'Rice' and status == 'conditional':
        labels['conditional'] = 'Check irrigation and planting schedule'
    return {'crop': crop, 'status': status, 'label': labels[status], 'selected_month': month,
            'reasons': reasons, 'reference_checks': checks, 'source_ids': source_keys,
            'window_months': [(month - 1 + offset) % 12 + 1 for offset in range(WINDOW_MONTHS)],
            'stage': 'Crop establishment; not flowering, harvest timing or full lifetime suitability'}


def planting_assessment(baseline, month, enabled_crops=None):
    cycle = baseline.get('monthly_cycle') or []
    enabled = {str(c).lower() for c in enabled_crops} if enabled_crops is not None else None
    names = [c for c in CROPS if enabled is None or c.lower() in enabled]
    crops = [assess_crop(crop, cycle, month) for crop in names]
    selected = next((row for row in cycle if row.get('month') == month), {})
    moisture = selected.get('moisture_status', 'unavailable')
    for crop in crops:
        # Monthly candidates meet only the defined moisture checks. They are
        # neither an official planting calendar nor a new crop ranking.
        crop['moisture_supported_months'] = [m for m in range(1, 13) if assess_crop(crop['crop'], cycle, m)['status'] == 'favorable_moisture']
    return {
        'version': VERSION, 'title': 'Seasonal planting assessment',
        'selected_month_moisture': {
            'status': moisture,
            'label': {'humid': 'Wet conditions', 'dry': 'Dry conditions',
                      'intermediate': 'Transitional conditions'}.get(moisture, 'Seasonal conditions unavailable'),
            'basis': 'Historical monthly rainfall versus estimated reference evapotranspiration; not an official wet/dry season declaration or forecast.',
        },
        'status': 'available' if crops and all(c['status'] != 'unavailable' for c in crops) else 'partial' if any(c['status'] != 'unavailable' for c in crops) else 'unavailable',
        'basis': 'Published-reference seasonal moisture screening using historical monthly climate; not a trained seasonal prediction',
        'window_description': 'Selected month plus the next three calendar months; application screening horizon, not crop maturity duration',
        'water_supply_assumption': 'Rainfall-based screening. Irrigation, field soil moisture, drainage and water storage are unknown.',
        'local_validation': 'Reference-based prototype; moisture estimates and advisory rules have not been field-validated in Panabo.',
        'moisture_method': 'Monthly total gridded rainfall / Hargreaves estimated reference ETo: dry <0.5, intermediate 0.5 to <1, humid >=1. This proxy omits effective rainfall and soil storage; it is not the complete FAO growing-period method.',
        'crops': crops, 'sources': {key: dict(value) for key, value in SOURCES.items()},
        'model_ranking_effect': 'none', 'forecast': False,
    }
