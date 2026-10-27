---
name: geosustain-web-data
description: "Implement truthful GeoSustain web resource loading/error/stale states and bounded server page/search fetching."
---

# Fix resource states, refresh and large-record loading

Use [Phase 04](../../PHASE_04_Data_States_Refresh_and_Pagination.md) for work items and acceptance. Read [web execution rules](../../EXECUTION_RULES.md) and the relevant review findings before changes.

These instructions refine decisions for this web phase; they do not supply provider credentials, scientific validation or new external authorization.

- Initial failure, valid empty, search no-match and refresh failure with old data are different states. Do not show an unavailable resource or failed count as a confirmed empty result.
- A History button should navigate if presented as navigation; the current common Refresh Data button only refreshes weather. Match the action to the current resource or rename it precisely.
- Rendered 20-row pagination is not bounded loading if ApiService first downloads every 50-row history page. Keep aggregate metric scope independent from a loaded page.
- Guard delayed responses by owner/query/route epoch; existing valid panels should survive independent failures.
- Measure the compiled browser network path on a named owned dataset. Prior SQL query latency does not establish browser first-page speed or inference throughput.

Record actual outcomes in the project tracker and `defense-evidence/web-fix-execution/phase-04/`. If a prerequisite is absent, state the missing input and continue independent authorized work rather than converting the case to PASS.
