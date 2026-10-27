# GeoSustain web fix plan

Latest implementation increment: [27 October analyst/planner workflow and evidence](../defense-evidence/operator-workflow-execution/README.md), following the [detailed operator review](../web-review-2026-10-27/DETAILED_WEB_REVIEW.md). Provider/scientific/manual acceptance remains distinct from these software changes.

Eight execution phases for the detailed 26 October 2026 web review. **Execution underway.** See the [current execution evidence](../defense-evidence/web-fix-execution/README.md) and task tracker; source completion is separate from live/provider acceptance.

**Project:** GeoSustain · **Website:** https://geosustain.vercel.app/ · **Baseline source:** `7f4c81e7b0d9441127e32fedffab101af84559b7`.

This is the current web-specific repair plan. Existing `defense-readiness-plan` remains context for the larger capstone; it is not deleted or counted complete. Mobile work is deferred at the owner's request.

## Start here

1. Read [execution rules](EXECUTION_RULES.md), then Phase 00 and its linked skill.
2. Keep the [issue crosswalk](ISSUE_CROSSWALK.md) and [tracker](EXECUTION_TRACKER.csv) open while executing. Every WEB-01 through WEB-18 has one repair owner.
3. Record real work with [the evidence template](EVIDENCE_TEMPLATE.json). No evidence execution folders are prefilled with passes.
4. Validate plan structure with `python web-fix-plan/validate_plan.py` from the project root.

## Phases and skills

| Phase | Outcome | Findings | Main dependency | Skill |
| --- | --- | --- | --- | --- |
| [00: Verify the deployed web baseline and hosting](PHASE_00_Web_Baseline_and_Hosting.md) | Identify the actual frontend/backend candidate and make intended hosting policies effective before accepting subsequent live fixes. | WEB-02, WEB-03 | None | [geosustain-web-baseline](skills/geosustain-web-baseline/SKILL.md) |
| [01: Complete web authentication and delivery setup](PHASE_01_Web_Identity_and_Delivery.md) | Make required email, Google, profile phone and web push capabilities usable with clear configuration and real receipt evidence. | WEB-01, WEB-10, WEB-11 | 00 | [geosustain-web-identity](skills/geosustain-web-identity/SKILL.md) |
| [02: Correct analytical results, charts and statistics](PHASE_02_Analysis_Grades_Charts_and_Statistics.md) | Ensure every web result and statistic expresses the evidence actually available, without fabricated distribution values or unsupported nutrient conclusions. | WEB-04, WEB-07, WEB-08 | 00 | [geosustain-web-analysis](skills/geosustain-web-analysis/SKILL.md) |
| [03: Repair the responsive web shell and navigation](PHASE_03_Responsive_Shell_Theme_and_Navigation.md) | Keep authorized operators working across window sizes and provide consistent theme, usable navigation, activity and help. | WEB-05, WEB-12, WEB-13, WEB-14, WEB-15 | 00 | [geosustain-web-shell](skills/geosustain-web-shell/SKILL.md) |
| [04: Fix resource states, refresh and large-record loading](PHASE_04_Data_States_Refresh_and_Pagination.md) | Make loading, failure, empty, no-match and stale data visible and keep first-page fetching bounded. | WEB-09, WEB-16 | 00 | [geosustain-web-data](skills/geosustain-web-data/SKILL.md) |
| [05: Protect account actions and the browser session](PHASE_05_Account_Actions_and_Web_Session_Security.md) | Prevent accidental destructive account actions and establish an explicit, tested web session design without breaking shared clients. | WEB-06, WEB-17 | 00 | [geosustain-web-account-safety](skills/geosustain-web-account-safety/SKILL.md) |
| [06: Validate keyboard, accessibility and browser behavior](PHASE_06_Accessibility_and_Browser_Acceptance.md) | Turn source reflow/focus risks into actual tested browser behavior on the corrected candidate. | WEB-18 | 02, 03, 04, 05 | [geosustain-web-accessibility](skills/geosustain-web-accessibility/SKILL.md) |
| [07: Deploy the matched fixes and reconcile web QA](PHASE_07_Live_Web_Regression_and_Handover.md) | Close only evidence-supported findings on a matched deployed release and deliver a truthful web-only acceptance decision. | All 18: final retest | 00, 01, 02, 03, 04, 05, 06 | [geosustain-web-final-qa](skills/geosustain-web-final-qa/SKILL.md) |

## Execution order

Phase 00 establishes identity and hosting. Phase 01 owns the required email/Firebase/SMS/push gates. Once the baseline is understood, independent code work in Phases 02–05 can proceed while provider inputs are pending. Phase 05 safety fixes should be prioritized before exposing account deletion to real users; phase numbering is not a reason to delay a reproduced destructive-action issue. Phase 06 accepts the corrected interfaces in browsers. Phase 07 requires all final live/provider/browser gates.

Dependencies are about accepted outcomes, not a requirement to idle while an unrelated provider is unavailable. Do not mark a phase complete just to let later useful source work begin.

## Known external inputs

- Owner-controlled Vercel/Render project configuration and actual frontend build identity.
- Real email sender/provider configuration plus authorized test recipients; the review found required email configuration unavailable.
- An owned Firebase project, Google web client/domain, phone verification setup, web VAPID/public config and private backend FCM setup. No project was supplied at the review baseline.
- Actual browser/user participation for resize/zoom, keyboard/screen reader, maps, PDF and background push receipt.
- Compatible CAGRO association/method/unit/criteria evidence and adviser acceptance before complete nutrient claims. Useful preliminary screening remains in scope.
- Owned staging data/backup and actual reviewer/monitoring recipients for final recovery and acceptance.

## Source and evidence

- [Full review](../defense-evidence/web-live-2026-10-26/WEB_REVIEW.md) and [readable review](../defense-evidence/web-live-2026-10-26/WEB_REVIEW.html).
- [Original structured findings](../defense-evidence/web-live-2026-10-26/web-review-findings.json) and [dated public deployment checks](../defense-evidence/web-live-2026-10-26/public-deployment-checks.json).
- [Machine-readable plan](plan.json) and [plan validation](PLAN_VALIDATION.json).

The plan has 8 phases, 37 actionable tasks, 18 original findings and 8 portable phase skills. Skill frontmatter is validated separately; these files are not installed globally. Read a linked SKILL.md explicitly when carrying out its phase.

The broad original QA remains at its existing dated scope until actual fixes and retests support a scoped update. This plan neither deletes old evidence nor converts scientific/provider/mobile cases into PASS.
