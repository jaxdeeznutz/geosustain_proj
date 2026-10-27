# Web plan execution rules

This folder is an execution plan, not a claim that the 18 review findings are fixed. All tasks begin NOT_STARTED. The review is a dated snapshot; recheck live state when execution begins.

- Work on the selected GeoSustain checkout and the web app at https://geosustain.vercel.app/. Mobile acceptance is deferred, not removed or passed. Shared changes still need impact notes for deferred clients.
- Preserve the owner's testing preference: collect an agreed browser sweep first, then batch non-blocking UI repairs. Record/fix a reproduced blocking issue when it prevents useful testing. No constant per-phase permission requests are implied.
- Keep required email/identity/push features and scientific limitations explicit. Do not disable required flags, fabricate NPK grades or mark unknown land cover non-arable merely to obtain green QA.
- Use the phase's local SKILL.md and only the conditional installed skills needed by its actual work. These eight skills are portable project files; they are not installed globally or automatically active merely because this folder exists. Read the linked skill before executing its phase.
- Source changes, focused tests, build success, deployment, live browser behavior and actual message receipt are separate milestones. A missing provider/browser/credential is a precise pending gate; continue independent code work where possible.
- Preserve original 191-row QA IDs, instructions and history. Review priorities P0/P1/P2 are not QA statuses. No broad PASS follows from one fixed label or unit test.
- Use controlled local/staging data for destructive/security/load tests. Never delete a real user/farm or stress public inference providers to create evidence. The plan adds no new external messaging, deployment or account-creation authorization; use existing session authorization when applicable and resolve only actual missing inputs/access.
- Secrets belong in private host configuration; evidence must omit passwords, OTPs, bearer/FCM tokens, private keys and identifying farm payloads. Public Firebase app identifiers are distinct from private service-account credentials.
- Store actual execution evidence under `defense-evidence/web-fix-execution/phase-XX/` when the work is performed. An evidence path or template is not proof that a case ran. Use relative links from the project and exact artifact/build identities.
- Record per-task status and evidence in EXECUTION_TRACKER.csv as execution progresses. Suggested statuses: NOT_STARTED, IN_PROGRESS, CODE_COMPLETE, VERIFIED_LOCAL, VERIFIED_LIVE, PENDING_EXTERNAL, REQUIRES_MANUAL, COMPLETE. COMPLETE requires the task's whole acceptance; CODE_COMPLETE is not live acceptance.
- After material changes, run appropriate affected checks; broaden only where dependency changes or failures justify it. Required real browser/provider/scientific/independent checks remain distinct.
