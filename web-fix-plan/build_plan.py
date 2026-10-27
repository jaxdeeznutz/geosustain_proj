"""Generate a traceable web-only remediation plan from the 18-item review."""
import csv
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
REVIEW = ROOT / "defense-evidence/web-live-2026-10-26/web-review-findings.json"
review = json.loads(REVIEW.read_text(encoding="utf-8"))
issues = {f["id"]: f for f in review["findings"]}
tracker_path = HERE / "EXECUTION_TRACKER.csv"
if tracker_path.exists():
    with tracker_path.open(encoding="utf-8", newline="") as handle:
        previous_rows = list(csv.DictReader(handle))
    progress_columns = ["code_or_config_revision", "local_test_evidence", "deployed_web_api_identity", "live_test_evidence", "reviewed_by", "reviewed_at"]
    if any(row.get("status") != "NOT_STARTED" or any(row.get(c) for c in progress_columns) for row in previous_rows):
        raise SystemExit("Execution progress exists. Update the plan deliberately; regeneration would reset the tracker.")

def task(suffix, title, work, done, evidence, kind="CODE_AND_TEST"):
    return dict(suffix=suffix, title=title, work=work, acceptance=done, evidence=evidence, kind=kind)

phases = [
dict(id="00", title="Verify the deployed web baseline and hosting", slug="Web_Baseline_and_Hosting",
 issues=["WEB-02","WEB-03"], depends=[], skill="geosustain-web-baseline",
 purpose="Identify the actual frontend/backend candidate and make intended hosting policies effective before accepting subsequent live fixes.",
 files=["web/index.html", "deployment/vercel.json", "deployment/RELEASE_HANDOVER.md", ".github/workflows/render-health-check.yml"],
 external="Vercel project/build/root settings and Render configuration must be available through owned access. A missing connector does not justify guessing deployment identity.",
 tasks=[
 task("01","Record the actual frontend and backend candidate",
      "Capture source commit, GitHub main, Vercel deployment commit, Flutter SDK/build flags, API origin, public JS hash and backend /health revision. Compare to the dated review. A hash mismatch alone is not proof of an old build. Add a small non-secret build/version identifier if the deployed frontend has none.",
      "A tester can identify the exact web and API versions without secrets, and evidence distinguishes reviewed source from deployed behavior.","baseline.json; frontend/backend identity screenshots or API metadata", "CONFIG_AND_CODE"),
 task("02","Apply the frontend response policies",
      "Inspect Vercel root/build/output settings and ensure the prepared header rules actually reach the deployed site. Retain Flutter/Firebase/map/report compatibility; avoid introducing a blanket script policy without testing required resources. Check HTML, bootstrap, JS, worker and public Firebase configuration cache behavior.",
      "Intended frame, MIME and referrer policies are present on the checked live responses, assets have deliberate cache rules, and sign-in/maps/report loading still work.","before/after public response headers and functional smoke", "HOST_CONFIGURATION"),
 task("03","Publish a matching testable candidate and upgrade path",
      "Use a matching frontend/API candidate after source changes are reviewed. Record the previous compatible release, configuration ownership, backup/recovery procedure and data reconciliation window before schema changes. Test a fresh browser and a browser with the prior cached build. Never publish credentials or historical personal evidence.",
      "Fresh and returning browsers load the intended complete candidate; no mixed web assets/API are credited as a pass; the previous release is identified.","deployment manifest, cache upgrade observations, rollback preparation", "LIVE_RELEASE_CHECK"),
 task("04","Separate liveness, readiness and browser availability",
      "Record /health and /ready independently, including the known email_configuration gap. Define useful monitoring/receipt ownership without treating the ten-minute health workflow as uptime or real delivery proof. Record one warm and one naturally cold startup when observable; do not manufacture production outages.",
      "Monitoring notes distinguish healthy process, configured required services, actual browser workflow and recipient delivery. Email setup can remain pending while independent code phases continue.","readiness snapshot, startup observations and monitor ownership", "OPERATIONS_CHECK")]),

dict(id="01", title="Complete web authentication and delivery setup", slug="Web_Identity_and_Delivery",
 issues=["WEB-01","WEB-10","WEB-11"], depends=["00"], skill="geosustain-web-identity",
 purpose="Make required email, Google, profile phone and web push capabilities usable with clear configuration and real receipt evidence.",
 files=["lib/web/auth/web_auth_login.dart", "lib/web/screens/web_trends_weather_soil_settings_screen.dart", "lib/screens/identity_settings.dart", "lib/firebase_runtime.dart", "lib/federated_identity.dart", "lib/push_notifications.dart", "web/firebase-config.js", "web/firebase-messaging-sw.js", "backend/mail_delivery.py", "backend/email_verification.py", "backend/password_reset.py", "backend/federated_identity.py", "deployment/IDENTITY_AND_DELIVERY_SETUP.md"],
 external="No owned Firebase project was supplied. A real sender/domain, private provider configuration and authorized test recipients are also needed. Work on UI and controlled tests can continue while these remain pending.",
 tasks=[
 task("01","Resolve the required email readiness failure",
      "Use the existing mail transport integration with an owned sender and supported delivery configuration on Render. Keep secrets on the host and preserve required email verification. Do not disable a required flag to obtain a green readiness result.",
      "Live /ready reports required email configuration ready; configuration presence is recorded separately from message receipt.","sanitized configuration-presence/readiness results", "PROVIDER_CONFIGURATION"),
 task("02","Accept real signup and recovery journeys",
      "With authorized disposable accounts, verify actual email receipt, valid/wrong/expired code, resend/guess limits, one-use behavior, duplicate email and readable field errors. Test recovery separately and confirm older sessions are invalidated while existing accounts still sign in.",
      "Both delivered signup verification and recovery complete with bounded invalid attempts and no account enumeration or automatic privilege grant.","redacted receipt metadata, case results and session revocation checks", "LIVE_PROVIDER_TEST"),
 task("03","Configure owned Google and web push identities",
      "Create or select the owner-controlled project through available authorized access, configure actual Vercel domain/OAuth web client and public Flutter identifiers, and align service-worker config/VAPID with backend project credentials. Keep service-account keys out of web assets. State any SMS billing/quota or provider dependency as an owner input rather than promising a free service.",
      "All client/server public project identifiers match, required backend checks are honest, and unconfigured features have clear UI explanations.","public configuration identity manifest without private values", "PROVIDER_CONFIGURATION"),
 task("04","Expose complete desktop identity settings",
      "Mount or adapt IdentityProfileSection in desktop settings: phone edit/verified state, OTP request/verify and explicit Google linking. Keep verification bound to the current owner and exact normalized number; show inline invalid/pending/unavailable feedback. Preserve admin-only role assignment.",
      "A desktop operator can reach and complete the intended controls without switching to a farmer/mobile layout. Wrong/expired/replayed proof and changed-number invalidation behave correctly.","desktop integration tests and redacted browser case evidence"),
 task("05","Verify actual Google, SMS and background push",
      "Use authorized test accounts/recipients only. Test Google login versus explicit linking, the current phone challenge and real SMS receipt, browser permission grant/deny, foreground/background web push, notification click and reauthentication. A mocked accepted delivery or visible inbox is not background receipt.",
      "Real provider outcomes are recorded separately for acceptance, receipt and authorized target opening. Unsupported or unavailable states remain pending with reasons.","provider/browser outcome matrix with no codes, tokens or private payloads", "LIVE_PROVIDER_TEST"),
 task("06","Handle sign-in and recovery errors consistently",
      "Keep field errors and corrected input readable across desktop auth pages, add a labelled password-visibility control where missing, and preserve retry/draft behavior during a cold backend or expired session. Add no new login mechanism beyond the existing project requirements.",
      "Invalid input, incorrect password, expired session, provider unavailable and network failure give distinct recoverable feedback without leaking account data.","focused widget regressions plus live error-state observations")]),

dict(id="02", title="Correct analytical results, charts and statistics", slug="Analysis_Grades_Charts_and_Statistics",
 issues=["WEB-04","WEB-07","WEB-08"], depends=["00"], skill="geosustain-web-analysis",
 purpose="Ensure every web result and statistic expresses the evidence actually available, without fabricated distribution values or unsupported nutrient conclusions.",
 files=["lib/web/screens/web_dashboard_screen.dart", "lib/web/screens/web_analyze_screen.dart", "lib/web/widgets/web_common.dart", "lib/web/screens/web_history_reports_screen.dart", "lib/web/screens/web_planner_queue_screen.dart", "lib/web/screens/web_trends_weather_soil_settings_screen.dart", "lib/main.dart", "lib/widgets/analysis_coverage.dart", "lib/screens/reference_analysis.dart", "backend/soil_nutrient_screening.py"],
 external="Complete CAGRO-based nutrient grades still need compatible units/methods, an accepted sample-to-farm rule and documented crop criteria or validated model evidence. These are not replaced by code or analyst approval.",
 tasks=[
 task("01","Define one web analysis presentation contract",
      "Inventory live analysis, map popup, historical detail, planner review and PDF fields. Document AI model score versus factor grade, full versus preliminary, unknown land cover versus non-arable evidence, and raw observations versus estimates. Reuse shared factor/coverage/CAGRO components where appropriate.",
      "All result surfaces use the same definitions and retain source, period, units and missing-value meaning. Suitable/Limited/Not suitable/Not assessed are text labels, not just colors.","field/label contract and representative fixtures", "CONTRACT_AND_CODE"),
 task("02","Remove invented distribution graphics",
      "Replace the 5%/72% constant in _WebDistributionPanel with actual categories/counts from an explicitly scoped eligible dataset, or remove the panel until meaningful. Treat missing, zero, preliminary and not assessed distinctly. Do not treat the separate Crop Trends implementation as already fixed by this repair.",
      "Empty data displays no invented segment. Different documented fixture distributions change the chart and visible counts correctly.","dataset-to-chart assertions and before/after screenshots"),
 task("03","Repair KPI and trend definitions",
      "Choose labels and denominators that match calculations: recommendation frequency is not most suitable crop, verified requires status filtering, zero is not missing, and unique farm area is not the sum of repeated analysis areas. Make personal history versus reviewed submissions explicit; document tie and duplicate behavior.",
      "Zero/missing/duplicate-farm/preliminary/pending/rejected/verified fixtures yield the documented totals, percentages and labels.","metric definitions, calculation regressions and fixture outputs"),
 task("04","Apply truthful factors and CAGRO states everywhere",
      "Replace legacy '% final'/'% suitability' fallbacks that misrepresent model rank. Surface the shared coverage, factor status, source and uncertainty in the main workspace and historical detail as well as planner review. Keep unavailable NPK and unknown satellite states useful without labelling them complete or non-arable by default.",
      "The same record has consistent scientific meaning in map, analysis, history, planner detail and export. No unsupported CAGRO substitution, unit conversion or score-to-grade invention is introduced.","cross-screen fixture matrix and actual partial-result screenshots"),
 task("05","Verify report provenance and analytic regressions",
      "Check PDF output from the exact saved record, including original model/rule/source versions and partial outcomes. If PDF layout changes, use the installed PDF skill and render every affected page for visual inspection. Retest point/polygon admission and stale-score suppression using existing regression coverage.",
      "Saved/exported content does not silently recompute history under current rules or upgrade a partial result; actual PDF pages are readable and claims match the screen.","PDF/source identity, rendered affected pages and focused test logs", "REGRESSION_AND_EXPORT")]),

dict(id="03", title="Repair the responsive web shell and navigation", slug="Responsive_Shell_Theme_and_Navigation",
 issues=["WEB-05","WEB-12","WEB-13","WEB-14","WEB-15"], depends=["00"], skill="geosustain-web-shell",
 purpose="Keep authorized operators working across window sizes and provide consistent theme, usable navigation, activity and help.",
 files=["lib/main.dart", "lib/web/web_analyst_shell.dart", "lib/web/web_admin_shell.dart", "lib/web/widgets/web_common.dart", "lib/web/auth/web_auth_login.dart", "lib/web/screens/web_dashboard_screen.dart", "lib/web/screens/web_analyze_screen.dart", "lib/web/screens/web_trends_weather_soil_settings_screen.dart", "web/index.html", "deployment/vercel.json"],
 external="Exact browser/OS and supported zoom evidence requires a real compiled browser. New routes must match the deployed Vercel SPA setup.",
 tasks=[
 task("01","Separate role permission from viewport layout",
      "Remove analyst/admin access denial caused solely by width/height. Keep backend authorization and unknown-role denial intact. Add a responsive drawer/rail/sidebar transition and reflow dashboard, analysis toolbars, settings and admin tables while preserving selected record, form input and analysis state.",
      "Resizing or zoom does not change the authorized role or discard work. Narrow/short windows remain operable without ordinary controls being clipped.","responsive widget checks and real resize/zoom observations"),
 task("02","Make theme colors coherent across desktop screens",
      "Replace incompatible hard-coded surfaces/text with paired theme values, or explicitly apply a consistent supported portal theme. Cover auth/logout/register, dashboard, map overlays, results, history, planner/admin dialogs and settings. Preserve the requested GeoSustain branding; do not redesign unrelated mobile screens.",
      "The supported light/dark choices persist and text/selection/focus/errors remain readable on actual painted surfaces.","paired screenshots and measured contrast samples"),
 task("03","Wire menu, activity and useful help",
      "Make the menu icon open/collapse real navigation; connect the bell to a unified permission-aware activity destination with unread/read state. Implement How It Works as a short selection→analysis→save/report→review guide that explains partial results. Weather advisories remain clearly separated from review/activity events.",
      "Pointer and keyboard activate each offered control and return to preserved work; no enabled no-op remains in the reviewed shell.","navigation/action inventory and interaction case results"),
 task("04","Add browser routes with safe return state",
      "Define stable role-aware routes for dashboard, analysis, history, reports, queue, settings and appropriate record detail. Decide which harmless filters/selection belong in URLs versus local state. Configure SPA fallback only as necessary and fetch authorized details after login; do not trust record IDs or notification payloads as permission.",
      "Direct links, reload and Back/Forward work for permitted targets. Unauthorized or missing IDs have a useful safe destination and do not expose cached foreign records.","route matrix, browser history observations and negative ID checks"),
 task("05","Preserve auth and pending-work transitions",
      "Verify layout changes, tab changes, login/logout and route transitions do not resurrect old users, old results or abandoned polygons. Keep in-flight work truthful and provide a recoverable pending/error state rather than silently hiding it.",
      "Account switching and viewport/route changes retain only the correct owner's intended state; returning to an analysis does not duplicate submission.","state-transition regressions and matching browser cases")]),

dict(id="04", title="Fix resource states, refresh and large-record loading", slug="Data_States_Refresh_and_Pagination",
 issues=["WEB-09","WEB-16"], depends=["00"], skill="geosustain-web-data",
 purpose="Make loading, failure, empty, no-match and stale data visible and keep first-page fetching bounded.",
 files=["lib/main.dart", "lib/api_service.dart", "lib/web/widgets/web_common.dart", "lib/web/screens/web_history_reports_screen.dart", "lib/web/screens/web_dashboard_screen.dart", "lib/web/screens/web_planner_queue_screen.dart", "lib/web/web_admin_shell.dart", "backend/fastapi_app.py"],
 external="Actual compiled-browser network/memory measurements require a representative owned staging dataset and browser. Do not stress shared production or providers to create evidence.",
 tasks=[
 task("01","Give each resource explicit display state",
      "Track and display first-load progress, valid empty, no search matches, refresh failure with stale rows and retry for history, saved analyses, reports, counts and trends. Replace swallowed errors with resource-specific state while preserving valid panels. Do not present an unavailable count as verified zero.",
      "Controlled initial and refresh failures never look like successful empty lists. A retry recovers only the intended resources and retains valid data where appropriate.","failure/empty/stale fixture cases and UI observations"),
 task("02","Make refresh and navigation labels match actions",
      "Make Refresh Data refresh the current resource or label it explicitly as weather refresh. Make History navigate when offered as navigation. Coalesce duplicate refreshes and guard stale responses when the owner, route or query changes.",
      "Each control has one predictable action; old responses cannot overwrite a new query or account; success feedback corresponds to the request that actually succeeded.","control/action matrix and delayed-response tests"),
 task("03","Fetch desktop pages and searches from the server",
      "Replace all-history bootstrap for the affected desktop list flows with bounded server query/filter/page requests. Keep total counts and analytic aggregates explicit and consistently scoped rather than calculating whole-account claims from one loaded page. Retain the already bounded admin implementation unless changed behavior is justified.",
      "First page loads without retrieving every history page; full-dataset search remains correct; next/previous and changed queries have stable boundaries with no missing/duplicate rows.","request-count/bytes evidence and server pagination/search regressions"),
 task("04","Measure a realistic browser dataset and recovery",
      "Agree the staging dataset, browser/network/host conditions and response budget before measurement. Exercise a large account, rapid query changes, empty results, offline/reconnect and expired token; record startup and first-page requests/bytes/latency rather than extrapolating SQL benchmarks.",
      "The recorded first-page budget passes with bounded fetches and useful recovery; failures and unfinished runs remain visible instead of being counted as passes.","browser network/latency/memory notes, dataset identity and outcomes", "BROWSER_PERFORMANCE_CHECK")]),

dict(id="05", title="Protect account actions and the browser session", slug="Account_Actions_and_Web_Session_Security",
 issues=["WEB-06","WEB-17"], depends=["00"], skill="geosustain-web-account-safety",
 purpose="Prevent accidental destructive account actions and establish an explicit, tested web session design without breaking shared clients.",
 files=["lib/web/screens/web_trends_weather_soil_settings_screen.dart", "lib/session_token_store.dart", "lib/api_service.dart", "lib/screens/session_gate.dart", "lib/main.dart", "backend/fastapi_app.py", "deployment/vercel.json"],
 external="Destructive acceptance uses isolated disposable accounts/data. Cookie/session decisions require the actual Vercel/Render domain behavior and an explicit compatibility design; no production user is deleted for testing.",
 tasks=[
 task("01","Add deliberate account-action confirmation",
      "Show clear consequences and cancellation before delete/deactivate, with appropriate recent authentication for the chosen design. Disable repeated actions while pending and catch server/network errors. Preserve the approved deletion rule for owned farms/coordinates/analyses/photos/reports and anonymized audits.",
      "Cancel sends no request. Confirmation sends one request. Failure leaves a useful retry state and does not falsely claim deletion.","controlled API/UI tests with disposable identity fixtures"),
 task("02","Complete post-action logout and state cleanup",
      "After confirmed server success, revoke/clear the correct session, remove owner-bound client caches/subscriptions as required and leave the protected portal. Avoid clearing user work before an unsuccessful server action. Test account switch and stale asynchronous results.",
      "Deleted/deactivated accounts cannot remain in a usable protected shell; Back/reload cannot expose prior-owner data; failed actions do not lose unrelated valid data.","session/lifecycle regression results and disposable browser case"),
 task("03","Choose and document the web session boundary",
      "Review the existing JavaScript-accessible bearer preference store, expiry and revocation against actual domains and script exposure. Compare a secure HttpOnly session design with a deliberately hardened bearer approach; document the selected tradeoff. A cookie migration needs intentional SameSite/CORS/CSRF and shared API compatibility, not a local storage rename.",
      "A clear design decision identifies token/cookie lifetime, logout, recovery, account isolation and browser script assumptions. Android protected storage is not cited as web protection.","WEB_SESSION_DECISION.md and compatibility/threat cases", "DESIGN_AND_SECURITY_CHECK"),
 task("04","Implement the selected session hardening and retest roles",
      "Apply only the selected design, aligning frontend response policies and server checks. Retest expired/revoked sessions, logout, password reset/version changes, cross-account caches, role/owner denial and required CSRF/cookie behavior. Preserve mobile transport compatibility even though mobile testing is deferred; record any affected mobile cases for later.",
      "The changed session design passes the relevant browser/API security cases and a normal authorized role journey without weakening backend role/owner checks.","focused security regressions and live/staging role/session outcomes")]),

dict(id="06", title="Validate keyboard, accessibility and browser behavior", slug="Accessibility_and_Browser_Acceptance",
 issues=["WEB-18"], depends=["02","03","04","05"], skill="geosustain-web-accessibility",
 purpose="Turn source reflow/focus risks into actual tested browser behavior on the corrected candidate.",
 files=["lib/web/widgets/web_common.dart", "lib/web/screens/web_analyze_screen.dart", "lib/web/web_analyst_shell.dart", "lib/web/web_admin_shell.dart", "lib/web/auth/web_auth_login.dart", "web/index.html"],
 external="A controllable actual browser or the user's manual participation is required. If no browser surface is exposed, keep dependent cases pending and give concise user steps; do not call widget tests browser passes.",
 tasks=[
 task("01","Define the supported browser and viewport matrix",
      "Record browser/OS versions, viewport dimensions, actual browser zoom and relevant assistive technology. Cover the user's desktop browser and agreed Chrome/Edge/Firefox plus any required Safari target. Preserve previously required but deferred platforms as deferred rather than inventing passes.",
      "The matrix lists actual targets and explicitly pending/unavailable targets, with no assumption that simulated width proves a real engine/device pass.","BROWSER_MATRIX.csv with candidate identities", "MANUAL_ACCEPTANCE"),
 task("02","Complete keyboard and dialog navigation",
      "Run Tab/Shift+Tab/Enter/Space/Escape through auth, navigation, selection, analysis, review, settings and report actions. Give map controls meaningful names/tooltips, visible focus and usable non-pointer alternatives; ensure dialogs announce errors/status and return focus after close.",
      "Required journeys complete without pointer-only traps or unnamed essential controls. Focus remains visible and lands sensibly after navigation and dialogs.","keyboard case steps, semantic observations and human outcomes", "BROWSER_ACCESSIBILITY"),
 task("03","Check zoom, contrast, text reflow and status meaning",
      "Use actual 200/400% browser zoom and narrow/short windows on agreed targets. Measure text/surface pairs for applicable 4.5:1 normal-text and other agreed contrast criteria, including theme/focus/errors/disabled states. Keep maps' two-dimensional nature distinct from clipped ordinary controls and test non-color grade labels.",
      "No authorized access loss or clipped primary action; text and statuses remain understandable in both themes and the agreed reflow cases.","contrast measurements, viewport/zoom screenshots and issue retests", "BROWSER_ACCESSIBILITY"),
 task("04","Verify maps, downloads, history and permission recovery",
      "Test point/polygon editing, incomplete/invalid boundaries, map tile failure, geolocation grant/deny, browser Back/Forward, direct URLs, PDF download/print, popup restrictions and cache upgrades. Test the chosen theme and restored session in private/restricted storage modes where supported.",
      "Each required browser operation works or explains a real permission/storage limitation with recovery; failures are recorded on the exact target rather than generalized away.","browser feature matrix and redacted screenshots", "MANUAL_ACCEPTANCE")]),

dict(id="07", title="Deploy the matched fixes and reconcile web QA", slug="Live_Web_Regression_and_Handover",
 issues=[], depends=["00","01","02","03","04","05","06"], skill="geosustain-web-final-qa",
 purpose="Close only evidence-supported findings on a matched deployed release and deliver a truthful web-only acceptance decision.",
 files=["deployment/RELEASE_HANDOVER.md", "defense-evidence/web-live-2026-10-26/WEB_REVIEW.md", "defense-evidence/readiness-execution/checklist-results.json", "defense-evidence/readiness-execution/QA_CURRENT.html"],
 external="Real provider receipt, actual browser journeys, owned deployment/backup access, independent review where required and adviser acceptance of scientific claims remain external gates. Web acceptance does not complete deferred mobile criteria.",
 tasks=[
 task("01","Freeze the final tested candidate and run appropriate regression",
      "Record source/frontend/API/model/rule/schema/config identities. Run the relevant Flutter and backend tests, analysis/lints and web build after changes, with the completed counts and command exit status. Repeat only affected checks after later changes and retain the seven-test review baseline as historical evidence.",
      "The test results and delivered artifacts match the final candidate; build/local fixtures are not substituted for provider/browser acceptance.","final manifest, test logs and build identity", "REGRESSION_CHECK"),
 task("02","Deploy and execute full real role journeys",
      "Publish the matching frontend/backend through the existing authorized workflow. On controlled test identities, execute signup/recovery, analyst selection/analysis/save/report, planner decision/activity and admin users/audits. Include partial results, authorization denial and session/route/cache recovery. Capture a failed or unavailable step honestly.",
      "Each required web journey finishes on the same candidate with correct permissions, truthful analysis and actual configured provider receipt; unmet dependencies remain open.","end-to-end web case matrix with redacted live evidence", "LIVE_ACCEPTANCE"),
 task("03","Rehearse staging rollback and verify operations",
      "Use the named previous compatible release and backup to rehearse staging rollback/forward recovery including intervening writes and queued work. Verify actual monitor/alert receipt with authorized recipients and record operational ownership. Do not roll production backward merely to generate a test.",
      "Timed recovery reconciles the documented data window and retains owned records; monitoring evidence distinguishes /health from /ready and actual action completion.","staging rollback/forward recovery record and monitor receipt", "STAGING_OPERATIONS"),
 task("04","Reconcile every web finding without rewriting history",
      "For WEB-01 through WEB-18, record before/after, exact change, artifact and retest outcome. Compare affected original QA criteria before promoting any row; preserve all 191 IDs/instructions and history. A source fix may be complete while its live gate remains pending. Do not alter scientific FAILs or mark mobile checks passed because this web plan finished.",
      "All 18 issues have traceable evidence or a precise open reason; original QA counts recompute from actual records with no unsupported status changes.","finding closure register and scoped QA delta", "QA_RECONCILIATION"),
 task("05","Deliver the web handover and real acceptance decision",
      "Provide web URL/build, role-specific operating steps, configuration ownership, known limits, rollback path and actual reviewer decisions. Preserve provider/scientific/browser/mobile scope distinctions. Keep evidence free of credentials, OTPs, device tokens and private farm payloads.",
      "The owner can reproduce the offered web workflow and understands outstanding gates. No final sign-off or independent reviewer is invented.","web handover, remaining-gates register and dated actual decisions", "HANDOVER")]),
]

