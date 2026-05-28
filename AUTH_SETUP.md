# GeoSustain Google Sign-In + Email Verification Setup

## What was added
- Google sign-in route: `/auth/google`
- Google OAuth callback: `/auth/google/callback`
- Email verification page: `/verify-email`
- Resend code route: `/resend-verification`
- Mobile/API verification endpoints:
  - `POST /api/mobile/verify-email`
  - `POST /api/mobile/resend-verification`
- Database columns added automatically on startup:
  - `email_verified`
  - `verification_code_hash`
  - `verification_expires_at`
  - `google_sub`
  - `auth_provider`

## Render environment variables
Add these in Render → your service → Environment:

### Google OAuth
```
GOOGLE_CLIENT_ID=your-google-client-id
GOOGLE_CLIENT_SECRET=your-google-client-secret
GOOGLE_REDIRECT_URI=https://YOUR-RENDER-URL.onrender.com/auth/google/callback
```

### SMTP email sending
For Gmail SMTP, use an App Password, not your normal Gmail password.
```
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-gmail-app-password
SMTP_FROM=GeoSustain <your-email@gmail.com>
```

Optional:
```
VERIFICATION_CODE_MAX_AGE_MINUTES=10
SECRET_KEY=use-a-long-random-secret
```

## Google Cloud Console setup
1. Open Google Cloud Console.
2. Create/select a project.
3. Go to APIs & Services → OAuth consent screen.
4. Configure app name and support email.
5. Go to Credentials → Create Credentials → OAuth client ID.
6. Choose Web application.
7. Add this Authorized redirect URI:
   `https://YOUR-RENDER-URL.onrender.com/auth/google/callback`
8. Copy the Client ID and Client Secret to Render.

## Local development note
If SMTP variables are missing, GeoSustain prints the verification code in the backend terminal for testing.

## Email OTP backend endpoints
This update adds these mobile endpoints to both FastAPI and Flask fallback backend files:

- `POST /api/mobile/send-verification`
- `POST /api/mobile/resend-verification`
- `POST /api/mobile/verify-email`
- `POST /api/mobile/verify-code`

## Required Render environment variables for real email sending
Add these in Render → your web service → Environment:

```env
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=yourgmail@gmail.com
SMTP_PASS=your_16_character_gmail_app_password
SMTP_FROM=GeoSustain <yourgmail@gmail.com>
```

The backend also accepts `SMTP_USERNAME`/`SMTP_PASSWORD`, but `SMTP_USER`/`SMTP_PASS` are now supported too.

If SMTP is not configured, the backend will still generate the 6-digit OTP, but it will print it only in the backend logs instead of sending an email.

## Important after updating
Push this backend update to GitHub and redeploy Render. If Render is still running an older deployment, `/api/mobile/resend-verification` will keep showing `404 Not Found`.
