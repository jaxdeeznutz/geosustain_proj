# Published workflow candidate

On 27 October 2026, GitHub main received `6957ae5a57efca0f0ba95e29e2ba7d6e2c96b296`. Both the Vercel build manifest and Render health response subsequently reported that exact commit. Render deployment `dep-dbg7sk1srm7s73cpbqog` showed **Deploy succeeded | Live**, duration 2m06s.

- Frontend: https://geosustain.vercel.app/
- API: https://geosustain.onrender.com/
- Public evidence: `public-after.json`, `public-artifact-verification.json`.
- The retrieved compiled JavaScript SHA-256 matches the hosted manifest. Operator queue/map and admin SPA deep links return HTML successfully.
- The new operator inbox returns HTTP 401 without authentication. No production review decisions, farms or accounts were created for this public smoke check.
- API health is HTTP 200. Readiness remains HTTP 503: database and model are ready, required email configuration is unavailable. This gate was already present before publication and has not been bypassed.

The deployed commit changes only evidence/documentation after the locally tested application commit `5ba2aca`. Git comparison confirms no intervening changes in lib, web, assets, pubspec files, backend, deployment or vercel.json. The Windows local build and hosted Linux build have different fingerprints/artifact hashes; each is identified separately, and hosted JavaScript was verified against its own manifest.

Later evidence-only commits may trigger an equivalent frontend rebuild; the observations above identify the actual deployed release at verification time. Hosted signed-in analyst/farmer journeys and provider receipt remain separate acceptance targets. The Render dashboard also displays a workspace payment warning; deployment succeeded, and no billing changes were made.