skill_guidance = {
"00": ("Identify GeoSustain web deployments and apply frontend hosting/cache policies when fixing WEB-02 and WEB-03.",[
 "Treat the current source, previously built web directory and hosted Vercel bundle as different identities until provenance matches. A hash difference is a prompt to inspect build metadata, not proof of a stale release.",
 "deployment/vercel.json is ineffective unless the real Vercel root/output configuration consumes it; test public response headers, not just file existence.",
 "Keep /health, /ready, actual browser flows and provider delivery separate. The recorded readiness failure concerns email configuration while database/model passed.",
 "Use owned access already authorized by the user; request only missing external access/settings. This planning skill adds no permission to change unrelated services or accept provider terms."]),
"01": ("Complete GeoSustain desktop email, Google, phone proof and web push integration with real owned provider acceptance.",[
 "Existing password accounts must remain usable. Backend verification and safe explicit linking determine identity; email-only matching must not take over an account or grant a planner/admin role.",
 "Required production email verification is already enabled by the reviewed behavior. Do not reuse stale instructions that call the current production flow disabled by default.",
 "Mount the existing shared identity component in desktop settings rather than implementing a second incompatible phone/linking protocol.",
 "Google/SMS need Firebase Auth configuration; background web push additionally needs aligned worker/VAPID/backend credentials. Never ship a service-account key to the browser.",
 "Provider acceptance, human receipt and authorized target opening are distinct evidence. Keep live tests on owned disposable identities and explicitly authorized recipients; absent credentials or receipts leave a provider gate pending."]),
"02": ("Repair GeoSustain desktop model-score wording, environmental grades, CAGRO provenance, charts and KPI definitions.",[
 "The constant 5%/72% chart is a separate panel from Crop Trends; repairing one does not establish correct calculations in the other.",
 "Separate recommendation frequency from suitability, model scores from documented factor grades, zero from missing and cumulative analysis area from unique farm area.",
 "The planner detail already uses shared coverage/CAGRO/explanation/factor components. Bring the workspace/history/map into that contract rather than preserving contradictory legacy labels.",
 "Keep historical observations separate and maintain the user-approved Panabo preliminary screen. No arbitrary sample averaging, proxy NPK substitution or fabricated sample-to-farm/units/method compatibility.",
 "A grey/unknown/not-assessed result is useful truth, not a reason to fabricate a green grade. Render changed PDFs with the available PDF skill when export layout is part of the change."]),
"03": ("Repair GeoSustain operator viewport access, desktop theme pairing, activity/help controls and browser navigation state.",[
 "Viewport width/height is a layout input, not a role authorization rule. Preserve backend/unknown-role denial while letting authorized operators use narrow or zoomed windows.",
 "The existing state contains selected geometry and long-running analysis; moving between a drawer/sidebar or URL routes must not duplicate analysis or resurrect a different owner's result.",
 "A menu/bell must be actionable and keyboard named or presented without a control affordance. Route activity to the existing permission-aware event model; do not invent weather push.",
 "Pair hard-coded surfaces and inherited text consistently across auth/logout and portal dialogs. Avoid unrelated mobile redesign while fixing shared components.",
 "Use actual browser Back/reload and deep-link permission checks to accept routes; integer page-state widget tests alone cannot prove browser history behavior."]),
"04": ("Implement truthful GeoSustain web resource loading/error/stale states and bounded server page/search fetching.",[
 "Initial failure, valid empty, search no-match and refresh failure with old data are different states. Do not show an unavailable resource or failed count as a confirmed empty result.",
 "A History button should navigate if presented as navigation; the current common Refresh Data button only refreshes weather. Match the action to the current resource or rename it precisely.",
 "Rendered 20-row pagination is not bounded loading if ApiService first downloads every 50-row history page. Keep aggregate metric scope independent from a loaded page.",
 "Guard delayed responses by owner/query/route epoch; existing valid panels should survive independent failures.",
 "Measure the compiled browser network path on a named owned dataset. Prior SQL query latency does not establish browser first-page speed or inference throughput."]),
"05": ("Protect GeoSustain desktop delete/deactivate actions and choose/test a compatible browser session security design.",[
 "Use disposable isolated accounts for delete/deactivate evidence, preserving the accepted owned-data removal and anonymized audit policy. Do not exercise destructive production actions to fill a QA row.",
 "Cancellation must send no API request; only confirmed server success triggers final client cleanup. Failed operations must not discard valid account work or claim success.",
 "JavaScript-accessible web preferences are not Android protected storage. This is a session design risk, not an already demonstrated XSS exploit.",
 "Choose and record bearer hardening versus HttpOnly session behavior before implementation. Cookie designs require actual domain/SameSite/CORS/CSRF testing and must preserve the shared API/client contract.",
 "Changing the web session path can affect deferred mobile clients. Record affected checks for later; do not uninstall user apps or claim their compatibility from web tests."]),
"06": ("Execute actual GeoSustain desktop keyboard, contrast, zoom/reflow, map and download acceptance on recorded browser targets.",[
 "Use the supported computer-use/browser interface when available; read its installed skill at that time. If no controllable browser exists, guide concise user steps and mark the result user-confirmed or pending.",
 "Tab/Enter/Escape operation, visible focus, dialog focus return and meaningful map labels need human/browser evidence. Semantics or a compiled web build alone is not screen-reader acceptance.",
 "Actual browser zoom can change the portal's effective viewport and previously triggered role denial. Test short windows as well as narrow widths, retaining exact target dimensions/zoom.",
 "Distinguish map two-dimensional interaction from ordinary text/control reflow. Provide workable coordinates/selection alternatives instead of silently exempting the entire workflow.",
 "Retain agreed unavailable browser/platform targets as pending. Simulated viewports or WebKit automation are not automatically a real Safari/device result."]),
"07": ("Reconcile GeoSustain web findings and QA against a matched deployed release, live role journeys and explicit remaining gates.",[
 "Source-fixed, local-tested, deployed, live-tested and accepted are separate milestones. The review's seven focused tests and prior broad counts remain dated scopes.",
 "Close a WEB issue only against its acceptance and affected actual QA criteria. Keep all 191 original IDs/instructions/history and calculate deltas from records, not report wording.",
 "Full web software repair does not validate unsupported CAGRO science or complete deferred mobile work. Preserve the preliminary demonstration scope explicitly.",
 "Only actual owner/tester/adviser decisions can be recorded as sign-off. Independently required retest cannot be supplied by inventing another reviewer.",
 "Exercise recovery on owned staging with post-backup writes/queued work; keep private provider/signing/test credentials and identifying payloads outside published evidence."]),
}

