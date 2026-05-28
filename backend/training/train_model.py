import pandas as pd
import numpy as np
import joblib
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report

# GeoSustain Random Forest training script
# Base dataset: Kaggle Crop_recommendation.csv
# Added GIS features: ndvi, elevation, slope
# Note: NDVI/elevation/slope are estimated feature ranges per crop type because
# the public crop dataset does not include geospatial columns.

RANDOM_SEED = 42
np.random.seed(RANDOM_SEED)

DATASET_PATH = 'Crop_recommendation.csv'
MODEL_PATH = 'crop_model.pkl'
FEATURES_PATH = 'crop_model_features.pkl'

print('Loading dataset...')
df = pd.read_csv(DATASET_PATH)

required = ['N', 'P', 'K', 'temperature', 'humidity', 'ph', 'rainfall', 'label']
missing = [c for c in required if c not in df.columns]
if missing:
    raise ValueError(f'Missing required columns: {missing}')

# Realistic geospatial feature ranges based on common crop ecology.
# These are NOT field-measured values; they are training proxies so the model
# can learn how GIS inputs such as NDVI, elevation, and slope influence suitability.
# Replace/retrain with field and validated agricultural data when available.
CROP_GIS_RANGES = {
    'rice':        {'ndvi': (0.45, 0.82), 'elevation': (0, 80),    'slope': (0, 5)},
    'maize':       {'ndvi': (0.35, 0.75), 'elevation': (5, 250),   'slope': (0, 12)},
    'banana':      {'ndvi': (0.55, 0.90), 'elevation': (5, 300),   'slope': (0, 10)},
    'coconut':     {'ndvi': (0.45, 0.85), 'elevation': (0, 120),   'slope': (0, 8)},
    'jute':        {'ndvi': (0.45, 0.82), 'elevation': (5, 150),   'slope': (0, 8)},  # maps to abaca locally
    'cotton':      {'ndvi': (0.35, 0.70), 'elevation': (20, 250),  'slope': (0, 12)}, # maps to abaca locally
    'coffee':      {'ndvi': (0.55, 0.88), 'elevation': (100, 800), 'slope': (3, 18)}, # maps to cacao locally

    'abaca':       {'ndvi': (0.58, 0.86), 'elevation': (80, 450),  'slope': (3, 18)},
    'cacao':       {'ndvi': (0.60, 0.88), 'elevation': (50, 500),  'slope': (2, 16)},
    'durian':      {'ndvi': (0.55, 0.84), 'elevation': (20, 350),  'slope': (1, 14)},
    'cassava':     {'ndvi': (0.35, 0.70), 'elevation': (0, 250),   'slope': (0, 12)},
    'sweet potato':{'ndvi': (0.35, 0.72), 'elevation': (0, 300),   'slope': (0, 14)},
    'rubber':      {'ndvi': (0.58, 0.88), 'elevation': (50, 450),  'slope': (2, 18)},
    'pomelo':      {'ndvi': (0.45, 0.78), 'elevation': (0, 250),   'slope': (0, 12)},
    'mango':       {'ndvi': (0.35, 0.75), 'elevation': (0, 250),   'slope': (0, 12)},
    'papaya':      {'ndvi': (0.45, 0.80), 'elevation': (0, 200),   'slope': (0, 10)},
    'mungbean':    {'ndvi': (0.30, 0.65), 'elevation': (0, 250),   'slope': (0, 10)},
    'pigeonpeas':  {'ndvi': (0.30, 0.65), 'elevation': (0, 350),   'slope': (0, 12)},
    'mothbeans':   {'ndvi': (0.25, 0.60), 'elevation': (0, 350),   'slope': (0, 12)},
    'blackgram':   {'ndvi': (0.30, 0.65), 'elevation': (0, 250),   'slope': (0, 10)},
    'lentil':      {'ndvi': (0.25, 0.60), 'elevation': (20, 400),  'slope': (0, 12)},
    'chickpea':    {'ndvi': (0.25, 0.60), 'elevation': (20, 400),  'slope': (0, 12)},
    'kidneybeans': {'ndvi': (0.30, 0.70), 'elevation': (100, 900), 'slope': (2, 18)},
    'watermelon':  {'ndvi': (0.30, 0.65), 'elevation': (0, 150),   'slope': (0, 8)},
    'muskmelon':   {'ndvi': (0.30, 0.65), 'elevation': (0, 150),   'slope': (0, 8)},
    # Non-local labels retained because they exist in the Kaggle dataset.
    'apple':       {'ndvi': (0.35, 0.75), 'elevation': (500, 2000),'slope': (3, 25)},
    'grapes':      {'ndvi': (0.30, 0.70), 'elevation': (50, 600),  'slope': (0, 15)},
    'orange':      {'ndvi': (0.35, 0.75), 'elevation': (50, 500),  'slope': (0, 15)},
    'pomegranate': {'ndvi': (0.30, 0.70), 'elevation': (20, 500),  'slope': (0, 15)},
}

DEFAULT_RANGE = {'ndvi': (0.35, 0.75), 'elevation': (0, 250), 'slope': (0, 12)}


