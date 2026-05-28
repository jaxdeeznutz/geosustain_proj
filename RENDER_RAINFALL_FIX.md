# Render Rainfall Fix

This ZIP keeps your working project but improves rainfall fetching for Render.

What changed:
- CHIRPS via Google Earth Engine is still the primary rainfall source.
- If CHIRPS fails on Render, Open-Meteo is now used as a stronger online backup.
- The Open-Meteo backup uses no API key and should not fall back unless the network/API fails.
- Model/static/template paths were made Render-safe.
- A root `render.yaml` was added so Render can deploy from the full project root.

Render environment variables to check:
- `GEE_SERVICE_ACCOUNT_JSON` = full Earth Engine service account JSON
- `GEE_PROJECT_ID` = your Google Cloud / Earth Engine project ID
- `DATABASE_URL` = your Render PostgreSQL URL, if using Render DB
- `SECRET_KEY` = any long random string

After uploading/pushing:
1. Push this project to GitHub.
2. In Render, redeploy using **Manual Deploy > Clear build cache & deploy**.
3. Test this in browser:
   `https://YOUR-RENDER-URL.onrender.com/api/health`
4. Analyze a land point. In the response/details, rainfall source should show either:
   - `CHIRPS DAILY 30-day rainfall via Google Earth Engine`, or
   - `Open-Meteo Archive 30-day rainfall backup`

If it still says fallback, open Render logs. The new logs will show why CHIRPS/Open-Meteo failed.