all_tasks=[]
for p in phases:
    p["file"] = f"PHASE_{p['id']}_{p['slug']}.md"
    p["status"] = "NOT_STARTED"
    p["skill_path"] = f"skills/{p['skill']}/SKILL.md"
    for t in p["tasks"]:
        t["id"] = f"W{p['id']}-{t.pop('suffix')}"
        t["status"] = "NOT_STARTED"
        t["phase"] = p["id"]
        all_tasks.append(t)

plan = dict(name="GeoSustain web issue remediation", created_date="2026-10-27",
 scope="Web only; implementation has not started; previous mobile work remains deferred",
 baseline_commit=review["reviewed_source_commit"], review_path=str(REVIEW.relative_to(ROOT)).replace('\\','/'),
 review_sha256=hashlib.sha256(REVIEW.read_bytes()).hexdigest(), findings=list(issues.values()), phases=phases)
(HERE/"plan.json").write_text(json.dumps(plan,indent=2),encoding="utf-8")

rules="""# Web plan execution rules

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
"""
(HERE/"EXECUTION_RULES.md").write_text(rules,encoding="utf-8")

for p in phases:
    description,guidance=skill_guidance[p["id"]]
    skilldir=HERE/"skills"/p["skill"]
    skilldir.mkdir(parents=True,exist_ok=True)
    body=["---", f"name: {p['skill']}", "description: "+json.dumps(description), "---", "",
          f"# {p['title']}", "",f"Use [Phase {p['id']}](../../{p['file']}) for work items and acceptance. Read [web execution rules](../../EXECUTION_RULES.md) and the relevant review findings before changes.", "",
          "These instructions refine decisions for this web phase; they do not supply provider credentials, scientific validation or new external authorization.", ""]
    body += ["- "+x for x in guidance]
    body += ["",f"Record actual outcomes in the project tracker and `defense-evidence/web-fix-execution/phase-{p['id']}/`. If a prerequisite is absent, state the missing input and continue independent authorized work rather than converting the case to PASS.",""]
    (skilldir/"SKILL.md").write_text("\n".join(body),encoding="utf-8")
    md=[f"# Phase {p['id']}: {p['title']}","", "[Plan index](README.md) · [Execution rules](EXECUTION_RULES.md) · [Issue crosswalk](ISSUE_CROSSWALK.md)","",
        "**Status:** NOT_STARTED — planned work only.","",f"**Goal:** {p['purpose']}","",
        f"**Primary skill:** [{p['skill']}]({p['skill_path']}). Read this skill before executing the phase.","",
        "**Dependencies:** "+("; ".join(f"[Phase {x}]({next(q['file'] for q in phases if q['id']==x)})" for x in p["depends"]) or "None; this establishes the candidate baseline."),"",
        "Dependencies establish baseline/final acceptance order. Provider setup in Phase 01 does not block independent source fixes in Phases 02–05; its live gates remain open until completed.","",
        "**Issues owned:** "+(", ".join(f"{i}: {issues[i]['title']}" for i in p["issues"]) or "Final cross-phase regression and acceptance for WEB-01 through WEB-18; no additional finding invented."),"",
        "## Relevant implementation", ""]
    md += [f"- [{f}](../{f})" for f in p["files"] if (ROOT/f).exists()]
    md += ["", "## External inputs and limitations", "",p["external"],"", "## Work and acceptance", ""]
    for t in p["tasks"]:
        md += [f"### {t['id']}: {t['title']}","",t["work"],"", "**Acceptance:** "+t["acceptance"],"", "**Evidence:** "+t["evidence"]+".","", "**Initial status:** NOT_STARTED.",""]
    md += ["## Focused verification", ""]
    if p["issues"]:
        for key in p["issues"]:
            md += [f"- **{key}:** {issues[key]['acceptance']}"]
    else:
        md += ["- Retest all 18 findings on the matched deployed candidate and complete the required real role/provider/browser matrix."]
    if p["id"]=="02":
        md += ["- If an actual XLSX is reconciled, read the available spreadsheets skill; if PDF appearance changes, read the available PDF skill and render/inspect pages. Neither skill supplies missing scientific criteria."]
    if p["id"] in ("00","06","07"):
        md += ["- Use the installed computer-use skill only when an actual supported browser surface is available; otherwise record manual user steps/outcomes explicitly."]
    md += ["", "## Exit and handover", "",f"Store actual execution under `defense-evidence/web-fix-execution/phase-{p['id']}/`; start from [EVIDENCE_TEMPLATE.json](EVIDENCE_TEMPLATE.json). Link source/frontend/backend identity, expected versus actual results, test/provider/browser scope and remaining gates.","",
           "The phase is complete only when its full acceptance is supported. Source-only fixes can be handed on with pending live dependencies recorded; do not mark the whole phase complete from a build or plan file.","",
           "| Task | Current state | Evidence | Remaining gate |", "| --- | --- | --- | --- |"]
    md += [f"| {t['id']} | NOT_STARTED | Not executed | {t['acceptance']} |" for t in p["tasks"]]
    md += [""]
    (HERE/p["file"]).write_text("\n".join(md),encoding="utf-8")