# Local Mindanao / Davao crop training profiles.
# These rows are localized training augmentation based on typical crop suitability
# ranges and should be replaced/improved with validated agricultural and field datasets when available.
LOCAL_CROP_PROFILES = {
    # Extra localized profiles improve ML-only calibration for Panabo/Davao lowland crops.
    # Rainfall here uses the app's recent 30-day/CHIRPS style input, not annual rainfall.
    'rice': {
        'count': 160,
        'N': (55, 105), 'P': (35, 70), 'K': (35, 65),
        'temperature': (24.0, 31.0), 'humidity': (78, 96), 'ph': (5.5, 7.0),
        'rainfall': (80, 260), 'ndvi': (0.45, 0.82), 'elevation': (0, 90), 'slope': (0, 5),
    },
    'maize': {
        'count': 160,
        'N': (45, 125), 'P': (30, 60), 'K': (30, 60),
        'temperature': (24.0, 33.0), 'humidity': (55, 85), 'ph': (5.5, 7.2),
        'rainfall': (35, 170), 'ndvi': (0.35, 0.75), 'elevation': (0, 250), 'slope': (0, 12),
    },
    'banana': {
        'count': 160,
        'N': (60, 125), 'P': (52, 74), 'K': (48, 70),
        'temperature': (25.0, 32.0), 'humidity': (72, 90), 'ph': (5.5, 6.8),
        'rainfall': (70, 220), 'ndvi': (0.60, 0.90), 'elevation': (5, 180), 'slope': (0, 8),
    },
    'abaca': {
        'count': 160,
        'N': (45, 115), 'P': (35, 50), 'K': (38, 55),
        'temperature': (24.0, 29.0), 'humidity': (80, 92), 'ph': (5.6, 6.8),
        'rainfall': (180, 320), 'ndvi': (0.58, 0.86), 'elevation': (80, 450), 'slope': (3, 18),
    },
    'coconut': {
        'count': 160,
        'N': (35, 110), 'P': (25, 45), 'K': (50, 75),
        'temperature': (26.0, 32.0), 'humidity': (70, 86), 'ph': (5.8, 7.2),
        'rainfall': (120, 240), 'ndvi': (0.45, 0.82), 'elevation': (0, 120), 'slope': (0, 8),
    },
    'cacao': {
        'count': 160,
        'N': (40, 115), 'P': (32, 52), 'K': (45, 65),
        'temperature': (24.0, 30.0), 'humidity': (78, 90), 'ph': (5.5, 6.8),
        'rainfall': (160, 280), 'ndvi': (0.60, 0.88), 'elevation': (50, 500), 'slope': (2, 16),
    },
    'durian': {
        'count': 160,
        'N': (40, 115), 'P': (30, 48), 'K': (45, 70),
        'temperature': (25.0, 31.0), 'humidity': (72, 88), 'ph': (5.8, 7.0),
        'rainfall': (150, 260), 'ndvi': (0.55, 0.84), 'elevation': (20, 350), 'slope': (1, 14),
    },
    'cassava': {
        'count': 160,
        'N': (25, 100), 'P': (18, 38), 'K': (28, 55),
        'temperature': (25.0, 33.0), 'humidity': (60, 82), 'ph': (5.5, 7.5),
        'rainfall': (80, 180), 'ndvi': (0.35, 0.70), 'elevation': (0, 250), 'slope': (0, 12),
    },
    'sweet potato': {
        'count': 160,
        'N': (25, 100), 'P': (18, 40), 'K': (35, 65),
        'temperature': (24.0, 32.0), 'humidity': (62, 84), 'ph': (5.5, 7.0),
        'rainfall': (90, 190), 'ndvi': (0.35, 0.72), 'elevation': (0, 300), 'slope': (0, 14),
    },
    'rubber': {
        'count': 160,
        'N': (35, 110), 'P': (25, 45), 'K': (40, 65),
        'temperature': (25.0, 31.0), 'humidity': (72, 90), 'ph': (4.8, 6.5),
        'rainfall': (170, 300), 'ndvi': (0.58, 0.88), 'elevation': (50, 450), 'slope': (2, 18),
    },
    'pomelo': {
        'count': 160,
        'N': (35, 110), 'P': (25, 45), 'K': (40, 65),
        'temperature': (24.0, 31.0), 'humidity': (65, 85), 'ph': (5.8, 7.3),
        'rainfall': (110, 220), 'ndvi': (0.45, 0.78), 'elevation': (0, 250), 'slope': (0, 12),
    },
    'papaya': {
        'count': 160,
        'N': (35, 105), 'P': (35, 65), 'K': (35, 65),
        'temperature': (24.0, 33.0), 'humidity': (65, 88), 'ph': (5.8, 7.2),
        'rainfall': (80, 190), 'ndvi': (0.45, 0.80), 'elevation': (0, 200), 'slope': (0, 10),
    },
    'mango': {
        'count': 160,
        'N': (25, 90), 'P': (25, 55), 'K': (35, 65),
        'temperature': (25.0, 34.0), 'humidity': (55, 80), 'ph': (5.8, 7.5),
        'rainfall': (60, 160), 'ndvi': (0.35, 0.75), 'elevation': (0, 250), 'slope': (0, 12),
    },
    'watermelon': {
        'count': 160,
        'N': (35, 105), 'P': (35, 70), 'K': (30, 60),
        'temperature': (24.0, 34.0), 'humidity': (55, 78), 'ph': (5.8, 7.2),
        'rainfall': (35, 130), 'ndvi': (0.30, 0.65), 'elevation': (0, 150), 'slope': (0, 8),
    },
}

