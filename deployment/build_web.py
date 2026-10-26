"""Build matched Flutter/public Firebase artifacts. Never copies server secrets."""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
PUBLIC_KEYS = ('FIREBASE_API_KEY','FIREBASE_PROJECT_ID','FIREBASE_SENDER_ID',
               'FIREBASE_WEB_APP_ID','FIREBASE_AUTH_DOMAIN','GOOGLE_WEB_CLIENT_ID',
               'FIREBASE_WEB_VAPID_KEY')

def config():
    api=os.getenv('API_BASE_URL','https://geosustain.onrender.com').rstrip('/')
    uri=urlparse(api)
    if uri.scheme!='https' or not uri.hostname or uri.username or uri.password or uri.query or uri.fragment:
        raise ValueError('API_BASE_URL must be an HTTPS origin without credentials, query or fragment')
    public={key:os.environ[key] for key in PUBLIC_KEYS if os.getenv(key)}
    required=('FIREBASE_API_KEY','FIREBASE_PROJECT_ID','FIREBASE_SENDER_ID','FIREBASE_WEB_APP_ID')
    if any(k in public for k in required) and not all(k in public for k in required):
        raise ValueError('Partial Firebase web configuration: provide the four required public app identifiers together')
    return api,public

def identity():
    commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    names=subprocess.check_output(['git','ls-files','-z','lib','web','assets','pubspec.yaml','pubspec.lock'],cwd=ROOT).decode().split('\0')
    # Include new application files as well as tracked source while implementing.
    names+= [str(p.relative_to(ROOT)).replace('\\','/') for folder in ('lib','web','assets') for p in (ROOT/folder).rglob('*') if p.is_file()]
    digest=hashlib.sha256()
    for name in sorted(set(filter(None,names))):
        path=ROOT/name
        if path.is_file():
            digest.update(name.encode());digest.update(b'\0');digest.update(path.read_bytes())
    return commit,digest.hexdigest()


def machine_sdk_version(output):
    """Flutter can print first-run setup progress before its machine JSON."""
    decoder = json.JSONDecoder()
    for index, char in enumerate(output):
        if char != '{':
            continue
        try:
            value, _ = decoder.raw_decode(output[index:])
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict) and isinstance(value.get('frameworkVersion'), str):
            return value
    raise ValueError('Flutter did not return recognizable SDK version metadata')


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',default='build/web');parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    api,public=config();commit,fingerprint=identity()
    build_id=commit[:12]+'-'+fingerprint[:12]
    if args.check:
        print(json.dumps({'valid':True,'source_commit':commit,'source_fingerprint':fingerprint,'build_id':build_id,'api_origin':api,'public_config_keys':sorted(public)}));return
    flutter=os.getenv('FLUTTER_BIN') or shutil.which('flutter')
    if not flutter: raise SystemExit('Flutter SDK is required; use the Vercel bootstrap or set FLUTTER_BIN')
    sdk=machine_sdk_version(subprocess.check_output([flutter,'--version','--machine'],cwd=ROOT,text=True))
    defines={'API_BASE_URL':api,'WEB_BUILD_ID':build_id,**public}
    subprocess.run([flutter,'pub','get'],cwd=ROOT,check=True)
    subprocess.run([flutter,'build','web','--release','--pwa-strategy=none','--output='+args.output,*['--dart-define='+k+'='+v for k,v in defines.items()]],cwd=ROOT,check=True)
    if identity() != (commit,fingerprint):
        raise SystemExit('Application source changed during compilation; rebuild the stable candidate before publishing.')
    out=Path(args.output);out=out if out.is_absolute() else ROOT/out
    app=out/'main.dart.js'
    manifest={'source_commit':commit,'source_fingerprint':fingerprint,'build_id':build_id,'api_origin':api,'flutter_version':sdk.get('frameworkVersion'),'built_at_utc':datetime.now(timezone.utc).isoformat(),'main_js_sha256':hashlib.sha256(app.read_bytes()).hexdigest(),'public_firebase_project':public.get('FIREBASE_PROJECT_ID'),'web_push_configured':bool(public.get('FIREBASE_WEB_VAPID_KEY'))}
    (out/'build-info.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    worker_config=None
    if public:
        worker_config=dict(apiKey=public['FIREBASE_API_KEY'],projectId=public['FIREBASE_PROJECT_ID'],messagingSenderId=public['FIREBASE_SENDER_ID'],appId=public['FIREBASE_WEB_APP_ID'],authDomain=public.get('FIREBASE_AUTH_DOMAIN',public['FIREBASE_PROJECT_ID']+'.firebaseapp.com'))
    (out/'firebase-config.js').write_text('self.GEOSUSTAIN_FIREBASE = '+json.dumps(worker_config)+';\n',encoding='utf-8')
    # Allows safe manual deployment of the built output as its own Vercel root.
    rules=json.loads((ROOT/'vercel.json').read_text(encoding='utf-8'))
    (out/'vercel.json').write_text(json.dumps({'headers':rules['headers']},indent=2),encoding='utf-8')
    print(json.dumps(manifest))

if __name__=='__main__': main()
