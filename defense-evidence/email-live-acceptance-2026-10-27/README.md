# Email configuration and live acceptance

27 October 2026. Browser retry recovered and the user signed into the actual live GeoSustain analyst portal in Brave. No authentication was automated.

## Executed

Public live HTTP results are recorded in [public-baseline.json](public-baseline.json). Backend health returns 200. The operator inbox, map and overview, admin dashboard and current-user endpoints all reject anonymous access with 401. These are unsigned access checks, not signed-in role acceptance.

The observed frontend is on evidence-only commit 1bf3e5c and backend on 6957ae5. Git comparison confirms their application/backend/deployment files match. See [acceptance status](ACCEPTANCE_STATUS.json) for completed signed-in observations. The live inbox, saved case, browser Back/Forward, refresh/session restoration and case PDF print preview were observed. The preview was canceled without printing. No existing farm review decision was changed.

## Required inputs

- An owned email provider and sender. The owner has only Gmail and no domain. Brevo HTTPS support was added for the verified individual sender route; Resend HTTPS and TLS SMTP remain supported. No provider credential is available in the process or local configuration, and live readiness reports email_configuration unavailable.
- Sender address and an authorized disposable test inbox. Keep keys/passwords in the host's private environment; do not send them in chat or commit them.
- The user completed the live analyst sign-in in Brave. This is separate from the synthetic local QA account.

## Gmail-only configuration to apply after an owned sender is verified

On the existing GeoSustain Render service, configure privately:

```text
EMAIL_TRANSPORT=brevo
MAIL_FROM=GeoSustain <actual-verified-sender@gmail.com>
BREVO_API_KEY=<private Brevo API key, entered on Render only>
EMAIL_VERIFICATION_REQUIRED=1
```

Deploy the host configuration, verify /ready, then test actual signup email receipt and recovery using the authorized disposable account. A presence/configuration check cannot establish delivery receipt.

Render Free blocks outbound SMTP ports 25/465/587. The supported HTTPS transport avoids that limitation. Brevo verifies an individual sender by email; Gmail's domain itself cannot be authenticated, so the provider may replace the visible sender domain. Transactional account approval and actual inbox receipt must be checked. References: [Render Free limits](https://render.com/docs/free), [Brevo sender setup](https://help.brevo.com/hc/en-us/articles/208836149-Create-a-new-sender-From-name-and-From-email), [provider domain explanation](https://help.brevo.com/hc/en-us/articles/16045394674066-Troubleshooting-Domain-authentication). See the exact [setup steps](../../deployment/IDENTITY_AND_DELIVERY_SETUP.md).

## Automated validation of the integration

29 focused email/configuration/signup checks and 297 complete backend regressions passed. Ruff F checks passed for the changed Python files. Logs: [focused](email-focused-tests.txt), [regression](backend-regression.txt). Calls in these tests were mocked; they establish payload, secret/error handling, missing-config behavior and stable retry identity, not provider receipt. No Flutter source changed in this email increment.

## Remaining acceptance

Actual signup/recovery receipt, resend/wrong/expired/reused code flows; signed-in analyst overview/inbox/map/case/history/reports/activity/settings/navigation; controlled farmer correction and review decision; admin role checks; full accessibility/browser matrix. Record each performed result and its scope. Do not promote unexecuted checks or change existing real farm decisions solely to generate evidence.