def _build_local_rows():
    rows = []
    for label, profile in LOCAL_CROP_PROFILES.items():
        for _ in range(profile['count']):
            row = {'label': label}
            for col in ['N', 'P', 'K']:
                lo, hi = profile[col]
                row[col] = int(np.random.randint(lo, hi + 1))
            for col in ['temperature', 'humidity', 'ph', 'rainfall', 'ndvi', 'elevation', 'slope']:
                lo, hi = profile[col]
                value = np.random.uniform(lo, hi)
                row[col] = round(value, 3 if col in ['ndvi', 'ph'] else 2)
            rows.append(row)
    return pd.DataFrame(rows)

def sample_range(label, key):
    r = CROP_GIS_RANGES.get(str(label).lower(), DEFAULT_RANGE)[key]
    return np.random.uniform(r[0], r[1])

# Add localized Mindanao crop rows before training.
# This makes the model able to output local crops directly instead of only mapping
# non-local Kaggle labels to local crop names.
local_df = _build_local_rows()
df = pd.concat([df, local_df], ignore_index=True)
print(f'Added localized crop rows: {len(local_df)}')

# Keep the model focused on crops that GeoSustain can reasonably recommend
# for Panabo/Mindanao. This is not rule-based prediction; it only prevents
# non-local classes from diluting Random Forest probabilities during training.
SUPPORTED_LABELS = {
    'rice', 'maize', 'banana', 'coconut', 'abaca', 'cacao', 'durian',
    'cassava', 'sweet potato', 'rubber', 'pomelo', 'papaya', 'mango',
    'watermelon', 'mungbean', 'pigeonpeas', 'blackgram',
}
df = df[df['label'].astype(str).str.lower().isin(SUPPORTED_LABELS)].copy()
print(f'Focused training rows after local crop filter: {len(df)}')
print('Training class counts:')
print(df['label'].value_counts().sort_index())

# Balance every supported crop to the same number of rows so no crop dominates.
# This is ML dataset balancing, not rule-based recommendation.
max_per_class = 260
balanced_parts = []
for label, group in df.groupby('label'):
    replace_rows = len(group) < max_per_class
    balanced_parts.append(group.sample(n=max_per_class, replace=replace_rows, random_state=RANDOM_SEED))
df = pd.concat(balanced_parts, ignore_index=True).sample(frac=1, random_state=RANDOM_SEED).reset_index(drop=True)
print('Balanced training class counts:')
print(df['label'].value_counts().sort_index())

# Add/replace GIS proxy columns for base rows that did not have GIS values.
# Keep local crop GIS values already generated above.
if 'ndvi' not in df.columns:
    df['ndvi'] = np.nan
if 'elevation' not in df.columns:
    df['elevation'] = np.nan
if 'slope' not in df.columns:
    df['slope'] = np.nan

df['ndvi'] = df.apply(lambda r: round(sample_range(r['label'], 'ndvi'), 3) if pd.isna(r.get('ndvi')) else r['ndvi'], axis=1)
df['elevation'] = df.apply(lambda r: round(sample_range(r['label'], 'elevation'), 2) if pd.isna(r.get('elevation')) else r['elevation'], axis=1)
df['slope'] = df.apply(lambda r: round(sample_range(r['label'], 'slope'), 2) if pd.isna(r.get('slope')) else r['slope'], axis=1)

features = ['N', 'P', 'K', 'temperature', 'humidity', 'ph', 'rainfall', 'ndvi', 'elevation', 'slope']
X = df[features]
y = df['label']

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.20, random_state=RANDOM_SEED, stratify=y
)

print('Training Random Forest with GIS features...')
model = RandomForestClassifier(
    n_estimators=500,
    max_depth=14,
    min_samples_leaf=6,
    min_samples_split=12,
    max_features='sqrt',
    random_state=RANDOM_SEED,
    class_weight='balanced_subsample',
    n_jobs=-1,
)
model.fit(X_train, y_train)

pred = model.predict(X_test)
acc = accuracy_score(y_test, pred)
print(f'Model Training Complete! Accuracy: {acc * 100:.2f}%')
print(classification_report(y_test, pred, zero_division=0))

joblib.dump(model, MODEL_PATH)
joblib.dump(features, FEATURES_PATH)
df.to_csv('Crop_recommendation_with_gis.csv', index=False)

print(f'Saved model: {MODEL_PATH}')
print(f'Saved feature list: {FEATURES_PATH}')
print('Saved augmented dataset: Crop_recommendation_with_gis.csv')
