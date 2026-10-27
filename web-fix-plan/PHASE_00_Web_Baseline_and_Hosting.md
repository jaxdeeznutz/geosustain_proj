# Phase 00: Verify the deployed web baseline and hosting

[Plan index](README.md) · [Execution rules](EXECUTION_RULES.md) · [Issue crosswalk](ISSUE_CROSSWALK.md)

**Status:** PARTIAL — see current execution below.

**Goal:** Identify the actual frontend/backend candidate and make intended hosting policies effective before accepting subsequent live fixes.

**Primary skill:** [geosustain-web-baseline](skills/geosustain-web-baseline/SKILL.md). Read this skill before executing the phase.

**Dependencies:** None; this establishes the candidate baseline.

Dependencies establish baseline/final acceptance order. Provider setup in Phase 01 does not block independent source fixes in Phases 02–05; its live gates remain open until completed.

**Issues owned:** WEB-02: Prepared Vercel security headers are absent from the checked live responses, WEB-03: The live frontend has no verified link to the reviewed source revision

## Relevant implementation

- [web/index.html](../web/index.html)
- [deployment/vercel.json](../deployment/vercel.json)
- [deployment/RELEASE_HANDOVER.md](../deployment/RELEASE_HANDOVER.md)
- [.github/workflows/render-health-check.yml](../.github/workflows/render-health-check.yml)

## External inputs and limitations

Vercel project/build/root settings and Render configuration must be available through owned access. A missing connector does not justify guessing deployment identity.

## Work and acceptance

### W00-01: Record the actual frontend and backend candidate

Capture source commit, GitHub main, Vercel deployment commit, Flutter SDK/build flags, API origin, public JS hash and backend /health revision. Compare to the dated review. A hash mismatch alone is not proof of an old build. Add a small non-secret build/version identifier if the deployed frontend has none.

**Acceptance:** A tester can identify the exact web and API versions without secrets, and evidence distinguishes reviewed source from deployed behavior.

**Evidence:** baseline.json; frontend/backend identity screenshots or API metadata.

**Initial status:** NOT_STARTED.

### W00-02: Apply the frontend response policies

Inspect Vercel root/build/output settings and ensure the prepared header rules actually reach the deployed site. Retain Flutter/Firebase/map/report compatibility; avoid introducing a blanket script policy without testing required resources. Check HTML, bootstrap, JS, worker and public Firebase configuration cache behavior.

**Acceptance:** Intended frame, MIME and referrer policies are present on the checked live responses, assets have deliberate cache rules, and sign-in/maps/report loading still work.

**Evidence:** before/after public response headers and functional smoke.

**Initial status:** NOT_STARTED.

### W00-03: Publish a matching testable candidate and upgrade path

Use a matching frontend/API candidate after source changes are reviewed. Record the previous compatible release, configuration ownership, backup/recovery procedure and data reconciliation window before schema changes. Test a fresh browser and a browser with the prior cached build. Never publish credentials or historical personal evidence.

**Acceptance:** Fresh and returning browsers load the intended complete candidate; no mixed web assets/API are credited as a pass; the previous release is identified.

**Evidence:** deployment manifest, cache upgrade observations, rollback preparation.

**Initial status:** NOT_STARTED.

### W00-04: Separate liveness, readiness and browser availability

Record /health and /ready independently, including the known email_configuration gap. Define useful monitoring/receipt ownership without treating the ten-minute health workflow as uptime or real delivery proof. Record one warm and one naturally cold startup when observable; do not manufacture production outages.

**Acceptance:** Monitoring notes distinguish healthy process, configured required services, actual browser workflow and recipient delivery. Email setup can remain pending while independent code phases continue.

**Evidence:** readiness snapshot, startup observations and monitor ownership.

**Initial status:** NOT_STARTED.

## Focused verification

- **WEB-02:** Fetch the deployed frontend responses and confirm intended headers; verify normal login, maps, PDF export and configured Firebase still work.
- **WEB-03:** The deployed frontend commit/build identity is visible and matches the intended candidate; a returning browser loads the new candidate without mixed assets.
- Use the installed computer-use skill only when an actual supported browser surface is available; otherwise record manual user steps/outcomes explicitly.

## Exit and handover

Store actual execution under `defense-evidence/web-fix-execution/phase-00/`; start from [EVIDENCE_TEMPLATE.json](EVIDENCE_TEMPLATE.json). Link source/frontend/backend identity, expected versus actual results, test/provider/browser scope and remaining gates.

The phase is complete only when its full acceptance is supported. Source-only fixes can be handed on with pending live dependencies recorded; do not mark the whole phase complete from a build or plan file.

| Task | Current state | Evidence | Remaining gate |
| --- | --- | --- | --- |
| W00-01 | COMPLETE | Current execution below | A tester can identify the exact web and API versions without secrets, and evidence distinguishes reviewed source from deployed behavior. |
| W00-02 | CODE_COMPLETE | Current execution below | Intended frame, MIME and referrer policies are present on the checked live responses, assets have deliberate cache rules, and sign-in/maps/report loading still work. |
| W00-03 | PENDING_EXTERNAL | Current execution below | Fresh and returning browsers load the intended complete candidate; no mixed web assets/API are credited as a pass; the previous release is identified. |
| W00-04 | PENDING_EXTERNAL | Current execution below | Monitoring notes distinguish healthy process, configured required services, actual browser workflow and recipient delivery. Email setup can remain pending while independent code phases continue. |

## Current execution

Source and deployment identity are now visible without secrets. GitHub main, Vercel manifest and Render health match e03c7a1. Flutter 3.41.9 and build flags recorded; downloaded hosted JavaScript hash and committed Git-blob application fingerprint match the published manifest. Frontend/JS security and cache headers are verified live. Live Brave sign-in render observed. Historical prepublication probe and original review remain distinct.

**Remaining:** Full fresh/returning authenticated cache, map, report and configured Firebase compatibility journeys remain open.; Required email readiness remains unavailable; actual provider/alert receipt and operational ownership remain separate.; Cold-start behavior was not manufactured or accepted from repeated warm health requests.

[Execution evidence](../defense-evidence/web-fix-execution/phase-00/README.md).