cross=["# Web issue ownership and closure crosswalk","", "[Plan index](README.md) · [Detailed review](../defense-evidence/web-live-2026-10-26/WEB_REVIEW.md)","",
       "Each original review finding has one primary repair phase. Later accessibility/final checks may retest it without taking ownership or changing its original evidence basis.","",
       "| Issue | Priority | Original evidence basis | Finding | Primary phase | Closure acceptance |","| --- | --- | --- | --- | --- | --- |"]
for key,f in issues.items():
    p=next(p for p in phases if key in p["issues"])
    cross += [f"| {key} | {f['priority']} | {f['basis']} | {f['title']} | [Phase {p['id']}]({p['file']}) | {f['acceptance']} |"]
cross += ["","Phase 07 reconciles all 18 findings and any affected original QA rows. No issue is closed by creating this plan.",""]
(HERE/"ISSUE_CROSSWALK.md").write_text("\n".join(cross),encoding="utf-8")
with (HERE/"EXECUTION_TRACKER.csv").open("w",encoding="utf-8",newline="") as handle:
    writer=csv.DictWriter(handle,fieldnames=["task_id","phase","title","type","owned_findings","status","code_or_config_revision","local_test_evidence","deployed_web_api_identity","live_test_evidence","remaining_gate","reviewed_by","reviewed_at"])
    writer.writeheader()
    for p in phases:
        for t in p["tasks"]:
            writer.writerow(dict(task_id=t["id"],phase=p["id"],title=t["title"],type=t["kind"],owned_findings=";".join(p["issues"]),status="NOT_STARTED",remaining_gate=t["acceptance"]))
