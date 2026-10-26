# Web session decision

The current split Vercel/Render deployment retains the existing signed bearer
API contract. Tokens remain JavaScript-accessible in browser preferences; this
does not provide HttpOnly protection and is an explicit residual script/XSS risk,
not a demonstrated exploit. Moving authentication into third-party cookies
without an owned same-site/session design would introduce new cross-site cookie,
CSRF and browser compatibility problems and would not preserve all clients.

The server enforces the existing 24-hour token maximum, active-user checks,
password-version checks and per-session revocation. Browser startup asks the
server to validate stored identity. An already rejected session now clears local
state directly rather than requiring another successful logout network request.
Normal online logout still confirms server revocation before clearing the client.

Desktop delete/deactivate uses a separate owner-authenticated endpoint requiring
the current password or a recent validated proof for the exact linked Google
subject. It is quota limited and preserves the existing database lifecycle and
last-admin safeguards. The UI confirms consequences, prevents duplicate pending
actions, retains useful state after failure and leaves protected routes only
after confirmed success. Credentials/proofs are not stored in UI preferences.

Root/built-output Vercel policies restrict embedding and MIME interpretation.
The new build emits only allowlisted public configuration; there are no injected
server keys or HTML-rendered untrusted record strings. Live host policy presence,
real browser session expiry/logout/account switching and future script dependency
review remain acceptance requirements. This is a hardened bearer decision, not
a claim that XSS is impossible or browser storage is encrypted.

A future HttpOnly migration should use a reviewed same-site gateway/domain and
test Secure/HttpOnly/SameSite, CSRF, CORS, recovery/revocation, all intended browser
modes and the shared mobile API. No cookie migration or mobile storage change is
made by this web repair.
