# Password login update

Registration now creates a PostgreSQL user immediately and returns to login. Firebase, SMTP and email verification are not required. Passwords remain bcrypt-hashed; plaintext is never accepted by login. Farmer/analyst land-analysis verification is unchanged.

## Existing users and database migration

The supplied screenshot appears to contain one plaintext password in `password_hash`; the other shown values appear to be bcrypt hashes. This is evidence of mixed password storage, not proof of why every account fails. Existing bcrypt passwords are preserved. Firebase provider labels alone do not determine whether a password works.

Use the backend's existing DATABASE_URL and SECRET_KEY. This release has not been deployed and no live database records have been changed.

1. Back up the database. Stop the old backend while migrating so it cannot create new pending registrations.
2. From `backend`, install `requirements.txt` and run `python migrate_password_auth.py`. This previews the transaction and rolls it back. It prints counts and IDs needing attention, never passwords.
3. If a reported user's stored password is confirmed to be plaintext, add `--plaintext-user-ids USER_ID`. Replace USER_ID with the actual numeric ID. Do not use this option for unknown hash formats or Firebase-only credentials; those require a password reset. Do not replace correct bcrypt hashes manually.
4. Review the dry-run output, then repeat the same command with `--apply` to commit.
5. Deploy the updated backend and Flutter web/mobile builds together. Refresh/reload the Vercel application and test with an existing account and a new signup.

The migration normalizes email addresses, adds a case-insensitive unique index, marks supported password accounts as `auth_provider='email'`, clears obsolete OTP values, and promotes pending registrations only when they do not conflict with existing users. Unsupported password formats are reported for reset. A duplicate normalized email aborts the migration for manual resolution. IDs, farm records, existing active status and existing user roles are preserved. It does not falsely mark unverified email addresses as verified; `email_verified` remains historical and is no longer a login gate. Legacy columns and unpromoted pending rows are retained to avoid losing account data.

The admin user table now displays the sign-in method instead of the obsolete email-verification icon. The migration updates provider labels only when a usable bcrypt hash is present or an explicitly confirmed plaintext password was converted.

## If an existing bcrypt account still fails

Confirm the Render backend DATABASE_URL points at the same database shown in your table, and the Flutter API_BASE_URL points at that backend. Check that the stored bcrypt value is complete (normally 60 characters), the account is active and the submitted password is the original exact password. Email is normalized; password spaces/case are intentionally preserved. Firebase passwords cannot be recovered from a provider label. A wrong password or incompatible hash requires a controlled reset, not bypassing password verification.

## Running

Backend: `uvicorn fastapi_app:app --host 0.0.0.0 --port 8000`

Web: `flutter build web --release --dart-define=API_BASE_URL=https://YOUR-BACKEND`

Old verification URLs now redirect to password login (HTML) or return HTTP 410 (API); they never issue tokens. The optional Flask backend has also been updated, but FastAPI is the supported deployment entry point.

## Validation for this release

- 26 Python tests passed, including authentication and migration safeguards.
- 8 Flutter tests passed; Flutter analyzer reported no issues.
- Release web build passed, including the Wasm dry run.
- Python syntax and Ruff F checks passed.
- Four dataset/model files are byte-for-byte unchanged.

Tests use mocked database calls; the migration has not been executed against your live PostgreSQL database. Full login with your real accounts remains unverified until migration and deployment. Existing FastAPI/Starlette deprecation warnings remain.

The source ZIP excludes generated build files, local secrets and machine-specific caches. Keep your existing deployment environment variables; configure your local backend environment separately. The separate web ZIP contains the tested build with the existing default backend URL https://geosustain.onrender.com.
