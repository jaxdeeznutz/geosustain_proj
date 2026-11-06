"""Read-only actual-artifact and annual-input/XAI replay; no live providers."""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
import pandas as pd

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))
from climate_contract import (PROTOTYPE_MODE, annual_model_ready, annual_prototype_policy,
                              mark_annual_prototype)
from model_artifacts import APPROVED_LABELS, FEATURES, load_model_artifact
from model_explainability import FEATURE_LABELS, forest_snapshot
from model_ranking import attach_model_ranking
from crop_requirements import annual_rainfall_references, slope_references, elevation_references
from training.activate_colab_no_npk import MODEL_VERSION as COLAB_MODEL_VERSION

EXPECTED_VERSION = '55ee230b370ea90071df7d32dcb209f916b2dcfa77a6522dd264d10e830f7eaf'
SOURCE_HASHES = {
    'Crop_recommendation.csv': '54a5a6e5408668e668667efc50de2fc867c1b875e0431b4f54dd331b0a109a4e',
    'Crop_recommendation_with_gis.csv': '1a6dcf3b22c20ff51c0ef7eee310df3ad5d359263d78d1a93e2dbaa7245ec03a',
}


def verify(output=None):
    loaded = load_model_artifact()
    if loaded.version not in (EXPECTED_VERSION, COLAB_MODEL_VERSION):
        raise ValueError('Expected an exact verified owner-selected prototype artifact.')
    if set(loaded.model.classes_) != APPROVED_LABELS or not annual_prototype_policy(loaded.metadata, loaded.model.classes_):
        raise ValueError('Expected the exact seven-crop explicit annual-input prototype.')
    if annual_model_ready(loaded.model, loaded.metadata):
        raise ValueError('The unvalidated experiment must not claim reviewed annual training.')
    if loaded.metadata.get('elevation_reference_requirements') != elevation_references():
        raise ValueError('Saved seven-crop elevation reference metadata differs from the catalog.')
    if loaded.metadata.get('slope_reference_requirements') != slope_references():
        raise ValueError('Saved seven-crop slope reference metadata differs from the catalog.')
    if loaded.metadata.get('reference_requirements') != annual_rainfall_references():
        raise ValueError('Active model metadata must include the selected seven-crop annual reference evidence.')
    for name, expected in SOURCE_HASHES.items():
        if hashlib.sha256((BACKEND / name).read_bytes()).hexdigest() != expected:
            raise ValueError(f'Original source CSV changed: {name}')
    samples = []
    # Synthetic numbers test software routing/reconstruction, not agronomic validity.
    for i in range(9):
        complete = dict(zip(FEATURES, [80 + i, 55, 46, 27, 80, 6, 2100 + 10 * i, .6, 30, 3]))
        names = list(loaded.model.feature_names_in_)
        inputs = {name: complete[name] for name in names}
        frame = pd.DataFrame([inputs], columns=names)
        scores = loaded.model.predict_proba(frame)[0]
        sample = forest_snapshot(loaded.model, loaded.version, inputs, loaded.model.predict(frame)[0],
            dict(zip(map(str, loaded.model.classes_), map(float, scores))),
            feature_labels={**FEATURE_LABELS, 'rainfall': ('Annual rainfall (5-year mean)', 'mm/year')})
        sample['runtime_input_policy'] = deepcopy(loaded.metadata['runtime_input_policy'])
        if 'N' not in names:
            sample['samples'][0]['npk_used'] = False
        sample['samples'][0]['model_climate_inputs'] = {
            'rainfall': {'value': inputs['rainfall'], 'unit': 'mm/year', 'period': 'annual_mean_total',
                         'quality': 'modelled', 'source': 'Controlled software fixture, not field data'}}
        samples.append(sample)
    result = mark_annual_prototype(attach_model_ranking({}, samples))
    local = result['local_model_explanation']
    if local['status'] != 'available' or set(local['class_order']) != APPROVED_LABELS:
        raise ValueError('Local explanation failed verification.')
    scores = np.mean([list(s['samples'][0]['class_probabilities'].values()) for s in samples], axis=0)
    np.testing.assert_allclose(local['model_scores'], scores, rtol=0, atol=1e-12)
    np.testing.assert_allclose(np.asarray(local['base_values']) + np.sum(local['contributions'], axis=1),
                               local['model_scores'], rtol=0, atol=1e-9)
    rain = next(item for item in local['feature_definitions'] if item['feature'] == 'rainfall')
    if rain['unit'] != 'mm/year' or any(s['samples'][0]['inputs']['rainfall'] < 2100 for s in samples):
        raise ValueError('Raw annual rainfall input/attribution label changed.')
    if output:
        output = Path(output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    return {'verified': True, 'model_version': loaded.version, 'class_count': len(loaded.model.classes_),
            'classes': list(map(str, loaded.model.classes_)), 'metadata_status': loaded.metadata_status,
            'model_usage': result['model_usage'], 'feature_count': len(loaded.model.feature_names_in_),
            'npk_used': 'N' in loaded.model.feature_names_in_, 'annual_input': 'raw mm/year; no conversion to 30-day rainfall',
            'source_csvs_unchanged': True, 'sample_count': 9, 'local_explanation': 'verified',
            'annual_reference_metadata': 'verified; reference evidence only',
            'slope_reference_metadata': 'all seven crops verified; reference checks only',
            'elevation_reference_metadata': 'all seven crops verified; reference checks only',
            'annual_training_validated': False, 'live_provider_validation': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.output), indent=2))
