"""Read-only deployment verification; does not initialize DB or providers."""
import argparse
import json

from model_artifacts import load_model_artifact


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected-version', help='Required SHA-256 of crop_model.pkl')
    parser.add_argument('--require-training-metadata', action='store_true')
    args = parser.parse_args()
    loaded = load_model_artifact(expected_version=args.expected_version,
                                 require_metadata=args.require_training_metadata)
    status = loaded.health()
    print(json.dumps(status, indent=2))
    return 1 if status['restart_required'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
