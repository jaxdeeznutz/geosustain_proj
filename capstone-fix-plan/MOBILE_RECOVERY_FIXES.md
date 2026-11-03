# Mobile result crash, recovery and navigation fixes

Owner report: farmer crop summaries show `double is not a subtype of bool?`;
farms/analysis show repeated unavailable errors after use; remove Switch
analysis and the duplicate Farm Details coverage prose; clarify Google signup.

## Changes

- Farmer disclosures previously had no PageStorageKey. Under the keyed Analysis
  scroll view, ExpansionTile read the stored double scroll offset as a bool.
  Each disclosure now has its own record-scoped expansion key. Children remain
  lazy through Builder, including when Flutter restores an expanded tile.
  Related boundary and source-detail expanders get distinct record-scoped keys.
- Safe authenticated farm/history/record/status reads use the existing bounded
  warmup retry (three attempts, 30 seconds per attempt, 2/4 second backoff).
  Retry checks account identity before each read and before returning. Actual
  401/403 responses are not retried or converted into a successful login.
- After a gateway error on an analysis POST, the client checks the existing
  idempotency key and recovers a completed/in-flight result. It does not blindly
  repeat the write. Interrupted requests remain explicitly checkable/retryable.
- A transport error could leave offlineWorkspace true indefinitely. A deliberate
  online analysis retry now refreshes connectivity before deciding it is still
  offline; locally queued farms still require sync. Account/selection isolation
  and the original analysis calculation are preserved.
- Starting a new farm analysis clears its old local error. A completed analysis
  with an unavailable history refresh shows a separate retry-history control.
- Analysis has a header back button to My Farms. The Switch analysis sheet is
  removed; previous results remain available through History/farm records.
- Farm Details goes directly from farm identity/area to its boundary map.
  Duplicate coverage paragraphs and the CoverageExplorer panel are removed
  there. Unsupported coverage still blocks analysis with a short message;
  scientific provenance/limitations remain in actual analysis details/reports.
- Google signup already checks the backend Google subject and verified email:
  a genuinely new email creates a Farmer and requires one-time password setup.
  An email already in GeoSustain cannot create a duplicate account. The 409
  message now opens a dialog offering the existing password or another Google
  account. Existing password entry is prefilled with the selected Google email
  when available; explicit profile linking remains required. Cancelling creates
  no application session or duplicate account.

No backend, model, source observations, crop ranking or scientific criteria are
changed. The prior Review Inbox UI update remains in the same working tree.

## Verification and limits

```powershell
.\deployment\verify-mobile-recovery.ps1
```

The verifier checks all 137 tracked backend hashes, offline dependency
resolution, full Flutter analysis/tests, the Firebase-enabled Web build and a
Firebase-enabled debug APK. It includes the new mobile recovery tests and the
pending Review Inbox regressions. The APK uses the normal package and this
computer's registered debug signing certificate.

The agent reran the existing identity/password setup backend contracts:
43 passed, 4 warnings. This supports the new-user versus existing-email
behavior without changing the backend. Dart parsing/formatting and script/hash
checks are available locally; protected package-cache access prevents full
agent-side Flutter acceptance. The owner must run the verifier and inspect the
installed build.

The owner subsequently supplied Render logs confirming missing humidity after
Open-Meteo daily rate limiting, and confirmed no primary OpenWeather key is
configured. See [provider quota repair](PROVIDER_QUOTA_RECOVERY.md). The earlier
UI-only backend integrity statement above describes the mobile repair before
that separate provider fix. Use `verify-provider-recovery.ps1` for the combined
candidate; do not rewrite the UI-only baseline. No live provider success is
claimed. Client recovery alone cannot reset a provider's daily quota.
No service is restarted or deployed and no user data is cleared.
