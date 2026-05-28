# GeoSustain OTP Email Setup

The OTP page needs the backend route and SMTP settings.

## Required Render Environment Variables

Set these in Render > your web service > Environment:

SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=yourgmail@gmail.com
SMTP_PASS=your_gmail_app_password
SMTP_FROM=GeoSustain <yourgmail@gmail.com>

Use a Gmail App Password, not your normal Gmail password.

## Mobile OTP endpoints included

POST /api/mobile/register
POST /api/mobile/send-verification
POST /api/mobile/resend-verification
POST /api/mobile/verify-email
POST /api/mobile/verify-code

If the app shows 404 on resend, Render is still running the old backend. Push this project and redeploy Render.
