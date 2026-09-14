# GeoSustain — Setup & Run Guide

AI-Driven Geospatial Decision Support System for Sustainable Landscape Management  
**Location:** Panabo City, Davao del Norte, Philippines

---

## Prerequisites

- Python 3.10+
- PostgreSQL 14+ (running locally or on a server)
- Google Earth Engine account (authenticated)

---

## 1. Create the PostgreSQL Database

Open pgAdmin or psql and run:

```sql
CREATE DATABASE geosustain_db;
```

The app creates all tables automatically on first run — you do not need to run any SQL manually.

---

## 2. Configure Environment Variables

Copy the example file and edit it:

```bash
cp .env.example .env
```

Edit `.env`:

```
DATABASE_URL=postgresql://postgres:YOUR_PASSWORD@localhost:5432/geosustain_db
SECRET_KEY=any-long-random-string
OPENWEATHER_API_KEY=your-openweather-key
```

---

## 3. Install Python Dependencies

```bash
pip install -r requirements.txt
```

---

## 4. Authenticate Google Earth Engine

Run once in your terminal:

```bash
earthengine authenticate
```

Follow the browser prompt. Your credentials are saved locally and reused automatically.

---

## 5. Run the App

```bash
python app.py
```

Open your browser at: **http://127.0.0.1:5000**

---

## Project Structure

```
geosustain/
├── app.py                  # Flask routes (auth + analysis API)
├── database.py             # PostgreSQL connection + all DB helpers
├── rainfallDatasets.py     # GEE data collection + Random Forest inference
├── train_model.py          # (Re)train the crop model if needed
├── crop_model.pkl          # Trained Random Forest model
├── Crop_recommendation.csv # Training dataset (22 crops)
├── requirements.txt
├── .env.example
├── static/
│   ├── app.js              # Frontend map + analysis logic
│   ├── style.css           # Dashboard styles
│   └── auth.css            # Login / register styles
└── templates/
    ├── login.html
    ├── register.html
    ├── index.html          # Main dashboard
    └── history.html        # Past analyses table
```

---

## User Roles

GeoSustain has three roles, and they have **different, backend-enforced permissions** — not shared access.

| Role | Access |
|------|--------|
| `farmer` | Mobile app. Manages their own profile, farms/boundaries, runs polygon-based analyses, submits for verification, views their own results/reports. Cannot see or touch other Farmers' data, cannot verify submissions, cannot change roles. |
| `agricultural_planning_analyst` | Web app. Reviews the Farmer verification queue, inspects submitted farm evidence, verifies/rejects submissions with notes. Cannot self-promote or assign roles. |
| `super_admin` | Web app. Manages users and roles, crop/reference data, and system configuration. The only role allowed to change another user's role. |

Role changes can **only** be made by a Super Administrator, through the admin user-management endpoint. No profile-update or registration request can set a user's own role to a privileged value — this is enforced on the backend regardless of what the client sends.

---

## Key Fixes Applied (from original code)

1. **Rainfall unit** — GEE CHIRPS daily mm is now multiplied × 30 to match the training dataset's monthly mm unit. This was the root cause of wrong crop predictions.
2. **Potassium baseline** — K corrected from 250 → 50 (within banana optimal range 45–55 in dataset).
3. **Full crop map** — all 22 dataset crops are now mapped to Panabo equivalents. Unmapped crops trigger a low-confidence advisory instead of showing "Apple" or "Grapes".
4. **Top-3 recommendations** — the system returns the top 3 Panabo-suitable crops, not just one.
5. **Suitability levels** — Highly Suitable / Moderately Suitable / Low Suitability labels added.
6. **DB persistence** — every analysis is saved to PostgreSQL under the logged-in user's account.

## Clean Folder Note

Backend files were moved into the `backend/` folder to make the project easier to view in VS Code.

Start backend on Windows:

```bat
start_backend.bat
```

Run Flutter:

```bat
run_flutter.bat
```
