# Configure the owned services

The implementation is present. No Firebase project or real email sender has been supplied, so provider receipt is pending. Local proof/transport doubles do not certify Google, SMS, email or push delivery.

## Firebase Auth and Messaging

1. Create an owner-controlled Firebase project. Keep its Project ID; do not paste service-account keys into chat or source.
2. Add Android apps for the actual release application ID `com.example.geosustain_clean_arranged` and, if needed, the separate QA IDs ending `.phoneqa` and `.automatedqa`. Add each app's real signing SHA-1/SHA-256 fingerprints. The release uses a separate private key; the debug fingerprint is different.
3. Add a Web app and the real web origin. Enable Google and Phone in Authentication, configure authorized domains and the required SMS regions/quotas/billing in the console. Test numbers are useful for development but are not real SMS receipt evidence.
4. Configure these **public** Flutter build defines from General/app configuration: `FIREBASE_API_KEY`, `FIREBASE_PROJECT_ID`, `FIREBASE_SENDER_ID`, `FIREBASE_ANDROID_APP_ID`, `FIREBASE_WEB_APP_ID`, `FIREBASE_AUTH_DOMAIN`, `GOOGLE_WEB_CLIENT_ID` (Web OAuth client ID), and `FIREBASE_WEB_VAPID_KEY` for browser push.
5. Set backend `FIREBASE_AUTH_PROJECT_ID` to the same Project ID. Set `IDENTITY_REQUIRED=true` on the intended completed deployment. Firebase issues a proof; the backend verifies signature/issuer/audience/recent provider authentication and issues its own role-bearing app session. A client cannot assign its role or verified phone state.
6. Configure a narrowly authorized FCM service identity privately on the backend: `FCM_PROJECT_ID`, `FCM_SERVICE_ACCOUNT_JSON`, `PUSH_REQUIRED=true`, `PUBLIC_WEB_APP_URL=https://<real-flutter-host>`. Never put that private JSON in Flutter defines or web worker files.
7. Generate `web/firebase-config.js` with only public app config, matching the deployed client. Its service worker must be served as JavaScript on the same HTTPS origin. Inspect `deployment/vercel.json` before deployment.
8. Validate fresh Google signup creates a farmer, explicit existing-account linking requires the current password and same email, cancellation leaves existing login intact, phone code/replay/changed-number behavior, sign-out, account switching, and native/web notification permission denial.
9. Record a controlled real email/SMS receipt and push receipt in foreground, background and terminated states. Distinguish FCM acceptance, visible notification, authenticated click target and inbox read. Wrong-owner clicks must refuse access.

Official setup: [Google/Flutter](https://firebase.google.com/docs/auth/flutter/federated-auth), [Phone/Flutter](https://firebase.google.com/docs/auth/flutter/phone-auth), [server ID token verification](https://firebase.google.com/docs/auth/admin/verify-id-tokens), [FCM reception](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages).

## Email verification and recovery

Render Free blocks SMTP ports 25, 465 and 587. The backend supports Brevo and Resend over HTTPS as well as TLS SMTP for hosts that support it. [Render limits](https://render.com/docs/free), [Resend endpoint](https://resend.com/docs/api-reference/emails/send-email), [Brevo endpoint](https://developers.brevo.com/docs/send-a-transactional-email).

### Gmail-only setup with Brevo

1. Create/sign into your owned Brevo account. In Settings -> Senders, Domains, IPs -> Senders, add the name `GeoSustain` and your Gmail address. Complete the verification email yourself. [Sender setup](https://help.brevo.com/hc/en-us/articles/208836149-Create-a-new-sender-From-name-and-From-email).
2. Confirm transactional sending is activated. New accounts may require approval from Brevo; an API key alone does not establish sending permission. [Activation troubleshooting](https://help.brevo.com/hc/en-us/articles/115000188150-Troubleshooting-Issues-with-Brevo-SMTP).
3. Generate a private Brevo API key and enter it directly in the existing GeoSustain Render service's Environment page. Do not paste it into chat, Git, evidence or frontend configuration.

```text
EMAIL_TRANSPORT=brevo
MAIL_FROM=GeoSustain <your-verified-gmail-address@gmail.com>
BREVO_API_KEY=<private Brevo API key, not an SMTP key>
EMAIL_VERIFICATION_REQUIRED=1
```

4. Save/redeploy the Render environment. Configuration presence should make the email configuration check ready, but does not prove key validity, sender/account approval or receipt. Perform real signup and recovery on an explicitly authorized disposable test inbox, recording receipt without publishing addresses or codes.

Gmail is a free domain you cannot authenticate in Brevo. The provider may replace the visible From domain with its own sending domain. This is an interim capstone option; the actual sender presentation and delivery must be tested. An owned authenticated domain improves sender identity/deliverability later. [Provider explanation](https://help.brevo.com/hc/en-us/articles/16045394674066-Troubleshooting-Domain-authentication). Do not claim that verifying a Gmail address authenticates gmail.com.

### Owned domain with Resend

Configure a verified owned sender/domain privately:

```text
EMAIL_TRANSPORT=resend
MAIL_FROM=GeoSustain <verified-sender@your-domain.example>
RESEND_API_KEY=<private host secret>
EMAIL_VERIFICATION_REQUIRED=1
```

Production defaults to required email verification; the explicit development example `0` is only for isolated local testing. Existing accounts remain usable. Registration and email recovery use expiring one-use codes with shared quotas. Recovery replies do not disclose whether an account exists; successful recovery changes the password version and revokes previous app sessions/subscriptions. It does not automatically sign the user in.

Confirm sender verification, actual arrival/spam behavior, resend throttling, wrong/expired/reused codes and delivery outage recovery on owned test accounts. Never store codes or recipient addresses in public evidence. Provider acceptance alone is not a receipt test.