template={"phase":"", "task_ids":[], "finding_ids":[], "observed_at_utc":"", "source_commit":"", "frontend":{"url":"","deployment_commit":"","build_id":"","asset_sha256":""},"backend":{"url":"","revision":"","ready_status":None},"test_target":{"environment":"","disposable_dataset_id":"","browser_version":"","os_version":"","viewport":"","zoom":""},"cases":[{"case_id":"","expected":"","actual":"","evidence_scope":"source/local/browser/user-confirmed/provider-receipt","outcome":"NOT_RUN","evidence_files":[]}],"required_external_gates":[],"private_data_excluded":True,"actual_reviewer":"","remaining_work":[]}
(HERE/"EVIDENCE_TEMPLATE.json").write_text(json.dumps(template,indent=2),encoding="utf-8")

readme=["# GeoSustain web fix plan","", "Eight execution phases for the detailed 26 October 2026 web review. **Planning only: no findings are fixed and no live acceptance is claimed by these files.**", "",
        "**Project:** GeoSustain · **Website:** https://geosustain.vercel.app/ · **Baseline source:** `7f4c81e7b0d9441127e32fedffab101af84559b7`.","",
        "This is the current web-specific repair plan. Existing `defense-readiness-plan` remains context for the larger capstone; it is not deleted or counted complete. Mobile work is deferred at the owner's request.","",
        "## Start here","", "1. Read [execution rules](EXECUTION_RULES.md), then Phase 00 and its linked skill.",
        "2. Keep the [issue crosswalk](ISSUE_CROSSWALK.md) and [tracker](EXECUTION_TRACKER.csv) open while executing. Every WEB-01 through WEB-18 has one repair owner.",
        "3. Record real work with [the evidence template](EVIDENCE_TEMPLATE.json). No evidence execution folders are prefilled with passes.",
        "4. Validate plan structure with `python web-fix-plan/validate_plan.py` from the project root.","",
        "## Phases and skills","", "| Phase | Outcome | Findings | Main dependency | Skill |", "| --- | --- | --- | --- | --- |"]
