"""Force-stop only the dev app at an observed disposable server boundary."""
import json
import sys
import time
from phone import adb, OUT, PACKAGE

phase, value = sys.argv[1:]
assert phase in ('received', 'committed')
started = time.time()
adb('shell', 'input', 'tap', '500', '350')  # observed home sync banner
deadline = time.monotonic() + 12
while time.monotonic() < deadline:
    events = [json.loads(line) for line in (OUT / 'requests.jsonl').read_text().splitlines()]
    matching = [e for e in events if e['at'] >= started and
                e['payload'].get('value') == value and e['phase'] == phase]
    if matching:
        adb('shell', 'am', 'force-stop', PACKAGE)
        (OUT / f'interrupt-{phase}-{value}.json').write_text(json.dumps({
            'event': matching[-1], 'force_stopped_at': time.time()
        }, indent=2))
        print(f'Force-stopped dev app after observed {phase}: {value}')
        break
    time.sleep(.1)
else:
    raise RuntimeError('Required server boundary not observed; app not stopped')
