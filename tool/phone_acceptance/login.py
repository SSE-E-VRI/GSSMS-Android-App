"""Enter generated disposable credentials using fresh field bounds and pacing."""
import json
import re
import sys
import time
import xml.etree.ElementTree as ET
from phone import adb, snapshot, OUT

prefix = 'other_' if sys.argv[1:] == ['other'] else ''
credentials = json.loads((OUT / 'credentials.json').read_text())


def nodes():
    return list(ET.parse(OUT / 'login-current.xml').getroot().iter('node'))


def tap(node):
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.attrib['bounds']))
    adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
    time.sleep(.3)


for index, field in enumerate(['username', 'password']):
    snapshot('login-current')
    inputs = [n for n in nodes() if n.attrib.get('class', '').endswith('EditText')]
    assert len(inputs) == 2, 'Expected login screen; stop rather than type elsewhere'
    tap(inputs[index])
    adb('shell', 'input', 'keyevent', '123')
    for _ in range(len(inputs[index].attrib.get('text', ''))):
        adb('shell', 'input', 'keyevent', '67')
        time.sleep(.08)
    for character in credentials[prefix + field]:
        adb('shell', 'input', 'text', character)
        time.sleep(.15)
    adb('shell', 'input', 'keyevent', '4')
snapshot('login-current')
buttons = [n for n in nodes() if
           (n.attrib.get('text') or n.attrib.get('content-desc')) == 'Sign In']
assert len(buttons) == 1
tap(buttons[0])
time.sleep(1.5)
snapshot('48-other-login' if prefix else 'login-tech-result')
