"""ADB helper scoped to the connected acceptance phone and dev package."""
import subprocess
import json
import time
import os
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ADB = r'C:\Users\ADMIN\AppData\Local\Android\Sdk\platform-tools\adb.exe'
DEVICE = '61ac9e71'
PACKAGE = 'com.ssee_vri.gssms_mobile.dev'
OUT = Path(os.environ.get('GSSMS_PHONE_TEST_OUTPUT',
    Path(__file__).resolve().parents[2] / 'build' / 'phone-acceptance'))
OUT.mkdir(parents=True, exist_ok=True)


def adb(*args):
    return subprocess.check_output([ADB, '-s', DEVICE, *args])


def snapshot(label):
    for attempt in range(3):
        adb('shell', 'rm', '-f', '/sdcard/gssms-acceptance.xml')
        adb('shell', 'uiautomator', 'dump', '/sdcard/gssms-acceptance.xml')
        try:
            raw = adb('shell', 'cat', '/sdcard/gssms-acceptance.xml')
            break
        except subprocess.CalledProcessError:
            if attempt == 2:
                raise
            time.sleep(1)
    (OUT / f'{label}.png').write_bytes(adb('exec-out', 'screencap', '-p'))
    (OUT / f'{label}.xml').write_bytes(raw)
    root = ET.fromstring(raw)
    for node in root.iter('node'):
        a = node.attrib
        name = a.get('text') or a.get('content-desc')
        if name or a.get('class', '').endswith('EditText'):
            print(a.get('class', '').split('.')[-1], repr(name), a.get('bounds'),
                  'enabled=' + a.get('enabled', ''),
                  'click=' + a.get('clickable', ''))


if __name__ == '__main__':
    action, *args = sys.argv[1:]
    if action == 'snapshot':
        snapshot(args[0])
    elif action == 'tap':
        adb('shell', 'input', 'tap', *args)
    elif action == 'tap-label':
        snapshot('ui-current')
        candidates = [node for node in ET.parse(OUT / 'ui-current.xml').getroot().iter('node')
          if (node.attrib.get('text') or node.attrib.get('content-desc') or '') == args[0]]
        assert len(candidates) == 1, 'Expected one observed label'
        x1, y1, x2, y2 = map(int, re.findall(r'\d+', candidates[0].attrib['bounds']))
        adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
    elif action == 'text':
        adb('shell', 'input', 'text', args[0])
    elif action == 'key':
        adb('shell', 'input', 'keyevent', *args)
    elif action == 'launch':
        adb('shell', 'am', 'start', '-n', PACKAGE + '/com.ssee_vri.gssms_mobile.MainActivity')
    elif action == 'stop':
        adb('shell', 'am', 'force-stop', PACKAGE)
    elif action == 'queue':
        raw = adb('shell', 'run-as', PACKAGE, 'cat',
                  'shared_prefs/FlutterSharedPreferences.xml')
        prefs = ET.fromstring(raw)
        values = {n.attrib.get('name'): n.text for n in prefs}
        queued = values.get('flutter.gssms_cache_outbox_commands', '[]')
        commands = json.loads(queued)
        result = [{'key': c.get('idempotency_key'), 'owner': c.get('owner_user_id'),
                   'status': c.get('status'), 'entity': c.get('entity_id'),
                   'payload': c.get('payload')} for c in commands]
        print(json.dumps(result))
        if args:
            (OUT / f'{args[0]}.json').write_text(json.dumps(result, indent=2))
    elif action == 'cached-record':
        raw = adb('shell', 'run-as', PACKAGE, 'cat',
                  'shared_prefs/FlutterSharedPreferences.xml')
        values = {n.attrib.get('name'): n.text for n in ET.fromstring(raw)}
        record = json.loads(values['flutter.gssms_cache_record_' + args[0]])
        result = {'id': record['id'], 'lines': [
            {'id': line['id'], 'recorded_value': line.get('recorded_value')}
            for line in record.get('lines', [])]}
        print(json.dumps(result))
        if len(args) > 1:
            (OUT / f'{args[1]}.json').write_text(json.dumps(result, indent=2))
