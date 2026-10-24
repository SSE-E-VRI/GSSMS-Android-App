"""Exercise the observed home sync banner while one request is delayed."""
import json
import time
from phone import adb, snapshot, OUT

def received():
    return [json.loads(line) for line in (OUT / 'requests.jsonl').read_text().splitlines()
            if json.loads(line)['phase'] == 'received']

before = len(received())
(OUT / 'fault.json').write_text(json.dumps({'before_seconds': 3, 'status': 503}))
try:
    for _ in range(3):
        adb('shell', 'input', 'tap', '500', '350')
        time.sleep(.15)
    time.sleep(4)
    snapshot('42-repeated-sync-taps')
    delta = len(received()) - before
    result = {'taps': 3, 'new_requests': delta}
    (OUT / '42-repeated-sync-result.json').write_text(json.dumps(result))
    print(json.dumps(result))
    assert delta == 1, result
finally:
    (OUT / 'fault.json').write_text('{}')