for p in phases:
    readme += [f"| [{p['id']}: {p['title']}]({p['file']}) | {p['purpose']} | {', '.join(p['issues']) or 'All 18: final retest'} | {', '.join(p['depends']) or 'None'} | [{p['skill']}]({p['skill_path']}) |"]
readme += ["", "## Execution order", "", "Phase 00 establishes identity and hosting. Phase 01 owns the required email/Firebase/SMS/push gates. Once the baseline is understood, independent code work in Phases 02–05 can proceed while provider inputs are pending. Phase 05 safety fixes should be prioritized before exposing account deletion to real users; phase numbering is not a reason to delay a reproduced destructive-action issue. Phase 06 accepts the corrected interfaces in browsers. Phase 07 requires all final live/provider/browser gates.","",
           "Dependencies are about accepted outcomes, not a requirement to idle while an unrelated provider is unavailable. Do not mark a phase complete just to let later useful source work begin.","",
           "## Known external inputs", "",
           "- Owner-controlled Vercel/Render project configuration and actual frontend build identity.",
           "- Real email sender/provider configuration plus authorized test recipients; the review found required email configuration unavailable.",
           "- An owned Firebase project, Google web client/domain, phone verification setup, web VAPID/public config and private backend FCM setup. No project was supplied at the review baseline.",
           "- Actual browser/user participation for resize/zoom, keyboard/screen reader, maps, PDF and background push receipt.",
           "- Compatible CAGRO association/method/unit/criteria evidence and adviser acceptance before complete nutrient claims. Useful preliminary screening remains in scope.",
           "- Owned staging data/backup and actual reviewer/monitoring recipients for final recovery and acceptance.","",
           "## Source and evidence", "",
           "- [Full review](../defense-evidence/web-live-2026-10-26/WEB_REVIEW.md) and [readable review](../defense-evidence/web-live-2026-10-26/WEB_REVIEW.html).",
           "- [Original structured findings](../defense-evidence/web-live-2026-10-26/web-review-findings.json) and [dated public deployment checks](../defense-evidence/web-live-2026-10-26/public-deployment-checks.json).",
           "- [Machine-readable plan](plan.json) and [plan validation](PLAN_VALIDATION.json).",
           "",f"The plan has {len(phases)} phases, {len(all_tasks)} actionable tasks, {len(issues)} original findings and {len(phases)} portable phase skills. Skill frontmatter is validated separately; these files are not installed globally. Read a linked SKILL.md explicitly when carrying out its phase.","",
           "The broad original QA remains at its existing dated scope until actual fixes and retests support a scoped update. This plan neither deletes old evidence nor converts scientific/provider/mobile cases into PASS.",""]
(HERE/"README.md").write_text("\n".join(readme),encoding="utf-8")
(HERE/"PLAN_VALIDATION.json").write_text(json.dumps({"valid":False,"validation_pending":True}),encoding="utf-8")
print(json.dumps({"phases":len(phases),"tasks":len(all_tasks),"findings":len(issues),"skills":len(phases),"folder":str(HERE)}))
