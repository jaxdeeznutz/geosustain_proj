# Authentication hardening ? 2026-10-19

Passwords were already stored as salted bcrypt hashes. This update retains existing hashes and explicitly uses cost 12. New registrations and password changes require at least 8 characters (up to 72 UTF-8 bytes for bcrypt), no whitespace, and at least one ASCII punctuation character, as requested by the user. Existing shorter passwords can still log in. Public signup always creates farmers; administrators assign privileged roles.

Changes:
- Shared password policy in API registration, HTML registration and password changes; matching Flutter length guidance.
- Unknown-user login performs a dummy bcrypt comparison. Invalid credentials use a generic error.
- Validation responses omit raw input values, protecting passwords from being echoed in errors.
- Authentication POSTs limited to 20 attempts per client IP per five minutes, including successful requests. Retry-After is returned. Buckets are bounded and expire.
- Cross-origin HTML login/registration submissions are rejected when Origin or Fetch Metadata identifies them as cross-site.
- Authentication responses are not cacheable. Session state is cleared before sign-in.
- Bearer tokens expire after 24 hours. Existing password-version checks revoke old tokens/sessions after password changes.
- Production requires a non-placeholder SECRET_KEY of at least 32 characters; development without a valid key uses a random process-local key. Production session cookies use Secure, HttpOnly (Starlette default), and SameSite=Lax.

## Deployment
Keep the existing strong SECRET_KEY; rotating it signs everyone out. Render is detected automatically. Other production hosting must set APP_ENV=production and use HTTPS. Configure proxy trust correctly so the ASGI client address is authentic. No database migration or password reset is needed. Changes have not been deployed.

## Remaining boundaries
This is not a complete security certification. The limiter is in process: multiple workers/instances require a shared or edge limiter, and restarts reset counters. Duplicate-email registration remains an explicit 409 for existing client compatibility. The legacy Flask entry point is not hardened here and must not be deployed. Flutter bearer tokens still use SharedPreferences; native secure storage and a web HttpOnly-cookie/session design remain follow-up work. Logout clears the client token; a copied bearer token remains valid until expiry/password change. Email ownership verification, password recovery delivery, MFA, a full breached-password list, and synchronizer CSRF tokens for all legacy HTML mutations are not implemented.

Guidance: https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html and https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html

Validation: 97 backend tests passed; focused Ruff checks passed. Tests mock external services and do not modify production accounts.
