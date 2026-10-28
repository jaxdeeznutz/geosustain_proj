# Analyst web workflow

The analyst web portal exposes two existing tasks: reviewing submitted farmer
assessments and running independent land assessments for planning.

## Reviewing a submission

Dashboard or Review Inbox → open a submitted case → inspect the saved boundary,
data sources, date, coverage and limitations → complete the checklist → verify
the assessment, request information, or reject with an explanation. The existing
farmer correction and resubmission process retains earlier analysis revisions
and decisions. Analysts cannot decide their own submissions.

Verification records review of the assessment. It does not guarantee land
suitability or crop success and does not replace field or laboratory evidence.

## Independent assessment

Analyze Area, or Planning Map → Select an area → Continue to analysis → run point
or boundary analysis → inspect the recorded evidence → save the assessment or
create its report. No farmer submission is required. Independent results use the
existing account-owned analysis records and do not replace submitted evidence or
record a review decision.

Point selection provides preliminary location screening. A boundary describes
an area assessment; coverage and missing measurements still apply.

## Navigation and scope

Main navigation: Dashboard, Review Inbox, Planning Map, Analyze Area, Assessment
Records and Reports. Settings and Activity remain available below these items.
Recommendation Patterns is accessible from Reports, and existing URLs remain
valid. Assessment Records contains the signed-in account's analyses; farmer
submissions and their review history remain in the Review Inbox.

This change adjusts the Flutter analyst interface. It introduces no database
migration, analysis model changes, new data providers, or backend permission or
review-status changes. This note describes implementation behavior; the project's
formal research objectives remain defined by its thesis documentation.

## Checks

Run `flutter analyze --no-pub`, then
`flutter test --no-pub test/analyst_flow_test.dart test/operator_workflow_test.dart test/web_remediation_test.dart`
and `flutter build web --no-pub` in an environment with access to the Flutter SDK
and dependency cache. The new workflow tests cover navigation, retaining a
selected boundary, no analysis write during map-to-workspace navigation, and
disabled decisions on an analyst's own submission.
