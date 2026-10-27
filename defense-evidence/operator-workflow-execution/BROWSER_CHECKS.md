# Actual browser observations

Target: Brave on Windows, local development build, owned isolated QA backend. User signed in to the local synthetic analyst account.

- The first browser pass reproduced a direct `/operator/queue` URL showing Overview instead of the inbox.
- Navigation mixed the manual hash controller with Flutter authentication route reporting. Source repair adds direct/hash decoding, a non-reporting web Navigator, controlled pushState and popstate observation. Hosted operator/admin deep links receive explicit SPA rewrites.
- Updated-build Back/reload/case/map/zoom/print checks are in progress. This file must be updated with actual outcomes before any browser PASS is claimed.
- Safari, screen-reader and full hosted role journeys remain separate acceptance targets.

No credentials or real farm payloads are included.
