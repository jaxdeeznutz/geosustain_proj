"""Supported transactional transports. Acceptance is not recipient receipt."""
import os
import smtplib
import ssl
from email.message import EmailMessage
from email.utils import parseaddr
from uuid import NAMESPACE_URL, uuid5
import requests
from fastapi import HTTPException


def transport():
    selected = os.getenv('EMAIL_TRANSPORT', '').lower()
    return selected or ('resend' if os.getenv('RESEND_API_KEY') else
                        'brevo' if os.getenv('BREVO_API_KEY') else 'smtp')


def brevo_sender(sender):
    if not sender or '\r' in sender or '\n' in sender:
        return None
    name, address = parseaddr(sender)
    if '@' not in address or any(not part for part in address.rsplit('@', 1)):
        return None
    return {'name': name or 'GeoSustain', 'email': address}


def configured():
    sender = os.getenv('MAIL_FROM') or os.getenv('SMTP_FROM')
    if transport() == 'resend':
        return bool(sender and os.getenv('RESEND_API_KEY'))
    if transport() == 'brevo':
        return bool(brevo_sender(sender) and os.getenv('BREVO_API_KEY'))
    if transport() != 'smtp' or not sender or not os.getenv('SMTP_HOST'):
        return False
    try:
        port = int(os.getenv('SMTP_PORT', '587'))
    except ValueError:
        return False
    return (1 <= port <= 65535 and os.getenv('SMTP_SECURITY','starttls') in ('ssl','starttls')
        and not (os.getenv('SMTP_USERNAME') and not os.getenv('SMTP_PASSWORD'))
        and not (os.getenv('RENDER') and port in (25, 465, 587)))


def send(email, subject, text, *, idempotency_key=None):
    if not configured():
        raise HTTPException(503, 'Email delivery is not configured for this host. Please try again later.')
    sender = os.getenv('MAIL_FROM') or os.getenv('SMTP_FROM')
    try:
        if transport() == 'brevo':
            payload = {'sender': brevo_sender(sender), 'to': [{'email': email}],
                       'subject': subject, 'textContent': text}
            if idempotency_key:
                # Brevo requires a UUID; keep retry identity stable without
                # including the raw challenge/recipient in the custom header.
                payload['headers'] = {'IdempotencyKey': str(uuid5(
                    NAMESPACE_URL, 'geosustain-email:' + idempotency_key))}
            response = requests.post('https://api.brevo.com/v3/smtp/email',
                headers={'api-key': os.environ['BREVO_API_KEY'], 'Accept': 'application/json'},
                json=payload, timeout=(5, 15), allow_redirects=False)
            if response.status_code not in (200, 201) or not response.json().get('messageId'):
                raise ValueError('Provider did not accept the message')
            return
        if transport() == 'resend':
            headers = {'Authorization': 'Bearer ' + os.environ['RESEND_API_KEY']}
            if idempotency_key:
                headers['Idempotency-Key'] = idempotency_key
            response = requests.post('https://api.resend.com/emails',
                headers=headers, json={'from': sender, 'to': [email], 'subject': subject, 'text': text},
                timeout=(5, 15), allow_redirects=False)
            if response.status_code not in (200, 201) or not response.json().get('id'):
                raise ValueError('Provider did not accept the message')
            return
        mode = os.getenv('SMTP_SECURITY', 'starttls')
        if mode not in ('ssl', 'starttls'):
            raise ValueError('TLS mail transport required')
        message = EmailMessage()
        message['Subject'], message['From'], message['To'] = subject, sender, email
        message.set_content(text)
        port = int(os.getenv('SMTP_PORT', '465' if mode == 'ssl' else '587'))
        factory = smtplib.SMTP_SSL if mode == 'ssl' else smtplib.SMTP
        options = {'context': ssl.create_default_context()} if mode == 'ssl' else {}
        with factory(os.environ['SMTP_HOST'], port, timeout=15, **options) as smtp:
            if mode == 'starttls':
                smtp.starttls(context=ssl.create_default_context())
            if os.getenv('SMTP_USERNAME'):
                smtp.login(os.environ['SMTP_USERNAME'], os.getenv('SMTP_PASSWORD', ''))
            if smtp.send_message(message):
                raise ValueError('Recipient refused')
    except Exception:
        # Do not expose provider bodies, addresses, codes or credentials in errors.
        raise HTTPException(503, 'Email could not be sent. Please try again later.') from None
