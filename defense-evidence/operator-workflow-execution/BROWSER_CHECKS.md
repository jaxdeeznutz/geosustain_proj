# Actual browser observations

Target: Brave on Windows, local profile build of application commit `5ba2aca7146184337e1724e6c32c0e31d6fa2de0`, owned isolated QA backend. User signed in to the local synthetic analyst account. Checks performed on 27 October 2026.

- The first browser pass reproduced a direct `/operator/queue` URL showing Overview instead of the inbox.
- Navigation mixed the manual hash controller with Flutter's single-entry browser history. The final repair decodes direct/hash URLs, disables competing imperative Navigator reports and publishes portal locations through Flutter's multi-entry history API. Hosted operator/admin deep links receive explicit SPA rewrites.
- PASS locally: direct `/operator/queue` opens the inbox after session restoration.
- PASS locally: opening synthetic case #2 loads its saved analysis #4 and recorded-boundary evidence; unavailable measurements remain unavailable.
- PASS locally: browser Back restores the inbox; Forward restores case #2 and remains there after the asynchronous load. Reload retains the signed-in analyst and selected case. See `browser-final-history.txt`.
- PASS locally: Planning Map loads the independent submitted-case page with a status legend and explicit parcel-center scope. A synthetic unmatched query changes loaded distinct farms from 1 to 0; returning to Review Inbox retains its separate pending filter, two cases and no applied search. See `browser-map-inbox-independence.txt`.
- The saved text contains only the synthetic application accessibility subtree, excluding other browser tabs. The fixture's historical name includes “EMULATOR TEST ONLY”; no emulator was used for these checks.
- Actual 200% browser zoom, complete keyboard/focus audit, export download/print-dialog behavior and browser decision submission/correction journeys remain manual acceptance. Widget/API/PDF checks are recorded separately and do not replace these observations.
- Safari, screen-reader and full hosted role journeys remain separate acceptance targets.

No credentials or real farm payloads are included. These are local observations, not hosted role acceptance or adviser sign-off.
