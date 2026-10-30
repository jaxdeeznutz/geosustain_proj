"""Deterministic non-agricultural data for testing the isolated evaluation runner."""
import argparse
import json
from pathlib import Path
import sys

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from training.evaluate_models import FEATURES, file_hash, safe_output


def make_fixture(output, seed=731):
    output = safe_output(output)
    output.mkdir(parents=True, exist_ok=False)
    rng = np.random.default_rng(seed)
    rows = []
    scales = np.array([20, 15, 12, 3, 7, .4, 30, .1, 90, 3])
    for label_index, label in enumerate(('fixture_alpha', 'fixture_beta', 'fixture_gamma')):
        for group in range(30):
            latent = rng.normal(0, .7, len(FEATURES))
            center = np.array([label_index-.8, (label_index-1)**2, -label_index*.5,
                               label_index*.3, 0, .4*label_index, -.4*label_index,
                               label_index*.6, 0, label_index*.2])
            for observation in range(4):
                values = (center+latent+rng.normal(0, .8, len(FEATURES)))*scales
                rows.append({'observation_id': f'{label}-{group}-{observation}',
                             'independent_unit': f'{label}-group-{group}', 'label': label,
                             **dict(zip(FEATURES, np.round(values, 8)))})
    # One duplicate-feature observation nominally assigned to another unit.
    # The evaluator must join both declared units before any partitioning.
    for feature in FEATURES:
        rows[4][feature] = rows[0][feature]
    frame = pd.DataFrame(rows)
    dataset = output/'controlled.csv'
    frame.to_csv(dataset, index=False, lineterminator='\n')
    contract = {'schema_version': 1, 'purpose': 'controlled_fixture',
                'data_basis': 'synthetic_controlled', 'dataset_sha256': file_hash(dataset),
                'source': 'Seeded Gaussian numeric software fixture; arbitrary labels and scales. No crop, farm, sensor or field measurements.',
                'label_column': 'label', 'record_id_column': 'observation_id', 'group_column': 'independent_unit',
                'group_basis': 'Synthetic repeated-unit observations; shared latent numeric noise. Exact duplicate features join nominal units.',
                'feature_order': FEATURES,
                'features': {feature: {'unit': 'arbitrary_fixture_unit', 'period': 'synthetic_not_observed',
                                       'method': 'Seeded class offset plus unit and observation noise, scaled numerically; not a crop profile.',
                                       'source': 'controlled_fixture.py'} for feature in FEATURES},
                'generator': {'seed': seed, 'rows': len(frame), 'groups_before_duplicate_union': 90,
                              'script_sha256': file_hash(__file__)}}
    (output/'contract.json').write_text(json.dumps(contract, indent=2)+'\n', encoding='utf-8')
    return dataset, contract


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--seed', type=int, default=731)
    args = parser.parse_args()
    dataset, _ = make_fixture(args.output, args.seed)
    print(f'Created controlled software fixture: {dataset}; not agricultural validation.')


if __name__ == '__main__':
    main()
