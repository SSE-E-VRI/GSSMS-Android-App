"""Local-only, explicitly controlled faults for one synthetic checklist route."""
import json
import time
import os
from pathlib import Path
from django.http import JsonResponse

OUT = Path(os.environ.get('GSSMS_PHONE_TEST_OUTPUT',
    Path(__file__).resolve().parents[2] / 'build' / 'phone-acceptance'))
OUT.mkdir(parents=True, exist_ok=True)


class AcceptanceFaults:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        target = request.method == 'POST' and request.path.endswith('/submit_line/')
        control_file = OUT / 'fault.json'
        control = json.loads(control_file.read_text()) if control_file.exists() else {}
        if not target:
            return self.get_response(request)
        event = {'path': request.path, 'at': time.time(),
                 'key': request.headers.get('Idempotency-Key'),
                 'payload': json.loads(request.body or '{}')}
        def log(phase, **extra):
            with (OUT / 'requests.jsonl').open('a', encoding='utf-8') as stream:
                stream.write(json.dumps({**event, 'phase': phase, **extra}) + '\n')
        log('received')
        time.sleep(float(control.get('before_seconds', 0)))
        if control.get('status'):
            response = JsonResponse({'detail': 'Disposable acceptance fault'},
                                    status=int(control['status']))
        else:
            response = self.get_response(request)
        log('committed', status=response.status_code)
        time.sleep(float(control.get('after_seconds', 0)))
        log('responding', status=response.status_code)
        return response
